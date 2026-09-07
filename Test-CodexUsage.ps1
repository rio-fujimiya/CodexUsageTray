$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'Codex Usage Tray diagnostics'

Write-Host '=== Codex Usage Tray diagnostics ===' -ForegroundColor Cyan
Write-Host ("Time: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))
Write-Host ("PowerShell: " + $PSVersionTable.PSVersion)
Write-Host ("CODEX_HOME: " + $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { '<not set>' }))
Write-Host ''

Write-Host '[1] CLI discovery' -ForegroundColor Cyan
try {
    $paths = & where.exe codex 2>&1
    $paths | ForEach-Object { Write-Host $_ }
    $cmdPaths = & where.exe codex.cmd 2>&1
    $cmdPaths | ForEach-Object { Write-Host $_ }
} catch { Write-Host $_.Exception.Message -ForegroundColor Red }
Write-Host ''

Write-Host '[2] Version' -ForegroundColor Cyan
cmd.exe /d /s /c "codex --version" 2>&1 | ForEach-Object { Write-Host $_ }
Write-Host ''

Write-Host '[3] Login status' -ForegroundColor Cyan
cmd.exe /d /s /c "codex login status" 2>&1 | ForEach-Object { Write-Host $_ }
Write-Host ''

Write-Host '[4] Codex doctor (first lines)' -ForegroundColor Cyan
try {
    cmd.exe /d /s /c "codex doctor" 2>&1 | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
} catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
Write-Host ''

Write-Host '[5] Raw account/rateLimits/read' -ForegroundColor Cyan
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.Arguments = '/d /s /c "codex app-server --stdio"'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

function Read-Response([int]$id, [int]$timeoutMs = 15000) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($proc.HasExited) { throw "app-server exited ($($proc.ExitCode))" }
        $remain = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $task = $proc.StandardOutput.ReadLineAsync()
        if (-not $task.Wait($remain)) { throw "timeout waiting for id=$id" }
        $line = $task.Result
        if ($null -eq $line) { throw 'stdout closed' }
        Write-Host ("stdout> " + $line) -ForegroundColor DarkGray
        try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($null -ne $o.id -and [int]$o.id -eq $id) { return $o }
    }
    throw "timeout waiting for id=$id"
}

try {
    if (-not $proc.Start()) { throw 'Failed to start app-server' }
    $errTask = $proc.StandardError.ReadToEndAsync()

    $proc.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-diagnostic","version":"1.1.0"},"capabilities":{"experimentalApi":true}}}')
    $proc.StandardInput.Flush()
    $init = Read-Response 1
    if ($null -ne $init.error) { Write-Host ("Initialize error: " + ($init.error | ConvertTo-Json -Compress)) -ForegroundColor Red }

    $proc.StandardInput.WriteLine('{"method":"initialized"}')
    $proc.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":null}')
    $proc.StandardInput.Flush()
    $usage = Read-Response 2

    Write-Host ''
    Write-Host 'Parsed usage response:' -ForegroundColor Green
    $usage | ConvertTo-Json -Depth 12 | Write-Host
} catch {
    Write-Host ("RPC ERROR: " + $_.Exception.Message) -ForegroundColor Red
} finally {
    try { $proc.StandardInput.Close() } catch {}
    try { if (-not $proc.HasExited) { & taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null } } catch {}
    try { $proc.WaitForExit(1000) | Out-Null } catch {}
    try {
        if ($null -ne $errTask -and $errTask.Wait(1000)) {
            $e = $errTask.Result.Trim()
            if ($e) { Write-Host ''; Write-Host 'stderr:' -ForegroundColor Yellow; Write-Host $e }
        }
    } catch {}
    try { $proc.Dispose() } catch {}
}

Write-Host ''
Write-Host 'Expected success: login status says ChatGPT sign-in, and step [5] contains result.rateLimits.' -ForegroundColor Cyan
Write-Host 'If step [2] fails: install/update the standalone Codex CLI.'
Write-Host 'If step [3] is signed out or API-key-only: run codex login and choose ChatGPT sign-in.'
Write-Host 'If step [5] fails but [2]/[3] pass: copy this console output; it contains the exact app-server error.'
