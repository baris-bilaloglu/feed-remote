# Creates or removes a Startup folder shortcut that runs feed-remote-helper.ps1 hidden at logon.
# No admin rights needed.
param([switch]$Remove)
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) "Feed Remote.lnk"
if ($Remove) {
    if (Test-Path $lnk) { Remove-Item $lnk -Force }
    Write-Host "Removed: $lnk"
    exit 0
}
$script = Join-Path $PSScriptRoot "feed-remote-helper.ps1"
$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle = 7
$s.Save()
if (Test-Path $lnk) { Write-Host "Feed Remote helper now starts hidden with Windows."; Write-Host $lnk } else { Write-Host "ERROR: shortcut could not be created"; exit 1 }
