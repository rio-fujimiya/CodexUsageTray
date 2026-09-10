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

Start-Process -FilePath $ngrokExe -WindowStyle Hidden `
    -ArgumentList @('http', '8765', '--log', 'stdout', '--log-format', 'json') `
    -RedirectStandardOutput $logPath -RedirectStandardError $errorLogPath
