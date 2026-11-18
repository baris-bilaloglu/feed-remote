@echo off
set "M=%~dp0com.feedremote.host.json"
for %%K in ("Google\Chrome" "BraveSoftware\Brave-Browser" "Microsoft\Edge" "Chromium" "Vivaldi") do reg add "HKCU\Software\%%~K\NativeMessagingHosts\com.feedremote.host" /ve /t REG_SZ /d "%M%" /f >nul
echo Feed Remote mouse helper installed. Restart your browser.
pause
