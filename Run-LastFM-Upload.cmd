@echo off
setlocal

cd /d "%~dp0"

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Start-LastFM-Upload.ps1"
) else (
    echo PowerShell 7+ was not found.
    echo Install it from https://learn.microsoft.com/powershell/scripting/install/installing-powershell
)

echo.
pause
