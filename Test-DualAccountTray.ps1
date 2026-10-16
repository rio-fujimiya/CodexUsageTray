# Offline regression checks: real WinForms and cache files, mocked usage RPC.
param(
    [ValidateSet('DEFAULT', 'ECC')]
    [string]$Account,
    [string]$TestDataRoot,
    [switch]$DuplicateProbe
)

$ErrorActionPreference = 'Stop'

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not $Account) {
    function Test-Launcher {
        $script:Launches = @()
        function Start-Process {
            param($FilePath, $ArgumentList, $WindowStyle)
            $script:Launches += [pscustomobject]@{ File = $FilePath; Arguments = $ArgumentList; Style = $WindowStyle }
        }
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot 'CodexUsageTray.ps1'), [ref]$tokens, [ref]$parseErrors)
        $launchGuard = $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.IfStatementAst] } | Select-Object -First 1
        $launchLoop = $launchGuard.Clauses[0].Item2.Statements[0]
        . ([scriptblock]::Create($launchLoop.Extent.Text))
        Assert-True ($script:Launches.Count -eq 2) 'Launcher did not start two workers.'
        Assert-True ($script:Launches[0].Arguments -like '*-Account DEFAULT') 'DEFAULT launch argument missing.'
        Assert-True ($script:Launches[1].Arguments -like '*-Account ECC') 'ECC launch argument missing.'
        foreach ($launch in $script:Launches) {
            Assert-True ($launch.Style -eq 'Hidden') 'Worker launch is not hidden.'
            Assert-True ($launch.File -eq (Join-Path $PSHOME 'powershell.exe')) 'Unexpected worker executable.'
        }
    }
    Test-Launcher
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexUsageTray-tests-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        foreach ($name in @('DEFAULT', 'ECC')) {
            & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Account $name -TestDataRoot $testRoot
            Assert-True ($LASTEXITCODE -eq 0) "$name worker checks failed."
        }
        $cacheRoot = Join-Path $testRoot 'CodexUsageTray'
        $defaultCache = Get-Content (Join-Path $cacheRoot 'usage-cache.json') -Raw | ConvertFrom-Json
        $eccCache = Get-Content (Join-Path $cacheRoot 'usage-cache-ecc.json') -Raw | ConvertFrom-Json
        Assert-True ($defaultCache.fiveHour.remainingPercent -eq 75) 'DEFAULT cache was overwritten.'
        Assert-True ($eccCache.fiveHour.remainingPercent -eq 25) 'ECC cache did not stay separate.'
        Assert-True (Test-Path (Join-Path $cacheRoot 'state.json')) 'DEFAULT recovery state missing.'
        Assert-True (Test-Path (Join-Path $cacheRoot 'state-ecc.json')) 'ECC recovery state missing.'
        Write-Host 'PASS: launcher, duplicate prevention, account homes, UI labels, HUD positions, cache/state isolation, recovery and errors.'
    } finally {
        # Only remove the exact temporary directory created above.
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        if ((Split-Path -Parent $resolvedTestRoot) -eq $resolvedTemp -and
            (Split-Path -Leaf $resolvedTestRoot) -like 'CodexUsageTray-tests-*') {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
    }
    exit 0
}

# Force a conflicting inherited home to prove each worker selects its own home.
$env:CODEX_HOME = Join-Path $TestDataRoot 'wrong-home'
$env:LOCALAPPDATA = $TestDataRoot

$source = Get-Content (Join-Path $PSScriptRoot 'CodexUsageTray.ps1') -Raw -Encoding UTF8
# Use a test-only mutex namespace so an installed monitor cannot skip the test.
$source = $source.Replace('Local\CodexUsageTray', ('Local\CodexUsageTray-Test-' + (Split-Path -Leaf $TestDataRoot)))
$uiStart = $source.LastIndexOf('$script:Hud.Form.Show()')
Assert-True ($uiStart -gt 0) 'Could not locate UI startup boundary.'
# Initialize the actual worker, functions, UI and event handlers without showing
# windows, calling Codex or entering the permanent WinForms message loop.
. ([scriptblock]::Create($source.Substring(0, $uiStart))) -Account $Account

try {
    Assert-True (-not $DuplicateProbe) 'Duplicate worker passed the mutex guard.'
    # A second process must exit at the actual mutex guard, before reaching UI
    # startup or this assertion. Both account workers are tested separately.
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-DualAccountTray.ps1') -Account $Account -TestDataRoot $TestDataRoot -DuplicateProbe
    Assert-True ($LASTEXITCODE -eq 0) 'Duplicate account monitor was not rejected.'
    $expectedDirectory = if ($Account -eq 'ECC') { '.codex-ecc' } else { '.codex' }
    Assert-True ($env:CODEX_HOME -eq (Join-Path $env:USERPROFILE $expectedDirectory)) 'Incorrect account home.'
    Assert-True ($script:Hud.Form.Text -eq "Codex Usage - $Account") 'HUD title lacks account.'
    Assert-True ($script:Hud.Form.Controls[0].Text -eq $Account) 'HUD account label missing.'
    Assert-True ($menu.Items[0].Text -eq $Account) 'Menu account label missing.'
    Assert-True ($exitItem.Text -eq "Exit $Account") 'Exit action is ambiguous.'
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $offset = if ($Account -eq 'ECC') { $script:Hud.Form.Height + 8 } else { 0 }
    Assert-True ($script:Hud.Form.Top -eq ($wa.Bottom - $script:Hud.Form.Height - 8 - $offset)) 'Incorrect HUD position.'

    foreach ($iconState in @('loading', 'normal', 'exhausted', 'error')) {
        $window = if ($iconState -eq 'loading') { $null } else {
            [pscustomobject]@{ Remaining = $(if ($iconState -eq 'exhausted') { 0 } else { 100 }) }
        }
        $icon = New-UsageIcon $window $window ($iconState -eq 'error')
        $bitmap = $icon.ToBitmap()
        try {
            $pixel = $bitmap.GetPixel(12, 15)
            $isWhiteE = $pixel.A -eq 255 -and $pixel.R -gt 240 -and $pixel.G -gt 240 -and $pixel.B -gt 240
            Assert-True ($isWhiteE -eq ($Account -eq 'ECC')) "Incorrect account E in $iconState state."
            if ($iconState -eq 'normal') {
                $barColor = (Get-GaugeColor $window).ToArgb()
                Assert-True ($bitmap.GetPixel(31, 8).ToArgb() -eq $barColor) '5h gauge is shortened or obscured.'
                Assert-True ($bitmap.GetPixel(31, 24).ToArgb() -eq $barColor) 'Weekly gauge is shortened or obscured.'
                Assert-True ($bitmap.GetPixel(16, 4).ToArgb() -eq $barColor) 'Upper gauge margin is obscured.'
                Assert-True ($bitmap.GetPixel(16, 28).ToArgb() -eq $barColor) 'Lower gauge margin is obscured.'
            }
        } finally {
            $bitmap.Dispose(); $icon.Dispose()
        }
    }

    $script:Remaining = if ($Account -eq 'ECC') { 25 } else { 75 }
    $script:FailRead = $false
    $script:RecoveryNotifications = 0
    function Invoke-CodexRateLimitRead {
        if ($script:FailRead) { throw 'Simulated account read failure' }
        return [pscustomobject]@{ result = [pscustomobject]@{ rateLimits = [pscustomobject]@{
            planType = 'test'
            primary = [pscustomobject]@{ windowDurationMins = 300; usedPercent = (100 - $script:Remaining); resetsAt = 2000000000 }
            secondary = [pscustomobject]@{ windowDurationMins = 10080; usedPercent = 50; resetsAt = 2000000000 }
        } } }
    }
    function Show-RecoveredNotification { param($Usage) $script:RecoveryNotifications++ }

    Update-Usage
    Assert-True (-not $errorItem.Visible) 'Successful read displayed an error.'
    Assert-True ($notify.Text -like "$Account - 5h *") 'Tooltip lacks account or usage.'
    $cache = Get-Content $script:UsageCachePath -Raw | ConvertFrom-Json
    Assert-True ($cache.fiveHour.remainingPercent -eq $script:Remaining) 'Usage cache has incorrect data.'

    $savedRemaining = $script:Remaining
    $script:Remaining = 0
    Update-Usage
    $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
    Assert-True ($state.BlockedBuckets -contains '5h') 'Exhausted quota was not persisted.'
    $script:Remaining = $savedRemaining
    Update-Usage
    Assert-True ($script:RecoveryNotifications -eq 1) 'Quota recovery was not detected exactly once.'

    $cacheBefore = Get-Content $script:UsageCachePath -Raw
    $script:FailRead = $true
    Update-Usage
    Assert-True ($script:LastError -eq 'Simulated account read failure') 'Read failure was not handled.'
    Assert-True ($notify.Text -like "$Account - Usage unavailable*") 'Error tooltip lacks account.'
    Assert-True ((Get-Content $script:UsageCachePath -Raw) -eq $cacheBefore) 'Failed read corrupted cache.'
    Assert-True (-not $script:RefreshInProgress) 'Failed read left refresh locked.'
    $script:FailRead = $false
    Update-Usage
    Assert-True ($script:LastError -eq '') 'Account failed to resume after an error.'
    Write-Host "PASS: $Account"
} finally {
    $timer.Stop(); $timer.Dispose()
    $script:TrayClickTimer.Dispose()
    $notify.Visible = $false; $notify.Dispose()
    foreach ($bar in @($script:Hud.FiveBar, $script:Hud.WeekBar)) {
        if ($bar.Image) { $bar.Image.Dispose() }
    }
    $script:Hud.Form.Dispose()
    $script:Hud.FontLabel.Dispose(); $script:Hud.FontReset.Dispose()
    if ($script:CurrentIcon) { $script:CurrentIcon.Dispose() }
    $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose()
}
