@echo off
schtasks /create /tn "Feed Remote" /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0feed-remote-helper.ps1\"" /sc onlogon /rl limited /f >nul
schtasks /run /tn "Feed Remote" >nul
echo Feed Remote helper now starts hidden with Windows, and is running.
pause
