# Herbie local server.
# - Serves Herbie's page on http://localhost:<Port>/ and opens it in its own app window.
# - Passes /api/* to Lemonade Server, so the page and the model share one origin and everything stays on this PC.
# - Files saved tickets to Jira (/herbie/jira) using the login in .env. The token never reaches the browser.
param(
  [int]$Port = 8765,
  [string]$Lemonade = "http://localhost:13305",   # Lemonade's default port
  [string]$EnvFile = "",                          # defaults to .env next to this script
  [switch]$NoBrowser,                             # don't open a window (testing)
  [switch]$Quiet                                  # started from the Herbie shortcut: no console, errors as pop-ups, exits when Herbie's window is closed
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

$root = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $EnvFile) { $EnvFile = Join-Path $root ".env" }
$filedPath = Join-Path $root "herbie_filed.json"
$logPath = Join-Path $root "herbie_jira.log"
$url = "http://localhost:$Port/"

# Only Herbie's own page files are served; never .env, logs or ticket records.
$types = @{
  ".html" = "text/html; charset=utf-8"; ".svg" = "image/svg+xml"; ".png" = "image/png"
  ".ico" = "image/x-icon"; ".webmanifest" = "application/manifest+json"
}

function Show-Problem([string]$text) {
  if ($Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($text, "Herbie", "OK", "Warning")
  } else {
    Write-Host ""; Write-Host "  $text" -ForegroundColor Red
  }
}

# Open Herbie in his own window (browser app mode: no tabs or address bar), like the original desktop shortcut.
function Open-Herbie {
  if ($NoBrowser) { return }
  $candidates = @(
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  $browser = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if ($browser) { Start-Process -FilePath $browser -ArgumentList "--app=$url" } else { Start-Process $url }
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromMinutes(10)   # the first request can wait while Lemonade loads a model

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($url)
try {
  $listener.Start()
} catch {
  # Port taken. If it's Herbie already running, just open him; otherwise explain.
  $already = $false
  try { $already = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).Content -match "<title>Herbie" } catch { }
  if ($already) {
    if (-not $Quiet) { Write-Host ""; Write-Host "  Herbie is already running - opening him." -ForegroundColor Cyan }
    Open-Herbie
    Start-Sleep -Seconds 1
    exit 0
  }
  Show-Problem "Herbie couldn't start: port $Port is being used by another program. Close that program and try again."
  exit 1
}
if (-not $Quiet) {
  Write-Host ""
  Write-Host "  Herbie is running at $url" -ForegroundColor Cyan
  Write-Host "  Talking to Lemonade at $Lemonade"
  Write-Host "  Keep this window open while you use Herbie. Press Ctrl+C to stop."
  Write-Host ""
}
Open-Herbie

function Send-Bytes($res, [int]$status, [string]$type, [byte[]]$bytes) {
  $res.StatusCode = $status
  $res.ContentType = $type
  $res.Headers["Cache-Control"] = "no-store"
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}
function Send-Json($res, [int]$status, $obj) {
  Send-Bytes $res $status "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $obj -Compress -Depth 10)))
}
function Write-Log([string]$line) {
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  try { [IO.File]::AppendAllText($logPath, "$stamp  $line`r`n", [Text.UTF8Encoding]::new($false)) } catch { }
  if (-not $Quiet) { Write-Host "  $line" }
}

# ---------------- Jira ----------------

function Read-JiraConfig {
  $cfg = @{ JIRA_SITE = ""; JIRA_PROJECT = "KAN"; JIRA_EMAIL = ""; JIRA_TOKEN = "" }
  if (Test-Path -LiteralPath $EnvFile) {
    foreach ($line in [IO.File]::ReadAllLines($EnvFile)) {
      if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2].Trim('"').Trim("'") }
    }
  }
  if ($cfg.JIRA_SITE -and $cfg.JIRA_SITE -notmatch '^https?://') { $cfg.JIRA_SITE = "https://" + $cfg.JIRA_SITE }
  $cfg.JIRA_SITE = $cfg.JIRA_SITE.TrimEnd('/')
  $cfg.configured = [bool]($cfg.JIRA_SITE -and $cfg.JIRA_EMAIL -and $cfg.JIRA_TOKEN)
  return $cfg
}

function Invoke-Jira($cfg, [string]$method, [string]$path, $body = $null) {
  $msg = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($method), $cfg.JIRA_SITE + $path)
  $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cfg.JIRA_EMAIL):$($cfg.JIRA_TOKEN)"))
  $msg.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Basic", $auth)
  $msg.Headers.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("application/json"))
  if ($null -ne $body) {
    $json = ConvertTo-Json -InputObject $body -Depth 30 -Compress
    $msg.Content = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
  }
  try { $resp = $client.SendAsync($msg).GetAwaiter().GetResult() }
  catch { return [pscustomobject]@{ status = 0; ok = $false; data = $null; text = $_.Exception.Message } }
  $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $data = $null
  if ($text) { try { $data = ConvertFrom-Json -InputObject $text } catch { } }
  return [pscustomobject]@{ status = [int]$resp.StatusCode; ok = $resp.IsSuccessStatusCode; data = $data; text = $text }
}

# Turn a failed Jira call into an error the page can explain: "<code>|<message>"
function Assert-Jira($r, [string]$what) {
  if ($r.ok) { return }
  $detail = ""
  if ($r.data) {
    $parts = @()
    if ($r.data.errorMessages) { $parts += @($r.data.errorMessages) }
    if ($r.data.errors) { $parts += @($r.data.errors.PSObject.Properties | ForEach-Object { "$($_.Name): $($_.Value)" }) }
    $detail = ($parts | Where-Object { $_ }) -join "; "
  } elseif ($r.status -eq 0) { $detail = $r.text }
  $code = switch ($r.status) { 0 { "unreachable" } 401 { "login" } 403 { "login" } 404 { "not_found" } default { "rejected" } }
  throw "$code|$what failed ($($r.status)). $detail"
}

function Add-Paras($list, [string]$text) {
  $lines = @(($text -split "\r?\n") | Where-Object { $_.Trim() })
  if ($lines.Count -eq 0) { $lines = @("Not stated") }
  foreach ($l in $lines) { [void]$list.Add(@{ type = "paragraph"; content = @(@{ type = "text"; text = $l }) }) }
}
function Add-Heading($list, [string]$text) {
  [void]$list.Add(@{ type = "heading"; attrs = @{ level = 3 }; content = @(@{ type = "text"; text = $text }) })
}
# Jira description (Atlassian Document Format): one heading per section, then the original notes as a quote.
function New-Description($t) {
  $c = [System.Collections.ArrayList]::new()
  foreach ($pair in @(@("Issue", "issue"), @("Root cause", "root_cause"), @("Steps taken", "steps_taken"), @("Resolution", "resolution"), @("Reason for category", "reason"))) {
    Add-Heading $c $pair[0]; Add-Paras $c ([string]$t.($pair[1]))
  }
  if ($t.notes) {
    Add-Heading $c "Original notes"
    $q = [System.Collections.ArrayList]::new(); Add-Paras $q ([string]$t.notes)
    [void]$c.Add(@{ type = "blockquote"; content = $q })
  }
  [void]$c.Add(@{ type = "paragraph"; content = @(@{ type = "text"; text = "Written by Herbie on a local AI model (Lemonade)."; marks = @(@{ type = "em" }) }) })
  return @{ type = "doc"; version = 1; content = $c }
}

function Get-Slug([string]$s) { ($s.ToLower() -replace '[^a-z0-9]+', '-').Trim('-') }
function Get-JiraPriority([string]$p) { if ($p -eq "Critical") { "Highest" } elseif ($p) { $p } else { "Medium" } }
function Get-Title($t) {
  $title = [string]$t.summary
  if (-not $title) { $title = "Ticket from Herbie" }
  if ($t.client -and $t.client -notmatch '^(unknown|not stated)$') { $title = "[$($t.client)] $title" }
  if ($title.Length -gt 250) { $title = $title.Substring(0, 250) }
  return ($title -replace '[\r\n]+', ' ')
}
function Get-Labels($t, [bool]$typeMissing) {
  $labels = [System.Collections.ArrayList]@("herbie")
  if ($t.client -and $t.client -notmatch '^(unknown|not stated)$') { $s = Get-Slug ([string]$t.client); if ($s) { [void]$labels.Add($s) } }
  if ($typeMissing) { [void]$labels.Add("category-" + ([string]$t.category).ToLower()) }
  return $labels
}

# Time worked, from phrases like "45 min" or "1.5 hours" in the notes. Skips "20 min later", "after 10 min idle", etc.
function Get-WorkSeconds([string]$notes) {
  if (-not $notes) { return 0 }
  foreach ($m in [regex]::Matches($notes, '(?i)(?<!(?:after|every|within|in|for the last|last)\s)\b(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?)\b(?!\s*(?:later|ago|earlier|before|after|apart|idle|in a row))')) {
    $n = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    $secs = if ($m.Groups[2].Value -match '^(?i)h') { $n * 3600 } else { $n * 60 }
    if ($secs -ge 60 -and $secs -le 86400) { return [int]$secs }
  }
  return 0
}

function Move-ToDone($cfg, [string]$key) {
  $r = Invoke-Jira $cfg GET "/rest/api/3/issue/$key/transitions"
  if (-not $r.ok) { Write-Log "  $key couldn't read transitions ($($r.status))"; return }
  $done = @($r.data.transitions | Where-Object { $_.to.statusCategory.key -eq "done" }) | Select-Object -First 1
  if (-not $done) { Write-Log "  $key has no transition to a done status"; return }
  $p = Invoke-Jira $cfg POST "/rest/api/3/issue/$key/transitions" @{ transition = @{ id = $done.id } }
  if ($p.ok) { Write-Log "  $key moved to $($done.to.name)" } else { Write-Log "  $key couldn't be moved to done ($($p.status))" }
}

function New-JiraIssue($cfg, $t, [bool]$logTime = $true) {
  $proj = Invoke-Jira $cfg GET "/rest/api/3/project/$($cfg.JIRA_PROJECT)"
  Assert-Jira $proj "Reading Jira space $($cfg.JIRA_PROJECT)"
  $names = @($proj.data.issueTypes | Where-Object { -not $_.subtask } | ForEach-Object { $_.name })
  $want = @{ Incident = "Incident"; Request = "Service Request"; Problem = "Problem"; Change = "Change" }[[string]$t.category]
  $typeName = $names | Where-Object { $want -and $_ -ieq $want } | Select-Object -First 1
  $typeMissing = -not $typeName
  if ($typeMissing) {
    $typeName = $names | Where-Object { $_ -ieq "Task" } | Select-Object -First 1
    if (-not $typeName) { $typeName = $names | Select-Object -First 1 }
  }
  $fields = @{
    project = @{ key = $cfg.JIRA_PROJECT }; issuetype = @{ name = $typeName }
    summary = (Get-Title $t); description = (New-Description $t); labels = (Get-Labels $t $typeMissing)
    priority = @{ name = (Get-JiraPriority ([string]$t.priority)) }
  }
  $me = Invoke-Jira $cfg GET "/rest/api/3/myself"
  if ($me.ok -and $me.data.accountId) { $fields.assignee = @{ accountId = $me.data.accountId } }
  $r = Invoke-Jira $cfg POST "/rest/api/3/issue" @{ fields = $fields }
  if ($r.status -eq 400) {
    # Some spaces don't allow setting priority or assignee on create; try once without them.
    Write-Log "  create rejected ($($r.text)); retrying without priority/assignee"
    $fields.Remove("priority"); $fields.Remove("assignee")
    $r = Invoke-Jira $cfg POST "/rest/api/3/issue" @{ fields = $fields }
  }
  Assert-Jira $r "Creating the Jira ticket"
  $key = [string]$r.data.key
  Write-Log "  created $key ($typeName)"
  $secs = if ($logTime) { Get-WorkSeconds ([string]$t.notes) } else { 0 }
  if ($secs -gt 0) {
    $w = Invoke-Jira $cfg POST "/rest/api/3/issue/$key/worklog" @{ timeSpentSeconds = $secs }
    if ($w.ok) { Write-Log "  $key logged $([math]::Round($secs / 60)) min" } else { Write-Log "  $key work log failed ($($w.status))" }
  }
  if ($t.ticket_status -eq "Resolved") { Move-ToDone $cfg $key }
  return $key
}

function Update-JiraIssue($cfg, $t, [string]$key) {
  $fields = @{ summary = (Get-Title $t); description = (New-Description $t); priority = @{ name = (Get-JiraPriority ([string]$t.priority)) } }
  $r = Invoke-Jira $cfg PUT "/rest/api/3/issue/$key" @{ fields = $fields }
  if ($r.status -eq 400) { $fields.Remove("priority"); $r = Invoke-Jira $cfg PUT "/rest/api/3/issue/$key" @{ fields = $fields } }
  Assert-Jira $r "Updating $key"
  Write-Log "  updated $key"
  if ($t.ticket_status -eq "Resolved") { Move-ToDone $cfg $key }
}

function Add-JiraComment($cfg, [string]$key, [string]$text) {
  $body = @{ body = @{ type = "doc"; version = 1; content = @(@{ type = "paragraph"; content = @(@{ type = "text"; text = $text }) }) } }
  [void](Invoke-Jira $cfg POST "/rest/api/3/issue/$key/comment" $body)
}

function Get-Filed {
  $h = @{}
  if (Test-Path -LiteralPath $filedPath) {
    try {
      (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($filedPath))).PSObject.Properties |
        ForEach-Object { $h[$_.Name] = @{ key = $_.Value.key; category = $_.Value.category; at = $_.Value.at } }
    } catch { }
  }
  return $h
}
function Save-Filed($h) { [IO.File]::WriteAllText($filedPath, (ConvertTo-Json -InputObject $h -Depth 5), [Text.UTF8Encoding]::new($false)) }

# One saved or edited ticket from the page -> Jira. Returns what the page shows.
function Send-ToJira($t) {
  $cfg = Read-JiraConfig
  if (-not $cfg.configured) { throw "not_configured|Jira isn't set up on this PC yet." }
  $hid = [string]$t.hid
  if (-not $hid) { throw "rejected|The ticket has no Herbie id." }
  $filed = Get-Filed
  $prior = $null
  if ($filed.ContainsKey($hid)) { $prior = $filed[$hid] }
  elseif ($t.jira_key) { $prior = @{ key = [string]$t.jira_key; category = [string]$t.prev_category } }

  $result = @{ key = ""; url = ""; already = $false; replaced = "" }
  if ($t.action -ne "update") {
    if ($prior) { $result.key = $prior.key; $result.already = $true; Write-Log "Already in Jira as $($prior.key)" }
    else { $result.key = New-JiraIssue $cfg $t }
  } elseif (-not $prior) {
    $result.key = New-JiraIssue $cfg $t   # edited before it ever reached Jira
  } else {
    $prevCat = if ($t.prev_category) { [string]$t.prev_category } else { [string]$prior.category }
    if ($prevCat -and $prevCat -ne [string]$t.category) {
      # Category changed: new ticket of the new type, linked to the old one (time stays logged on the old one).
      $newKey = New-JiraIssue $cfg $t $false
      [void](Invoke-Jira $cfg POST "/rest/api/3/issueLink" @{ type = @{ name = "Relates" }; inwardIssue = @{ key = $prior.key }; outwardIssue = @{ key = $newKey } })
      if ($prevCat -eq "Incident" -and $t.category -eq "Problem") {
        Add-JiraComment $cfg $prior.key "Linked to Problem $newKey for root-cause investigation."
      } else {
        Add-JiraComment $cfg $prior.key "Replaced by $newKey (category changed from $prevCat to $($t.category))."
        Move-ToDone $cfg $prior.key
      }
      $result.key = $newKey; $result.replaced = $prior.key
    } else {
      Update-JiraIssue $cfg $t $prior.key
      $result.key = $prior.key
    }
  }
  $filed[$hid] = @{ key = $result.key; category = [string]$t.category; at = (Get-Date).ToString("o") }
  Save-Filed $filed
  $result.url = "$($cfg.JIRA_SITE)/browse/$($result.key)"
  return $result
}

# ---------------- Request loop ----------------

$lastSeen = Get-Date; $seenPage = $false
try {
  while ($listener.IsListening) {
    $task = $listener.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(500)) {
      # Started from the shortcut: stop once Herbie's window has been closed for a few minutes (no pings).
      if ($Quiet -and $seenPage -and ((Get-Date) - $lastSeen).TotalMinutes -gt 3) { exit 0 }
    }
    $ctx = $task.GetAwaiter().GetResult()
    $req = $ctx.Request; $res = $ctx.Response
    $lastSeen = Get-Date
    try {
      $path = $req.Url.AbsolutePath
      # Only Herbie's own page may use the model or Jira: right host, no foreign origin, Herbie's header.
      $hostOk = $req.Headers["Host"] -eq "localhost:$Port"
      $origin = $req.Headers["Origin"]
      $trusted = $hostOk -and ((-not $origin) -or $origin -eq "http://localhost:$Port") -and $req.Headers["X-Herbie"] -eq "1"
      if (-not $hostOk) {
        Send-Bytes $res 403 "text/plain" ([Text.Encoding]::UTF8.GetBytes("Forbidden"))
      } elseif (($path.StartsWith("/api/") -or $path.StartsWith("/herbie/")) -and -not $trusted) {
        Send-Json $res 403 @{ error = @{ code = "forbidden"; message = "Only Herbie's own page can use this." } }
      } elseif ($path -eq "/herbie/ping") {
        $seenPage = $true
        Send-Json $res 200 @{ ok = $true }
      } elseif ($path -eq "/herbie/jira/status") {
        $cfg = Read-JiraConfig
        Send-Json $res 200 @{ configured = $cfg.configured; site = $cfg.JIRA_SITE; project = $cfg.JIRA_PROJECT }
      } elseif ($path -eq "/herbie/jira" -and $req.HttpMethod -eq "POST") {
        $sr = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8)
        $t = ConvertFrom-Json -InputObject $sr.ReadToEnd()
        Write-Log ("Jira {0}: {1} [{2}]" -f $(if ($t.action -eq "update") { "update" } else { "new" }), $t.summary, $t.category)
        try {
          Send-Json $res 200 (Send-ToJira $t)
        } catch {
          $parts = "$($_.Exception.Message)" -split '\|', 2
          $code = if ($parts.Count -eq 2) { $parts[0] } else { "error" }
          $message = $parts[-1]
          Write-Log "  FAILED: $message"
          Send-Json $res 502 @{ error = @{ code = $code; message = $message } }
        }
      } elseif ($path.StartsWith("/api/")) {
        # Pass through to Lemonade
        $msg = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($req.HttpMethod), $Lemonade.TrimEnd("/") + $req.Url.PathAndQuery)
        if ($req.HasEntityBody) {
          $ms = [IO.MemoryStream]::new(); $req.InputStream.CopyTo($ms)
          $msg.Content = [System.Net.Http.ByteArrayContent]::new($ms.ToArray())
          # Keep the page's own content type (JSON for chat, multipart for voice recordings)
          $ctype = if ($req.ContentType) { $req.ContentType } else { "application/json" }
          [void]$msg.Content.Headers.TryAddWithoutValidation("Content-Type", $ctype)
        }
        try {
          $up = $client.SendAsync($msg).GetAwaiter().GetResult()
          $bytes = $up.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
          $ct = $up.Content.Headers.ContentType
          Send-Bytes $res ([int]$up.StatusCode) $(if ($ct) { $ct.ToString() } else { "application/json" }) $bytes
          if (-not $Quiet) { Write-Host ("  {0} {1} -> {2}" -f $req.HttpMethod, $path, [int]$up.StatusCode) }
        } catch {
          Send-Json $res 502 @{ error = @{ code = "lemonade_unreachable"; message = "Can't reach Lemonade at $Lemonade" } }
          if (-not $Quiet) { Write-Host "  $($req.HttpMethod) $path -> Lemonade unreachable" -ForegroundColor Yellow }
        }
      } else {
        # Herbie's page files only
        if ($path -eq "/") { $path = "/index.html" }
        $name = [Uri]::UnescapeDataString($path).TrimStart("/")
        $file = [IO.Path]::GetFullPath((Join-Path $root $name))
        $ext = [IO.Path]::GetExtension($file).ToLower()
        if ($file.StartsWith($root + [IO.Path]::DirectorySeparatorChar) -and $types.ContainsKey($ext) -and
            -not [IO.Path]::GetFileName($file).StartsWith(".") -and (Test-Path -LiteralPath $file -PathType Leaf)) {
          Send-Bytes $res 200 $types[$ext] ([IO.File]::ReadAllBytes($file))
        } else {
          Send-Bytes $res 404 "text/plain" ([Text.Encoding]::UTF8.GetBytes("Not found"))
        }
      }
    } catch {
      if (-not $Quiet) { Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red }
      try { $res.StatusCode = 500 } catch { }
    } finally {
      try { $res.Close() } catch { }
    }
  }
} finally {
  $listener.Stop()
  $client.Dispose()
}
