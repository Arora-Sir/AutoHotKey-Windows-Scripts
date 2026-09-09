# Architecture & Engineering Gotchas: WSL2 ext4 External Storage Engine

## 1. Executive Summary

This document is the engineering reference for the ext4 external SSD automation suite on Windows 11 using WSL2 and Samba. It covers the underlying hardware protocols, kernel traps, failure modes encountered, and the solutions implemented to keep mount/unmount reliable and free of focus-stealing console windows.

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
- **Root Cause**: If code executes `FileExist("P:\...")` or `Test-Path P:\` while the physical drive is disconnected, the Windows SMB redirector (`mrxsmb.sys` / `rdbss.sys`) sends SMB2 requests across TCP port 445 to Samba.
  - Because the physical hardware was yanked, the Linux kernel blocks I/O operations in uninterruptible sleep (D-state).
  - The Windows kernel blocks the calling thread waiting for the full network timeout (30-60 seconds).
  - Because AutoHotkey v1.1 is single-threaded, the entire AHK process freezes.
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
- **Resolution**: Detect known faulted attachment conditions
  (`WSL_E_DISK_ALREADY_ATTACHED`, `Operation not permitted`, or any non-zero
  unmount exit code like `-1073741819`).
  - Instead of waiting 15 seconds for a hung detach to time out, immediately
    trigger `wsl.exe --shutdown`.
  - A VM shutdown terminates the virtual SCSI bus cleanly in 1.2 seconds,
    allowing the subsequent `--bare` attach to succeed immediately in 2.6 seconds.

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
- **Root Cause**:
  1. **Task Scheduler Subsystem Trap**: `WSL_Mount_PixelSSD` and `WSL_Unmount_PixelSSD` were registered in Windows Task Scheduler with `Execute: powershell.exe`.
     - Because `powershell.exe` is a CUI (Console User Interface) application, Windows Task Scheduler invokes `CreateProcessAsUser` in the interactive desktop session.
     - Even with `-WindowStyle Hidden`, Windows Console Subsystem (`conhost.exe` or Windows Terminal) initializes and maps a top-level window onto the desktop before PowerShell can parse its parameters and hide itself.
     - Windows Window Manager immediately grants this new window input focus, stealing focus from the user's active application.
  2. **AutoHotkey Process Spawning**: AutoHotkey v1's native `Run, powershell.exe ...,, Hide` sets `SW_HIDE` in `STARTUPINFO`, but does not pass `CREATE_NO_WINDOW (0x08000000)` to the kernel. In Windows 11, console hosts can still intercept the new console allocation.
  3. **PowerShell `Start-Job` Overhead**: In `unmount_wsl_ssd.ps1`, `Start-Job` was used to run the Ubuntu unmount script with a timeout. In PowerShell 5.1, `Start-Job` spawns an entire secondary `powershell.exe` background worker process, introducing 1.5s latency and console allocation risks.
- **Production Architecture & Solutions**:
  1. **Native GUI Subsystem Launcher (`run_silent.exe`)**:
     - Built from C# source (`SilentLauncher.cs`) compiled via .NET Framework `csc.exe` with `/target:winexe`.
     - Marked as `IMAGE_SUBSYSTEM_WINDOWS_GUI` in its PE header. When Task Scheduler or AutoHotkey executes `run_silent.exe`, Windows NEVER creates a console window or conhost process.
     - Extracts the raw target command from `Environment.CommandLine` (preserving quotes, spaces, and arguments exactly as passed, bypassing CLR argument stripping).
     - Launches `powershell.exe` via `ProcessStartInfo` with `CreateNoWindow = true` (`CREATE_NO_WINDOW = 0x08000000`), `UseShellExecute = false`, and `WindowStyle = ProcessWindowStyle.Hidden`.
     - Because no console window is ever created, there is no window blip, no DWM notification, and no focus theft to begin with.
  2. **Replacement of `Start-Job` with `Invoke-SilentProcess`**:
     - Converted `Start-Job` in `unmount_wsl_ssd.ps1` to direct `System.Diagnostics.Process` with `CreateNoWindow = true` and precise millisecond timeout watchdog.
  3. **Deferred Explorer Opening**:
     - File Explorer is launched ONLY after all background operations (attach, fsck, mount, Samba check, and drive mapping) have fully completed and verified.
  4. **Silent Shell Change Notifications**:
     - Broadcasts native Win32 `SHChangeNotify` messages (`SHCNE_DRIVEADD` 0x00000008, `SHCNE_DRIVEREMOVED` 0x00000020) to update "This PC" silently in the background without stealing user focus.

---

## 6. Device Ejection & Hardware Safe Removal

### Gotcha 10: Safe Hardware Ejection Veto (PNP_VetoOutstandingOpen) & Programmatic PnP Safe Removal

- **The Problem**: Clicking the Windows taskbar "Safely Remove Hardware and Eject Media" icon for the USB SSD resulted in an error dialog: *"Problem Ejecting USB Attached SCSI (UAS) Mass Storage Device: This device is currently in use. Close any programs or windows that might be using the device, and then try again."*
- **Root Cause**:
  1. WSL2 attaches external drives as raw Hyper-V SCSI pass-through disks (`\\.\PHYSICALDRIVE*`). The Hyper-V storage virtualization stack holds exclusive kernel-mode handles to the physical disk.
  2. When the user initiates a safe removal in Windows, the PnP Configuration Manager issues a query-remove request. Because Hyper-V holds open handles, PnP returns `CR_REMOVE_VETOED (23)` with `VetoType = 6 (PNP_VetoOutstandingOpen)` naming the SCSI disk PDO.
  3. Standard Windows Explorer does not know how to tell WSL to unmount; it simply displays the modal error dialog.
- **Architectural Solution**:
  1. **Clean Dismount Pipeline in `unmount_wsl_ssd.ps1`**:
     - Deletes the SMB network drive mapping (`net use P: /delete`).
     - Invokes guest helper `/usr/local/bin/unmount_pixel_ssd.sh` to lazy-unmount `/mnt/pixel_ssd` and stop Samba.
     - Detaches the disk from WSL host (`wsl --unmount \\.\PHYSICALDRIVE*`).
     - Resolves the USB parent device ID dynamically via `DEVPKEY_Device_Parent`.
     - Invokes Win32 Configuration Manager API `CM_Request_Device_EjectW` (`cfgmgr32.dll`) to programmatically cut power and notify Windows that the hardware is safely removable.
  2. **Reactive Auto-Resolution in `Ext4SsdManager.ahk`**:
     - A 400ms polling timer monitors for `#32770` error windows titled "Problem Ejecting USB Attached SCSI...".
     - When detected, the AHK script immediately closes the error dialog via `WinClose`, displays a status tooltip, and triggers `UnmountExt4Ssd(true, false)`.
     - This guarantees that even if the user forgets the `Win+Alt+U` hotkey and uses the Windows taskbar tray icon, the conflict is automatically intercepted and resolved within milliseconds.

### Gotcha 11: Asynchronous Scheduled Task Race Condition & Double-Click Eject Bug

- **The Symptom**: When clicking Windows taskbar eject or the unmount hotkey, the first click would unmount the filesystem but fail to power down the hardware. The user was forced to click eject a second time for Windows to actually complete the safe removal.
- **Diagnosis**:
  - `schtasks /run` is non-blocking - it merely queues the task in Windows Task Scheduler and returns immediately.
  - `unmount_wsl_ssd.ps1` was proceeding to the eject step and calling `CM_Request_Device_EjectW` before `wsl.exe --unmount` had actually finished detaching the physical drive.
  - Because Hyper-V was still in the middle of closing its SCSI handle, Windows PnP vetoed the first eject call. By the time `wsl.exe --unmount` finished a moment later, the user's second click found the disk already free, so only the second attempt succeeded.
- **The Resolution**:
  1. **Cross-Process Synchronization Flag**: `wsl_unmount_elevated.ps1` writes a temporary completion flag (`%TEMP%\wsl_unmount_done.flag`) upon completing the detach.
  2. **Synchronous Barrier**: `unmount_wsl_ssd.ps1` polls for this flag (up to 6 seconds at 250ms intervals), ensuring `wsl.exe --unmount` has fully finished and released all handles before Step 6 begins.
  3. **Multi-Attempt Retry Loop**: Step 6 now executes up to 6 retry attempts (spaced 350ms apart) for `CM_Request_Device_EjectW`, gracefully accommodating any brief driver-stack teardown latency.
  4. **Single-Action Guarantee**: Safe removal now completes reliably on the very first click, displaying Windows native "Safe to Remove Hardware" toast.

---

## 7. Multi-Resolution Display Switching & Desktop Layout Engine

### Gotcha 12: The 73px Logical Screen Width Deficit (1536px vs 1463px) & Boundary Clamping Cascade

- **Symptom**: When switching from Laptop mode to Tablet mode, Simple Sticky Notes windows clump together in the middle of the screen or cascade into each other, instead of maintaining their neat column positions.
- **Root Cause**:
  1. The host laptop display (`DISPLAY1`) runs at 1920x1080 with 125% Windows DPI scaling. The logical desktop resolution is:
     $$\text{Width} = \frac{1920}{1.25} = 1536\text{ DIP}, \quad \text{Height} = \frac{1080}{1.25} = 864\text{ DIP}$$
  2. The tablet display (HDMI dummy plug `DISPLAY4` matching Galaxy Tab S10 Ultra) runs at 2560x1600 with 175% Windows DPI scaling. The logical desktop resolution is:
     $$\text{Width} = \frac{2560}{1.75} \approx 1462.85 \to 1463\text{ DIP}, \quad \text{Height} = \frac{1600}{1.75} \approx 914.28 \to 914\text{ DIP}$$
  3. The tablet screen is 73 logical pixels narrower than the laptop screen (1463px vs 1536px).
  4. On the laptop, Column 3 sits at $X = 1268$ with width $W = 268$, extending flush to the right boundary:
     $$X + W = 1268 + 268 = 1536\text{px}$$
  5. When switched to the tablet, any note positioned at $X = 1268$ exceeds the screen boundary by 73px ($1536 > 1463$).
  6. `ssn.exe` monitors display boundaries. When it detects a window outside the new screen dimensions, it automatically clamps the window inward to keep it visible. This shoves Column 3 into Column 2 ($X = 968$), which then shoves Column 2 into Column 1 ($X = 728$), causing an irreversible clumping cascade.
- **Resolution**: Separate deterministic pixel coordinate profiles for each screen topology:
  - **Laptop Profile**: Col 0 at $X = 0$, Col 1 at $X = 728$, Col 2 at $X = 968$, Col 3 at $X = 1268$ (flush at 1536px).
  - **Tablet Profile**: Shift columns leftward to fit within 1463px: Col 0 at $X = 0$, Col 1 at $X = 640$, Col 2 at $X = 885$, Col 3 at $X = 1190$ ($1190 + 268 = 1458\text{px}$, leaving a safe 5px margin before the 1463px edge).

### Gotcha 13: Dynamic Window Position Snapshotting Poisoning

- **Symptom**: AutoHotkey scripts that try to remember positions dynamically by reading `WinGetPos` on switch and saving to an INI file end up corrupting positions permanently after 1 or 2 display toggles.
- **Root Cause**:
  1. If the user triggers a switch while already on the tablet, or if a switch is triggered while DWM is mid-transition, `WinGetPos` captures the already-clumped or scaled coordinates (e.g. $X = 2219$ or $X = 906$).
  2. The script saves these corrupted coordinates as the "laptop baseline", overwriting the true layout.
  3. Dynamic snapshotting relies on the assumption that windows are in their intended positions at the moment of capture, which is violated during automated lid events, disconnects, and rapid re-toggles.
- **Resolution**: Use static deterministic coordinate profiles. Never dynamically snapshot live coordinates at switch time. The exact pixel coordinates for each note profile are hardcoded in `apply_ssn_layout.ps1` based on mathematical layout rules.

### Gotcha 14: Ephemeral HWNDs and Post-WM_DISPLAYCHANGE Destruction/Recreation

- **Symptom**: Restoring notes by saved window handle (`HWND`) fails because half or all of the windows report as invalid or do not move.
- **Root Cause**: `ssn.exe` responds to the Windows `WM_DISPLAYCHANGE` (0x007E) message by destroying its existing `UINoteWindow` handles and recreating new Win32 windows with entirely new HWNDs to adapt to the new display device context.
- **Resolution**: Never identify sticky notes by HWND across display switches. Instead, identify them dynamically by:
  1. Win32 class name `UINoteWindow`.
  2. Dimension signature $(W, H)$ which Simple Sticky Notes preserves across instances (e.g. $240 \times 120$ for small note, $300 \times 240$ for medium note, $268 \times 548$ for expanded "Today" note, $268 \times 32$ for minimized title bars).
  3. Vertical sorting ($Y$ coordinate) to break ties when multiple notes share identical dimensions.

### Gotcha 15: Hardware EDID / DWM Topology Renegotiation Race Condition (Dual-Wave Settle)

- **Symptom**: The layout script executes, reports success, but notes are still clumped or partially displaced.
- **Root Cause**:
  1. Calling `DisplaySwitch.exe /internal` or `DisplaySwitch.exe /external` initiates physical EDID handshake and DWM reconfiguration. This hardware negotiation takes between 1.5 and 2.5 seconds.
  2. If the positioning script runs too early (e.g. after a fixed 800ms sleep), it moves the windows while Windows is still running on the old display context.
  3. At ~2.0 seconds, Windows finalizes the display transition and broadcasts `WM_DISPLAYCHANGE`. Upon receiving this message, `ssn.exe` recreates its windows at its own default clamped positions, completely undoing the script's work.
- **Resolution**: Dual-wave settlement architecture in `apply_ssn_layout.ps1`:
  1. Active polling loop: Polls every 300ms for up to 6 seconds until target windows exist in the new desktop session.
  2. Primary wave: Positions all notes once windows are detected.
  3. Secondary wave (Dual-wave lock): Sleeps 1.2 seconds to allow DWM and `ssn.exe` to complete any late `WM_DISPLAYCHANGE` handling, then applies `SetWindowPos` a second time with `SWP_NOZORDER | SWP_NOACTIVATE`.

### Gotcha 16: Desktop Window Station Isolation in AutoHotkey (`WinGet` Failure)

- **Symptom**: During or immediately following a display switch, AutoHotkey's built-in `WinGet, idList, List, ahk_class UINoteWindow` returns 0 windows, even while sticky notes are clearly visible on screen.
- **Root Cause**:
  1. When Windows switches display topologies or changes session state, threads can be temporarily isolated from the active interactive desktop station (`WinSta0\Default`).
  2. AutoHotkey v1's `WinGet` uses standard `EnumWindows`, which is scoped to the calling thread's current desktop. If the desktop handle is not synchronized with the active DWM surface, `EnumWindows` returns an empty set.
- **Resolution**: Implement the positioning engine in PowerShell with native Win32 P/Invoke:
  1. Explicitly call `OpenDesktop("Default", 0, false, 0x01FF)` to acquire a handle to the interactive desktop.
  2. Attach the worker thread via `SetThreadDesktop(hDesktop)`.
  3. Query `GetProcessByName("ssn")` and iterate through all process threads using `EnumThreadWindows`. This guarantees enumeration of every note window regardless of desktop transition state.

### Gotcha 17: 16:9 vs 16:10 Vertical Aspect Ratio Variance (864px vs 914px DIP)

- **Symptom**: On the tablet screen, there is approximately 50 pixels of extra empty space between the bottom notes and the taskbar compared to the laptop.
- **Root Cause**:
  1. Host laptop screen is 16:9 aspect ratio ($1920 \times 1080$). At 125% DPI scaling, height is 864 DIP.
  2. Tablet screen is 16:10 aspect ratio ($2560 \times 1600$). At 175% DPI scaling, height is 914 DIP.
  3. The tablet provides $914 - 864 = 50$ extra vertical pixels.
  4. Preserving the exact top positions ($Y = 0$, $Y = 120$, $Y = 240$, $Y = 423$) keeps note alignment consistent from the top of the screen down, leaving the surplus 50px at the bottom.
- **Resolution**: This is mathematically expected behavior due to the 16:10 aspect ratio. Anchoring notes from the top edge maintains visual muscle memory across devices.
