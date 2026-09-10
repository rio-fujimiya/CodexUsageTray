# セットアップ手順 — ngrok固定URL版

## 1. Windows側

`windows\CodexUsageTray-v2.0-ngrok` で:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

最後に表示される **Android relay token** を控えます。

relay確認:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexUsageTray\Test-Relay.ps1"
```

## 2. ngrok Free

無料アカウントを作り、Dashboardに表示される **assigned dev domain** を確認します。
例:

```text
your-assigned-name.ngrok-free.app
```

ngrokをインストール:

```powershell
winget install ngrok -s msstore
```

DashboardのauthtokenをPCに登録:

```powershell
ngrok config add-authtoken <YOUR_AUTHTOKEN>
```

固定domainをこのツールに設定:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexUsageTray\Configure-Ngrok.ps1" -DevDomain your-assigned-name.ngrok-free.app
```

以後はWindowsログイン時に `CodexUsageNgrok.lnk` がngrokを非表示起動し、同じdev domainへ接続します。

ルーターのポート開放はしません。relayも127.0.0.1だけで待ち受けます。

## 3. Android

`android\CodexUsageWidget` をAndroid Studioで開き、APKをbuild/installします。

アプリ設定:

```text
URL    https://your-assigned-name.ngrok-free.app
Token  WindowsのInstall.ps1で表示されたrelay token
```

**保存してテスト** → 接続OKならホーム画面へウィジェットを追加します。

## 4. 1x1表示

1x1では:

```text
5h 74%
21:36
W 38%
09/14
```

の2行表示です。resetが24時間以内なら `HH:mm`、それより先なら `MM/dd`。

ウィジェットを横に広げ、十分な幅（約180dp以上）があれば自動で従来のバー表示に切り替わります。

## 5. 更新

- 自動: WorkManagerで15分周期（Android側の省電力制御により遅れる場合あり）
- wide表示の `↻`: 即時更新
- 1x1: 本体タップで設定画面

## 6. Free枠の目安

15分間隔なら1端末で約2,880 request/月。ngrok Freeの20,000 HTTP/S request/月の範囲内です。

## 7. ngrok警告ページ

Androidクライアントは:

```http
ngrok-skip-browser-warning: 1
```

を送るため、Free endpointのbrowser interstitialを回避します。API自体には別途relay Bearer tokenが必要です。
