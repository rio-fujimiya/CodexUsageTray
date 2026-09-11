Option Explicit
Dim sh, base, cmd
Set sh = CreateObject("WScript.Shell")
base = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\CodexUsageTray"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & base & "\CodexUsageRelay.ps1" & Chr(34)
sh.Run cmd, 0, False
