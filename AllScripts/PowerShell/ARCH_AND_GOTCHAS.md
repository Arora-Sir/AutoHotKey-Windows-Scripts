# Architecture & Engineering Gotchas: WSL2 ext4 External Storage Engine

## 1. Executive Summary

This document serves as the permanent engineering reference for the ext4 external SSD automation suite on Windows 11 using WSL2 and Samba. It details the underlying hardware protocols, kernel traps, failure modes encountered, and the exact production solutions implemented to guarantee 100% reliable, zero-focus operation.

---

## 2. Hardware & Protocol Gotchas

### Gotcha 1: NVMe Enclosures & UASP SCSI Classification

- **Symptom**: When plugging in an external NVMe SSD over USB 3.1/3.2, WMI queries for `InterfaceType == "USB"` return zero results. The script believes the drive is absent.
- **Root Cause**: Modern external NVMe enclosures utilize the USB Attached SCSI Protocol (UASP) to achieve high throughput. The Windows storage miniport driver (`uaspstor.sys` / `storport.sys`) exposes the bridge as a SCSI device to the operating system. Consequently, WMI's `Win32_DiskDrive` reports `InterfaceType: SCSI`, not `USB`.
- **Resolution**: Never filter by `InterfaceType == "USB"` in WMI for NVMe-to-USB enclosures. Query `Win32_DiskDrive` matching against disk model substrings (`EXT4_SSD_MODEL_SUBSTRINGS`: e.g. `Samsung`, `SanDisk`, `NVMe`), while verifying bus topology via `Get-Disk` where `BusType -eq 'USB'`.

### Gotcha 2: Windows RAW Drive Letter Assignment & Format Nag Popups

- **Symptom**: Whenever an ext4 disk is connected, Windows assigns a drive letter to the RAW partition and displays an intrusive modal: "You need to format the disk in drive X: before you can use it."
- **Root Cause**: Windows mounts all recognized partition tables (MBR/GPT) by default. Because ext4 is not a native Windows filesystem, Windows marks it as RAW and attempts to prompt the user for formatting.
- **Resolution**: Immediately upon bus arrival, `wsl_mount_elevated.ps1` runs `Get-Partition` and calls `Remove-PartitionAccessPath` to strip the RAW Windows drive letter before Windows Explorer can display formatting nag prompts.

---

## 3. Kernel & Runtime Gotchas

### Gotcha 3: Windows SMB Redirector Kernel Hang in Single-Threaded Runtimes

- **Symptom**: When the external SSD is abruptly unplugged, AutoHotkey freezes completely. Subsequent USB plug events and hotkeys fail to respond for 30 to 60 seconds.
- **Root Cause**: If code executes `FileExist("P:\...")` or `Test-Path P:\` while the physical drive is disconnected, the Windows SMB redirector (`mrxsmb.sys` / `rdbss.sys`) sends SMB2 requests across TCP port 445 to Samba. Because the physical hardware was yanked, the Linux kernel blocks I/O operations in uninterruptible sleep (D-state). The Windows kernel blocks the calling thread waiting for the full network timeout (30-60 seconds). Because AutoHotkey v1.1 is single-threaded, the entire AHK process freezes.
- **Resolution**: NEVER execute blocking filesystem I/O on network drive paths inside AutoHotkey. State presence must be determined via non-blocking local API checks (`DriveGet, pType, Type, P:` and in-memory WMI disk queries).

### Gotcha 4: WSL2 UTF-16LE Pipe Encoding Trap in PowerShell

- **Symptom**: String regex matches on `wsl.exe` output (such as `-match "WSL_E_DISK_ALREADY_ATTACHED"`) consistently evaluate to `$false`, even though the exact string appears on the terminal screen.
- **Root Cause**: `wsl.exe` emits output in UTF-16LE (wide-character) byte streams. When PowerShell captures output via `$out = wsl.exe 2>&1`, null bytes (`[char]0`) are placed between each character (e.g. `W\0S\0L\0...`). Standard regex operations fail to match.
- **Resolution**: Always sanitize raw `wsl.exe` text before parsing:
  ```powershell
  $cleanOut = ($rawOut -replace [char]0, '').Trim()
  ```

### Gotcha 5: Abrupt USB Pulls & Hyper-V Virtual SCSI Fault (0xc0000001)

- **Symptom**: When a USB SSD is abruptly yanked while attached to WSL2, subsequent `wsl --mount` commands fail with `WSL_E_DISK_ALREADY_ATTACHED` and `Operation not permitted`.
- **Root Cause**: An abrupt physical disconnection tears down the underlying USB PDO while Hyper-V still holds an open kernel channel to the virtual SCSI controller. In `dmesg`, this logs as `hv 0xc0000001`. The virtual SCSI bus driver locks up and rejects detach requests.
- **Resolution**: Detect known faulted attachment conditions (`WSL_E_DISK_ALREADY_ATTACHED`, `Operation not permitted`, or any non-zero unmount exit code like `-1073741819`). Instead of waiting 15 seconds for a hung detach to time out, immediately trigger `wsl.exe --shutdown`. A VM shutdown terminates the virtual SCSI bus cleanly in 1.2 seconds, allowing the subsequent `--bare` attach to succeed immediately in 2.6 seconds.

### Gotcha 6: Ghost Partitions in Linux lsblk Table

- **Symptom**: After reconnecting the SSD, `mount_wsl_ssd.ps1` checks `lsblk` and sees `sde1 part`, assuming the drive is already attached. It skips attaching the newly connected physical drive, leaving `P:` mapped to a dead, disconnected Linux device.
- **Root Cause**: Unclean disconnections leave stale partition entries in the guest Linux device tree until an I/O operation is attempted.
- **Resolution**: Perform an active block read test using `head -c 512 /dev/$partDev`. If reading sector 0 fails with an I/O error, the partition is confirmed as a dead ghost. The script executes `wsl.exe --shutdown` to flush Hyper-V, and then cleanly attaches the real physical drive.

---

## 4. Filesystem & Storage Architecture

### Gotcha 7: `wsl --mount --bare` vs `--type ext4`

- **Why `--type ext4` Fails**: Passing `--partition 1 --type ext4` tells WSL to mount the partition inside the hidden WSL system distro. If the ext4 journal has uncommitted transactions from an unclean shutdown, WSL aborts with `Operation not permitted`.
- **Why `--bare` Succeeds**: `--bare` attaches the raw block device directly to the Linux VM (`/dev/sd*`) without attempting an internal mount. This allows our guest helper `/usr/local/bin/mount_pixel_ssd.sh` to safely run `fsck.ext4 -p` to replay the journal, and mount with optimized flags:

  ```bash
  mount -o noatime,nodiratime,errors=remount-ro /dev/sde1 /mnt/pixel_ssd
  ```

  - `noatime,nodiratime`: Eliminates flash wear and latency by disabling access timestamp updates.
  - `errors=remount-ro`: Prevents filesystem corruption by immediately remounting read-only if hardware disconnects during write.

### Gotcha 8: Fail-Closed vs Fail-Open SMB Mapping (The 0.98 TB Empty Rootfs Bug)

- **The Bug**: WSL2's virtual root disk (`ext4.vhdx`) has a default virtual capacity of 1.0 TB (~952 GB free). If the ext4 partition failed to mount, `/mnt/pixel_ssd` was simply an empty directory on WSL's root disk. Mapping `P:` in that state showed `952 GB free of 0.98 TB` and "This folder is empty".
- **The Rule**: Fail-closed architecture. Under no circumstances may `net use` execute unless:
  1. The block device partition is verified alive in `lsblk`.
  2. The actual volume subdirectory (`/mnt/pixel_ssd/backup_volume`) is verified to exist in Ubuntu.
     If either check fails, `mount_wsl_ssd.ps1` immediately deletes any existing `P:` mapping and exits with error.

---

## 5. User Experience & Focus Preservation

### Gotcha 9: Focus Theft from Console Window Creation & Task Scheduler Execution

- **The Problem**: Whenever the SSD was connected or disconnected, a console window blipped onto the screen for 50 to 100 milliseconds, and whatever the user was typing lost focus.
- **Deep Root Cause Analysis**:
  1. **Task Scheduler Subsystem Trap**: `WSL_Mount_PixelSSD` and `WSL_Unmount_PixelSSD` were registered in Windows Task Scheduler with `Execute: powershell.exe`. Because `powershell.exe` is a CUI (Console User Interface) application, Windows Task Scheduler invokes `CreateProcessAsUser` in the interactive desktop session. Even with `-WindowStyle Hidden`, Windows Console Subsystem (`conhost.exe` or Windows Terminal) initializes and maps a top-level window onto the desktop before PowerShell can parse its parameters and hide itself. Windows Window Manager immediately grants this new window input focus, stealing focus from the user's active application.
  2. **AutoHotkey Process Spawning**: AutoHotkey v1's native `Run, powershell.exe ...,, Hide` sets `SW_HIDE` in `STARTUPINFO`, but does not pass `CREATE_NO_WINDOW (0x08000000)` to the kernel. In Windows 11, console hosts can still intercept the new console allocation.
  3. **PowerShell `Start-Job` Overhead**: In `unmount_wsl_ssd.ps1`, `Start-Job` was used to run the Ubuntu unmount script with a timeout. In PowerShell 5.1, `Start-Job` spawns an entire secondary `powershell.exe` background worker process, introducing 1.5s latency and console allocation risks.
- **Production Architecture & Solutions**:
  1. **Native GUI Subsystem Launcher (`run_silent.exe`)**:
     - Built from C# source (`SilentLauncher.cs`) compiled via .NET Framework `csc.exe` with `/target:winexe`.
     - Marked as `IMAGE_SUBSYSTEM_WINDOWS_GUI` in its PE header. When Task Scheduler or AutoHotkey executes `run_silent.exe`, Windows NEVER creates a console window or conhost process.
     - Extracts the raw target command from `Environment.CommandLine` (preserving quotes, spaces, and arguments exactly as passed, bypassing CLR argument stripping).
     - Launches `powershell.exe` via `ProcessStartInfo` with `CreateNoWindow = true` (`CREATE_NO_WINDOW = 0x08000000`), `UseShellExecute = false`, and `WindowStyle = ProcessWindowStyle.Hidden`.
     - Guarantees 0.0ms window blip, zero DWM notifications, and 0% focus theft.
  2. **Replacement of `Start-Job` with `Invoke-SilentProcess`**:
     - Converted `Start-Job` in `unmount_wsl_ssd.ps1` to direct `System.Diagnostics.Process` with `CreateNoWindow = true` and precise millisecond timeout watchdog.
  3. **Deferred Explorer Opening**:
     - File Explorer is launched ONLY after all background operations (attach, fsck, mount, Samba check, and drive mapping) have fully completed and verified.
  4. **Silent Shell Change Notifications**:
     - Broadcasts native Win32 `SHChangeNotify` messages (`SHCNE_DRIVEADD` 0x00000008, `SHCNE_DRIVEREMOVED` 0x00000020) to update "This PC" silently in the background without stealing user focus.
