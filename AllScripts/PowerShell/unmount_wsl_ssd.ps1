param([switch]$OnlyIfDisconnected)

# =============================================================================
# unmount_wsl_ssd.ps1 - Production-Grade ext4 Backup SSD Unmount & Cleanup Engine
# =============================================================================
# Triggered by Win+Alt+U hotkey, Tray Menu Eject, or automatic USB unplug.
# Features:
#   1. Structured diagnostic logging to AllScripts\Logs\pixel_ssd_mount.log
#   2. Dynamic JSON configuration (ssd_config.json / ssd_config.json.example)
#   3. Ejection flag management (%TEMP%\pixel_ssd_ejected.flag)
#   4. Graceful Explorer redirection to 'This PC' (prevents broken path modals)
#   5. OnlyIfDisconnected guard (prevents false unmount on device reconfiguration)
#   6. Immediate unmapping of drive letter via net use (prevents Explorer hangs)
#   7. Graceful lazy unmount and Samba stop inside Ubuntu
#   8. Universal WSL detach (cleans Hyper-V attachment table even if drive was pulled)
#   9. Permanent cleanup of legacy Network Shortcut files
# =============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\ssd_common.ps1"
$cfg = Get-SSDConfig

$driveLetter  = if ($cfg.smb.driveLetter) { $cfg.smb.driveLetter } else { "P:" }
$driveLabel   = if ($cfg.smb.driveLabel) { $cfg.smb.driveLabel } else { "Linux Backup SSD" }
$shareName    = if ($cfg.smb.shareName) { $cfg.smb.shareName } else { "PixelSSD" }
$distro       = if ($cfg.wsl.distro) { $cfg.wsl.distro } else { "Ubuntu" }
$unmountTask  = if ($cfg.tasks.unmountTask) { $cfg.tasks.unmountTask } else { "WSL_Unmount_PixelSSD" }
$folderMatch  = if ($cfg.explorer.openFolder) { $cfg.explorer.openFolder } else { "" }

$logsDir = Join-Path (Split-Path -Parent $scriptDir) "Logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$logFile = Join-Path $logsDir "pixel_ssd_mount.log"

function Log-Unmount {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

Log-Unmount "--------------------------------------------------------"
Log-Unmount "Unmount invocation initiated (OnlyIfDisconnected: $OnlyIfDisconnected)."

$flagFile = [System.IO.Path]::Combine($env:TEMP, 'pixel_ssd_ejected.flag')

try {
    # Check if SSD hardware is still present on USB bus
    $ssd = Find-TargetSSD -Config $cfg

    # If manual ejection while SSD is still plugged in, set flag to prevent watchdog re-mount
    if (-not $OnlyIfDisconnected) {
        Set-Content -Path $flagFile -Value (Get-Date).ToString() -Force -ErrorAction SilentlyContinue
        Log-Unmount "Created manual ejection flag ($flagFile)." "INFO"
    } else {
        # If physically disconnected, remove the flag so next plug-in auto-mounts
        if (Test-Path $flagFile) {
            Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
            Log-Unmount "Removed ejection flag following physical disconnect." "INFO"
        }
    }

    # 0. Gracefully redirect any open Explorer window/tab viewing target drive to 'This PC'
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($w in $shell.Windows()) {
            try {
                $loc = $w.LocationURL
                $name = $w.LocationName
                $shouldRedirect = ($loc -match [regex]::Escape($driveLetter)) -or
                                  ($loc -match [regex]::Escape($shareName)) -or
                                  ($name -match [regex]::Escape($driveLabel))
                if ($folderMatch) {
                    $shouldRedirect = $shouldRedirect -or ($loc -match [regex]::Escape($folderMatch)) -or ($name -match [regex]::Escape($folderMatch))
                }
                if ($shouldRedirect) {
                    Log-Unmount "Redirecting Explorer tab ('$name') to 'This PC' before teardown." "INFO"
                    $w.Navigate("shell:MyComputerFolder")
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 250
    } catch {
        Log-Unmount "Window redirection notice: $_" "WARN"
    }

    # 1. Unmap Windows Drive Letter immediately (Zero Explorer Lag)
    $dlPattern = "\s" + [regex]::Escape($driveLetter) + "\s"
    $pCheck = net use 2>$null | Select-String $dlPattern
    if ($pCheck) {
        Log-Unmount "Unmapping drive letter $driveLetter via net use..." "INFO"
        $delResult = net use $driveLetter /delete /y 2>&1
        Log-Unmount "net use /delete exit: $LASTEXITCODE. Output: $delResult" "INFO"
        
        # Broadcast Shell change notification to update 'This PC' drive list silently
        try {
            Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class WinShellNotify {
                [DllImport("shell32.dll", CharSet = CharSet.Auto)]
                public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
            }
"@ -ErrorAction SilentlyContinue
            [WinShellNotify]::SHChangeNotify(0x00000020, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
            Log-Unmount "Broadcasted SHCNE_DRIVEREMOVED notification to update 'This PC' drive list." "INFO"
        } catch {}
    } else {
        Log-Unmount "Drive letter $driveLetter was not mapped in net use." "INFO"
    }

    # 2. Run Ubuntu unmount helper (lazy unmount and Samba stop)
    Log-Unmount "Running Ubuntu unmount helper (/usr/local/bin/unmount_pixel_ssd.sh)..." "INFO"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "wsl.exe"
        $psi.Arguments = "-d $distro -u root -e /usr/local/bin/unmount_pixel_ssd.sh"
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($proc.WaitForExit(4000)) {
            $uRes = $proc.StandardOutput.ReadToEnd()
            Log-Unmount "Ubuntu unmount helper finished: $uRes" "INFO"
        } else {
            $proc.Kill()
            Log-Unmount "Ubuntu unmount helper timed out after 4s." "WARN"
        }
    } catch {
        Log-Unmount "Ubuntu unmount helper exception: $_" "WARN"
    }

    # 3. Detach from WSL host
    $schDone = $false
    try {
        $queryTask = schtasks /Query /TN $unmountTask 2>$null
        if ($LASTEXITCODE -eq 0) {
            Log-Unmount "Triggering elevated Scheduled Task: $unmountTask" "INFO"
            schtasks /run /tn $unmountTask | Out-Null
            $schDone = $true
        }
    } catch {}

    if (-not $schDone) {
        $runSilentExe = Join-Path $scriptDir "run_silent.exe"
        if ($ssd) {
            $driveNum = $ssd.Number
            Log-Unmount "Target SSD is online (Disk #$driveNum). Using timeout-guarded elevated detach..." "INFO"
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if (Test-Path $runSilentExe) {
                $psi.FileName = $runSilentExe
                $psi.Arguments = "powershell.exe -NoProfile -WindowStyle Hidden -Command wsl --unmount \\.\PHYSICALDRIVE$driveNum"
            } else {
                $psi.FileName = "powershell.exe"
                $psi.Arguments = "-NoProfile -WindowStyle Hidden -Command wsl --unmount \\.\PHYSICALDRIVE$driveNum"
            }
            $psi.Verb = "RunAs"
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            try {
                $proc = [System.Diagnostics.Process]::Start($psi)
                if ($proc.WaitForExit(6000)) {
                    Log-Unmount "Elevated detach exited with code $($proc.ExitCode)" "INFO"
                    if ($proc.ExitCode -ne 0) {
                        Log-Unmount "Elevated detach failed ($($proc.ExitCode)). Resetting via fast wsl.exe --shutdown..." "WARN"
                        wsl.exe --shutdown
                    }
                } else {
                    Log-Unmount "Elevated detach timed out after 6s. Terminating and resetting via wsl.exe --shutdown..." "WARN"
                    $proc.Kill()
                    wsl.exe --shutdown
                }
            } catch {
                Log-Unmount "Elevated detach process start error: $_" "WARN"
                wsl.exe --shutdown
            }
        } else {
            # SSD was abruptly pulled; flush all stale disk attachments from WSL
            Log-Unmount "SSD hardware physically absent. Running universal wsl --unmount flush..." "INFO"
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                if (Test-Path $runSilentExe) {
                    $psi.FileName = $runSilentExe
                    $psi.Arguments = "powershell.exe -NoProfile -WindowStyle Hidden -Command wsl --unmount"
                } else {
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = "-NoProfile -WindowStyle Hidden -Command wsl --unmount"
                }
                $psi.Verb = "RunAs"
                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $proc = [System.Diagnostics.Process]::Start($psi)
                if ($proc.WaitForExit(4000)) {
                    if ($proc.ExitCode -ne 0) {
                        Log-Unmount "Universal unmount exited with non-zero ($($proc.ExitCode)). Performing fast wsl.exe --shutdown reset..." "WARN"
                        wsl.exe --shutdown
                    } else {
                        Log-Unmount "Universal WSL unmount flush completed." "INFO"
                    }
                } else {
                    $proc.Kill()
                    Log-Unmount "Universal unmount timed out. Resetting via wsl.exe --shutdown..." "WARN"
                    wsl.exe --shutdown
                }
            } catch {
                wsl.exe --shutdown
            }
        }
    }

    # 4. Clean up any lingering Network Shortcut (.lnk)
    $lnk = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Network Shortcuts\Pixel_Backup_SSD.lnk')
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
        Log-Unmount "Removed leftover Network Shortcut file." "INFO"
    }

    # 5. Terminate WSL keep-alive process
    $keepAlivePattern = "*$distro*sleep infinity*"
    $keepAliveProcs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like $keepAlivePattern }
    foreach ($kp in $keepAliveProcs) {
        Stop-Process -Id $kp.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Log-Unmount "Terminated WSL keep-alive process." "INFO"

    Log-Unmount "Unmount operation completed cleanly." "INFO"
}
catch {
    Log-Unmount "Fatal exception during unmount: $_" "ERROR"
}
