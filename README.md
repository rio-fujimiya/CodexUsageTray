# CodexUsageTray v1.7

## v1.7 fix

- Fixed a crash when clicking the HUD (`null 値の式ではメソッドを呼び出せません`).
- HUD mouse handlers no longer retain a local `Form` variable after `New-Hud` returns; they use the script-scoped HUD reference instead.
- Tray single-click/HUD visibility handlers use the same guarded script-scoped reference.

Small Windows monitor for the ChatGPT Work / Codex shared agentic usage pool.

## Install / update

Run this from the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer replaces the older copy in `%LOCALAPPDATA%\CodexUsageTray`, recreates the Startup shortcut, and launches the new version.

## Display

Windows notification-area icons are only about 16-32 logical pixels, so two quota bars plus readable reset text cannot be placed inside the icon itself.

v1.7 uses the normal tray icon as a compact status indicator, plus a more transparent frameless always-on-top HUD immediately above the tray as the readable "extended icon":

```text
5h  [████████░░░░]  18:42
W   [█████░░░░░░░]  09/12
```

- both rows: if the reset is **today**, show the reset time (`HH:mm`); otherwise show the reset date (`MM/dd`)
- bar length: remaining quota
- green: 50% or more remaining
- amber: 20-49% remaining
- red: below 20% remaining

Exact percentages remain available from the tray tooltip / right-click menu, e.g. `5h 74% | W 38%`.

- **Single left-click the tray icon:** toggle HUD show/hide
- **Double left-click the tray icon:** open the configured ChatGPT Windows app shortcut (`OpenAI.Codex_2p2nqsd0c76g0!App`)
- Right-click the tray icon and toggle **Show extended tray HUD** to hide/show the HUD
- **Left-click anywhere on the HUD:** hide it immediately
- Choose **Refresh now** for an immediate refresh

HUD opacity is 84% (more transparent than v1.4). Automatic refresh is every 5 minutes.

## Recovery notification

If quota exhaustion made Work / Codex unusable, the app remembers which quota window was blocking. When all previously blocking windows are reported above 0% again, it sends a Windows notification:

```text
Work / Codex is available again
Usage limit reset. 5h 100% | W 38%
```

No notification is sent on the first successful read when there is no prior saved state, so a fresh install does not create a false recovery alert. The blocking state is persisted in `%LOCALAPPDATA%\CodexUsageTray\state.json`, so recovery can still be detected across app restarts. If a previously blocking quota disappears from the API response, the app waits rather than falsely announcing recovery.

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
