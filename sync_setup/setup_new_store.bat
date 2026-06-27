@echo off
title ELATTAR Store - GitHub Link Setup
:: Check for administrative permissions
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :admin
) else (
    goto :elevate
)

:elevate
echo Requesting administrator privileges...
powershell -Command "Start-Process '%~dp0setup_new_store.bat' -Verb RunAs"
exit /b

:admin
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "setup_new_store.ps1"
