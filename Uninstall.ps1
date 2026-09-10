$ErrorActionPreference = 'SilentlyContinue'

$dest = Join-Path $env:LOCALAPPDATA 'CodexUsageTray'
$startup = [Environment]::GetFolderPath('Startup')
Remove-Item (Join-Path $startup 'CodexUsageTray.lnk') -Force
Remove-Item (Join-Path $startup 'CodexUsageRelay.lnk') -Force
Remove-Item (Join-Path $startup 'CodexUsageNgrok.lnk') -Force

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object {
        $_.CommandLine -and (
            $_.CommandLine.IndexOf((Join-Path $dest 'CodexUsageTray.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.CommandLine.IndexOf((Join-Path $dest 'CodexUsageRelay.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.CommandLine.IndexOf((Join-Path $dest 'Start-Ngrok.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Get-CimInstance Win32_Process -Filter "Name='ngrok.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains('8765') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Sleep -Milliseconds 300
Remove-Item $dest -Recurse -Force
Write-Host 'CodexUsageTray + relay + ngrok startup uninstalled.'
