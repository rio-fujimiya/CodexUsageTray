# CodexUsageTray v1.3

Small Windows monitor for the ChatGPT Work / Codex shared agentic usage pool.

## Install / update

Run this from the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer replaces the older copy in `%LOCALAPPDATA%\CodexUsageTray`, recreates the Startup shortcut, and launches the new version.

## Display

Windows notification-area icons are only about 16-32 logical pixels, so two quota bars plus readable reset text cannot be placed inside the icon itself.

v1.3 therefore uses the normal tray icon as a compact status indicator, plus a tiny frameless always-on-top HUD immediately above the tray as the readable "extended icon":

```text
5h  [████████░░░░]  18:42
W   [█████░░░░░░░]  09/12
```

- top row: 5-hour quota remaining + reset time (`HH:mm`)
- bottom row: weekly quota remaining + reset date (`MM/dd`)
- bar length: remaining quota
- green: 50% or more remaining
- amber: 20-49% remaining
- red: below 20% remaining

Exact percentages remain available from the tray tooltip / right-click menu, e.g. `5h 74% | W 38%`.

Right-click the tray icon and toggle **Show extended tray HUD** to hide/show the HUD.
Double-click the HUD or choose **Refresh now** for an immediate refresh.
Automatic refresh is every 5 minutes.

If OpenAI does not report one quota window, its bar is empty and its reset display becomes `--:--` / `--/--`. This is intentionally different from an RPC error, which is displayed as `ERR`.

## Usage unavailable

Right-click the tray icon and choose **Run diagnostics...**. The diagnostics verify:

1. Codex CLI discovery
2. Codex CLI version
3. ChatGPT login status
4. `codex doctor`
5. raw `account/rateLimits/read` exchange

Useful checks:

```powershell
codex.cmd --version
codex.cmd login status
```

If needed:

```powershell
codex.cmd login
```

and sign in with ChatGPT.

## Usage / credit cost

Each refresh starts a hidden `codex app-server --stdio`, performs the initialization handshake, calls `account/rateLimits/read`, then terminates it.

It does **not** start a model turn, so the monitor does not intentionally consume model tokens / agentic allowance. It only performs a small account-metadata request every five minutes.
