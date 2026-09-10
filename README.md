# CodexUsageTray v2.0 ngrok

Windows side for the Android Codex / ChatGPT Work usage widget.

## Components

- `CodexUsageTray.ps1`: reads `account/rateLimits/read` and exports `usage-cache.json`
- `CodexUsageRelay.ps1`: bearer-authenticated read-only API on localhost
- `Configure-Ngrok.ps1`: binds your free assigned ngrok dev domain to that relay
- `Start-Ngrok.ps1`: starts ngrok hidden at Windows login

## 0. Environment

Activated `Codex-CLI` is required.

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
