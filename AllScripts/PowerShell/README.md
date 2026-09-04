# WSL2 ext4 SSD Storage & Automation Engine

Automated, commercial-grade storage engine for mounting, managing, and browsing Linux ext4 external SSDs natively on Windows 11 using WSL2, Direct SMB, and AutoHotkey.

---

## 🏗️ Architecture Overview

Windows 11 cannot natively read or mount `ext4` filesystems without third-party drivers. This engine bridges the gap by leveraging Hyper-V block device attachment (`wsl --mount`), guest ext4 optimization (`noatime,nodiratime,errors=remount-ro`), and loopback Direct SMB (port 445), orchestrated by event-driven AutoHotkey monitoring.

```
                                       STORAGE LIFECYCLE ENGINE
+----------------------------+      +----------------------------+      +----------------------------+
|       USB PLUG EVENT       | ---> |    HARDWARE BUS DETECT     | ---> |  WSL ATTACH & KEEP-ALIVE   |
|   (DBT_DEVNODES_CHANGED)   |      |   (22ms in-memory query)   |      | (noatime, nodiratime, fsck)|
+----------------------------+      +----------------------------+      +----------------------------+
                                                                                      |
                                                                                      v
+----------------------------+      +----------------------------+      +----------------------------+
|     SAFE EJECT / PULL      | <--- |   EXPLORER AUTO-REDIRECT   | <--- |    PURE DIRECT SMB 445     |
|   (Lazy umount & flush)    |      |   (Redirect to "This PC")  |      |   (net use P: mapped OK)   |
+----------------------------+      +----------------------------+      +----------------------------+
```

---

## 🛠️ Prerequisites

1. **Windows 11** with WSL2 installed (`wsl --install`).
2. **Ubuntu** (or Debian) WSL2 guest distro.
3. **AutoHotkey v1.1** (running via `StartupScript.exe`).

---

## 🚀 Setup Guide

### Step 1: Ubuntu (WSL2) Configuration

Open your WSL terminal (`wsl -d Ubuntu`) and install Samba and e2fsprogs:

```bash
sudo apt update && sudo apt install -y samba e2fsprogs
```

Create the mount point:

```bash
sudo mkdir -p /mnt/pixel_ssd
```

Add your Samba user (match credentials configured in `ssd_config.json`):

```bash
sudo useradd -M -s /usr/sbin/nologin wsluser 2>/dev/null
sudo smbpasswd -a wsluser
# Enter password (e.g. wslpassword123)
```

Edit `/etc/samba/smb.conf` (`sudo nano /etc/samba/smb.conf`):

```ini
[global]
   workgroup = WORKGROUP
   server string = %h server (Samba, Ubuntu)
   netbios name = WSLUBUNTU
   disable netbios = yes
   smb ports = 445
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user

[PixelSSD]
   comment = Linux ext4 Backup SSD Mount
   path = /mnt/pixel_ssd
   browseable = yes
   read only = no
   guest ok = no
   valid users = wsluser
   force user = root
   create mask = 0777
   directory mask = 0777
```

Install the mount helper script inside Ubuntu:

```bash
sudo cp /mnt/<drive>/path/to/AutoHotKey/AllScripts/PowerShell/mount_pixel_ssd.sh /usr/local/bin/mount_pixel_ssd.sh
sudo chmod +x /usr/local/bin/mount_pixel_ssd.sh
```

Restart Samba:

```bash
sudo service smbd restart
```

---

### Step 2: Windows Configuration

1. **Discover Your SSD Hardware Model**:
   Run this in PowerShell to see your external USB drives and models:

   ```powershell
   Get-Disk | Where-Object BusType -eq 'USB' | Select-Object Number, FriendlyName, Model, BusType, Size
   ```

2. **Configure Your Drive**:
   Copy `ssd_config.json.example` to `ssd_config.json` (this file is gitignored):

   ```powershell
   Copy-Item "ssd_config.json.example" "ssd_config.json"
   ```

   Edit `ssd_config.json` with your disk model filter, drive letter, and credentials:

   ```json
   {
     "disk": {
       "modelFilter": ["YourDiskModel", "VendorName"],
       "busType": "USB",
       "minSizeGB": 200,
       "maxSizeGB": 300
     },
     "wsl": {
       "distro": "Ubuntu",
       "mountPoint": "/mnt/pixel_ssd",
       "volumeLabel": "my_backup_volume"
     },
     "smb": {
       "shareName": "PixelSSD",
       "driveLetter": "P:",
       "driveLabel": "Linux Backup SSD",
       "username": "wsluser",
       "password": "wslpassword123"
     },
     "explorer": {
       "openFolder": "my_backup_volume\\DCIM\\Camera"
     },
     "tasks": {
       "mountTask": "WSL_Mount_PixelSSD",
       "unmountTask": "WSL_Unmount_PixelSSD"
     }
   }
   ```

3. **Register Elevated Tasks (One-Time Setup)**:
   Double-click `Install_WSL_Mount_Tasks.bat` (or right-click the AutoHotkey tray icon and select **"Register Zero-UAC Tasks"**).
   Approve the Windows UAC elevation prompt once. This registers `WSL_Mount_PixelSSD` and `WSL_Unmount_PixelSSD` in Windows Task Scheduler, allowing future automated mounts with zero UAC prompts.

4. **Configure Local AutoHotkey Paths (Optional Overrides)**:
   In `AllScripts/local_paths.ahk` (gitignored, see `local_paths.ahk.example`):
   ```ahk
   EXT4_SSD_MODEL_SUBSTRINGS := "YourDiskModel,VendorName"
   EXT4_SSD_DRIVE_LETTER     := "P:"
   EXT4_SSD_LABEL            := "Linux Backup SSD"
   EXT4_SSD_TARGET_PATH      := "my_backup_volume\DCIM\Camera"
   ```

---

## 📁 File Manifest

| File                          | Type            | Purpose                                                                                                          |
| :---------------------------- | :-------------- | :--------------------------------------------------------------------------------------------------------------- |
| `ssd_config.json.example`     | Git Tracked     | Open-source JSON configuration template.                                                                         |
| `ssd_config.json`             | Gitignored      | Active workstation configuration (credentials, hardware filters).                                                |
| `ssd_common.ps1`              | Helper Script   | Shared module providing `Get-SSDConfig` and `Find-TargetSSD`.                                                    |
| `mount_wsl_ssd.ps1`           | Orchestrator    | Attaches disk, suppresses RAW drive letter, probes port 445, maps drive, and launches Explorer.                  |
| `unmount_wsl_ssd.ps1`         | Teardown        | Redirects open Explorer tabs to "This PC", unmaps drive, flushes WSL attachments, and executes PnP safe removal. |
| `wsl_mount_elevated.ps1`      | Elevated Action | Helper executed by `WSL_Mount_PixelSSD` Task Scheduler action.                                                   |
| `wsl_unmount_elevated.ps1`    | Elevated Action | Helper executed by `WSL_Unmount_PixelSSD` Task Scheduler action (signals completion via flag).                   |
| `setup_scheduled_tasks.ps1`   | Installer       | Registers elevated tasks in Task Scheduler without quote bugs.                                                   |
| `Install_WSL_Mount_Tasks.bat` | Batch Helper    | Self-elevating batch installer for one-click setup.                                                              |
| `mount_pixel_ssd.sh`          | Bash Script     | Guest mount helper (`noatime,nodiratime,errors=remount-ro`) with `fsck.ext4 -p`.                                 |
| `run_silent.exe`              | GUI Launcher    | Native Windows GUI runner (`CREATE_NO_WINDOW`) for zero-focus background PowerShell execution.                   |
| `SilentLauncher.cs`           | C# Source       | Source code for `run_silent.exe` preserving raw command line quotes.                                             |
| `ARCH_AND_GOTCHAS.md`         | Architecture    | Deep-dive documentation on UASP SCSI, kernel SMB hangs, UTF-16LE, Hyper-V faults, and safe eject.                |

---

## 🛡️ Reliability & Self-Healing Features

- **Instant RAW Suppression**: Removes Windows RAW drive letter assignments before AutoPlay can suggest formatting the drive.
- **Kernel MUP Hang Elimination**: Non-blocking DLL checks and fast port probing eliminate the 30-second Windows freeze on dead network shares.
- **WSL2 Idle VM Shutdown Defense**: Background `sleep infinity` keepalive holds the VM open while mounted.
- **Broken Window Prevention**: Active Explorer tabs viewing the drive are automatically navigated to "This PC" before unmounting.
- **Dirty Detach Recovery**: If the drive is abruptly unplugged, `fsck.ext4 -p` automatically replays the journal on the next insertion.

---

## ⚡ Abrupt Disconnect & Auto-Recovery Lifecycle

### Scenario A: Abrupt Physical Pull (Emergency Disconnect)

When the external SSD is suddenly unplugged without unmounting:

1. **Hardware Drop Notification**: Windows broadcasts `WM_DEVICECHANGE` (`0x0007` / `0x8004`).
2. **Instant Bus Verification**: The AutoHotkey watcher executes a 22ms in-memory WMI query confirming physical removal.
3. **Graceful Windows Teardown**:
   - Every active Explorer tab viewing the drive or its subfolders is redirected to "This PC", preventing Windows "Location is not available" error popups.
   - `net use P: /delete /y` instantly severs the network mapping, eliminating Windows kernel `MUP.SYS` dead-share hangs.
4. **Clean Linux State**: Ubuntu runs a lazy unmount (`umount -l`) to release filesystem descriptors, and Hyper-V releases the detached physical drive record.
5. **Flag Reset**: Any manual ejection flags are cleared automatically because the drive is physically absent.

### Scenario B: Physical Re-plug (Automatic Mount)

When the drive is plugged back in later:

1. **Hardware Arrival**: Windows signals device arrival (`0x0007` / `0x8000`).
2. **Model Match**: AutoHotkey detects the target SSD on the USB bus.
3. **Elevated Hyper-V Attach**: The registered zero-UAC Task Scheduler job attaches the drive to WSL2 and strips Windows RAW drive letters.
4. **Safe Journal Replay**: The guest Linux helper executes `/sbin/fsck.ext4 -p` before mounting, repairing any pending journal transactions caused by the abrupt disconnect.
5. **Direct SMB Mapping**: Direct SMB 445 connects, maps `P:`, and launches Explorer directly to your target directory.
6. **Zero Manual Action Required**: No keypresses or commands are needed. The system mounts automatically.

### Scenario C: Proactive Safe Software Ejection (`Win+Alt+U` or Tray Menu)

When you press `Win+Alt+U` (or right-click the tray icon and choose "Eject Pixel SSD Safely"):

1. Open Explorer tabs are safely navigated to "This PC".
2. `net use P: /delete` unmaps the drive letter immediately.
3. Guest helper `/usr/local/bin/unmount_pixel_ssd.sh` runs lazy-unmount and stops Samba.
4. Elevated Task Scheduler action `WSL_Unmount_PixelSSD` detaches `\\.\PHYSICALDRIVE*` from Hyper-V and writes `%TEMP%\wsl_unmount_done.flag`.
5. `unmount_wsl_ssd.ps1` waits for the flag barrier, then invokes native Win32 `CM_Request_Device_EjectW` (`cfgmgr32.dll`) on the parent USB device node with adaptive retry backoff.
6. Windows cuts power to the USB device and displays the native "Safe to Remove Hardware" notification.
7. An ejection marker (`%TEMP%\pixel_ssd_ejected.flag`) prevents the watchdog from re-mounting the drive until physically re-plugged.

### Scenario D: Reactive Taskbar Ejection (Single-Click Conflict Auto-Resolution)

When clicking the Windows taskbar "Safely Remove Hardware" icon instead of using the hotkey:

1. Windows initially attempts removal, finds Hyper-V's open SCSI handle, and begins to display the modal: _"Problem Ejecting USB Attached SCSI (UAS) Mass Storage Device: This device is currently in use."_
2. The `AutoResolveEjectConflict` routine in `BackgroundAutomations.ahk` intercepts the `#32770` dialog within 400ms and closes it via `WinClose`.
3. Displays a non-intrusive status tooltip: _"<Drive Label> in use by WSL. Safely unmounting and ejecting..."_ (default: _"Linux Backup SSD in use by WSL..."_).
4. Invokes `unmount_wsl_ssd.ps1`, which unmounts Ubuntu, detaches from WSL, synchronizes via completion flag, and invokes `CM_Request_Device_EjectW`.
5. Safe removal completes on that **single action**, and Windows displays its native "Safe to Remove Hardware" toast.
