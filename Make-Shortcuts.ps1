# Creates "Herbie" shortcuts on the Desktop and in the Start menu, with Herbie's icon.
# They start Herbie's server with no console window and open Herbie in his own app window.
# Run once:  right-click this file -> Run with PowerShell
$here = [IO.Path]::GetFullPath($PSScriptRoot)
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$shell = New-Object -ComObject WScript.Shell
$places = @(
  [Environment]::GetFolderPath("Desktop"),
  (Join-Path ([Environment]::GetFolderPath("Programs")) "")
)
foreach ($dir in $places) {
  $lnk = $shell.CreateShortcut((Join-Path $dir "Herbie.lnk"))
  $lnk.TargetPath = $ps
  $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$here\serve-herbie.ps1`" -Quiet"
  $lnk.WorkingDirectory = $here
  $lnk.IconLocation = "$here\herbie.ico,0"
  $lnk.WindowStyle = 7
  $lnk.Description = "Herbie: job notes to tickets, on a local AI model"
  $lnk.Save()
  Write-Host "Created $(Join-Path $dir 'Herbie.lnk')"
}
Write-Host ""
Write-Host "To pin Herbie: right-click the Herbie shortcut on your Desktop -> Pin to taskbar."
