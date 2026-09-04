# =============================================================================
# setup_scheduled_tasks.ps1 - One-Time Elevation Registration for WSL ext4 Mount
# =============================================================================
# Registers two elevated tasks in Windows Task Scheduler:
#   1. Mount Task    - Strips RAW drive letter and attaches SSD to WSL
#   2. Unmount Task  - Safely detaches SSD from WSL
#
# Running them via 'schtasks /run' allows non-elevated scripts (AHK, user shells)
# to execute wsl --mount with ZERO UAC prompts and ZERO background hanging!
# =============================================================================

# Check for Administrator elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator elevation to register Scheduled Tasks..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
    exit
}

$scriptDir = Split-Path -Parent $PSCommandPath
. "$scriptDir\ssd_common.ps1"
$cfg = Get-SSDConfig

$mountTaskName   = if ($cfg.tasks.mountTask) { $cfg.tasks.mountTask } else { "WSL_Mount_PixelSSD" }
$unmountTaskName = if ($cfg.tasks.unmountTask) { $cfg.tasks.unmountTask } else { "WSL_Unmount_PixelSSD" }

$mountScript = Join-Path $scriptDir "wsl_mount_elevated.ps1"
$unmountScript = Join-Path $scriptDir "wsl_unmount_elevated.ps1"

$runSilentExe = Join-Path $scriptDir "run_silent.exe"
$mountCmd = "`"$runSilentExe`" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$mountScript`""
$unmountCmd = "`"$runSilentExe`" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$unmountScript`""

# Clean up obsolete legacy task names if present
schtasks /Delete /TN "WSL_Ext4_SSD_Mount" /F 2>$null | Out-Null
schtasks /Delete /TN "WSL_Ext4_SSD_Unmount" /F 2>$null | Out-Null

# Register Mount Task
schtasks /Create /TN $mountTaskName /TR $mountCmd /SC ONCE /ST 00:00 /F /RL HIGHEST
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Registered Task: $mountTaskName"
} else {
    Write-Error "Failed to register $mountTaskName"
}

# Register Unmount Task
schtasks /Create /TN $unmountTaskName /TR $unmountCmd /SC ONCE /ST 00:00 /F /RL HIGHEST
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Registered Task: $unmountTaskName"
} else {
    Write-Error "Failed to register $unmountTaskName"
}

Write-Host "Setup complete. Scheduled Tasks are now ready for zero-UAC mounting."
