@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0autostart.ps1"
if errorlevel 1 goto end
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0feed-remote-helper.ps1"
echo It is running now too.
:end
pause
