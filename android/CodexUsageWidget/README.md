# Codex Usage Widget for Android v1.1

Home-screen widget for the Codex / ChatGPT Work shared usage pool, intended for an ngrok fixed dev domain.

## Widget sizes

### 1x1 compact

Two compact rows keep both quota windows and reset times:

```text
5h 74%
21:36
W 38%
09/14
```

Status is shown only when necessary (`SET`, `ERR`, `!`). Tapping the compact widget opens settings.

### Wide

When the launcher gives the widget at least about 180dp width and 68dp height, it switches automatically to the previous bar layout with an explicit refresh button.

## Network behavior

- HTTPS only
- relay bearer token stored using Android Keystore / AES-GCM
- `ngrok-skip-browser-warning: 1` sent with requests
- automatic refresh every 15 minutes with WorkManager
- last good values remain visible if refresh fails

## Build

Open this folder in a current Android Studio and build/install the `app` module, or:

```powershell
.\gradlew.bat assembleDebug
```

Debug APK:

```text
app\build\outputs\apk\debug\app-debug.apk
```

## Configure

1. Open **Codex Usage**.
2. URL: `https://your-assigned-name.ngrok-free.app`
3. Token: the Windows `Install.ps1` relay token.
4. Tap **保存してテスト**.
5. Add the **Codex Usage** widget to the home screen and resize to 1x1 if necessary.
