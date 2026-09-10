# CodexUsageTray.ps1
# Windows notification-area monitor for ChatGPT Work / Codex shared agentic usage.
# v2.0 ngrok - v1.8 UI plus usage-cache.json export for the local WAN relay.

$ErrorActionPreference = 'Stop'
$RefreshSeconds = 60
$RpcTimeoutMs = 15000

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('CodexUsageTray.NativeMethods' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace CodexUsageTray {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }
}
"@
}

$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\CodexUsageTray')
if (-not $script:Mutex.WaitOne(0, $false)) { exit 0 }

$script:RefreshInProgress = $false
$script:CurrentIcon = $null
$script:LastError = ''
$script:StatePath = Join-Path (Join-Path $env:LOCALAPPDATA 'CodexUsageTray') 'state.json'
$script:UsageCachePath = Join-Path (Join-Path $env:LOCALAPPDATA 'CodexUsageTray') 'usage-cache.json'
$script:RecoveryState = $null

$script:TrayClickTimer = $null

function Open-ChatGPTApp {
    # Use the exact Start-menu shortcut target supplied by the user.
    # This is an AppUserModelId (AUMID), so launch it through shell:AppsFolder.
    $appId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $appId) -ErrorAction Stop | Out-Null
        return
    } catch {
        try {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open the configured ChatGPT app shortcut.`r`n`r`nTarget: $appId",
                'Codex Usage Tray'
            ) | Out-Null
        } catch {}
    }
}

function Get-CodexCommandLine {
    # Prefer the npm Windows shim, then a native exe.  cmd.exe can execute both.
    $cmd = Get-Command codex.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
        return '"' + $cmd.Source + '"'
    }

    $exe = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $exe) {
        return '"' + $exe.Source + '"'
    }

    # Last chance: cmd.exe PATHEXT resolution.
    $where = & where.exe codex 2>$null | Select-Object -First 1
    if ($where) {
        return '"' + $where + '"'
    }

    throw "Codex CLI was not found. Run 'codex.cmd --version'. If missing, install @openai/codex and sign in."
}

function Send-RpcMessage {
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [Parameter(Mandatory = $true)] [hashtable] $Message
    )
    $json = $Message | ConvertTo-Json -Compress -Depth 12
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
}

function Wait-RpcResponse {
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [Parameter(Mandatory = $true)] [int] $Id,
        [int] $TimeoutMs = $RpcTimeoutMs
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            throw "Codex app-server exited before response id=$Id (exit $($Process.ExitCode))."
        }

        $remaining = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $readTask = $Process.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait($remaining)) {
            throw "Timed out waiting for Codex app-server response id=$Id."
        }

        $line = $readTask.Result
        if ($null -eq $line) { throw 'Codex app-server closed stdout.' }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try { $obj = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }

        if ($null -ne $obj.id -and [int]$obj.id -eq $Id) {
            if ($null -ne $obj.error) {
                $message = if ($obj.error.message) { $obj.error.message } else { ($obj.error | ConvertTo-Json -Compress -Depth 8) }
                throw "Codex RPC error: $message"
            }
            return $obj
        }
    }
    throw "Timed out waiting for RPC response id=$Id."
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            # taskkill handles cmd.exe + codex child reliably on Windows PowerShell 5.1.
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    } catch {
        try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
    }
}

function Invoke-CodexRateLimitRead {
    $codex = Get-CodexCommandLine
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + $codex + ' app-server --stdio"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw 'Failed to start Codex app-server.' }

    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $response = $null
    $caught = $null

    try {
        # Match the current Codex App Server README examples exactly: no jsonrpc field,
        # initialized notification without params, and params:null for rateLimits/read.
        Send-RpcMessage $proc @{
            id = 1
            method = 'initialize'
            params = @{
                clientInfo = @{ name = 'codex-usage-tray'; version = '1.8.0' }
                capabilities = @{ experimentalApi = $true }
            }
        }
        [void](Wait-RpcResponse $proc 1)

        Send-RpcMessage $proc @{
            method = 'initialized'
        }

        Send-RpcMessage $proc @{
            id = 2
            method = 'account/rateLimits/read'
            params = $null
        }
        $response = Wait-RpcResponse $proc 2
    }
    catch {
        $caught = $_.Exception
    }
    finally {
        try { $proc.StandardInput.Close() } catch {}
        Stop-ProcessTree $proc
        try { $proc.WaitForExit(1000) | Out-Null } catch {}
    }

    $stderr = ''
    try {
        if ($stderrTask.Wait(1000)) { $stderr = $stderrTask.Result.Trim() }
    } catch {}
    try { $proc.Dispose() } catch {}

    if ($null -ne $caught) {
        $detail = $caught.Message
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            $tail = ($stderr -split "`r?`n" | Select-Object -Last 4) -join ' | '
            if ($tail.Length -gt 400) { $tail = $tail.Substring(0, 400) }
            $detail += " | stderr: $tail"
        }
        throw $detail
    }

    return $response
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Convert-Window {
    param($Window)
    if ($null -eq $Window) { return $null }
    $mins = Get-PropertyValue $Window 'windowDurationMins'
    $used = Get-PropertyValue $Window 'usedPercent'
    $reset = Get-PropertyValue $Window 'resetsAt'
    if ($null -eq $mins -or $null -eq $used) { return $null }

    $remaining = 100.0 - [double]$used
    $remaining = [Math]::Max(0.0, [Math]::Min(100.0, $remaining))
    [pscustomobject]@{
        Minutes = [int]$mins
        Remaining = [int][Math]::Round($remaining)
        ResetsAt = if ($null -ne $reset) { [long]$reset } else { $null }
    }
}

function Get-CodexUsage {
    $response = Invoke-CodexRateLimitRead
    $result = $response.result
    if ($null -eq $result) { throw 'account/rateLimits/read returned no result.' }

    $limits = Get-PropertyValue $result 'rateLimits'
    $byId = Get-PropertyValue $result 'rateLimitsByLimitId'
    if ($null -ne $byId) {
        $codexProp = $byId.PSObject.Properties['codex']
        if ($null -ne $codexProp -and $null -ne $codexProp.Value) { $limits = $codexProp.Value }
    }
    if ($null -eq $limits) {
        throw "No general Codex rate-limit bucket was returned. Make sure Codex CLI is signed in with ChatGPT, not only an API key."
    }

    $five = $null
    $week = $null
    foreach ($slot in @('primary', 'secondary')) {
        $window = Convert-Window (Get-PropertyValue $limits $slot)
        if ($null -eq $window) { continue }
        switch ($window.Minutes) {
            300   { $five = $window }
            10080 { $week = $window }
        }
    }

    [pscustomobject]@{
        FiveHour = $five
        Weekly = $week
        PlanType = Get-PropertyValue $limits 'planType'
        UpdatedAt = Get-Date
    }
}

function Format-ResetTime {
    param($Window, [switch]$IncludeDate)
    if ($null -eq $Window -or $null -eq $Window.ResetsAt) { return '--' }
    try {
        $local = [DateTimeOffset]::FromUnixTimeSeconds([long]$Window.ResetsAt).ToLocalTime()
        if ($IncludeDate) { return $local.ToString('M/d HH:mm') }
        return $local.ToString('HH:mm')
    } catch { return '--' }
}

function Format-HudReset {
    param($Window)
    if ($null -eq $Window -or $null -eq $Window.ResetsAt) { return '--/--' }
    try {
        $local = [DateTimeOffset]::FromUnixTimeSeconds([long]$Window.ResetsAt).ToLocalTime()
        $now = [DateTimeOffset]::Now
        if ($local.Date -eq $now.Date) { return $local.ToString('HH:mm') }
        return $local.ToString('MM/dd')
    } catch { return '--/--' }
}


function Save-UsageCache {
    param($Usage)

    function Convert-CacheWindow {
        param($Window)
        if ($null -eq $Window) { return $null }
        return [ordered]@{
            windowMinutes = [int]$Window.Minutes
            remainingPercent = [int]$Window.Remaining
            resetsAt = if ($null -ne $Window.ResetsAt) { [long]$Window.ResetsAt } else { $null }
        }
    }

    try {
        $dir = Split-Path -Parent $script:UsageCachePath
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $payload = [ordered]@{
            version = 1
            updatedAt = [DateTimeOffset]::Now.ToUnixTimeSeconds()
            planType = $Usage.PlanType
            fiveHour = (Convert-CacheWindow $Usage.FiveHour)
            weekly = (Convert-CacheWindow $Usage.Weekly)
        }

        $tmp = $script:UsageCachePath + '.tmp'
        $payload | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:UsageCachePath -Force
    } catch {
        # Cache export must never break the tray UI.
    }
}

function Load-RecoveryState {
    $default = [pscustomobject]@{ Initialized = $false; BlockedBuckets = @() }
    if (-not (Test-Path $script:StatePath)) { return $default }
    try {
        $raw = Get-Content -LiteralPath $script:StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $blocked = @()
        if ($null -ne $raw.BlockedBuckets) { $blocked = @($raw.BlockedBuckets) }
        return [pscustomobject]@{ Initialized = $true; BlockedBuckets = $blocked }
    } catch {
        return $default
    }
}

function Save-RecoveryState {
    param([string[]]$BlockedBuckets)
    try {
        $dir = Split-Path -Parent $script:StatePath
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [pscustomobject]@{
            Version = 1
            BlockedBuckets = @($BlockedBuckets)
            UpdatedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    } catch {}
}

function Format-Remaining {
    param($Window)
    if ($null -eq $Window) { return '--' }
    return [string]$Window.Remaining
}

function Get-GaugeColor {
    param($Window, [bool]$HasError = $false)
    if ($HasError) { return [System.Drawing.Color]::FromArgb(214, 82, 82) }
    if ($null -eq $Window) { return [System.Drawing.Color]::FromArgb(115, 122, 130) }
    $r = [int]$Window.Remaining
    if ($r -ge 50) { return [System.Drawing.Color]::FromArgb(74, 190, 116) }
    if ($r -ge 20) { return [System.Drawing.Color]::FromArgb(232, 177, 72) }
    return [System.Drawing.Color]::FromArgb(220, 86, 86)
}

function Draw-GaugeBar {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        $Window,
        [bool]$HasError = $false
    )
    $track = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(55, 60, 66))
    $fill = New-Object System.Drawing.SolidBrush (Get-GaugeColor $Window $HasError)
    $xPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235, 70, 70)), ([Math]::Max(2, [int][Math]::Round($Height / 5.0)))
    try {
        $Graphics.FillRectangle($track, $X, $Y, $Width, $Height)

        if ($HasError) {
            # Error state: use a red X instead of pretending the quota is full/empty.
            $pad = [Math]::Max(2, [int][Math]::Round($Height * 0.18))
            $Graphics.DrawLine($xPen, $X + $pad, $Y + $pad, $X + $Width - $pad - 1, $Y + $Height - $pad - 1)
            $Graphics.DrawLine($xPen, $X + $Width - $pad - 1, $Y + $pad, $X + $pad, $Y + $Height - $pad - 1)
            return
        }

        if ($null -eq $Window) { return }

        $remaining = [int]$Window.Remaining
        if ($remaining -le 0) {
            # Exhausted bucket: a red X is much more legible than a one-pixel red bar.
            $pad = [Math]::Max(2, [int][Math]::Round($Height * 0.18))
            $Graphics.DrawLine($xPen, $X + $pad, $Y + $pad, $X + $Width - $pad - 1, $Y + $Height - $pad - 1)
            $Graphics.DrawLine($xPen, $X + $Width - $pad - 1, $Y + $pad, $X + $pad, $Y + $Height - $pad - 1)
            return
        }

        $pixels = [int][Math]::Round($Width * ([double]$remaining / 100.0))
        $pixels = [Math]::Max(1, [Math]::Min($Width, $pixels))
        $Graphics.FillRectangle($fill, $X, $Y, $pixels, $Height)
    } finally {
        $track.Dispose(); $fill.Dispose(); $xPen.Dispose()
    }
}
function New-UsageIcon {
    param($FiveHour, $Weekly, [bool]$HasError = $false)

    # The tray icon is tiny, so use only two edge-to-edge bars:
    # top = 5h, bottom = weekly. No surrounding frame/border.
    # A bucket at 0% is rendered as a red X across that row.
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    try {
        Draw-GaugeBar $g 0 2 32 12 $FiveHour $HasError
        Draw-GaugeBar $g 0 18 32 12 $Weekly $HasError
    } finally {
        $g.Dispose()
    }

    $hIcon = $bmp.GetHicon()
    $icon = ([System.Drawing.Icon]::FromHandle($hIcon)).Clone()
    [void][CodexUsageTray.NativeMethods]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}
function New-Hud {
    # Windows notification-area icons are tiny. This frameless window sits just
    # above the tray and acts as a readable extended icon:
    # 5h [quota bar + percentage] HH:mm when reset is today, otherwise MM/dd
    # W  [quota bar + percentage] HH:mm when reset is today, otherwise MM/dd
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Codex Usage'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.BackColor = [System.Drawing.Color]::FromArgb(31, 34, 38)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.ClientSize = New-Object System.Drawing.Size(228, 54)
    $form.Opacity = 0.84

    $fontLabel = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $fontReset = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

    $fiveLabel = New-Object System.Windows.Forms.Label
    $fiveLabel.Text = '5h'; $fiveLabel.Font = $fontLabel
    $fiveLabel.ForeColor = [System.Drawing.Color]::FromArgb(230, 232, 235)
    $fiveLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $fiveLabel.Location = New-Object System.Drawing.Point(8, 5)
    $fiveLabel.Size = New-Object System.Drawing.Size(28, 20)

    # PictureBox lets us paint the bar and percentage into one bitmap, so the
    # text is truly overlaid on top of the fill instead of hiding it.
    $fiveBar = New-Object System.Windows.Forms.PictureBox
    $fiveBar.BackColor = [System.Drawing.Color]::FromArgb(55, 60, 66)
    $fiveBar.Location = New-Object System.Drawing.Point(38, 8)
    $fiveBar.Size = New-Object System.Drawing.Size(126, 14)
    $fiveBar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal

    $fiveReset = New-Object System.Windows.Forms.Label
    $fiveReset.Text = '--:--'; $fiveReset.Font = $fontReset
    $fiveReset.ForeColor = [System.Drawing.Color]::FromArgb(230, 232, 235)
    $fiveReset.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $fiveReset.Location = New-Object System.Drawing.Point(169, 4)
    $fiveReset.Size = New-Object System.Drawing.Size(51, 21)

    $weekLabel = New-Object System.Windows.Forms.Label
    $weekLabel.Text = 'W'; $weekLabel.Font = $fontLabel
    $weekLabel.ForeColor = [System.Drawing.Color]::FromArgb(230, 232, 235)
    $weekLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $weekLabel.Location = New-Object System.Drawing.Point(8, 29)
    $weekLabel.Size = New-Object System.Drawing.Size(28, 20)

    $weekBar = New-Object System.Windows.Forms.PictureBox
    $weekBar.BackColor = [System.Drawing.Color]::FromArgb(55, 60, 66)
    $weekBar.Location = New-Object System.Drawing.Point(38, 32)
    $weekBar.Size = New-Object System.Drawing.Size(126, 14)
    $weekBar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal

    $weekReset = New-Object System.Windows.Forms.Label
    $weekReset.Text = '--/--'; $weekReset.Font = $fontReset
    $weekReset.ForeColor = [System.Drawing.Color]::FromArgb(230, 232, 235)
    $weekReset.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $weekReset.Location = New-Object System.Drawing.Point(169, 28)
    $weekReset.Size = New-Object System.Drawing.Size(51, 21)

    [void]$form.Controls.AddRange(@(
        $fiveLabel, $fiveBar, $fiveReset,
        $weekLabel, $weekBar, $weekReset
    ))

    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(($wa.Right - $form.Width - 8), ($wa.Bottom - $form.Height - 8))

    # A left-button press anywhere on the HUD hides it immediately.
    $hideHudNow = {
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try {
                if ($null -ne $script:Hud -and $null -ne $script:Hud.Form) {
                    $script:Hud.Form.Hide()
                }
                if ($null -ne $script:HudMenuItem) {
                    $script:HudMenuItem.Checked = $false
                }
            } catch {}
        }
    }
    $form.add_MouseDown($hideHudNow)
    foreach ($c in @($fiveLabel, $fiveBar, $fiveReset, $weekLabel, $weekBar, $weekReset)) {
        $c.add_MouseDown($hideHudNow)
    }

    [pscustomobject]@{
        Form = $form
        FiveReset = $fiveReset
        FiveBar = $fiveBar
        WeekReset = $weekReset
        WeekBar = $weekBar
        FontLabel = $fontLabel
        FontReset = $fontReset
    }
}

function Set-HudWindow {
    param(
        [System.Windows.Forms.PictureBox]$Bar,
        $Window,
        [bool]$HasError = $false
    )

    if ($null -eq $Bar) { return }

    $w = [Math]::Max(1, $Bar.ClientSize.Width)
    $h = [Math]::Max(1, $Bar.ClientSize.Height)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $trackBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(55, 60, 66))
    $fillBrush = New-Object System.Drawing.SolidBrush (Get-GaugeColor $Window $HasError)
    $xPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235, 70, 70)), 2
    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 0, 0, 0))
    $font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    try {
        $g.FillRectangle($trackBrush, 0, 0, $w, $h)

        $text = '--%'
        if ($HasError) {
            $text = 'ERR'
            $pad = 2
            $g.DrawLine($xPen, $pad, $pad, $w - $pad - 1, $h - $pad - 1)
            $g.DrawLine($xPen, $w - $pad - 1, $pad, $pad, $h - $pad - 1)
        } elseif ($null -ne $Window) {
            $remaining = [int]$Window.Remaining
            $text = "$remaining%"
            if ($remaining -le 0) {
                $pad = 2
                $g.DrawLine($xPen, $pad, $pad, $w - $pad - 1, $h - $pad - 1)
                $g.DrawLine($xPen, $w - $pad - 1, $pad, $pad, $h - $pad - 1)
            } else {
                $pixels = [int][Math]::Round($w * ([double]$remaining / 100.0))
                $pixels = [Math]::Max(1, [Math]::Min($w, $pixels))
                $g.FillRectangle($fillBrush, 0, 0, $pixels, $h)
            }
        }

        # Tiny shadow keeps the overlaid percentage readable on green/amber/red fills.
        $rectShadow = New-Object System.Drawing.RectangleF 1, 1, $w, $h
        $rectText = New-Object System.Drawing.RectangleF 0, 0, $w, $h
        $g.DrawString($text, $font, $shadowBrush, $rectShadow, $format)
        $g.DrawString($text, $font, $textBrush, $rectText, $format)
    } finally {
        $g.Dispose()
        $trackBrush.Dispose(); $fillBrush.Dispose(); $xPen.Dispose()
        $textBrush.Dispose(); $shadowBrush.Dispose(); $font.Dispose(); $format.Dispose()
    }

    $old = $Bar.Image
    $Bar.Image = $bmp
    if ($null -ne $old) { try { $old.Dispose() } catch {} }
}
$script:Hud = New-Hud

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Text = 'Codex usage: loading...'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = '5h --% | W --%'; $statusItem.Enabled = $false
[void]$menu.Items.Add($statusItem)

$fiveResetItem = New-Object System.Windows.Forms.ToolStripMenuItem
$fiveResetItem.Text = '5h reset: --'; $fiveResetItem.Enabled = $false
[void]$menu.Items.Add($fiveResetItem)

$weekResetItem = New-Object System.Windows.Forms.ToolStripMenuItem
$weekResetItem.Text = 'W reset: --'; $weekResetItem.Enabled = $false
[void]$menu.Items.Add($weekResetItem)

$updatedItem = New-Object System.Windows.Forms.ToolStripMenuItem
$updatedItem.Text = 'Updated: --'; $updatedItem.Enabled = $false
[void]$menu.Items.Add($updatedItem)

$errorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$errorItem.Text = 'Error: none'; $errorItem.Enabled = $false; $errorItem.Visible = $false
[void]$menu.Items.Add($errorItem)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$hudItem = New-Object System.Windows.Forms.ToolStripMenuItem
$hudItem.Text = 'Show extended tray HUD'; $hudItem.Checked = $true; $hudItem.CheckOnClick = $true
$script:HudMenuItem = $hudItem
[void]$menu.Items.Add($hudItem)

$refreshItem = New-Object System.Windows.Forms.ToolStripMenuItem
$refreshItem.Text = 'Refresh now'; [void]$menu.Items.Add($refreshItem)

$diagnosticItem = New-Object System.Windows.Forms.ToolStripMenuItem
$diagnosticItem.Text = 'Run diagnostics...'; [void]$menu.Items.Add($diagnosticItem)

$copyErrorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$copyErrorItem.Text = 'Copy last error'; $copyErrorItem.Enabled = $false
[void]$menu.Items.Add($copyErrorItem)

$openUsageItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openUsageItem.Text = 'Open ChatGPT usage'; [void]$menu.Items.Add($openUsageItem)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = 'Exit'; [void]$menu.Items.Add($exitItem)
$notify.ContextMenuStrip = $menu

function Set-TrayIcon {
    param($FiveHour, $Weekly, [bool]$HasError = $false)
    $newIcon = New-UsageIcon $FiveHour $Weekly $HasError
    $oldIcon = $script:CurrentIcon
    $script:CurrentIcon = $newIcon
    $notify.Icon = $newIcon
    if ($null -ne $oldIcon) { try { $oldIcon.Dispose() } catch {} }
}

function Show-RecoveredNotification {
    param($Usage)
    try {
        $five = Format-Remaining $Usage.FiveHour
        $week = Format-Remaining $Usage.Weekly
        $notify.BalloonTipTitle = 'Work / Codex is available again'
        $notify.BalloonTipText = "Usage limit reset. 5h $five% | W $week%"
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notify.ShowBalloonTip(7000)
    } catch {}
}

function Update-RecoveryState {
    param($Usage)

    if ($null -eq $script:RecoveryState) {
        $script:RecoveryState = Load-RecoveryState
    }

    $current = @{
        '5h' = $Usage.FiveHour
        'W'  = $Usage.Weekly
    }
    $previousBlocked = @($script:RecoveryState.BlockedBuckets)
    $blockedNow = New-Object System.Collections.Generic.List[string]

    # A reported window at 0% blocks use. If a window that was previously blocking
    # disappears from the API, keep it blocked/unknown instead of falsely announcing recovery.
    foreach ($name in @('5h', 'W')) {
        $window = $current[$name]
        if ($null -ne $window -and [int]$window.Remaining -le 0) {
            [void]$blockedNow.Add($name)
        } elseif ($null -eq $window -and $previousBlocked -contains $name) {
            [void]$blockedNow.Add($name)
        }
    }

    $recovered = $false
    if ($script:RecoveryState.Initialized -and $previousBlocked.Count -gt 0) {
        $allPreviousBlockersRecovered = $true
        foreach ($name in $previousBlocked) {
            $window = $current[$name]
            if ($null -eq $window -or [int]$window.Remaining -le 0) {
                $allPreviousBlockersRecovered = $false
                break
            }
        }
        if ($allPreviousBlockersRecovered -and $blockedNow.Count -eq 0) {
            $recovered = $true
        }
    }

    $script:RecoveryState = [pscustomobject]@{
        Initialized = $true
        BlockedBuckets = @($blockedNow.ToArray())
    }
    Save-RecoveryState -BlockedBuckets $script:RecoveryState.BlockedBuckets

    if ($recovered) { Show-RecoveredNotification $Usage }
}

function Update-Usage {
    if ($script:RefreshInProgress) { return }
    $script:RefreshInProgress = $true
    try {
        $usage = Get-CodexUsage
        $fiveText = Format-Remaining $usage.FiveHour
        $weekText = Format-Remaining $usage.Weekly
        $statusItem.Text = "5h $fiveText% | W $weekText%"
        $fiveResetItem.Text = "5h reset: $(Format-ResetTime $usage.FiveHour)"
        $weekResetItem.Text = "W reset: $(Format-ResetTime $usage.Weekly -IncludeDate)"
        $updatedItem.Text = "Updated: $($usage.UpdatedAt.ToString('HH:mm:ss'))"
        $errorItem.Visible = $false
        $copyErrorItem.Enabled = $false
        $script:LastError = ''
        $tip = "5h $fiveText% | W $weekText%"
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $notify.Text = $tip
        Set-HudWindow $script:Hud.FiveBar $usage.FiveHour $false
        Set-HudWindow $script:Hud.WeekBar $usage.Weekly $false
        $script:Hud.FiveReset.Text = Format-HudReset $usage.FiveHour
        $script:Hud.WeekReset.Text = Format-HudReset $usage.Weekly
        Set-TrayIcon $usage.FiveHour $usage.Weekly $false
        Update-RecoveryState $usage
        Save-UsageCache $usage
    }
    catch {
        $message = $_.Exception.Message
        $script:LastError = $message
        $statusItem.Text = 'Usage unavailable'
        $fiveResetItem.Text = '5h reset: --'
        $weekResetItem.Text = 'W reset: --'
        $updatedItem.Text = "Failed: $(Get-Date -Format 'HH:mm:ss')"
        $short = $message
        if ($short.Length -gt 180) { $short = $short.Substring(0, 177) + '...' }
        $errorItem.Text = "Error: $short"
        $errorItem.Visible = $true
        $copyErrorItem.Enabled = $true
        $notify.Text = 'Codex usage unavailable - right-click for error'
        Set-HudWindow $script:Hud.FiveBar $null $true
        Set-HudWindow $script:Hud.WeekBar $null $true
        $script:Hud.FiveReset.Text = 'ERR'
        $script:Hud.WeekReset.Text = 'ERR'
        Set-TrayIcon $null $null $true
    }
    finally { $script:RefreshInProgress = $false }
}

$hudItem.add_CheckedChanged({
    try {
        if ($null -eq $script:HudMenuItem -or $null -eq $script:Hud -or $null -eq $script:Hud.Form) { return }
        if ($script:HudMenuItem.Checked) { $script:Hud.Form.Show() } else { $script:Hud.Form.Hide() }
    } catch {}
})
$refreshItem.add_Click({ Update-Usage })

# Single left-click toggles the HUD, but defer the action long enough to let a
# double-click cancel it. This prevents a double-click from briefly hiding/showing
# the HUD before ChatGPT opens.
$script:TrayClickTimer = New-Object System.Windows.Forms.Timer
$script:TrayClickTimer.Interval = [Math]::Max(180, [System.Windows.Forms.SystemInformation]::DoubleClickTime + 40)
$script:TrayClickTimer.add_Tick({
    $script:TrayClickTimer.Stop()
    try {
        if ($null -ne $script:HudMenuItem) {
            $script:HudMenuItem.Checked = -not $script:HudMenuItem.Checked
        }
    } catch {}
})
$notify.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:TrayClickTimer.Stop()
        $script:TrayClickTimer.Start()
    }
})
$notify.add_MouseDoubleClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:TrayClickTimer.Stop()
        Open-ChatGPTApp
    }
})
$copyErrorItem.add_Click({
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:LastError)) {
            [System.Windows.Forms.Clipboard]::SetText($script:LastError)
        }
    } catch {}
})
$diagnosticItem.add_Click({
    try {
        $diag = Join-Path $PSScriptRoot 'Test-CodexUsage.ps1'
        if (Test-Path $diag) {
            $args = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "' + $diag + '"'
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args
        } else {
            [System.Windows.Forms.MessageBox]::Show('Test-CodexUsage.ps1 was not found.', 'Codex Usage Tray') | Out-Null
        }
    } catch {}
})
$openUsageItem.add_Click({ try { Start-Process 'https://chatgpt.com/codex/settings/usage' } catch {} })
$exitItem.add_Click({ [System.Windows.Forms.Application]::Exit() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(60, $RefreshSeconds) * 1000
$timer.add_Tick({ Update-Usage })
$timer.Start()

Set-TrayIcon $null $null $false
$script:Hud.Form.Show()
Update-Usage
try { [System.Windows.Forms.Application]::Run() }
finally {
    $timer.Stop(); $timer.Dispose()
    if ($null -ne $script:TrayClickTimer) { try { $script:TrayClickTimer.Stop(); $script:TrayClickTimer.Dispose() } catch {} }
    $notify.Visible = $false; $notify.Dispose()
    try { if ($null -ne $script:Hud.FiveBar.Image) { $script:Hud.FiveBar.Image.Dispose() } } catch {}
    try { if ($null -ne $script:Hud.WeekBar.Image) { $script:Hud.WeekBar.Image.Dispose() } } catch {}
    try { $script:Hud.Form.Close(); $script:Hud.Form.Dispose() } catch {}
    try { $script:Hud.FontLabel.Dispose(); $script:Hud.FontReset.Dispose() } catch {}
    if ($null -ne $script:CurrentIcon) { try { $script:CurrentIcon.Dispose() } catch {} }
    try { $script:Mutex.ReleaseMutex() } catch {}
    $script:Mutex.Dispose()
}
