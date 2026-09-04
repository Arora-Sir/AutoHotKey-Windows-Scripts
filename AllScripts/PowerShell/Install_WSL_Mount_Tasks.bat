@echo off
:: =============================================================================
:: Install_WSL_Mount_Tasks.bat - Self-Elevating Installer for WSL SSD Scheduled Tasks
:: =============================================================================

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
echo ========================================================
echo  Registering WSL ext4 SSD Scheduled Tasks...
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_scheduled_tasks.ps1"

echo.
echo ========================================================
echo  Registration complete! Press any key to close this window.
echo ========================================================
pause >nul
