# =============================================================================
# setup_startup_task.ps1 - Automated Registration for AHK Startup Fleet
# =============================================================================
# Registers "AHK Startup Script" in Windows Task Scheduler:
#   - Action: Launches AllScripts\StartupScript.exe
#   - Trigger: At logon of current user with a 30-second delay (PT30S)
#   - Privilege: Standard user (RunLevel Limited) - zero UAC prompt on logon
#   - Resilience: Runs on battery, no execution timeout, demand start allowed
# =============================================================================

param(
    [switch]$Uninstall,
    [int]$DelaySeconds = 30
)

$ErrorActionPreference = "Stop"
$taskName = "AHK Startup Script"

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator elevation to register Scheduled Task..." -ForegroundColor Yellow
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Uninstall) { $argsList += " -Uninstall" }
    if ($DelaySeconds -ne 30) { $argsList += " -DelaySeconds $DelaySeconds" }
    Start-Process powershell.exe -ArgumentList $argsList -Verb RunAs -Wait
    exit
}

if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "[OK] Unregistered scheduled task: $taskName" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] Task '$taskName' is not registered." -ForegroundColor Gray
    }
    exit 0
}

$root    = $PSScriptRoot
$workDir = Join-Path $root "AllScripts"
$exePath = Join-Path $workDir "StartupScript.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "[WARNING] StartupScript.exe not found at $exePath" -ForegroundColor Yellow
    Write-Host "Please compile it first by running: .\build_startup_exe.ps1" -ForegroundColor Yellow
    Write-Host "Registering task anyway so it will be ready once compiled..." -ForegroundColor Gray
}

# 1. Action: Execute compiled StartupScript.exe with AllScripts as working directory
$action = New-ScheduledTaskAction -Execute $exePath -WorkingDirectory $workDir

# 2. Trigger: At logon of current user, delayed by N seconds to let Windows settle
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
if ($DelaySeconds -gt 0) {
    $trigger.Delay = "PT$($DelaySeconds)S"
}

# 3. Principal: Standard interactive user session (no UAC prompt required on boot)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# 4. Settings: Run on battery, allow manual start, and remove default execution timeout
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

# 5. Register or overwrite task
Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "========================================================" -ForegroundColor Green
Write-Host " [OK] Successfully registered task: '$taskName'" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Target:   $exePath" -ForegroundColor White
Write-Host "Trigger:  At logon of $env:USERNAME ($DelaySeconds-second delay)" -ForegroundColor White
Write-Host "To test:  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
Write-Host "To remove: .\setup_startup_task.ps1 -Uninstall" -ForegroundColor Gray
