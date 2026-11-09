@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\deploy-ui.ps1"
if errorlevel 1 pause
