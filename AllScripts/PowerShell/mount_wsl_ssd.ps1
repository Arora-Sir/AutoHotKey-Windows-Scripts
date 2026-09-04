param([switch]$OpenExplorer)

# =============================================================================
# mount_wsl_ssd.ps1 - Hardened ext4 Backup SSD Mount & Automation Engine
# =============================================================================
# Features:
#   1. Structured diagnostic logging to AllScripts\Logs\pixel_ssd_mount.log
#   2. Dynamic JSON configuration (ssd_config.json / ssd_config.json.example)
#   3. Intelligent IP-matching check (preserves valid Reconnecting/Disconnected drives)
#   4. Fast TCP 445 socket probe (prevents Windows kernel SMB I/O hangs)
#   5. WSL_E_DISK_ALREADY_MOUNTED self-healing (recovers from dirty detach)
#   6. Lockfile anti-race with stale lock recovery
#   7. Strict watchdog timeouts on all external elevated processes
#   8. Silent elevation via Scheduled Task (falls back to timeout-guarded RunAs)
#   9. Ubuntu helper script execution (/usr/local/bin/mount_pixel_ssd.sh with fsck)
#  10. Authenticated Samba mapping (net use <Drive>: \\<WSL_IP>\<Share>)
#  11. Explorer window deduplication (never opens duplicate windows)
#  12. Automatic cleanup of redundant Network Shortcut (.lnk)
# =============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\ssd_common.ps1"
$cfg = Get-SSDConfig

$distro       = if ($cfg.wsl.distro) { $cfg.wsl.distro } else { "Ubuntu" }
$mountPoint   = if ($cfg.wsl.mountPoint) { $cfg.wsl.mountPoint } else { "/mnt/pixel_ssd" }
$volLabel     = if ($cfg.wsl.volumeLabel) { $cfg.wsl.volumeLabel } else { "" }
$driveLetter  = if ($cfg.smb.driveLetter) { $cfg.smb.driveLetter } else { "P:" }
$shareName    = if ($cfg.smb.shareName) { $cfg.smb.shareName } else { "PixelSSD" }
$driveLabel   = if ($cfg.smb.driveLabel) { $cfg.smb.driveLabel } else { "Linux Backup SSD" }
$smbUser      = if ($cfg.smb.username) { $cfg.smb.username } else { "wsluser" }
$smbPass      = if ($cfg.smb.password) { $cfg.smb.password } else { "wslpassword123" }
$openFolder   = if ($cfg.explorer.openFolder) { $cfg.explorer.openFolder } else { "" }
$mountTask    = if ($cfg.tasks.mountTask) { $cfg.tasks.mountTask } else { "WSL_Mount_PixelSSD" }

$logsDir   = Join-Path (Split-Path -Parent $scriptDir) "Logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$logFile   = Join-Path $logsDir "pixel_ssd_mount.log"

function Log-Mount {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

# Rotate log if larger than 1MB
try {
    if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
        $lines = Get-Content $logFile -Tail 500
        Set-Content -Path $logFile -Value $lines -Force
        Log-Mount "Log file rotated (preserved last 500 lines)" "INFO"
    }
} catch {}

Log-Mount "--------------------------------------------------------"
Log-Mount "Mount invocation started (OpenExplorer: $OpenExplorer)"

# ---- 0. Anti-race lock guard with stale detection ----------------------
$lockFile = [System.IO.Path]::Combine($env:TEMP, 'mount_wsl_ssd.lock')
if (Test-Path $lockFile) {
    $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($lockAge.TotalSeconds -lt 12) {
        Log-Mount "Concurrent mount operation in progress (age: $($lockAge.TotalSeconds)s). Exiting." "WARN"
        exit 0
    } else {
        Log-Mount "Purging stale lockfile (age: $($lockAge.TotalSeconds)s)" "WARN"
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}
Set-Content -Path $lockFile -Value (Get-Date).ToString() -Force -ErrorAction SilentlyContinue

# Clear manual ejection flag if present (resumes automatic lifecycle)
$flagFile = [System.IO.Path]::Combine($env:TEMP, 'pixel_ssd_ejected.flag')
if (Test-Path $flagFile) {
    Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
    Log-Mount "Cleared manual ejection flag on mount start." "INFO"
}

function Start-SilentProcess {
    param([string]$FilePath, [string]$Arguments)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $Arguments
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        Start-Process $FilePath -ArgumentList $Arguments -WindowStyle Hidden
    }
}

# Ensure WSL keep-alive is active immediately so WSL never idles down during or after mount
$keepAlivePattern = "*$distro*sleep infinity*"
$keepAliveProc = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like $keepAlivePattern }
if (-not $keepAliveProc) {
    Start-SilentProcess "wsl.exe" "-d $distro -e sleep infinity"
    Log-Mount "Started WSL background keep-alive process silently." "INFO"
}

function Test-SmbPort {
    param([string]$IP, [int]$TimeoutMs = 400)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($IP, 445, $null, $null)
        $success = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($success) {
            $tcp.EndConnect($connect)
            $tcp.Close()
            return $true
        }
        $tcp.Close()
        return $false
    } catch {
        return $false
    }
}

function Open-DeduplicatedExplorer {
    param([string]$TargetPath)
    try {
        $shell = New-Object -ComObject Shell.Application
        $windows = $shell.Windows()
        $foundWin = $null
        foreach ($w in $windows) {
            try {
                $loc = $w.LocationURL
                $name = $w.LocationName
                $match = ($loc -match [regex]::Escape($driveLetter)) -or
                         ($loc -match [regex]::Escape($shareName)) -or
                         ($name -match [regex]::Escape($driveLabel))
                if ($openFolder) {
                    $match = $match -or ($loc -match [regex]::Escape($openFolder)) -or ($name -match [regex]::Escape($openFolder))
                }
                if ($match) {
                    $foundWin = $w
                    break
                }
            } catch {}
        }

        if ($foundWin) {
            Log-Mount "Existing Explorer window detected for $driveLetter ('$($foundWin.LocationName)'). Bringing to focus." "INFO"
            $wshell = New-Object -ComObject WScript.Shell
            $focused = $wshell.AppActivate($foundWin.LocationName)
            if (-not $focused -and $foundWin.HWND) {
                $wshell.AppActivate($foundWin.HWND) | Out-Null
            }
        } else {
            Log-Mount "Launching fresh Explorer window for $TargetPath" "INFO"
            Start-Process explorer.exe $TargetPath
        }
    } catch {
        Log-Mount "Window deduplication exception: $_. Falling back to Start-Process." "WARN"
        Start-Process explorer.exe $TargetPath
    }
}

try {
    # ---- 1. Check current WSL IP & net use status ----------------------
    $currentWslIp = ""
    try {
        $currentWslIp = (wsl -d $distro -e hostname -I 2>$null).Trim().Split(' ')[0]
    } catch {}

    $netUseOutput = net use 2>$null
    $dlPattern = "\s" + [regex]::Escape($driveLetter) + "\s"
    $pLine = ($netUseOutput | Where-Object { $_ -match $dlPattern } | Select-Object -First 1)

    if ($pLine) {
        $remotePath = ""
        if ($pLine -match '(\\\\[^\s]+)') { $remotePath = $matches[1] }
        $isOk = ($pLine -match '^\s*OK\s+')

        # Only trust mapping if net use reports OK, remote matches current WSL IP, port 445 is alive, and mountPoint is verified
        if ($isOk -and $remotePath -and $currentWslIp -and ($remotePath -ieq "\\$currentWslIp\$shareName")) {
            $isPortAlive = Test-SmbPort -IP $currentWslIp -TimeoutMs 400
            $isFolderAlive = $false
            if ($isPortAlive) {
                if ($volLabel) {
                    wsl -d $distro -e test -d "$mountPoint/$volLabel" 2>$null
                    if ($LASTEXITCODE -eq 0) { $isFolderAlive = $true }
                } else {
                    wsl -d $distro -e grep -qs "$mountPoint" /proc/mounts 2>$null
                    if ($LASTEXITCODE -eq 0) { $isFolderAlive = $true }
                }
            }

            if ($isPortAlive -and $isFolderAlive) {
                $keepAliveProc = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like $keepAlivePattern }
                if (-not $keepAliveProc) {
                    Start-SilentProcess "wsl.exe" "-d $distro -e sleep infinity"
                }
                Log-Mount "$driveLetter is mapped, OK, and verified to $mountPoint." "INFO"
                if ($OpenExplorer) {
                    $target = if ($openFolder -and (Test-Path "$($driveLetter)\$openFolder")) { "$($driveLetter)\$openFolder" } else { "$($driveLetter)\" }
                    Open-DeduplicatedExplorer -TargetPath $target
                }
                exit 0
            } elseif (-not $isPortAlive) {
                Log-Mount "$driveLetter mapped to $remotePath but Samba port 445 unresponsive. Purging..." "WARN"
                net use $driveLetter /delete /y 2>&1 | Out-Null
            } else {
                Log-Mount "$driveLetter mapped but $mountPoint unmounted in $distro. Proceeding to mount helper..." "WARN"
            }
        } else {
            Log-Mount "$driveLetter status is not OK ('$pLine'). Purging stale/disconnected mapping..." "WARN"
            net use $driveLetter /delete /y 2>&1 | Out-Null
        }
    }

    # Clean up redundant legacy Network Shortcut if present
    $lnkPath = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Network Shortcuts\Pixel_Backup_SSD.lnk')
    if (Test-Path $lnkPath) {
        Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue
        Log-Mount "Removed redundant Network Shortcut file." "INFO"
    }

    # ---- 2. Find SSD ---------------------------------------------------
    $ssd = Find-TargetSSD -Config $cfg

    if (-not $ssd) {
        Log-Mount "SSD hardware not detected on USB bus. Exiting." "INFO"
        exit 0
    }

    $driveNum = $ssd.Number
    Log-Mount "Found target SSD: Disk #$driveNum ($($ssd.FriendlyName), $($ssd.OperationalStatus))" "INFO"

    # ---- 3. Remove any Windows-assigned RAW drive letter ---------------
    $part = Get-Partition -DiskNumber $driveNum -PartitionNumber 1 -ErrorAction SilentlyContinue
    if ($part -and $part.DriveLetter) {
        $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction SilentlyContinue
        if ($vol -and $vol.FileSystem -and $vol.FileSystem -ne '') {
            Log-Mount "Disk has a recognized Windows filesystem ($($vol.FileSystem)). Aborting for safety." "WARN"
            exit 0
        }
        Log-Mount "Removing RAW drive letter ($($part.DriveLetter):) assigned by Windows..." "INFO"
        Remove-PartitionAccessPath -DiskNumber $driveNum -PartitionNumber 1 -AccessPath "$($part.DriveLetter):" -ErrorAction SilentlyContinue
    }

    # ---- 4. Check if attached in WSL -----------------------------------
    $isAttached = $false
    try {
        $lsblkOut = wsl -d $distro -e lsblk -nlo KNAME,TYPE 2>$null
        $partMatch = ($lsblkOut | Select-String 'sd([b-z]1)\s+part')
        if ($partMatch) {
            $partDev = $partMatch.Matches[0].Groups[1].Value
            # CRITICAL: Verify the partition is actually responsive and not a dead ghost
            # from a previous abrupt cable pull. If unresponsive, wsl.exe --shutdown clears Hyper-V SCSI.
            wsl -d $distro -e head -c 512 "/dev/$partDev" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $isAttached = $true
                Log-Mount "Partition /dev/$partDev verified attached and responsive in WSL." "INFO"
            } else {
                Log-Mount "Partition /dev/$partDev in lsblk is unresponsive (dead ghost from cable pull). Triggering fast wsl.exe --shutdown reset..." "WARN"
                wsl.exe --shutdown
                Start-Sleep -Milliseconds 1200
            }
        }
    } catch {}

    if (-not $isAttached) {
        Log-Mount "Partition not attached in WSL. Initiating attach..." "INFO"

        # Try elevated Scheduled Task first (Zero-UAC, instantaneous)
        $schtaskRan = $false
        try {
            $queryTask = schtasks /Query /TN $mountTask 2>$null
            if ($LASTEXITCODE -eq 0) {
                Log-Mount "Triggering elevated Scheduled Task: $mountTask" "INFO"
                schtasks /run /tn $mountTask | Out-Null
                $schtaskRan = $true
                for ($i = 0; $i -lt 12; $i++) {
                    Start-Sleep -Milliseconds 500
                    $chk = wsl -d $distro -e lsblk -nlo KNAME,TYPE 2>$null | Select-String 'sd[b-z]1\s+part'
                    if ($chk) { $isAttached = $true; break }
                }
            }
        } catch {}

        # Fall back to elevated Start-Process with 6s watchdog timeout if needed
        if (-not $isAttached) {
            Log-Mount "Scheduled task did not attach block device in time. Using timeout-guarded elevated attach..." "INFO"
            $runSilentExe = Join-Path $scriptDir "run_silent.exe"
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if (Test-Path $runSilentExe) {
                $psi.FileName = $runSilentExe
                $psi.Arguments = "powershell.exe -NoProfile -WindowStyle Hidden -Command wsl --mount \\.\PHYSICALDRIVE$driveNum --bare"
            } else {
                $psi.FileName = "powershell.exe"
                $psi.Arguments = "-NoProfile -WindowStyle Hidden -Command wsl --mount \\.\PHYSICALDRIVE$driveNum --bare"
            }
            $psi.Verb = "RunAs"
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            try {
                $proc = [System.Diagnostics.Process]::Start($psi)
                if ($proc.WaitForExit(6000)) {
                    Log-Mount "Elevated attach process exited with code $($proc.ExitCode)" "INFO"
                    if ($proc.ExitCode -ne 0) {
                        # Self-healing: if disk was in a dirty attach state, unmount first and retry
                        Log-Mount "Attach returned non-zero code. Attempting self-healing unmount reset..." "WARN"
                        $unmountPsi = New-Object System.Diagnostics.ProcessStartInfo
                        if (Test-Path $runSilentExe) {
                            $unmountPsi.FileName = $runSilentExe
                            $unmountPsi.Arguments = "powershell.exe -NoProfile -WindowStyle Hidden -Command wsl --unmount \\.\PHYSICALDRIVE$driveNum"
                        } else {
                            $unmountPsi.FileName = "powershell.exe"
                            $unmountPsi.Arguments = "-NoProfile -WindowStyle Hidden -Command wsl --unmount \\.\PHYSICALDRIVE$driveNum"
                        }
                        $unmountPsi.Verb = "RunAs"
                        $unmountPsi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        $uProc = [System.Diagnostics.Process]::Start($unmountPsi)
                        if ($uProc.WaitForExit(4000)) {
                            Start-Sleep -Milliseconds 600
                            # Retry attach once
                            Log-Mount "Retrying elevated attach after reset..." "INFO"
                            $retryProc = [System.Diagnostics.Process]::Start($psi)
                            $retryProc.WaitForExit(6000) | Out-Null
                        }
                    }
                } else {
                    Log-Mount "Elevated attach process timed out after 6s. Terminating." "ERROR"
                    $proc.Kill()
                }
            } catch {
                Log-Mount "Elevated attach failed to start: $_" "ERROR"
            }

            Start-Sleep -Milliseconds 500
            $chk = wsl -d $distro -e lsblk -nlo KNAME,TYPE 2>$null | Select-String 'sd[b-z]1\s+part'
            if ($chk) { $isAttached = $true }
        }
    } else {
        Log-Mount "Partition is already attached in WSL." "INFO"
    }

    # Strict Gate: Do not proceed if block device is not attached in WSL
    if (-not $isAttached) {
        Log-Mount "CRITICAL: Block device partition is not attached in WSL. Aborting mount to prevent mapping empty rootfs." "ERROR"
        net use $driveLetter /delete /y 2>&1 | Out-Null
        exit 1
    }

    # ---- 5. Mount partition inside WSL & start Samba ------------------
    Log-Mount "Running WSL mount helper script (/usr/local/bin/mount_pixel_ssd.sh)..." "INFO"
    wsl -d $distro -u root -e /usr/local/bin/mount_pixel_ssd.sh 2>&1 | Out-Null

    # Strict Gate: Verify mountPoint is actually mounted inside WSL
    $isMounted = $false
    if ($volLabel) {
        $checkOut = wsl -d $distro -e test -d "$mountPoint/$volLabel" 2>$null
        if ($LASTEXITCODE -eq 0) { $isMounted = $true }
    } else {
        $checkOut = wsl -d $distro -e grep -qs "$mountPoint" /proc/mounts 2>$null
        if ($LASTEXITCODE -eq 0) { $isMounted = $true }
    }

    if (-not $isMounted) {
        Log-Mount "CRITICAL: $mountPoint was not successfully mounted inside $distro! Aborting mount to prevent mapping empty rootfs." "ERROR"
        net use $driveLetter /delete /y 2>&1 | Out-Null
        exit 1
    }
    Log-Mount "$mountPoint verified inside $distro." "INFO"

    # ---- 6. Resolve WSL IP address -------------------------------------
    if (-not $currentWslIp) {
        try {
            $currentWslIp = (wsl -d $distro -e hostname -I 2>$null).Trim().Split(' ')[0]
        } catch {}
    }

    if (-not $currentWslIp) {
        Log-Mount "Failed to resolve WSL IP address. Exiting." "ERROR"
        exit 1
    }
    Log-Mount "Current WSL IP: $currentWslIp" "INFO"

    # ---- 7. Wait for Samba port 445 to be responsive (up to 5s) -------
    $portReady = $false
    for ($i = 0; $i -lt 10; $i++) {
        if (Test-SmbPort -IP $currentWslIp -TimeoutMs 400) {
            $portReady = $true
            Log-Mount "Samba port 445 confirmed ready on $currentWslIp (attempt #$($i+1))." "INFO"
            break
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $portReady) {
        Log-Mount "Samba port 445 not responding on $currentWslIp after 5s. Restarting smbd..." "WARN"
        wsl -d $distro -u root -e /usr/sbin/service smbd restart 2>&1 | Out-Null
        Start-Sleep -Milliseconds 1000
    }

    # ---- 8. Map Windows Drive Letter -----------------------------------
    $isMapped = $false
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        if (net use 2>$null | Select-String $dlPattern) {
            $isMapped = $true
            Log-Mount "$driveLetter confirmed mapped to \\$currentWslIp\$shareName." "INFO"
            break
        }
        Log-Mount "Mapping $driveLetter to \\$currentWslIp\$shareName (attempt #$attempt)..." "INFO"
        $mapResult = net use $driveLetter "\\$currentWslIp\$shareName" /user:$smbUser $smbPass /persistent:no 2>&1
        Log-Mount "net use exit code: $LASTEXITCODE. Output: $mapResult" "INFO"
        if ($LASTEXITCODE -eq 0) {
            $isMapped = $true
            break
        }
        Start-Sleep -Milliseconds 1000
    }

    # Ensure WSL keep-alive is active so WSL never idles down while SSD is mounted
    $keepAliveProc = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like $keepAlivePattern }
    if (-not $keepAliveProc) {
        Start-SilentProcess "wsl.exe" "-d $distro -e sleep infinity"
        Log-Mount "Active WSL keep-alive process verified silently." "INFO"
    }

    # ---- 8. Set Explorer custom label in registry ----------------------
    try {
        $mountKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\##$($currentWslIp)#$shareName"
        if (Test-Path $mountKey) {
            Set-ItemProperty -Path $mountKey -Name "_LabelFromReg" -Value $driveLabel -ErrorAction SilentlyContinue
            Log-Mount "Registry label set to '$driveLabel'" "INFO"
        }
    } catch {}

    # ---- 9. Broadcast Shell change notification to update 'This PC' silently ----
    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class WinShellNotify {
            [DllImport("shell32.dll", CharSet = CharSet.Auto)]
            public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
        }
"@ -ErrorAction SilentlyContinue
        # SHCNE_DRIVEADD = 0x00000008, SHCNF_FLUSH = 0x1000
        [WinShellNotify]::SHChangeNotify(0x00000008, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
        Log-Mount "Broadcasted SHCNE_DRIVEADD notification to refresh 'This PC' drive list." "INFO"
    } catch {
        Log-Mount "Shell notification notice: $_" "WARN"
    }

    # ---- 10. Open Explorer only after ALL background operations are completely verified ----
    if ($OpenExplorer) {
        $target = if ($openFolder -and (Test-Path "$($driveLetter)\$openFolder")) { "$($driveLetter)\$openFolder" } else { "$($driveLetter)\" }
        Log-Mount "All background processes finished. Launching Explorer to $target." "INFO"
        Open-DeduplicatedExplorer -TargetPath $target
    }

    Log-Mount "Mount operation completed successfully." "INFO"
}
catch {
    Log-Mount "Fatal exception during mount: $_" "ERROR"
}
finally {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    Log-Mount "Released lockfile." "INFO"
}
