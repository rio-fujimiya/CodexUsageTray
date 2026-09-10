param(
    [Parameter(Mandatory=$true)]
    [string]$DevDomain
)

$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'CodexUsageNgrok.lnk'
$domainPath = Join-Path $dest 'ngrok-domain.txt'
$startScript = Join-Path $dest 'Start-Ngrok.ps1'

$domain = $DevDomain.Trim().ToLowerInvariant()
$domain = $domain -replace '^https?://', ''
$domain = $domain.TrimEnd('/')
if ($domain.Contains('/')) { throw 'DevDomain must be only a hostname, not a path.' }
if ($domain -notmatch '^[a-z0-9.-]+$') { throw 'Invalid dev domain.' }
if (-not ($domain.EndsWith('.ngrok-free.app') -or $domain.EndsWith('.ngrok.app'))) {
    Write-Warning 'This does not look like an ngrok assigned dev domain. Continuing anyway.'
}

$ngrokCommand = Get-Command ngrok.exe -ErrorAction SilentlyContinue
if ($null -eq $ngrokCommand) { $ngrokCommand = Get-Command ngrok -ErrorAction SilentlyContinue }
if ($null -eq $ngrokCommand) {
    throw 'ngrok was not found in PATH. Install it first: winget install ngrok -s msstore'
}

New-Item -ItemType Directory -Path $dest -Force | Out-Null
Set-Content -LiteralPath $domainPath -Value $domain -Encoding ASCII -NoNewline

$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startScript + '"'
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'ngrok fixed dev domain for Codex usage widget'
$shortcut.Save()

# Restart only this app's ngrok process if it already exists.
Get-CimInstance Win32_Process -Filter "Name='ngrok.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine.Contains('8765') -or $_.CommandLine.Contains($domain)) } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 300

Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden `
    -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startScript + '"')


$tokenPath = Join-Path $dest 'relay-token.txt'
if (Test-Path -LiteralPath $tokenPath) {
    $relayToken = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    $headers = @{
        Authorization = "Bearer $relayToken"
        'ngrok-skip-browser-warning' = '1'
    }
    $online = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-RestMethod -Uri "https://$domain/health" -Headers $headers -TimeoutSec 5
            if ($health.ok -eq $true) { $online = $true; break }
        } catch {}
    }
    if ($online) {
        Write-Host 'WAN health check: OK'
    } else {
        Write-Warning 'WAN health check did not succeed. Check ngrok-error.log and confirm DevDomain is your assigned domain.'
    }
}

Write-Host ''
Write-Host 'ngrok fixed endpoint configured.'
Write-Host "Public URL: https://$domain"
Write-Host "Startup shortcut: $shortcutPath"
Write-Host ''
Write-Host 'Android URL:'
Write-Host "https://$domain"
Write-Host ''
Write-Host 'If the endpoint does not come online, check:'
Write-Host "  $dest\ngrok-error.log"
