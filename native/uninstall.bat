@echo off
for %%K in ("Google\Chrome" "BraveSoftware\Brave-Browser" "Microsoft\Edge" "Chromium" "Vivaldi") do reg delete "HKCU\Software\%%~K\NativeMessagingHosts\com.feedremote.host" /f >nul 2>&1
echo Feed Remote mouse helper removed.
pause
