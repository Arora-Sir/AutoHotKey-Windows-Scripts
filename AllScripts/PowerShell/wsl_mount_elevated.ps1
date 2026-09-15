<#
.SYNOPSIS
    Elevated physical disk attachment, revival, and Windows RAW drive letter suppression for WSL2.

.DESCRIPTION
    Invoked with Administrator privileges (via Scheduled Task WSL_Mount_PixelSSD or RunAs) to:
      1. Detect target ext4 SSD via Find-TargetSSD
      2. If dormant / held for eject, revive the DevNode via pnputil /restart-device, /remove-device, and /scan-devices
      3. Strip any Windows-assigned RAW drive letter before format nag prompts appear
      4. Attach raw physical block device to WSL2 with wsl.exe --mount --bare
      5. Handle dirty attachment recovery via selective unmount or wsl.exe --shutdown reset
#>

. "$PSScriptRoot\ssd_common.ps1"

$logPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Logs\pixel_ssd_mount.log"
function Log-Elevated([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $logPath -Value "[$ts] [ELEVATED] $msg" -ErrorAction SilentlyContinue
}

Log-Elevated "wsl_mount_elevated.ps1 invoked."
$cfg = Get-SSDConfig
$ssd = Find-TargetSSD -Config $cfg

if (-not $ssd) {
    Log-Elevated "SSD not detected by Find-TargetSSD. Checking for dormant/ejected USB storage hardware..."
    $ejectedDev = Find-EjectedTargetUSBDevice -Config $cfg
    if ($ejectedDev) {
        Log-Elevated "Reviving ejected devnode ($($ejectedDev.InstanceId)) via pnputil..."
        $restartRes = pnputil /restart-device $ejectedDev.InstanceId 2>&1
        $cleanRes = ($restartRes -replace [char]0, '').Trim()
        Log-Elevated "pnputil /restart-device output: $cleanRes"

        if ($cleanRes -match "reboot" -or $cleanRes -match "Failed") {
            Log-Elevated "Restart blocked by pending reboot. Forcing devnode removal and fresh bus re-enumeration..."
            $remRes = pnputil /remove-device $ejectedDev.InstanceId /force 2>&1
            $cleanRem = ($remRes -replace [char]0, '').Trim()
            Log-Elevated "pnputil /remove-device output: $cleanRem"
            Start-Sleep -Milliseconds 800
        }

        $scanRes = pnputil /scan-devices 2>&1
        $cleanScan = ($scanRes -replace [char]0, '').Trim()
        Log-Elevated "pnputil /scan-devices output: $cleanScan"

        for ($i = 0; $i -lt 16; $i++) {
            Start-Sleep -Milliseconds 500
            $ssd = Find-TargetSSD -Config $cfg
            if ($ssd) {
                Log-Elevated "Target SSD successfully revived and detected on attempt #$($i + 1): Disk #$($ssd.Number) ($($ssd.FriendlyName))"
                break
            }
        }
    } else {
        Log-Elevated "No dormant/ejected USB device found matching target signatures. Triggering full hardware bus scan..."
        pnputil /scan-devices 2>&1 | Out-Null
        Start-Sleep -Milliseconds 1000
        $ssd = Find-TargetSSD -Config $cfg
    }
}

if ($ssd) {
    Log-Elevated "Found target SSD: Disk #$($ssd.Number) ($($ssd.FriendlyName))"
    $part = Get-Partition -DiskNumber $ssd.Number -PartitionNumber 1 -ErrorAction SilentlyContinue
    if ($part -and $part.DriveLetter) {
        Remove-PartitionAccessPath -DiskNumber $ssd.Number -PartitionNumber 1 -AccessPath "$($part.DriveLetter):" -ErrorAction SilentlyContinue
        Log-Elevated "Removed RAW drive letter $($part.DriveLetter):"
    }
    $mountOut = wsl.exe --mount \\.\PHYSICALDRIVE$($ssd.Number) --bare 2>&1
    $cleanMountOut = ($mountOut -replace [char]0, '').Trim()
    Log-Elevated "wsl.exe --mount --bare exit: $LASTEXITCODE, output: $cleanMountOut"

    if ($LASTEXITCODE -ne 0) {
        if ($cleanMountOut -match "WSL_E_DISK_ALREADY_ATTACHED" -or $cleanMountOut -match "Operation not permitted") {
            Log-Elevated "Known faulted attachment detected ($cleanMountOut). Performing fast wsl.exe --shutdown reset..."
            wsl.exe --shutdown
            Start-Sleep -Milliseconds 1200
        } else {
            Log-Elevated "Non-zero attach exit code ($LASTEXITCODE). Attempting unmount reset..."
            $unm = wsl.exe --unmount \\.\PHYSICALDRIVE$($ssd.Number) 2>&1
            $cleanUnm = ($unm -replace [char]0, '').Trim()
            Log-Elevated "Reset unmount exit: $LASTEXITCODE, output: $cleanUnm"

            if ($LASTEXITCODE -ne 0 -or $cleanUnm -match "Operation not permitted") {
                Log-Elevated "SCSI controller faulted or dirty attachment. Performing fast wsl.exe --shutdown reset..."
                wsl.exe --shutdown
                Start-Sleep -Milliseconds 1200
            }
        }

        $retryOut = wsl.exe --mount \\.\PHYSICALDRIVE$($ssd.Number) --bare 2>&1
        $cleanRetry = ($retryOut -replace [char]0, '').Trim()
        Log-Elevated "Retry mount --bare exit: $LASTEXITCODE, output: $cleanRetry"
    }
} else {
    Log-Elevated "No target SSD found by Find-TargetSSD after revival check."
}
