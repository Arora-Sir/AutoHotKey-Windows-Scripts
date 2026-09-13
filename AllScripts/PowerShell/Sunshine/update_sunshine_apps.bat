@echo off
rem Elevates to Administrator to update Sunshine apps.json and restart SunshineService
echo Elevating to Administrator to update Sunshine apps.json...
powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0update_sunshine_apps.ps1\"' -Verb RunAs"
