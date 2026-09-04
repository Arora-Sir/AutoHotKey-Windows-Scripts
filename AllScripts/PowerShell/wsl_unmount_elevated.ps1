# =============================================================================
# wsl_unmount_elevated.ps1 - Elevated Detach for WSL ext4 Automation
# =============================================================================
. "$PSScriptRoot\ssd_common.ps1"

$logPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Logs\pixel_ssd_mount.log"
function Log-ElevatedUnmount([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $logPath -Value "[$ts] [ELEVATED_UNMOUNT] $msg" -ErrorAction SilentlyContinue
}

Log-ElevatedUnmount "wsl_unmount_elevated.ps1 invoked."
$cfg = Get-SSDConfig
$ssd = Find-TargetSSD -Config $cfg

if ($ssd) {
    Log-ElevatedUnmount "Detaching PHYSICALDRIVE$($ssd.Number)..."
    $unmOut = wsl.exe --unmount \\.\PHYSICALDRIVE$($ssd.Number) 2>&1
    $cleanUnm = ($unmOut -replace [char]0, '').Trim()
    Log-ElevatedUnmount "wsl.exe --unmount exit: $LASTEXITCODE, output: $cleanUnm"
    if ($LASTEXITCODE -ne 0) {
        Log-ElevatedUnmount "Detach returned non-zero ($LASTEXITCODE). Performing fast wsl.exe --shutdown reset..."
        wsl.exe --shutdown
    }
} else {
    Log-ElevatedUnmount "SSD not detected by Find-TargetSSD. Running universal wsl.exe --unmount..."
    $unmOut = wsl.exe --unmount 2>&1
    $cleanUnm = ($unmOut -replace [char]0, '').Trim()
    Log-ElevatedUnmount "wsl.exe --unmount universal exit: $LASTEXITCODE, output: $cleanUnm"
    if ($LASTEXITCODE -ne 0) {
        Log-ElevatedUnmount "Universal unmount returned non-zero ($LASTEXITCODE). Performing fast wsl.exe --shutdown reset..."
        wsl.exe --shutdown
    }
}

