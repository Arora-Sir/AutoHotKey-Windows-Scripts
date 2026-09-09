@echo off
:: =============================================================================
:: Install_Startup_Task.bat - Self-Elevating Installer for AutoHotkey Startup Task
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
echo  Registering AutoHotkey Startup Script in Task Scheduler...
echo ========================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_startup_task.ps1"

echo.
echo ========================================================
echo  Setup complete! Press any key to close this window.
echo ========================================================
pause >nul
