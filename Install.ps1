$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$startup = [Environment]::GetFolderPath('Startup')
$trayShortcutPath = Join-Path $startup 'CodexUsageTray.lnk'
$relayShortcutPath = Join-Path $startup 'CodexUsageRelay.lnk'
$tokenPath = Join-Path $dest 'relay-token.txt'
$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'

# Stop older installed instances before replacing files.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -like '*CodexUsageTray.ps1*' -or
            $_.CommandLine -like '*CodexUsageRelay.ps1*' -or
            $_.CommandLine -like '*Start-Ngrok.ps1*'
        )
    } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 300

New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($name in @(
    'CodexUsageTray.ps1',
    'CodexUsageRelay.ps1',
    'Test-CodexUsage.ps1',
    'Test-Relay.ps1',
    'Start-Tray.vbs',
    'Start-Relay.vbs',
    'Start-Ngrok.vbs',
    'Start-Ngrok.ps1',
    'Configure-Ngrok.ps1',
    'Uninstall.ps1',
    'README.md'
)) {
    $src = Join-Path $source $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $dest $name) -Force }
}

# VBScript Host can reject UTF-8 BOM as an invalid first character (800A0408).
# Re-write the wrappers explicitly as ASCII/no-BOM after copying.
foreach ($name in @('Start-Tray.vbs','Start-Relay.vbs','Start-Ngrok.vbs')) {
    $src = Join-Path $source $name
    $dst = Join-Path $dest $name
    if (Test-Path -LiteralPath $src) {
        $text = Get-Content -LiteralPath $src -Raw
        [System.IO.File]::WriteAllText($dst, $text, [System.Text.Encoding]::ASCII)
    }
}

if (-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    Set-Content -LiteralPath $tokenPath -Value $token -Encoding ASCII -NoNewline
}

$ws = New-Object -ComObject WScript.Shell

# Important: the startup .lnk launches wscript.exe, not powershell.exe.
# wscript is a GUI subsystem process, so no console window is created at login.
$shortcut = $ws.CreateShortcut($trayShortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = '"' + (Join-Path $dest 'Start-Tray.vbs') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Codex / ChatGPT Work usage tray monitor (silent startup)'
$shortcut.Save()

$shortcut = $ws.CreateShortcut($relayShortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = '"' + (Join-Path $dest 'Start-Relay.vbs') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Local-only relay for Codex usage Android widget (silent startup)'
$shortcut.Save()

# Launch installed components through the exact same no-console path used at login.
Start-Process -FilePath $wscript -ArgumentList ('"' + (Join-Path $dest 'Start-Tray.vbs') + '"') | Out-Null
Start-Process -FilePath $wscript -ArgumentList ('"' + (Join-Path $dest 'Start-Relay.vbs') + '"') | Out-Null

Write-Host ""
Write-Host "Installed/updated to: $dest"
Write-Host "Tray startup:  $trayShortcutPath -> wscript.exe"
Write-Host "Relay startup: $relayShortcutPath -> wscript.exe"
Write-Host ""
Write-Host "Android relay token (keep private):"
Write-Host (Get-Content -LiteralPath $tokenPath -Raw)
Write-Host ""
Write-Host "Local test:"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$dest\Test-Relay.ps1`""
Write-Host ""
Write-Host "ngrok next step (after ngrok config add-authtoken):"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$dest\Configure-Ngrok.ps1`" -DevDomain YOUR_ASSIGNED_DOMAIN.ngrok-free.app"
