@echo off
:: =============================================================================
:: Uninstall_Startup_Task.bat - Self-Elevating Uninstaller for AHK Startup Task
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
echo  Unregistering AutoHotkey Startup Script from Task Scheduler...
echo ========================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_startup_task.ps1" -Uninstall

echo.
echo ========================================================
echo  Uninstallation complete! Press any key to close this window.
echo ========================================================
pause >nul
