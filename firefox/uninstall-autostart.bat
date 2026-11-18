@echo off
schtasks /end /tn "Feed Remote" >nul 2>&1
schtasks /delete /tn "Feed Remote" /f >nul 2>&1
echo Feed Remote helper removed from startup and stopped.
pause
