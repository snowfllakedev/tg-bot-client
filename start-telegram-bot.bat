@echo off
chcp 866 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0telegram-bot.ps1"
pause