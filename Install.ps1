$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'CodexUsageTray.lnk'

# Stop an older installed instance before replacing files.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*CodexUsageTray.ps1*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 300

New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($name in @('CodexUsageTray.ps1','Test-CodexUsage.ps1','Uninstall.ps1','README.md')) {
    $src = Join-Path $source $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $dest $name) -Force }
}

$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dest 'CodexUsageTray.ps1') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Codex / ChatGPT Work usage tray monitor'
$shortcut.Save()

$trayScript = Join-Path $dest 'CodexUsageTray.ps1'
$launchArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $trayScript + '"'
Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList $launchArgs

Write-Host "Installed/updated to: $dest"
Write-Host "Startup shortcut: $shortcutPath"
Write-Host "If it still says Usage unavailable, right-click -> Run diagnostics..."
