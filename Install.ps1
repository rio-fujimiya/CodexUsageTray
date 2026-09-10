$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$startup = [Environment]::GetFolderPath('Startup')
$trayShortcutPath = Join-Path $startup 'CodexUsageTray.lnk'
$relayShortcutPath = Join-Path $startup 'CodexUsageRelay.lnk'
$tokenPath = Join-Path $dest 'relay-token.txt'

# Stop older installed instances before replacing files.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -like '*CodexUsageTray.ps1*' -or
        $_.CommandLine -like '*CodexUsageRelay.ps1*'
    } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 300

New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($name in @(
    'CodexUsageTray.ps1',
    'CodexUsageRelay.ps1',
    'Test-CodexUsage.ps1',
    'Test-Relay.ps1',
    'Start-Ngrok.ps1',
    'Configure-Ngrok.ps1',
    'Uninstall.ps1',
    'README.md'
)) {
    $src = Join-Path $source $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $dest $name) -Force }
}

if (-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    Set-Content -LiteralPath $tokenPath -Value $token -Encoding ASCII -NoNewline
}

$ws = New-Object -ComObject WScript.Shell

$shortcut = $ws.CreateShortcut($trayShortcutPath)
$shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dest 'CodexUsageTray.ps1') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Codex / ChatGPT Work usage tray monitor'
$shortcut.Save()

$shortcut = $ws.CreateShortcut($relayShortcutPath)
$shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dest 'CodexUsageRelay.ps1') + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Local-only relay for Codex usage Android widget'
$shortcut.Save()

$trayScript = Join-Path $dest 'CodexUsageTray.ps1'
$relayScript = Join-Path $dest 'CodexUsageRelay.ps1'
Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $trayScript + '"')
Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $relayScript + '"')

Write-Host ""
Write-Host "Installed/updated to: $dest"
Write-Host "Tray startup:  $trayShortcutPath"
Write-Host "Relay startup: $relayShortcutPath"
Write-Host ""
Write-Host "Android relay token (keep private):"
Write-Host (Get-Content -LiteralPath $tokenPath -Raw)
Write-Host ""
Write-Host "Local test:"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$dest\Test-Relay.ps1`""
Write-Host ""
Write-Host "ngrok next step (after ngrok config add-authtoken):"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$dest\Configure-Ngrok.ps1`" -DevDomain YOUR_ASSIGNED_DOMAIN.ngrok-free.app"
