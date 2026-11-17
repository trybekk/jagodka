@echo off
rem Logi Jagodki z WoW Forever do logs\  (logs.bat = okienko, logs.bat -Quick = bez okienka, ostatni wybor)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0logs.ps1" %*
if "%~1"=="-Quick" pause
