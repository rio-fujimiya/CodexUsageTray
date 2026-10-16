# Offline WinForms regression checks; no monitor, credentials or RPC are started.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Send-MouseEvent($Control, [string]$Event, $Button, [System.Drawing.Point]$ScreenPoint) {
    $local = $Control.PointToClient($ScreenPoint)
    $mouseArgs = [System.Windows.Forms.MouseEventArgs]::new($Button, 1, $local.X, $local.Y, 0)
    $method = [System.Windows.Forms.Control].GetMethod(
        ('On' + $Event), [Reflection.BindingFlags]'Instance,NonPublic')
    [void]$method.Invoke($Control, @($mouseArgs))
}

$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'CodexUsageTray.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Tray script has syntax errors.'
$function = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-Hud'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))
# Also exercises the account label when run on the dual-account branch.
$Account = 'ECC'
$script:Hud = New-Hud
$script:HudMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$form = $script:Hud.Form
$left = [System.Windows.Forms.MouseButtons]::Left
$right = [System.Windows.Forms.MouseButtons]::Right
try {
    foreach ($control in @($form) + @($form.Controls)) {
        $form.Show()
        $script:HudMenuItem.Checked = $true
        $start = $control.PointToScreen([System.Drawing.Point]::new(2, 2))
        $origin = $form.Location
        Send-MouseEvent $control MouseDown $left $start
        Assert-True ($form.Visible -and $control.Capture) 'Mouse down hid the HUD or failed to capture.'
        # First move remains within the system drag threshold.
        $jitter = [System.Drawing.Point]::new(($start.X + 1), $start.Y)
        Send-MouseEvent $control MouseMove $left $jitter
        Assert-True ($form.Location -eq $origin) 'Small click movement moved the HUD.'
        $destination = [System.Drawing.Point]::new(($start.X - 60), ($start.Y - 30))
        Send-MouseEvent $control MouseMove $left $destination
        Assert-True ($form.Left -eq ($origin.X - 60) -and $form.Top -eq ($origin.Y - 30)) 'Drag displacement is incorrect.'
        # A second move must keep the original grab offset as the form moves.
        $destination = [System.Drawing.Point]::new(($start.X - 80), ($start.Y - 40))
        Send-MouseEvent $control MouseMove $left $destination
        Send-MouseEvent $control MouseUp $left $destination
        Assert-True ($form.Left -eq ($origin.X - 80) -and $form.Top -eq ($origin.Y - 40)) 'Repeated drag jumped.'
        Assert-True ($form.Visible -and $script:HudMenuItem.Checked -and -not $control.Capture) 'Drag release hid the HUD or retained capture.'

        $start = $control.PointToScreen([System.Drawing.Point]::new(2, 2))
        Send-MouseEvent $control MouseDown $left $start
        Send-MouseEvent $control MouseUp $left $start
        Assert-True (-not $form.Visible -and -not $script:HudMenuItem.Checked) 'Click did not hide HUD and uncheck menu.'
    }

    $form.Show()
    $script:HudMenuItem.Checked = $true
    $start = $form.PointToScreen([System.Drawing.Point]::new(2, 2))
    Send-MouseEvent $form MouseDown $right $start
    Send-MouseEvent $form MouseUp $right $start
    Assert-True ($form.Visible -and $null -eq $script:HudDrag) 'Right click started a drag or hid HUD.'
    Send-MouseEvent $form MouseDown $left $start
    $form.Capture = $false
    $origin = $form.Location
    Send-MouseEvent $form MouseMove $left ([System.Drawing.Point]::new(($start.X + 80), $start.Y))
    Send-MouseEvent $form MouseUp $left $start
    Assert-True ($null -eq $script:HudDrag -and $form.Location -eq $origin -and $form.Visible) 'Capture loss did not cancel the gesture.'
    Write-Host 'PASS: HUD background/labels/gauges drag, click-to-hide, right click and capture loss.'
} finally {
    $form.Dispose()
    $script:Hud.FontLabel.Dispose(); $script:Hud.FontReset.Dispose()
    $script:HudMenuItem.Dispose()
}
