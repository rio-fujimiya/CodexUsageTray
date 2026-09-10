@echo off
start "CodexUsageTray" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CodexUsageTray.ps1"
start "CodexUsageRelay" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CodexUsageRelay.ps1"
