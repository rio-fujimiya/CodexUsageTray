# CodexUsageRelay.ps1
# Local-only HTTP relay for CodexUsageTray usage-cache.json.
# Listens ONLY on 127.0.0.1. ngrok proxies this local listener to the WAN endpoint.

param(
    [int]$Port = 8765,
    [string]$CachePath = (Join-Path (Join-Path $env:LOCALAPPDATA 'CodexUsageTray') 'usage-cache.json'),
    [string]$TokenPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'CodexUsageTray') 'relay-token.txt')
)

$ErrorActionPreference = 'Stop'
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\CodexUsageRelay')
if (-not $script:Mutex.WaitOne(0, $false)) { exit 0 }

function Write-HttpResponse {
    param(
        [Parameter(Mandatory=$true)] [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        [string]$Body,
        [string]$ContentType = 'application/json; charset=utf-8',
        [hashtable]$ExtraHeaders = @{}
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $headers = New-Object System.Collections.Generic.List[string]
    [void]$headers.Add("HTTP/1.1 $StatusCode $StatusText")
    [void]$headers.Add("Content-Type: $ContentType")
    [void]$headers.Add("Content-Length: $($bytes.Length)")
    [void]$headers.Add("Cache-Control: no-store")
    [void]$headers.Add("Connection: close")
    [void]$headers.Add("X-Content-Type-Options: nosniff")
    foreach ($k in $ExtraHeaders.Keys) { [void]$headers.Add("$k`: $($ExtraHeaders[$k])") }
    [void]$headers.Add('')
    [void]$headers.Add('')
    $headBytes = [System.Text.Encoding]::ASCII.GetBytes(($headers -join "`r`n"))
    $Stream.Write($headBytes, 0, $headBytes.Length)
    if ($bytes.Length -gt 0) { $Stream.Write($bytes, 0, $bytes.Length) }
    $Stream.Flush()
}

function Write-JsonError {
    param($Stream, [int]$StatusCode, [string]$StatusText, [string]$Code)
    $body = @{ ok = $false; error = $Code } | ConvertTo-Json -Compress
    Write-HttpResponse $Stream $StatusCode $StatusText $body
}

function Get-RelayToken {
    if (-not (Test-Path -LiteralPath $TokenPath)) {
        throw "Relay token file not found: $TokenPath. Re-run Install.ps1."
    }
    $token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token.Length -lt 32) {
        throw "Relay token is missing or too short."
    }
    return $token
}

function Test-Token {
    param([string]$Given, [string]$Expected)
    if ($null -eq $Given -or $null -eq $Expected) { return $false }
    $a = [System.Text.Encoding]::UTF8.GetBytes($Given)
    $b = [System.Text.Encoding]::UTF8.GetBytes($Expected)
    if ($a.Length -ne $b.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $a.Length; $i++) {
        $diff = $diff -bor ($a[$i] -bxor $b[$i])
    }
    return $diff -eq 0
}

function Get-UsageResponseJson {
    if (-not (Test-Path -LiteralPath $CachePath)) {
        throw "usage cache is not ready"
    }
    $cache = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $updated = [long]$cache.updatedAt
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $age = [Math]::Max(0, $now - $updated)

    $out = [ordered]@{
        version = 1
        updatedAt = $updated
        planType = $cache.planType
        fiveHour = $cache.fiveHour
        weekly = $cache.weekly
        cacheAgeSeconds = $age
        stale = ($age -gt 900)
    }
    return ($out | ConvertTo-Json -Depth 6 -Compress)
}

$listener = $null
try {
    $expectedToken = Get-RelayToken
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()

    while ($true) {
        $client = $null
        try {
            $client = $listener.AcceptTcpClient()
            $client.ReceiveTimeout = 5000
            $client.SendTimeout = 5000
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine) -or $requestLine.Length -gt 4096) {
                Write-JsonError $stream 400 'Bad Request' 'bad_request'
                continue
            }

            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 2) {
                Write-JsonError $stream 400 'Bad Request' 'bad_request'
                continue
            }

            $method = $parts[0].ToUpperInvariant()
            $target = $parts[1]
            $headers = @{}
            $headerCount = 0
            $headersInvalid = $false
            while ($true) {
                $line = $reader.ReadLine()
                if ($null -eq $line -or $line -eq '') { break }
                $headerCount++
                if ($headerCount -gt 64 -or $line.Length -gt 8192) {
                    $headersInvalid = $true
                    break
                }
                $idx = $line.IndexOf(':')
                if ($idx -gt 0) {
                    $name = $line.Substring(0, $idx).Trim().ToLowerInvariant()
                    $value = $line.Substring($idx + 1).Trim()
                    $headers[$name] = $value
                }
            }
            if ($headersInvalid) {
                Write-JsonError $stream 431 'Request Header Fields Too Large' 'headers_too_large'
                continue
            }

            if ($method -ne 'GET') {
                Write-JsonError $stream 405 'Method Not Allowed' 'method_not_allowed'
                continue
            }

            $auth = if ($headers.ContainsKey('authorization')) { [string]$headers['authorization'] } else { '' }
            $prefix = 'Bearer '
            $givenToken = if ($auth.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $auth.Substring($prefix.Length).Trim()
            } else { '' }

            if (-not (Test-Token $givenToken $expectedToken)) {
                Write-JsonError $stream 401 'Unauthorized' 'unauthorized'
                continue
            }

            $path = ($target -split '\?', 2)[0]
            switch ($path) {
                '/usage' {
                    try {
                        $body = Get-UsageResponseJson
                        Write-HttpResponse $stream 200 'OK' $body
                    } catch {
                        Write-JsonError $stream 503 'Service Unavailable' 'usage_cache_not_ready'
                    }
                }
                '/health' {
                    $body = @{ ok = $true; relay = 'CodexUsageRelay'; version = '1.0' } | ConvertTo-Json -Compress
                    Write-HttpResponse $stream 200 'OK' $body
                }
                default {
                    Write-JsonError $stream 404 'Not Found' 'not_found'
                }
            }
        } catch {
            # Per-connection failures are intentionally swallowed.
        } finally {
            if ($null -ne $client) { try { $client.Close() } catch {} }
        }
    }
} finally {
    if ($null -ne $listener) { try { $listener.Stop() } catch {} }
    try { $script:Mutex.ReleaseMutex() } catch {}
    try { $script:Mutex.Dispose() } catch {}
}
