$ErrorActionPreference = 'SilentlyContinue'

$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$scriptPath = Join-Path $dest 'CodexUsageTray.ps1'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'CodexUsageTray.lnk'

Remove-Item $shortcutPath -Force

# Stop only PowerShell processes whose command line contains this exact installed script path.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($scriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Sleep -Milliseconds 300
Remove-Item $dest -Recurse -Force
Write-Host 'CodexUsageTray uninstalled.'
