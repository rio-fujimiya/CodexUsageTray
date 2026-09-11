$ErrorActionPreference = 'Stop'

$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$domainPath = Join-Path $dest 'ngrok-domain.txt'
$logPath = Join-Path $dest 'ngrok.log'
$errorLogPath = Join-Path $dest 'ngrok-error.log'

if (-not (Test-Path -LiteralPath $domainPath)) { exit 0 }
$domain = (Get-Content -LiteralPath $domainPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($domain)) { exit 0 }

$ngrokCommand = Get-Command ngrok.exe -ErrorAction SilentlyContinue
if ($null -eq $ngrokCommand) { $ngrokCommand = Get-Command ngrok -ErrorAction SilentlyContinue }
if ($null -eq $ngrokCommand) { exit 0 }
$ngrokExe = $ngrokCommand.Source

$alreadyRunning = Get-CimInstance Win32_Process -Filter "Name='ngrok.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains('8765') } |
    Select-Object -First 1
if ($null -ne $alreadyRunning) { exit 0 }

# Launch ngrok without allocating/inheriting a console window.
# ngrok writes its own logs directly to the file, so no console pipes are needed.
try {
    if (Test-Path -LiteralPath $errorLogPath) { Remove-Item -LiteralPath $errorLogPath -Force -ErrorAction SilentlyContinue }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ngrokExe
    $psi.Arguments = 'http 8765 --log "' + $logPath + '" --log-format json'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $dest

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw 'ngrok process failed to start.' }
} catch {
    $_ | Out-String | Set-Content -LiteralPath $errorLogPath -Encoding UTF8
    exit 1
}
