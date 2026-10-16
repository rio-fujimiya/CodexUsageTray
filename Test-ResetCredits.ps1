# Offline reset-credit parsing and HUD text checks. No credentials or RPC.
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'CodexUsageTray.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-PropertyValue', 'Convert-Window', 'Convert-ResetCredits', 'Format-ResetCredits', 'Get-CodexUsage', 'New-Hud')) {
    $definition = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$early = $now + 86400
$late = $now + 172800
$rows = @(
    @{ status = 'available'; expiresAt = $late },
    @{ status = 'available'; expiresAt = $null },
    @{ status = 'available'; expiresAt = $early },
    @{ status = 'consumed'; expiresAt = $now + 60 },
    @{ status = 'available'; expiresAt = $now - 60 }
)
$script:summary = @{ availableCount = 3; credits = $rows }
function Invoke-CodexRateLimitRead {
    [pscustomobject]@{ result = [pscustomobject]@{
        rateLimits = [pscustomobject]@{ primary = $null; secondary = $null; planType = 'pro' }
        rateLimitResetCredits = [pscustomobject]$script:summary
    } }
}
$usage = Get-CodexUsage
$credits = $usage.ResetCredits
Assert ($credits.AvailableCount -eq 3 -and $credits.EarliestExpiresAt -eq $early) 'Wrong count or earliest available expiry.'
Assert $credits.DetailsComplete 'Available detail completeness is incorrect.'
$expected = [DateTimeOffset]::FromUnixTimeSeconds($early).ToLocalTime().ToString('MM/dd HH:mm')
Assert ((Format-ResetCredits $credits -Compact) -eq "R 3 | $expected") 'HUD date is incorrect.'
Assert ((Format-ResetCredits $null) -eq 'Resets: -- | Earliest expiry: --') 'Missing summary must be unknown.'
$countOnly = Convert-ResetCredits ([pscustomobject]@{availableCount = 2; credits = $null})
Assert ((Format-ResetCredits $countOnly -Compact) -eq 'R 2 | --') 'Count-only response must not imply no expiry.'
$empty = Convert-ResetCredits ([pscustomobject]@{availableCount = 0; credits = @()})
Assert ((Format-ResetCredits $empty -Compact) -eq 'R 0 | none') 'Zero response is incorrect.'
$unlimited = Convert-ResetCredits ([pscustomobject]@{availableCount = 1; credits = @(@{status='available'; expiresAt=$null})})
Assert ((Format-ResetCredits $unlimited -Compact) -eq 'R 1 | no expiry') 'Non-expiring response is incorrect.'
$partial = Convert-ResetCredits ([pscustomobject]@{availableCount = 10; credits = @(@{status='available'; expiresAt=$early})})
Assert ((Format-ResetCredits $partial -Compact).EndsWith('*')) 'Capped details must be marked.'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$hud = New-Hud
try {
    foreach ($value in @($credits, $countOnly, $empty, $unlimited, $partial, $null)) {
        $hud.ResetCredits.Text = Format-ResetCredits $value -Compact
        $size = [System.Windows.Forms.TextRenderer]::MeasureText($hud.ResetCredits.Text, $hud.ResetCredits.Font)
        Assert ($size.Width -le $hud.ResetCredits.Width) "HUD text is clipped: $($hud.ResetCredits.Text)"
        Assert ($hud.ResetCredits.Bottom -le $hud.Form.ClientSize.Height) 'HUD row is outside the form.'
    }
} finally {
    $hud.Form.Dispose(); $hud.FontLabel.Dispose(); $hud.FontReset.Dispose()
}
Write-Output 'PASS: response integration, earliest expiry, status/expiry filtering, missing/zero/count-only/non-expiring/capped details.'
