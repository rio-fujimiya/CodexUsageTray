@echo off
start "CodexUsageTray" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CodexUsageTray.ps1"
