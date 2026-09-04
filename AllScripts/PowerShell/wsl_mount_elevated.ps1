# =============================================================================
# wsl_mount_elevated.ps1 - Elevated Attach & RAW Drive Suppression
# =============================================================================
. "$PSScriptRoot\ssd_common.ps1"

$logPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Logs\pixel_ssd_mount.log"
function Log-Elevated([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $logPath -Value "[$ts] [ELEVATED] $msg" -ErrorAction SilentlyContinue
}

Log-Elevated "wsl_mount_elevated.ps1 invoked."
$cfg = Get-SSDConfig
$ssd = Find-TargetSSD -Config $cfg

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
    Log-Elevated "No target SSD found by Find-TargetSSD."
}

