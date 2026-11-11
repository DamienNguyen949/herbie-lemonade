<#
  Herbie performance eval: laptop specs + text and voice accuracy, all on Lemonade.
  ---------------------------------------------------------------------------
  For each of the 32 test notes (20 clean, 12 messy shorthand):
    1. TEXT:  Herbie (Qwen3-4B, Herbie's real rules from index.html) turns the note into a ticket.
    2. SPEAK: Lemonade's Kokoro text-to-speech reads the note aloud (stand-in for a technician talking).
    3. HEAR:  Lemonade's Whisper-Base turns that audio back into text, with Herbie's IT word list.
    4. VOICE: Herbie tickets the transcript.
  Each phase runs for all notes before the next, so Lemonade isn't swapping models mid-note
  and the timings are clean.

  Outputs (next to this script): specs.txt, eval-voice-results.csv, eval-voice-summary.txt,
  and the generated audio in voice-test\.

  Needs: Windows PowerShell 5.1+, Lemonade Server running with Qwen3-4B-Instruct-2507-GGUF,
  kokoro-v1 and Whisper-Base downloaded. Put next to index.html and test-notes-all.json.
#>
param(
    [string]$BaseUrl   = "http://localhost:13305/api/v1",
    [string]$ChatModel = "Qwen3-4B-Instruct-2507-GGUF",
    [string]$TtsModel  = "kokoro-v1",
    [string]$SttModel  = "Whisper-Base",
    [string[]]$Voices  = @("nova", "echo"),
    [string]$NotesFile = (Join-Path $PSScriptRoot "test-notes-all.json"),
    [string]$HerbieHtml = (Join-Path $PSScriptRoot "index.html")
)
$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")
Add-Type -AssemblyName System.Net.Http
$http = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromMinutes(15)
$outDir = Join-Path $PSScriptRoot "voice-test"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Same word list Herbie's Talk button gives Whisper
$Vocab = "IT support job notes. Herbie, Jira, ADUC, Active Directory, Outlook, Microsoft 365, QuickBooks, Lacerte, Epic, Westlaw, VLAN, GPO, DNS, DHCP, VPN, Wi-Fi, router, firewall, printer."
# Terms we check Whisper spelled right (only counted when the note contains them)
$Terms = @("QuickBooks", "Epic", "VLAN", "GPO", "Outlook", "Lacerte", "Teams", "Microsoft 365", "firewall", "router", "Wi-Fi", "Client Trax", "SQL")

# ---------------------------------------------------------------- specs
function Get-Specs {
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os  = Get-CimInstance Win32_OperatingSystem
    $gpus = Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) (driver $($_.DriverVersion))" }
    $npu = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NPU|Neural|IPU" } | ForEach-Object { $_.FriendlyName }) -join "; "
    $lines = @(
        "Laptop:   $($cs.Manufacturer) $($cs.Model)",
        "CPU:      $($cpu.Name.Trim()) ($($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads)",
        ("RAM:      {0:N0} GB" -f ($cs.TotalPhysicalMemory / 1GB)),
        "GPU:      $($gpus -join '; ')",
        "NPU:      $(if ($npu) { $npu } else { 'not detected' })",
        "Windows:  $($os.Caption) $($os.Version)"
    )
    foreach ($p in "/system-info", "/health") {
        try {
            $j = Invoke-RestMethod -Uri "$BaseUrl$p" -TimeoutSec 20
            $lines += "Lemonade $p : " + ($j | ConvertTo-Json -Depth 6 -Compress)
        } catch { $lines += "Lemonade $p : (not available)" }
    }
    return $lines
}

# ---------------------------------------------------------------- helpers
if (-not (Test-Path $HerbieHtml)) { $HerbieHtml = Join-Path (Split-Path $PSScriptRoot -Parent) "index.html" }
$html = Get-Content $HerbieHtml -Raw -Encoding UTF8
$m = [regex]::Match($html, '(?s)const RULES = `(.*?)`;')
if (-not $m.Success) { Write-Host "Couldn't read Herbie's rules from $HerbieHtml" -ForegroundColor Red; exit 1 }
$Rules = $m.Groups[1].Value

function Invoke-Chat([string]$User) {
    $payload = @{ model = $ChatModel; temperature = 0.2; stream = $false; response_format = @{ type = "json_object" }
                  messages = @(@{ role = "system"; content = $Rules }, @{ role = "user"; content = $User }) }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 6))
    $r = Invoke-RestMethod -Uri "$BaseUrl/chat/completions" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 900
    return [string]$r.choices[0].message.content
}
function Get-Ticket([string]$Notes) {
    $t = (Invoke-Chat ("Job notes:`n" + $Notes + "`n/no_think")) -replace '(?s)<think>.*?</think>', ''
    $a = $t.IndexOf('{'); $b = $t.LastIndexOf('}')
    if ($a -lt 0 -or $b -le $a) { return @{ category = "Unreadable"; priority = "" } }
    try { $j = $t.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch { return @{ category = "Unreadable"; priority = "" } }
    if ($j.status -eq "needs_info" -or -not $j.ticket) { return @{ category = "Asked"; priority = "" } }
    $cat = "Unknown"; foreach ($c in "Incident", "Request", "Problem", "Change") { if ([string]$j.ticket.category -match $c) { $cat = $c; break } }
    return @{ category = $cat; priority = [string]$j.ticket.priority }
}

# Read a WAV (PCM16 or float32, any rate/channels) and write 16 kHz mono PCM16, like Herbie's Talk button
function Convert-To16k([byte[]]$wav) {
    $pos = 12; $fmt = 0; $ch = 1; $rate = 0; $bits = 16; $dataOff = -1; $dataLen = 0
    while ($pos + 8 -le $wav.Length) {
        $id = [Text.Encoding]::ASCII.GetString($wav, $pos, 4); $len = [BitConverter]::ToInt32($wav, $pos + 4)
        if ($id -eq "fmt ") { $fmt = [BitConverter]::ToInt16($wav, $pos + 8); $ch = [BitConverter]::ToInt16($wav, $pos + 10)
                              $rate = [BitConverter]::ToInt32($wav, $pos + 12); $bits = [BitConverter]::ToInt16($wav, $pos + 22) }
        elseif ($id -eq "data") {
            $dataOff = $pos + 8; $rest = $wav.Length - $dataOff
            # streamed WAVs say "unknown length" (0 or -1): use the rest of the file
            $dataLen = if ($len -le 0 -or $len -gt $rest) { $rest } else { $len }
            break }
        $pos += 8 + $len + ($len % 2)
    }
    if ($dataOff -lt 0 -or $rate -le 0) { throw "unreadable audio" }
    if ($bits -ne 16 -and $bits -ne 32) { throw "unsupported audio: $bits-bit" }
    $bps = $bits / 8; $frames = [int][Math]::Floor($dataLen / ($bps * $ch))
    if ($frames -lt $rate / 10) { throw "audio too short ($frames samples)" }
    $mono = New-Object 'double[]' $frames
    for ($i = 0; $i -lt $frames; $i++) {
        $o = $dataOff + $i * $bps * $ch
        if ($fmt -eq 3) { $mono[$i] = [BitConverter]::ToSingle($wav, $o) }
        elseif ($bits -eq 32) { $mono[$i] = [BitConverter]::ToInt32($wav, $o) / 2147483648.0 }
        else { $mono[$i] = [BitConverter]::ToInt16($wav, $o) / 32768.0 }
    }
    $ratio = $rate / 16000.0; $n = [int][Math]::Floor($frames / $ratio)
    $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $bw.Write([int](36 + $n * 2)); $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]16000); $bw.Write([int]32000); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes("data")); $bw.Write([int]($n * 2))
    for ($i = 0; $i -lt $n; $i++) {
        $a = [int][Math]::Floor($i * $ratio); $b = [Math]::Min($frames, [int][Math]::Floor(($i + 1) * $ratio)); $s = 0.0
        for ($k = $a; $k -lt $b; $k++) { $s += $mono[$k] }
        $v = [Math]::Max(-1.0, [Math]::Min(1.0, $s / [Math]::Max(1, $b - $a)))
        $bw.Write([int16][Math]::Round($v * 32767))
    }
    $bw.Flush(); return $ms.ToArray()
}

function Get-Words([string]$s) { return @(([regex]::Matches($s.ToLower(), "[a-z0-9']+")) | ForEach-Object { $_.Value }) }
function Get-WordErrors([string[]]$ref, [string[]]$hyp) {
    # word-level edit distance, two rows at a time
    $n = $hyp.Count
    $prev = New-Object 'int[]' ($n + 1)
    for ($j = 0; $j -le $n; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $ref.Count; $i++) {
        $cur = New-Object 'int[]' ($n + 1)
        $cur[0] = $i
        $word = $ref[$i - 1]
        for ($j = 1; $j -le $n; $j++) {
            $cost = 1
            if ($word -eq $hyp[$j - 1]) { $cost = 0 }
            $best = $prev[$j] + 1
            $ins = $cur[$j - 1] + 1
            if ($ins -lt $best) { $best = $ins }
            $sub = $prev[$j - 1] + $cost
            if ($sub -lt $best) { $best = $sub }
            $cur[$j] = $best
        }
        $prev = $cur
    }
    return $prev[$n]
}

# ---------------------------------------------------------------- run
$specs = Get-Specs
$specs | Set-Content (Join-Path $PSScriptRoot "specs.txt") -Encoding UTF8
Write-Host "=== This laptop ===" -ForegroundColor Cyan; $specs | ForEach-Object { Write-Host $_ }

$notes = Get-Content $NotesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$rows = @{}; foreach ($n in $notes) { $rows[$n.id] = [ordered]@{ Id = $n.id; Set = $n.set; Expected = $n.expected; Note = $n.note } }

Write-Host "`n=== 1/4 Text tickets ($ChatModel) ===" -ForegroundColor Cyan
[void](Get-Ticket "warm up: printer jammed, cleared it")
foreach ($n in $notes) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $t = Get-Ticket $n.note; $sw.Stop()
    $r = $rows[$n.id]; $r.TextCategory = $t.category; $r.TextPriority = $t.priority; $r.TextCorrect = ($t.category -eq $n.expected); $r.TextSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("{0}  {1,-8} -> {2,-8} {3,5}s" -f $n.id, $n.expected, $t.category, $r.TextSeconds)
}

Write-Host "`n=== 2/4 Speaking the notes ($TtsModel) ===" -ForegroundColor Cyan
$i = 0
foreach ($n in $notes) {
    $voice = $Voices[$i % $Voices.Count]; $i++
    $body = @{ model = $TtsModel; input = $n.note; voice = $voice; speed = 1.0; response_format = "wav" } | ConvertTo-Json
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $http.PostAsync("$BaseUrl/audio/speech", [System.Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, "application/json")).GetAwaiter().GetResult()
    $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult(); $sw.Stop()
    if (-not $resp.IsSuccessStatusCode) { throw "Text-to-speech failed for $($n.id): $([Text.Encoding]::UTF8.GetString($bytes))" }
    [IO.File]::WriteAllBytes((Join-Path $outDir "$($n.id).wav"), $bytes)
    $rows[$n.id].Voice = $voice; $rows[$n.id].SpeakSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("{0}  voice {1,-6} {2,5}s" -f $n.id, $voice, $rows[$n.id].SpeakSeconds)
}

Write-Host "`n=== 3/4 Hearing the notes ($SttModel) ===" -ForegroundColor Cyan
$audioTotal = 0.0
foreach ($n in $notes) {
    $wav16 = Convert-To16k ([IO.File]::ReadAllBytes((Join-Path $outDir "$($n.id).wav")))
    $audioSec = ($wav16.Length - 44) / 32000.0; $audioTotal += $audioSec
    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $file = [System.Net.Http.ByteArrayContent]::new($wav16); $file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("audio/wav")
    $form.Add($file, "file", "notes.wav")
    foreach ($kv in @(@("model", $SttModel), @("response_format", "json"), @("language", "en"), @("prompt", $Vocab))) {
        $form.Add([System.Net.Http.StringContent]::new($kv[1]), $kv[0]) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $http.PostAsync("$BaseUrl/audio/transcriptions", $form).GetAwaiter().GetResult()
    $txt = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(); $sw.Stop()
    if (-not $resp.IsSuccessStatusCode) { throw "Speech-to-text failed for $($n.id): $txt" }
    $heard = ([string](ConvertFrom-Json $txt).text -replace '\s+', ' ').Trim()
    $ref = Get-Words $n.note; $hyp = Get-Words $heard; $errs = Get-WordErrors $ref $hyp
    $termsIn = @($Terms | Where-Object { $n.note -match [regex]::Escape($_) })
    $termsOk = @($termsIn | Where-Object { $heard -match [regex]::Escape($_) })
    $r = $rows[$n.id]; $r.Heard = $heard; $r.AudioSeconds = [math]::Round($audioSec, 1); $r.HearSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $r.RefWords = $ref.Count; $r.WordErrors = $errs; $r.TermsInNote = $termsIn.Count; $r.TermsHeardRight = $termsOk.Count
    Write-Host ("{0}  {1,3} words, {2,2} errors, {3,4}s audio in {4,4}s" -f $n.id, $ref.Count, $errs, $r.AudioSeconds, $r.HearSeconds)
}

Write-Host "`n=== 4/4 Tickets from voice ($ChatModel) ===" -ForegroundColor Cyan
[void](Get-Ticket "warm up: printer jammed, cleared it")
foreach ($n in $notes) {
    $r = $rows[$n.id]
    $sw = [Diagnostics.Stopwatch]::StartNew(); $t = Get-Ticket $r.Heard; $sw.Stop()
    $r.VoiceCategory = $t.category; $r.VoiceCorrect = ($t.category -eq $n.expected); $r.VoiceTicketSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("{0}  {1,-8} -> {2,-8} {3,5}s" -f $n.id, $n.expected, $t.category, $r.VoiceTicketSeconds)
}

# ---------------------------------------------------------------- results
$all = @($notes | ForEach-Object { [pscustomobject]$rows[$_.id] })
$all | Export-Csv (Join-Path $PSScriptRoot "eval-voice-results.csv") -NoTypeInformation -Encoding UTF8
function Pct($a, $b) { if ($b) { "{0:N0}%" -f (100.0 * $a / $b) } else { "n/a" } }
function Avg($p) { [math]::Round((($all | Measure-Object $p -Average).Average), 1) }
$N = $all.Count
$textOk = @($all | Where-Object { $_.TextCorrect }).Count
$voiceOk = @($all | Where-Object { $_.VoiceCorrect }).Count
$refW = ($all | Measure-Object RefWords -Sum).Sum; $errW = ($all | Measure-Object WordErrors -Sum).Sum
$tIn = ($all | Measure-Object TermsInNote -Sum).Sum; $tOk = ($all | Measure-Object TermsHeardRight -Sum).Sum
$sets = foreach ($s in "clean", "messy") {
    $g = @($all | Where-Object { $_.Set -eq $s })
    "  {0,-6} notes: text {1}/{2}, voice {3}/{2}" -f $s, @($g | Where-Object { $_.TextCorrect }).Count, $g.Count, @($g | Where-Object { $_.VoiceCorrect }).Count
}
$summary = @"
Herbie performance eval - $(Get-Date -Format "yyyy-MM-dd HH:mm")
Everything ran locally on Lemonade ($BaseUrl). Cost: `$0.

$($specs -join "`r`n")

Models: chat $ChatModel | speech-to-text $SttModel | text-to-speech $TtsModel (voices: $($Voices -join ', '))
Test set: $N job notes (20 clean, 12 messy shorthand), expected ITIL category for each.

CATEGORY ACCURACY
  Typed notes:  $textOk/$N ($(Pct $textOk $N))
  Voice notes:  $voiceOk/$N ($(Pct $voiceOk $N))  (Kokoro speaks the note -> Whisper -> Herbie)
$($sets -join "`r`n")

WHISPER (speech-to-text)
  Word error rate: $(Pct $errW $refW) ($errW errors in $refW words; shorthand like "qb" and "svc" counts as errors when spoken out)
  IT terms heard right: $tOk/$tIn
  Speed: $([math]::Round($audioTotal,1)) s of audio transcribed, avg $(Avg 'HearSeconds') s per note

SPEED (average per note)
  Ticket from typed notes:  $(Avg 'TextSeconds') s
  Ticket from voice notes:  $(Avg 'VoiceTicketSeconds') s  (+ $(Avg 'HearSeconds') s to transcribe)
"@
$summary | Set-Content (Join-Path $PSScriptRoot "eval-voice-summary.txt") -Encoding UTF8
Write-Host "`n$summary" -ForegroundColor Cyan
