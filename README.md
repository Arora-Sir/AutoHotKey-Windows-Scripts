# How to Use AHK Scripts (for Windows 10 & 11)

Personal AutoHotkey fleet: global productivity hotkeys plus always-on background automation (crash recovery, Sefirah phone-link, Python servers, Linux ext4 backup SSD auto-mounting, DRM video streaming mode, Skills Vault auto-locking, and headless tablet display streaming), all orchestrated by a single compiled startup master script.

## Setup & First-Time Quickstart

Getting the fleet running on a new machine requires a few one-time manual configurations (to protect your privacy), followed by a 1-click automated build and registration.

### 1. Manual Prerequisites (One-Time)

1. **Install AutoHotkey v1.1**:
   - Download the official [v1.1 installer](https://www.autohotkey.com/) or run `winget install AutoHotkey.AutoHotkey` (select v1.1 if prompted).
   - *Note*: Every script in this fleet stays on `#Requires AutoHotkey v1.1` (v2 breaks `StartupScript.exe`'s tray submenu architecture).
2. **Configure Local Paths**:
   - Copy `AllScripts/LocalPaths.ahk.example` -> `AllScripts/LocalPaths.ahk`.
   - Fill in your machine-specific paths, device IPs, and optional tool locations.
   - This file is automatically **gitignored** to keep personal directories private.
3. **Configure Personal Keywords & App Launchers**:
   - Copy `AllScripts/PersonalKeywords.ahk.example` -> `AllScripts/PersonalKeywords.ahk`.
   - Add your private hotstrings, email shortcuts, or app launchers (gitignored).
4. **Enable Git Leak & Quality Protection (Recommended for Git Clones)**:
   - Run `git config core.hooksPath .githooks` in your terminal.
   - Activates `.githooks/pre-commit`, which automatically:
     - Prevents committing personal usernames, computer names, or private configuration files into public git history.
     - Enforces clean code comments and documentation by running `python scripts/clean_dashes.py --check` (blocks em-dashes and comment double-hyphens). Auto-repair anytime using `python scripts/clean_dashes.py --staged`.
5. **Optional: Linux ext4 Backup SSD Engine**:
   - If using external ext4 backup SSDs via WSL2: Copy `AllScripts/PowerShell/ssd_config.json.example` -> `AllScripts/PowerShell/ssd_config.json` (gitignored) and customize your drive letter, disk model, and WSL distro.

### 2. Automated 1-Click Build & Auto-Start

Once your local paths are configured, compile and register the fleet:

- **1-Step Terminal Build**:
  ```powershell
  .\build_startup_exe.ps1 -Relaunch
  ```
  - Automatically compiles `AllScripts\StartupScript.exe` using custom icons and the base 64-bit runtime.
  - Detects if `"AHK Startup Script"` is missing from Windows Task Scheduler and automatically launches `setup_startup_task.ps1` (prompting for Administrator approval once) to register the scheduled task.
  - Launches the fleet immediately via Task Scheduler in your standard user session.
- **Explorer 1-Click Batch Wrappers**:
  - Double-click **`.\Install_Startup_Task.bat`**: Self-elevates and registers the scheduled task directly.
  - Double-click **`.\Uninstall_Startup_Task.bat`**: Self-elevates and unregisters the scheduled task cleanly.
- **Why Task Scheduler instead of `shell:startup`?**
  - The task is registered with a **30-second logon delay** (`PT30S`).
  - At Windows user logon, Windows Explorer, audio services, network adapters (Tailscale/Wi-Fi), and graphics drivers initialize concurrently across multiple threads.
  - A 30-second delay guarantees that the desktop environment settles completely before the fleet launches, preventing startup race conditions and missing notification tray icons.
  - Configured with `RunLevel Limited` under your standard account (`$env:USERNAME`), eliminating boot-time UAC prompts while preserving normal window message routing.

---

## Compiling & Relaunching StartupScript.exe

Windows Task Scheduler launches the compiled binary `StartupScript.exe`, not the `.ahk` source file. A source edit to `StartupScript.ahk` takes effect only after recompiling:

- **Recompile Command**: Run `.\build_startup_exe.ps1` (or click **"Recompile & Relaunch"** under Additional Scripts -> StartupScript in the tray menu).
- **Safe Recompilation**: Automatically terminates the running `StartupScript.exe` to release file locks, compiles a fresh binary via `Ahk2Exe`, and restarts the fleet seamlessly via Task Scheduler.
- **Child Script Edits**: All managed child scripts (`BasicTasks.ahk`, `Brightness.ahk`, etc.) require only an instant fleet reload (`Win+Ctrl+Alt+R` or click **"Reload All"** under Additional Scripts -> StartupScript), no recompilation needed.

---

## Skills Vault Auto-Lock & Org Safe Mode (Claude vs. Antigravity)

Protects personal skills vaults, private study roadmaps, and sensitive configuration directories during professional or organizational pair-programming sessions.

- **Automated Focus Watcher (`BackgroundAutomations.ahk`)**:
  - Continuously monitors active window focus:
    - **Focusing Claude (`claude.exe`)**: Automatically triggers `lock-personal-skills.ps1` to revoke permissions and lock personal vaults (org safe mode). Displays an amber/red bottom-right badge.
    - **Focusing Antigravity (`Antigravity.exe` or `agy.exe`)**: Automatically triggers `unlock-personal-skills.ps1` to restore full personal workspace permissions. Displays a deep green badge.
- **Manual Cycle Mode (`BasicTasks.ahk`)**:
  - Press **`Win+Alt+L`** (or click **"Cycle Skills Vault Mode"** in the `BasicTasks` tray submenu).
  - Cycles between three modes: `Auto` -> `Force Locked` -> `Force Unlocked`.
  - Debounced with a 2000ms settle window and protected by a Win32 named mutex (`SkillsVaultLock_AHK_v1`) to prevent rapid presses from racing `icacls` ACL permissions sweeps.
  - Color-coded bottom-right corner badge confirms status: Deep Red for `[LOCKED]`, Deep Green for `[UNLOCKED]`, Deep Blue for `[AUTO]`, and Amber for `applying...`.

---

## Tablet Headless Display & Mouse Speed Engine (SunshineDisplayWatchdog)

Enables desktop streaming to a tablet (such as Samsung Galaxy Tab S10 Ultra) or handheld device via Moonlight and Sunshine without physical monitor constraints. Managed by `SunshineDisplayWatchdog.ahk`, pinned directly at the top of `StartupScript`'s master tray menu.

- **Display Switching Hotkeys**:
  - Press **`Win+Alt+P`**: Toggles between **PC Screen Only** (1080p @ 144Hz, mouse speed 10, pointer precision ON) and **Tablet Only** (dummy plug 2560x1600 @ 120Hz, mouse speed 20, pointer precision OFF). Resets mouse speed in 0 milliseconds.
  - Press **`Win+Alt+Shift+P`**: Toggles between **Extend Displays** (dual screen desktop, mouse speed 10) and **Duplicate Displays** (mirrored screen, mouse speed 20).
- **Master Tray Submenu & Dynamic Status Checkmarks**:
  - Pinned directly at the top level of the master AutoHotkey tray menu with zero extra standalone icons cluttering the notification area.
  - Submenu provides 1-click switching between PC Screen Only, Tablet Only, Extend Displays, and Duplicate Displays with a dynamic checkmark (tick) highlighting the currently active display topology.
  - Modern bottom-right rounded dark toast badge (`ShowBottomRightBadge`) displays mode transitions for 5.5 seconds with auto-calculated dimensions.
- **Sunshine Extended Desktop Profile**:
  - Dedicated "Desktop (Extended Tab)" profile in Sunshine (`apps.json`) targeting `\\.\DISPLAY4`.
  - Tablet displays the extended monitor directly while the laptop remains the primary display with all taskbar notification icons intact.
- **Watchdog Auto-Recovery (`SunshineDisplayWatchdog.ahk`)**:
  - Fast-reacting watchdog loop checks session state every 1.5 seconds.
  - Active stream synchronization: boosts mouse speed to 20 during active Moonlight streaming sessions across PC Screen Only (default mirror), Duplicate, and Tablet Only modes.
  - Disconnect or pause restores normal mouse speed (10) within 1.5 seconds on PC Screen Only, Duplicate, and Extend modes.
  - Active display topology guard: enforces mouse speed 10 when the stream is idle on laptop or extended displays, preventing speed-sticking glitches while keeping tablet streaming fast.
- **Hardware Lid-Open Auto-Recovery**:
  - Opening laptop lid triggers a Win32 `WM_DISPLAYCHANGE` notification.
  - Automatically restores mouse speed to 10 and restores laptop display mode if `monCount <= 1`. In Extend or Duplicate mode, multi-monitor configuration is preserved untouched.
- **System Wake, Hibernate & Session Unlock Auto-Recovery**:
  - Catches Win32 `WM_POWERBROADCAST` (0x0218) system resume events.
  - Triple-wave recovery (500ms, 2000ms, and 4000ms) restores display topology to PC Screen Only (`DISPLAY1`), restores mouse speed to 10, cycles low-level keyboard hooks to prevent dead keys after Modern Standby, and suppresses stale pre-wake Sunshine log events.
  - Catches Win32 `WM_WTSSESSION_CHANGE` (0x02B1) `WTS_SESSION_UNLOCK` events: refreshes low-level keyboard hooks after unlock while preserving Tablet Only mode during remote PIN entry.
- **Simple Sticky Notes Multi-Resolution Auto-Arrangement (`apply_ssn_layout.ps1`)**:
  - Automatically re-arranges Simple Sticky Notes (`ssn.exe`) windows to match the active screen resolution and DPI scaling:
    - **Laptop (1536x864 DIP)**: 4 columns flush against the right bezel ($X = 1268$, $W = 268 \to 1536\text{px}$).
    - **Tablet (1463x914 DIP)**: 4 columns shifted left to fit within the narrower 1463px canvas ($X = 1190$, $W = 268 \to 1458\text{px}$, leaving a 5px margin).
  - Eliminates clumping, overlapping, and off-screen window drift across manual toggles (`Win+Alt+P`), Moonlight disconnects, and lid re-openings using dual-wave Win32 thread enumeration.

---

## Browser graphics acceleration and DRM streaming mode

When streaming your desktop to a tablet or remote client via Moonlight/Sunshine, DRM-protected video (Netflix, Prime Video, Hotstar, Udemy) displays as a black screen due to Chromium hardware acceleration capturing protected surfaces.

- **Toggle Action**: Click **"Graphics Accel: Brave (ON) / Chrome (OFF)"** inside the `BasicTasks` tray submenu.
- **Live Status Indication**: Displays real-time hardware acceleration status for both Brave and Chrome on a single line with dynamic updates.
- **How it Works**:
  1. Detects active or frontmost Chromium browser (Brave or Google Chrome) via immediate focus, recent 20-second focus tracking across tray clicks, or desktop window Z-order. If neither browser is active, displays an informative badge and exits gracefully without disrupting background processes.
  2. Sends `WM_CLOSE` to gracefully save open tabs and session history, then terminates lingering background processes to unlock configuration files.
  3. Atomically edits Chromium's `Local State` JSON file to toggle `"hardware_acceleration_mode": {"enabled": false}`.
  4. Relaunches the browser with `--disable-gpu --restore-last-session --disable-session-crashed-bubble`.
  5. Displays a color-coded bottom-right corner badge indicating the new status.
- **Zero Display Alterations**: Strictly modifies browser acceleration state; does not alter monitor resolutions, refresh rates, or virtual display topologies.

---

## Dynamic Bottom-Right Corner Badge Engine

Shared toast notification surface (`AllScripts/SharedHelpers.ahk`) providing clean visual feedback for debounced toggles and background events.

- **Singleton Surface**: A second badge update modifies text and color in place without window destruction, eliminating visual flicker and transition gaps.
- **DPI Scaling Immune**: Operates with `-DPIScale` for 1:1 physical screen pixel accuracy across high-DPI displays.
- **Auto-Sizing & Aesthetics**: Uses Win32 GDI `DrawTextW` to dynamically size the badge according to text extent, with modern 10px rounded corners applied via `SetWindowRgn`.
- **Color Palette**:
  - Deep Green (`#1A6E3C`): Unlocked / active state.
  - Deep Red (`#8B1A1A`): Locked / restricted state.
  - Deep Blue (`#0D4F8B`): Automatic / focus-driven state.
  - Dark Slate Grey (`#3A3D40`): Off / inactive state.
  - Amber (`#6E5A00`): In-progress / applying changes.
  - Dark Orange (`#7A3B00`): Error.

---

## Native Core Audio Microphone Mute & Dynamic Tray Indicator

Global system-wide microphone mute toggle with real-time HUD feedback and an intelligent system tray indicator (`AllScripts/SharedHelpers.ahk` and `AllScripts/BasicTasks.ahk`).

- **Toggle Hotkey**: Press **`Win+Ctrl+Alt+M`** to toggle microphone mute state instantly.
- **Direct WASAPI Execution**: Calls Windows Core Audio COM interfaces (`IMMDeviceEnumerator`, `IAudioEndpointVolume`) directly via Win32 `DllCall`. Executes in under 5ms with zero process-spawning overhead.
- **Dual Endpoint Synchronization**: Simultaneously targets both `eConsole` (0) and `eCommunications` (2) capture endpoints so Discord, Zoom, Microsoft Teams, Google Meet, and browser calls are all muted in sync.
- **Dynamic System Tray Indicator**:
  - **Mute-Only Visibility**: The tray icon appears in the notification area only when the microphone is muted (`mic_muted.ico`). When unmuted, it hides completely for zero taskbar clutter.
  - **Option 1 High-Contrast Icon**: Features a solid pure-white (`#FFFFFF`) microphone body for maximum luminance contrast on dark taskbars (`#202020`), crossed by a vivid neon-red (`#FF2D55`) diagonal slash. Pixel-perfect at 16x16 (96 DPI) up to 64x64 high-DPI scaling.
  - **1-Click Unmuting**: Left-clicking the muted tray icon immediately unmutes the microphone and dismisses the icon.
- **Hardware & OS State Synchronization**:
  - A lightweight 1500ms background watcher (`WatchMicrophoneMuteState`) keeps the tray icon synchronized if the microphone is muted or unmuted externally via hardware buttons or third-party meeting software, without triggering disruptive toast notifications.
- **Visual HUD Feedback**: Displays an instant bottom-right rounded corner badge (`ShowBottomRightBadge`): deep red (`#8B1A1A`) for "Microphone Muted" and deep green (`#1A6E3C`) for "Microphone Unmuted".

---

## Watchdog: Auto-Relaunch Applications on Exit or Crash

`Watchdog.ahk` watches essential background processes and automatically relaunches them if they close or crash.

- Configure watched applications in `AllScripts/LocalPaths.ahk`:
  ```ahk
  WATCHDOG_APPS := [{name: "SomeApp.exe", path: "C:\Path\To\SomeApp.exe"}]
  ```
- Reacts to any application termination, checking every 10 seconds (`CheckIntervalMs`) and restarting missing processes silently.

---

## WSL ext4 Backup SSD Automation Suite

Plug-and-play auto-mount engine for external Linux ext4 SSDs on Windows 11 using WSL2, Samba, and AutoHotkey (`AllScripts/Ext4SsdManager.ahk`).

- **Automations**:
  - **USB Hotplug**: `WM_DEVICECHANGE` (`0x0007` / `0x8000`) detects hardware arrival via in-memory WMI check (22ms), attaches block device via zero-UAC scheduled task, starts guest keepalive, mounts ext4 (`noatime,nodiratime,errors=remount-ro`), probes Samba TCP port 445, maps drive letter (default `P:`), and opens the configured target folder in Explorer.
  - **USB Unplug**: `WM_DEVICECHANGE` (`0x8004` / hardware drop) gracefully redirects open Explorer tabs viewing the drive to "This PC" (preventing broken window errors), unmaps the drive letter, lazy-unmounts guest ext4, and cleans Hyper-V attachments.
  - **Boot / Wake**: Auto-reconciles state on boot and system wake (`WM_POWERBROADCAST`).
  - **Manual Hotkeys & Tray Controls**:
    - `Win+Alt+M`: Manual mount and open in Explorer.
    - `Win+Alt+U`: Safe ejection (sets flag so watchdog will not prematurely remount while plugged in).
    - Tray Menu: Click AutoHotkey tray icon -> "Additional Scripts" -> "Ext4SsdManager" -> "Mount Pixel SSD (P:)" / "Eject Pixel SSD Safely" / "Register Zero-UAC Tasks".
- **Setup & Guide**:
  - Double-click `AllScripts\PowerShell\Install_WSL_Mount_Tasks.bat` to register zero-UAC scheduled tasks.
  - See [AllScripts/PowerShell/README.md](AllScripts/PowerShell/README.md) for full Samba configuration steps and architecture details.

---

## Cross-Device Wireless Sharing Engine (S24 Ultra & Tab S10 Ultra)

Direct, zero-friction file transfer from Windows Explorer to connected Samsung devices (`/sdcard/Download/_LaptopTransfers/`) via Dual-IP ADB (`SendToDevice_Adb.ps1`).

- **Hotkeys**:
  - Single tap **`Win+Alt+T`**: Pushes selected Explorer file(s) to Samsung Galaxy S24 Ultra.
  - Double tap **`Win+Alt+T+T`** (within 500ms): Pushes selected Explorer file(s) to Samsung Galaxy Tab S10 Ultra.
- **Failover & Safety**:
  - **Dual-IP Failover**: Probes Tailscale IP first; if offline, immediately fails over to Local Wi-Fi LAN IP (or dynamically from `sefirah.db`).
  - **500ms Socket Pre-Check**: Eliminates the native 21-second ADB connect timeout on unreachable networks.
  - **Duplicate Auto-Numbering**: Prevents overwriting files in destination (`notes (1).txt`, `notes (2).txt`) using O(1) in-memory HashSets.
  - **URI-Encoded MediaScanner**: Triggers Android media indexation with properly escaped URIs so transferred files appear immediately in Samsung Gallery and My Files.
  - **Interactive Sefirah Fallback**: Automatically launches Sefirah GUI if wireless debugging is offline on Android.

---

## Master Tray Menu Organization

`StartupScript.ahk` consolidates the entire fleet into a clean, single system tray icon:

- **Left-Click & Right-Click**: Both left-click and right-click on the tray icon open the master tray context menu. Nothing else.
- **Pinned Scripts**: Pinned scripts (`SunshineDisplayWatchdog`, `BasicTasks`, `PersonalKeywords`) sit at the top level of the menu for instant access.
- **Additional Scripts Submenu**: All remaining background scripts (`BackgroundAutomations`, `Brightness`, `ClosePrograms`, `Ext4SsdManager`, `HotkeyHelp`, `Watchdog`) are collapsed into an expandable **"Additional Scripts"** submenu to prevent vertical clutter.
- **Submenu Separator Lines**: Child script submenus cleanly separate standard controls (`View Key History`, `Edit`, `Restart`, `Exit`) from custom published actions using native horizontal separator bars (`-|`).
- **Global Fleet Actions**: Positioned at the bottom: **"Suspend Hotkeys"** (global cascade toggle) and **"Exit"**. Fleet maintenance controls (**"Reload All"** and **"Recompile & Relaunch"**) live inside **"Additional Scripts -> StartupScript"** to prevent top-level menu clutter.

---

## Working Hotkeys

- ### BRIGHTNESS

  | Key         | Usage                             |
  | :---------- | :-------------------------------- |
  | `F1`        | Set Current +5 Brightness         |
  | `Shift+F1`  | Set Current -5 Brightness         |
  | `Ctrl+PgDn` | Push Brightness Extremes Down -10 |
  | `Ctrl+PgUp` | Push Brightness Extremes Up +10   |

- ### BASIC TASKS

  | Key                     | Usage                                                                                                |
  | :---------------------- | :--------------------------------------------------------------------------------------------------- |
  | `WheelUp` / `WheelDown` | (Over Taskbar) System Volume Up / Down when mouse is scrolled anywhere over the Windows Taskbar      |
  | `Volume_Up`             | Volume Up (+10)                                                                                      |
  | `Volume_Down`           | Volume Down (-10)                                                                                    |
  | `Win+Del`               | Empty Recycle Bin                                                                                    |
  | `Win+C`                 | Run Calculator                                                                                       |
  | `Win+M`                 | Minimize Active Window                                                                               |
  | `Win+F`                 | Open Firefox                                                                                         |
  | `Win+X+X`               | Sleep Laptop (double-tap Win+X puts laptop to sleep; single Win+X opens normal Quick Link menu)      |
  | `Win+Shift+A`           | Open Notification Center / Action Center                                                             |
  | `Win+Shift+E`           | Open Screenshots Folder (`%UserProfile%\Pictures\Screenshots`)                                       |
  | `Win+Shift+J`           | Open Java Course Folder (`%PATH_JAVA_COURSE%`)                                                       |
  | `Win+Alt+C`             | Run Windows Alarm Clock (`Microsoft.WindowsAlarms`)                                                  |
  | `Win+Alt+Ctrl+C`        | Open PowerShell 7 as Administrator                                                                   |
  | `Win+Alt+N`             | Clear All Notifications in Windows 11 Action Center                                                  |
  | `Win+Alt+X`             | Reconnect Cloudflare WARP / Run IP Rotator (`%PATH_IP_ROTATOR%`)                                     |
  | `Win+Alt+L`             | Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)                                     |
  | `Win+Ctrl+Alt+M`        | Toggle Microphone Mute state across all endpoints with HUD badge and dynamic tray indicator          |
  | `Win+Alt+T`             | Wirelessly send selected file(s) to S24 Ultra (Double-tap within 500ms sends to Tab S10 Ultra)       |
  | `Alt+Ctrl+Z`            | Capture selection and open in ShareX Image Editor                                                    |
  | `Ctrl+C`                | (In OneNote) Intercepts OneNote copy to extract clean text instead of pasting as an image/screenshot |
  | `Alt+F11`               | Toggle Window Caption Bar / Titlebar on active window (borderless fullscreen)                        |
  | `Alt+X`                 | Open Today's Calendar in browser (Checker Plus extension / Google Calendar)                          |
  | `Alt+D`                 | Open ChatGPT in browser                                                                              |
  | `Alt+G`                 | Monica AI Grammar Correction (copies selected text and launches Monica grammar fix)                  |
  | `Alt+Shift+S`           | Monica AI Summarize Content (copies selected text and launches Monica summary)                       |
  | `Alt+Ctrl+D`            | Sort Explorer Folder Content by Date                                                                 |
  | `Alt+Ctrl+E`            | Toggle File Extension Visibility in Explorer                                                         |
  | `Alt+Ctrl+H`            | Toggle Hidden Files Visibility in Explorer                                                           |
  | `Alt+Ctrl+MouseLButton` | Move background windows without activating or bringing them to foreground                            |
  | `Ctrl+G`                | Google Search selected/clipboard text in browser                                                     |
  | `Ctrl+T+T`              | Open new browser tab from anywhere (double-tap Ctrl+T)                                               |
  | `Ctrl+J+J`              | Close bottom downloads shelf in Chrome/Brave (double-tap Ctrl+J)                                     |
  | `Ctrl+Y+T`              | Open YouTube in browser                                                                              |
  | `Ctrl+Shift+V`          | Return to previous browser tab when capturing screenshot in Awesome Screen Recorder                  |
  | `Ctrl+Shift+WheelUp`    | (In VS Code) Increase Whole UI Zoom (+0.05 zoomLevel)                                                |
  | `Ctrl+Shift+WheelDown`  | (In VS Code) Decrease Whole UI Zoom (-0.05 zoomLevel)                                                |
  | `Capslock+Capslock`     | Double-tap CapsLock to toggle CapsLock on/off (prevents accidental toggling)                         |

- ### SUNSHINE DISPLAY WATCHDOG

  | Key               | Usage                                                                                                       |
  | :---------------- | :---------------------------------------------------------------------------------------------------------- |
  | `Win+Alt+P`       | Toggle PC Screen Only (1080p @ 144Hz, mouse speed 10) <-> Tablet Only (2560x1600 @ 120Hz, mouse speed 20) |
  | `Win+Alt+Shift+P` | Toggle Extend Displays (Dual screens, mouse speed 10) <-> Duplicate Displays (Mirrored, mouse speed 20)    |

- ### EXT4 SSD MANAGER

  | Key         | Usage                                    |
  | :---------- | :--------------------------------------- |
  | `Win+Alt+M` | Mount ext4 Backup SSD & Open in Explorer |
  | `Win+Alt+U` | Safely Unmount ext4 Backup SSD           |

- ### HOTKEYHELP

  | Key               | Usage                                   |
  | :---------------- | :-------------------------------------- |
  | `Win+F1`          | Display Interactive Hotkey Help GUI     |
  | `Ctrl+F`          | Find in Hotkey Help                     |
  | `Win+Ctrl+F1`     | Excluded Files, Hotkeys, and Hotstrings |
  | `Win+Alt+Ctrl+F1` | Raw Hotkey List                         |
  | `Win+Alt+F1`      | Settings                                |

- ### WINDOW STARTUP SCRIPT

  | Key / Action                    | Usage                                                                      |
  | :------------------------------ | :------------------------------------------------------------------------- |
  | `Tray Left-Click / Right-Click` | Open Master Tray Context Menu                                              |
  | `Tray Hover Tooltip`            | Displays dynamic sorted list of all currently active scripts               |
  | `Win+ScrollLock`                | Suspend All Scripts' Hotkeys (background timers and watchers keep running) |
  | `Win+Ctrl+Alt+ScrollLock`       | Terminate All Scripts (clean fleet exit)                                   |
  | `Win+Ctrl+Alt+R`                | Reload All Scripts (instant fleet-wide reload)                             |
  | `Win+Ctrl+Alt+W`                | Run Window Spy utility                                                     |

- ### PERSONAL KEYWORDS
  - It's a key-value pair. Type the key in the text field to get its corresponding value.

    | Keyword / Key | Usage                                                         |
    | :------------ | :------------------------------------------------------------ |
    | `ValueOfPie`  | `3.141592653589793238`                                        |
    | `e1.`         | `demo@example.com` (Email 1)                                  |
    | `e2.`         | `demo2@example.com` (Email 2)                                 |
    | `c1.`         | `+1-555-0100` (Contact 1)                                     |
    | `thnk.`       | Universal autonomous 5-phase engineering reasoning prompt     |
    | `Win+Alt+A`   | Open Samsung Notes / Notes App                                |
    | `Win+Alt+S`   | Open Notion                                                   |
    | `Win+Shift+P` | Open Bitwarden Vault                                          |

- ### FORCE CLOSE PROGRAMS
  - For programs that go to the system tray when closed by pressing the close button

    | Key            | Usage                                                                    |
    | :------------- | :----------------------------------------------------------------------- |
    | `Alt+Ctrl+F4`  | Close All Programs (gracefully closes open desktop applications)         |
    | `Alt+Shift+F4` | Close Specific Active Program (terminates stubborn background tray apps) |
    | `Alt+F4`       | Close Currently Active Screen (with key-release guard and tray cleanup)  |

---

## Get Installed Apps List and Run Apps

- Get installed app names and AppIDs:
  ```powershell
  Get-StartApps | Sort-Object Name | Format-Table -Property Name, AppID
  ```
- Run an app from AutoHotkey via its AppID:
  ```ahk
  Run, shell:AppsFolder\SamsungNotes_8wekyb3d8bbwe!App
  ```

---

## License

[MIT LICENSE](LICENSE)

<br />

---

<h3>
  <p align="center">
    💡 <b>Fleet Maintenance Tip:</b> After editing any child script (e.g. <code>BasicTasks.ahk</code>), press <code>Win+Ctrl+Alt+R</code> (or select <b>"Reload All"</b> in the tray menu) to reload the fleet instantly. Recompilation via <code>build_startup_exe.ps1</code> is only required when modifying <code>StartupScript.ahk</code>.
  </p>
</h3>

---
