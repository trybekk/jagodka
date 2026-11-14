@echo off
rem Double-click to refresh the WoW Forever API reference (doc\index.html). Needs only git.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
echo.
echo Gotowe. Odswiez doc\index.html w przegladarce.
pause
