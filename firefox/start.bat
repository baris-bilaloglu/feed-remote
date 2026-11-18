@echo off
start "Feed Remote" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0feed-remote-helper.ps1"
