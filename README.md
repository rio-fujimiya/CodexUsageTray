# CodexUsageTray v2.0 ngrok

Windows side for the Android Codex / ChatGPT Work usage widget.

## Components

- `CodexUsageTray.ps1`: reads `account/rateLimits/read` and exports `usage-cache.json`
- `CodexUsageRelay.ps1`: bearer-authenticated read-only API on localhost
- `Configure-Ngrok.ps1`: binds your free assigned ngrok dev domain to that relay
- `Start-Ngrok.ps1`: starts ngrok hidden at Windows login

## 0. Environment

Activated `Codex-CLI` is required.

Drag anywhere on the extended tray HUD with the left mouse button to move it,
including its labels and gauges. A left click without dragging hides the HUD;
click the tray icon to show it again. The position is kept while running and
resets to the default location on restart.

Offline HUD interaction checks (no Codex requests):

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-HudDrag.ps1
```

## DEFAULT / ECC accounts

Starting `CodexUsageTray.ps1` without arguments launches two tray monitors:

| Account | Codex home | Recovery state | Usage cache |
| --- | --- | --- | --- |
| DEFAULT | `%USERPROFILE%\.codex` | `state.json` | `usage-cache.json` |
| ECC | `%USERPROFILE%\.codex-ecc` | `state-ecc.json` | `usage-cache-ecc.json` |

State/cache files live in `%LOCALAPPDATA%\CodexUsageTray`. Each account must
already be signed in through Codex CLI in its own home. The monitors use these
fixed homes regardless of the launcher's `CODEX_HOME` or later account switches.
They do not copy credentials or change the account switcher configuration.

Both icons keep the existing full-size 5h/weekly gauges. ECC has a white E with
a dark outline at the center. The letter overlaps the bars while leaving their
upper and lower margins visible for reading progress. The E remains
visible in loading, exhausted and error states.
The tooltip, right-click menu,
recovery notification and extended HUD identify the account. The two HUDs are
stacked so they do not overlap. Refresh, errors, HUD visibility and Exit operate
independently. Launching again does not duplicate an account's monitor.
If an account is not signed in, its icon shows an error while the other continues.

The installed startup shortcut and `Run-Portable.cmd` launch both accounts.
To launch only one account:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CodexUsageTray.ps1 -Account DEFAULT
powershell -NoProfile -ExecutionPolicy Bypass -File .\CodexUsageTray.ps1 -Account ECC
```

The existing Android relay continues to serve DEFAULT's `usage-cache.json`.
ECC's cache is separate; Android account selection is not included in this change.

Offline regression checks (no Codex requests or credential changes):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-DualAccountTray.ps1
```

## 1. Install/update

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

(Optional) Keep the printed **Android relay token** private.

## 2. (Optional) Install and authenticate ngrok

Install ngrok, for example:

```powershell
winget install ngrok -s msstore
```

Then add the authtoken from your ngrok dashboard:

```powershell
ngrok config add-authtoken <YOUR_AUTHTOKEN>
```

## 3. (Optional) Configure your assigned dev domain

Your free account has one automatically assigned dev domain, such as:

```text
your-assigned-name.ngrok-free.app
```

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexUsageTray\Configure-Ngrok.ps1" -DevDomain your-assigned-name.ngrok-free.app
```

This creates `CodexUsageNgrok.lnk` in Startup and launches ngrok hidden. On later Windows logins it reconnects to the same dev domain.

## 4. (Optional) Android URL

Use:

```text
https://your-assigned-name.ngrok-free.app
```

The Android client sends `ngrok-skip-browser-warning: 1` and the separate relay bearer token.

## Local relay test

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexUsageTray\Test-Relay.ps1"
```

No router port forwarding or Windows Firewall inbound rule for 8765 is required.
