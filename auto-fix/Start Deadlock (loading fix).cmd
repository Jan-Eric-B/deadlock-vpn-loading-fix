@echo off
rem Double-click to start Deadlock with the loading-screen auto-fix.
rem Opens DeadlockLoadingFix.ps1 in a minimized PowerShell window.
start "Deadlock loading fix" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DeadlockLoadingFix.ps1"
