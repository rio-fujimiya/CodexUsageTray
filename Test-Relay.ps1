param(
    [int]$Port = 8765,
    [string]$TokenPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'CodexUsageTray') 'relay-token.txt')
)
$ErrorActionPreference = 'Stop'
$token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
$headers = @{ Authorization = "Bearer $token" }

Write-Host "GET http://127.0.0.1:$Port/health"
Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -Headers $headers | ConvertTo-Json -Depth 6
Write-Host ""
Write-Host "GET http://127.0.0.1:$Port/usage"
Invoke-RestMethod -Uri "http://127.0.0.1:$Port/usage" -Headers $headers | ConvertTo-Json -Depth 6
