@echo off
rem Wszystkie analizy z analysis\ w jednym zipie dla oficerow: analysis\exports\jagodka-analizy-RRRR.MM.DD_N.zip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export-analysis.ps1"
pause
