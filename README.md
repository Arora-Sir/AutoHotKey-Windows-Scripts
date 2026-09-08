# How to Use AHK Scripts (for Windows 10 & 11)

Personal AutoHotkey setup: global hotkeys plus always-on background automation (crash recovery, Sefirah phone-link, Python servers), all orchestrated by one startup script.

## Setup

- **Install AutoHotkey**: [installer](https://www.autohotkey.com/) or `winget install AutoHotkey.AutoHotkey` via the v2 dual-runtime installer. Scripts here stay on `#Requires AutoHotkey v1.1` regardless, a v2 script breaks `StartupScript.exe`'s tray submenu (see that file's comments for why).
- **Local Custom Paths**: copy `AllScripts/LocalPaths.ahk.example` -> `AllScripts/LocalPaths.ahk` for your machine paths, app/device config, and skills vault lock scripts. Gitignored.
- **Personal Keywords**: copy `AllScripts/PersonalKeywords.ahk.example` -> `AllScripts/PersonalKeywords.ahk` for private hotstrings. Gitignored.
- **Compiled Executables**: personally-compiled executables (e.g. `StartupScript.exe`) are never tracked in Git, since a compiled AHK exe can be decompiled back into readable script logic - compile `StartupScript.ahk` locally when it changes (see below). Third-party, publicly-distributed utility binaries (the AutoHotkey installers under `AHK Setup/`, NirCmd under `AutoHotkey Companion Files/`) are tracked deliberately, as a convenience bundle - they carry no personal information either way.

## Scripts Overview

| Script                      | Purpose                                                                                                                                                                                                                                                         |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `StartupScript.ahk`         | Orchestrator. Launches everything below at boot with a tray submenu each. Runs as the compiled `StartupScript.exe`.                                                                                                                                             |
| `BasicTasks.ahk`            | Hotkeys only, see tables below. Includes `Win+Alt+L` (3-way cycle: Auto Mode -> Force Locked -> Force Unlocked with bottom-right corner badge) and its own tray submenu (mirrors `Win+Shift+P`'s Toggle Display Mode, plus a Duplicate Only switch with no dedicated hotkey). |
| `BackgroundAutomations.ahk` | Everything that runs with no keypress: Tailscale tray launch, Google Drive silent launch, GravityBridge/CopyClip servers, Sefirah reconnect + phone priority, and Skills Vault auto-lock/unlock watcher (Claude focus locks, Antigravity focus unlocks, badge feedback shown by default, paused while a Force mode is active). |
| `Ext4SsdManager.ahk`        | Everything for the WSL ext4 backup SSD: `Win+Alt+M`/`Win+Alt+U` (manual mount/unmount), auto-mount on boot/hotplug (`mount_wsl_ssd.ps1` / `unmount_wsl_ssd.ps1`), wake-from-sleep remount check, tray items, and the Windows "Problem Ejecting" dialog auto-resolver. |
| `Watchdog.ahk`              | Generic crash-relaunch for whatever's listed in `WATCHDOG_APPS`.                                                                                                                                                                                                |
| `Brightness.ahk`            | Brightness hotkeys.                                                                                                                                                                                                                                             |
| `ClosePrograms.ahk`         | Force-close hotkeys for tray-minimizing apps.                                                                                                                                                                                                                   |
| `HotkeyHelp.ahk`            | In-app hotkey reference / settings GUI.                                                                                                                                                                                                                         |
| `PersonalKeywords.ahk`      | Private hotstrings (gitignored).                                                                                                                                                                                                                                |
| `SunshineMouseWatchdog.ahk` | Remote desktop watchdog for Sunshine: automatically switches the display back to Laptop (PC screen only) on a real disconnect/pause, and manages pointer speed (fast during active sessions, normal on disconnect). Switching TO Tablet mode on connect stays manual (`Win+Shift+P` / `BasicTasks.ahk` tray items) - tried automatic once, but reverted after it raced with Sunshine's own connect-time Duplicate-mode transition and caused a hang. |
| `LocalPaths.ahk`            | Personal machine config (gitignored).                                                                                                                                                                                                                           |
| `SharedHelpers.ahk`         | Pure function library included by other scripts (see ARCHITECTURE.md) - also kept as its own tray entry for quick Edit access; has no hotkeys of its own.                                                                                                      |

`GravityBridge`, `CopyClip`, and `Sefirah` above are separate personal projects/tools (Python servers and an Android companion app) launched or monitored by `BackgroundAutomations.ahk` - they aren't included in this repo.
Their own paths are configured through the gitignored `LocalPaths.ahk`.

## Compiling StartupScript.exe

Task Scheduler launches the compiled `.exe`, not the `.ahk` source, so an edit to `StartupScript.ahk` itself won't take effect until you rebuild it. Every other script still just needs a reload (`Win+Ctrl+Alt+R`), no rebuild involved.

Run `.\build_startup_exe.ps1`: rebuilds with the correct icon/base binary, auto-stops any running `StartupScript.exe` first (it locks itself while running). Doesn't relaunch it, prints the command to do that when ready.

If that script doesn't work on your machine: right-click `StartupScript.ahk` -> **Compile Script (GUI)**, set Source/Destination/Icon to the `.ahk`/`.exe`/`.ico` files here and Base to `AutoHotkeyU64.exe`, then Convert (stop any running `StartupScript.exe` first, it locks its own file).

## Watchdog: auto-relaunch an app if it crashes or closes

- Add an app with one entry, nothing in `Watchdog.ahk` itself ever needs editing:
  ```ahk
  WATCHDOG_APPS := [{name: "SomeApp.exe", path: "C:\Path\To\SomeApp.exe"}]
  ```
- Reacts to _any_ exit, crash or deliberate close, there's no reliable way to tell them apart from outside the process. Closing a watched app normally brings it back within one poll (`CheckIntervalMs`, 10s by default).

## WSL ext4 Backup SSD Automation Suite

Plug-and-play auto-mount engine for external Linux ext4 SSDs on Windows 11 using WSL2, Samba, and AutoHotkey.

- **Automations**:
  - **USB Hotplug**: `WM_DEVICECHANGE` (`0x0007` / `0x8000`) detects hardware arrival via in-memory WMI check (22ms), attaches block device via zero-UAC scheduled task, starts guest keepalive, mounts ext4 (`noatime,nodiratime,errors=remount-ro`), probes Samba TCP port 445, maps drive letter (default `P:`), and opens the configured target folder in Explorer.
  - **USB Unplug**: `WM_DEVICECHANGE` (`0x8004` / hardware drop) gracefully redirects open Explorer tabs viewing the drive to "This PC" (preventing broken window errors), unmaps the drive letter, lazy-unmounts guest ext4, and cleans Hyper-V attachments.
  - **Boot / Wake**: Auto-reconciles state on boot and system wake (`WM_POWERBROADCAST`).
  - **Manual Hotkeys & Tray Controls**:
    - `Win+Alt+M`: Manual mount and open in Explorer.
    - `Win+Alt+U`: Safe ejection (sets flag so watchdog will not prematurely remount while plugged in).
    - Tray Menu: Right-click AutoHotkey tray icon -> "Mount Pixel SSD (P:)" / "Eject Pixel SSD Safely" / "Register Zero-UAC Tasks".

- **Setup & Configuration**:
  1. **One-Time Zero-UAC Registration**:
     - Double-click `AllScripts\PowerShell\Install_WSL_Mount_Tasks.bat` (or click "Register Zero-UAC Tasks" in the tray menu) to register elevated Task Scheduler actions.
  2. **Configuring Your Own Drive**:
     - Copy `AllScripts\PowerShell\ssd_config.json.example` to `AllScripts\PowerShell\ssd_config.json` (gitignored).
     - Customize disk model filters, drive letter, WSL distro, and target folder.
     - Optionally add matching `EXT4_SSD_*` overrides to `AllScripts\LocalPaths.ahk` (gitignored, template in `LocalPaths.ahk.example`).
  3. **Full Architecture & Setup Guide**:
     - See [AllScripts/PowerShell/README.md](AllScripts/PowerShell/README.md) for full Ubuntu Samba setup steps, `/etc/samba/smb.conf` template, and troubleshooting details.

## Working Hotkeys

- ### BRIGHTNESS

  | Key       | Usage                             |
  | --------- | --------------------------------- |
  | F1        | Set Current +5 Brightness         |
  | Shift+F1  | Set Current -5 Brightness         |
  | Ctrl+PgDn | Push Brightness Extremes Down -10 |
  | Ctrl+PgUp | Push Brightness Extremes Up +10   |

- ### BASIC TASKS

  | Key                   | Usage                                                                                                                                                                                    |
  | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | Volume_Up              | Volume Up                                                                                                                                                                                |
  | Volume_Down            | Volume Down                                                                                                                                                                              |
  | Win+Del               | Empty Recycle Bin                                                                                                                                                                        |
  | Win+C                 | Run Calculator                                                                                                                                                                           |
  | Win+M                 | Minimize Active Window                                                                                                                                                                   |
  | Win+F                 | Open FireFox                                                                                                                                                                             |
  | Win+F8                | Bluetooth On/Off (Disabled)                                                                                                                                                              |
  | Win+X+X               | Sleep Laptop (single Win+X still passes through to the normal Quick Link menu)                                                                                                          |
  | Win+Shift+A           | Open Notification Center                                                                                                                                                                 |
  | Win+Shift+E           | (Folder) Open Downloads (Screenshots) Folder                                                                                                                                             |
  | Win+Shift+J           | (Folder) Open Java Course                                                                                                                                                                |
  | Win+Shift+P           | Toggle Display Mode (Laptop 1080p @ 144Hz <-> Tablet 2560x1600 @ 120Hz)                                                                                                                 |
  | Ctrl+Shift+P          | Same as above - alternate keybind, manual PC-side use only (see ARCHITECTURE.md for why it can't be triggered remotely from the tablet)                                                 |
  | Win+Alt+P             | Same as above - third keybind, manual PC-side use only (see ARCHITECTURE.md)                                                                                                             |
  | Win+Alt+C             | Run Alarm Clock                                                                                                                                                                          |
  | Win+Alt+N             | Clear Notification Center                                                                                                                                                                |
  | Win+Alt+X             | (Script) Reconnect Cloudflare Network                                                                                                                                                    |
  | Win+Alt+L             | (Script) Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)                                                                                                                 |
  | Alt+X                 | Open Today Calendar in [Checker Plus Extension](https://chromewebstore.google.com/detail/checker-plus-for-google-c/hkhggnncdpfibdhinjiegagmopldibha)                                     |
  | Alt+D                 | Open ChatGPT                                                                                                                                                                             |
  | Alt+G                 | Monica AI Grammar Correction                                                                                                                                                             |
  | Alt+Shift+S           | Monica AI Content Summary                                                                                                                                                                |
  | Alt+Shift+T           | This Window Always on Top (Disabled -> Using PowerToys)                                                                                                                                  |
  | Alt+Ctrl+D            | Sort Folder Content by Date                                                                                                                                                              |
  | Alt+Ctrl+E            | Enable/Disable File Extension                                                                                                                                                            |
  | Alt+Ctrl+H            | Enable/Disable Hidden Files                                                                                                                                                              |
  | Alt+Ctrl+MouseLButton | Move Background Apps                                                                                                                                                                     |
  | Ctrl+G                | Search the Selected/Clipboard Text                                                                                                                                                       |
  | Ctrl+T+T              | Open New Tab (In Browser)                                                                                                                                                                |
  | Ctrl+J+J              | Close Downloads Bar (In Browser)                                                                                                                                                         |
  | Ctrl+Y+T              | Open YouTube (In Browser)                                                                                                                                                                |
  | Ctrl+Shift+V          | Browser to Go to Previous Tab When Taking a Screenshot in [Awesome Screen Recorder](https://chromewebstore.google.com/detail/awesome-screen-recorder-s/nlipoenfbbikpbjkfpfillcgkoblgpmj) |
  | Ctrl+Shift+WheelUp    | (VS Code) Increase Whole UI Zoom (+0.05), only while VS Code is focused                                                                                                                  |
  | Ctrl+Shift+WheelDown  | (VS Code) Decrease Whole UI Zoom (-0.05), only while VS Code is focused                                                                                                                  |
  | Capslock+Capslock     | Double Tap to Activate/Deactivate                                                                                                                                                        |
  | MouseLButton          | Double Click Taskbar to Show/Hide it - handled by [WindHawk](https://windhawk.net/) (a separate third-party tool), not this repo's AHK code, which has its own version of this hotkey disabled |

- ### EXT4 SSD MANAGER

  | Key       | Usage                                     |
  | --------- | ------------------------------------------ |
  | Win+Alt+M | Mount ext4 Backup SSD & Open in Explorer    |
  | Win+Alt+U | Safely Unmount ext4 Backup SSD              |

- ### HOTKEYHELP

  | Key             | Usage                                   |
  | --------------- | --------------------------------------- |
  | Win+F1          | Display Help                            |
  | Ctrl+F          | Find in Hotkey Help                     |
  | Win+Ctrl+F1     | Excluded Files, Hotkeys, and Hotstrings |
  | Win+Alt+Ctrl+F1 | Raw Hotkey List                         |
  | Win+Alt+F1      | Settings                                |

- ### WINDOW STARTUP SCRIPT

  | Key                     | Usage                                                              |
  | ----------------------- | ------------------------------------------------------------------ |
  | Win+ScrollLock          | Suspend All Scripts' Hotkeys (background timers/watchers keep running) |
  | Win+Ctrl+Alt+ScrollLock | Terminate All Scripts                                              |
  | Win+Ctrl+Alt+R          | Reload All Scripts                                                 |
  | Win+Ctrl+Alt+W          | Run Window Spy Script                                              |

  The tray icon's right-click menu mirrors these last three as "Suspend Hotkeys" / "Exit" / "Reload All" - same actions, same keys.

  - These replace AutoHotkey's own native Suspend Hotkeys/Pause Script/Exit items (which only ever acted on the master script's own hotkeys, not the fleet). So there is exactly one of each, not two.
  - Each managed script's own submenu is trimmed to View Key History/Edit/Restart/Exit for that one script, plus any of its own published quick-actions. "Restart" kills and relaunches just that one script without a full fleet reload.

- ### PERSONAL KEYWORDS
  - It's a key-value pair. Type the key in the text field to get its corresponding value.

    | Key        | Usage                       |
    | ---------- | --------------------------- |
    | ValueOfPie | 3.141592653589793238        |
    | e1.        | demo@example.com (email 1)  |
    | e2.        | demo2@example.com (email 2) |
    | c1.        | +1-555-0100 (contact 1)     |

- ### FORCE CLOSE PROGRAMS
  - For programs that go to the system tray when closed by pressing the close button

    | Key         | Usage                         |
    | ----------- | ----------------------------- |
    | Alt+Ctrl+F4 | Close All Programs            |
    | Alt+F4      | Close Currently Active Screen |

## Get Installed Apps List and Run Apps

- Get installed app names:
  ```powershell
  Get-StartApps | Sort-Object Name | Format-Table -Property Name, AppID
  ```
- Run one from AHK:
  ```ahk
  Run, shell:AppsFolder\SamsungNotes_8wekyb3d8bbwe!App
  ```

## License

[MIT LICENSE](LICENSE)

<br />

---

<h3>
  <p align="center">
    :exclamation::exclamation: Reload the script `StartupScript.ahk` after any edit in ".ahk" file :smile:
  </p>
</h3>

---
