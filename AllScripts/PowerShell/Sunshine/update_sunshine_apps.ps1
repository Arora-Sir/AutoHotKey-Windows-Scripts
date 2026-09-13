# update_sunshine_apps.ps1: Registers Sunshine application profiles including Extended Desktop
# Updates C:\Program Files\Sunshine\config\apps.json and restarts SunshineService.
# Run with Administrator privileges.

$logDir = Join-Path $PSScriptRoot '..\..\Logs'
if (![System.IO.Directory]::Exists($logDir)) {
    [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
}
$logFile = Join-Path $logDir 'update_sunshine_apps.log'

try {
    Write-Host 'Updating Sunshine apps in C:\Program Files\Sunshine\config\apps.json...' -ForegroundColor Cyan
    Add-Content -Path $logFile -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] Starting apps update...')
    $appsPath = 'C:\Program Files\Sunshine\config\apps.json'
    
    $runSilentExe = (Join-Path $PSScriptRoot '..\run_silent.exe')
    if (-not (Test-Path $runSilentExe)) {
        $runSilentExe = 'D:\Software\Programming\AutoHotKey\AllScripts\PowerShell\run_silent.exe'
    }
    $runSilentCmd = ($runSilentExe.Replace('\', '\\'))
    $fastScript = (Join-Path $PSScriptRoot 'set_fast.ps1').Replace('\', '\\')
    $normalScript = (Join-Path $PSScriptRoot 'set_normal.ps1').Replace('\', '\\')

    $jsonContent = @"
{
    "apps": [
        {
            "auto-detach": true,
            "elevated": false,
            "exclude-global-prep-cmd": false,
            "exit-timeout": 5,
            "image-path": "desktop.png",
            "name": "Desktop",
            "prep-cmd": [
                {
                    "do": "\"$runSilentCmd\" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"$fastScript\"",
                    "elevated": false,
                    "undo": "\"$runSilentCmd\" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"$normalScript\""
                }
            ],
            "wait-all": true
        },
        {
            "auto-detach": true,
            "cmd": "",
            "elevated": false,
            "exclude-global-prep-cmd": false,
            "exit-timeout": 5,
            "image-path": "desktop-alt.png",
            "name": "Desktop (Extended Tab)",
            "output": "\\\\.\\DISPLAY4",
            "prep-cmd": [
                {
                    "do": "\"$runSilentCmd\" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"$fastScript\"",
                    "elevated": false,
                    "undo": "\"$runSilentCmd\" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"$normalScript\""
                }
            ],
            "wait-all": true
        },
        {
            "auto-detach": true,
            "cmd": "",
            "elevated": false,
            "exclude-global-prep-cmd": false,
            "exit-timeout": 5,
            "image-path": "",
            "name": "Desktop (TV)",
            "output": "",
            "wait-all": true
        },
        {
            "auto-detach": true,
            "cmd": "steam://open/bigpicture",
            "image-path": "steam.png",
            "name": "Steam Big Picture",
            "prep-cmd": [
                {
                    "do": "",
                    "undo": "steam://close/bigpicture"
                }
            ],
            "wait-all": true
        }
    ],
    "env": {}
}
'@

    [System.IO.File]::WriteAllText($appsPath, $jsonContent)
    Write-Host 'Apps configuration written successfully.' -ForegroundColor Green
    Add-Content -Path $logFile -Value 'Apps written successfully.'

    Write-Host 'Restarting SunshineService...' -ForegroundColor Cyan
    Restart-Service -Name SunshineService -Force -ErrorAction Stop
    Write-Host 'SunshineService restarted successfully!' -ForegroundColor Green
    Add-Content -Path $logFile -Value 'SunshineService restarted successfully.'
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Add-Content -Path $logFile -Value ('ERROR: ' + $_.Exception.Message)
}
