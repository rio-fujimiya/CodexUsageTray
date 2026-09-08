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
foreach ($name in @('CodexUsageTray.ps1','Test-CodexUsage.ps1','Uninstall.ps1','README.md','StartHidden.vbs')) {
    $src = Join-Path $source $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $dest $name) -Force }
}

# Login startup goes through wscript.exe so no console window is created.
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
$shortcut.Arguments = '"' + (Join-Path $dest 'StartHidden.vbs') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Codex / ChatGPT Work usage tray monitor'
$shortcut.Save()

# Launch the newly installed instance using the same hidden path.
Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') `
    -ArgumentList ('"' + (Join-Path $dest 'StartHidden.vbs') + '"')

Write-Host "Installed/updated to: $dest"
Write-Host "Startup shortcut: $shortcutPath"
Write-Host "If it still says Usage unavailable, right-click -> Run diagnostics..."
