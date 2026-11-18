@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0autostart.ps1" -Remove
echo To stop the running helper now, end "Windows PowerShell" in Task Manager or sign out.
pause
