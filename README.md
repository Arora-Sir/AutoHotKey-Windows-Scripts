# How to Use AHK Scripts (for Windows 10 & 11)

Personal AutoHotkey setup: global hotkeys plus always-on background automation (crash recovery, Sefirah phone-link, Python servers), all orchestrated by one startup script.

## Setup

- **Install AutoHotkey**: [installer](https://www.autohotkey.com/) or `winget install AutoHotkey.AutoHotkey` via the v2 dual-runtime installer. Scripts here stay on `#Requires AutoHotkey v1.1` regardless, a v2 script breaks `StartupScript.exe`'s tray submenu (see that file's comments for why).
- **Local Custom Paths**: copy `AllScripts/local_paths.ahk.example` -> `AllScripts/local_paths.ahk` for your machine paths and app/device config. Gitignored.
- **Personal Keywords**: copy `AllScripts/PersonalKeywords.ahk.example` -> `AllScripts/PersonalKeywords.ahk` for private hotstrings. Gitignored.
- **Compiled Executables**: `.exe` files aren't tracked in Git, compile `StartupScript.ahk` locally when it changes (see below).

## Scripts Overview

| Script | Purpose |
|---|---|
| `StartupScript.ahk` | Orchestrator. Launches everything below at boot with a tray submenu each. Runs as the compiled `StartupScript.exe`. |
| `BasicTasks.ahk` | Hotkeys only, see tables below. |
| `BackgroundAutomations.ahk` | Everything that runs with no keypress: Tailscale tray launch, GravityBridge/CopyClip servers, Sefirah reconnect + phone priority. |
| `Watchdog.ahk` | Generic crash-relaunch for whatever's listed in `WATCHDOG_APPS`. |
| `Brightness.ahk` | Brightness hotkeys. |
| `ClosePrograms.ahk` | Force-close hotkeys for tray-minimizing apps. |
| `HotkeyHelp.ahk` | In-app hotkey reference / settings GUI. |
| `PersonalKeywords.ahk` | Private hotstrings (gitignored). |
| `VolumeOsd.ahk` | Volume on-screen display. |
| `local_paths.ahk` | Personal machine config (gitignored). |

## Compiling StartupScript.exe

Task Scheduler launches the compiled `.exe`, not the `.ahk` source, so an edit to `StartupScript.ahk` itself won't take effect until you rebuild it. Every other script still just needs a reload (`Win+Ctrl+Alt+R`), no rebuild involved.

Run `.\build_startup_exe.ps1`: rebuilds with the correct icon/base binary, auto-stops any running `StartupScript.exe` first (it locks itself while running). Doesn't relaunch it, prints the command to do that when ready.

If that script doesn't work on your machine: right-click `StartupScript.ahk` -> **Compile Script (GUI)**, set Source/Destination/Icon to the `.ahk`/`.exe`/`.ico` files here and Base to `AutoHotkeyU64.exe`, then Convert (stop any running `StartupScript.exe` first, it locks its own file).

## Watchdog: auto-relaunch an app if it crashes or closes

- Add an app with one entry, nothing in `Watchdog.ahk` itself ever needs editing:
  ```ahk
  WATCHDOG_APPS := [{name: "SomeApp.exe", path: "C:\Path\To\SomeApp.exe"}]
  ```
- Reacts to *any* exit, crash or deliberate close, there's no reliable way to tell them apart from outside the process. Closing a watched app normally brings it back within one poll (`CheckIntervalMs`, 10s by default).

## Working Hotkeys

- ### BRIGHTNESS

  |    Key    |               Usage               |
  |-----------|-----------------------------------|
  |    F1     |     Set Current +5 Brightness     |
  | Shift+F1  |     Set Current -5 Brightness     |
  | Ctrl+PgDn | Push Brightness Extremes Down -10 |
  | Ctrl+PgUp |  Push Brightness Extremes Up +10  |

- ### BASIC TASKS

  |        Key        |               Usage               |
  |-------------------|-----------------------------------|
  |      Win+Del      |      Empty Recycle Bin            |
  |      Win+C        |      Run Calculator               |
  |      Win+M        |     Minimize Active Window        |
  |      Win+F        |           Open FireFox            |
  |      Win+F8       |      Bluetooth On/Off             |
  |   Win+Shift+A     | Open Notification Center          |
  |   Win+Shift+E     | (Folder) Open Downloads (Screenshots) Folder |
  |   Win+Shift+J     | (Folder) Open Java Course         |
  |   Win+Alt+C       |      Run Alarm Clock              |
  |   Win+Alt+N       |  Clear Notification Center        |
  |   Win+Alt+X       | (Script) Reconnect Cloudflare Network |
  |       Alt+X       |     Open Today Calendar in [Checker Plus Extension](https://chromewebstore.google.com/detail/checker-plus-for-google-c/hkhggnncdpfibdhinjiegagmopldibha)           |
  |       Alt+D       |        Open ChatGPT               |
  |       Alt+G       | Monica AI Grammar Correction      |
  |   Alt+Shift+S     | Monica AI Content Summary         |
  |   Alt+Shift+T     | This Window Always on Top         |
  |  Alt+Ctrl+D       |    Sort Folder Content by Date    |
  |  Alt+Ctrl+E       |   Enable/Disable File Extension   |
  |  Alt+Ctrl+H       |   Enable/Disable Hidden Files     |
  | Alt+Ctrl+MouseLButton |     Move Background Apps      |
  |      Ctrl+G       |   Search the Selected/Clipboard Text |
  |      Ctrl+T+T     |    Open New Tab (In Browser)      |
  |      Ctrl+J+J     | Close Downloads Bar (In Browser)  |
  |      Ctrl+Y+T     |    Open YouTube (In Browser)      |
  |  Ctrl+Shift+V     | Browser to Go to Previous Tab When Taking a Screenshot in [Awesome Screen Recorder](https://chromewebstore.google.com/detail/awesome-screen-recorder-s/nlipoenfbbikpbjkfpfillcgkoblgpmj) |
  | Ctrl+Shift+WheelUp | (VS Code) Increase Whole UI Zoom (+0.05), only while VS Code is focused |
  | Ctrl+Shift+WheelDown | (VS Code) Decrease Whole UI Zoom (-0.05), only while VS Code is focused |
  | Capslock+Capslock | Double Tap to Activate/Deactivate |
  | MouseLButton      | Double Click Functions (Taskbar Show/Hide) |

- ### HOTKEYHELP

  |       Key       |                  Usage                  |
  |-----------------|-----------------------------------------|
  |     Win+F1      |              Display Help               |
  |     Ctrl+F      |           Find in Hotkey Help           |
  |   Win+Ctrl+F1   | Excluded Files, Hotkeys, and Hotstrings |
  | Win+Alt+Ctrl+F1 |             Raw Hotkey List             |
  |   Win+Alt+F1    |                Settings                 |

- ### WINDOW STARTUP SCRIPT

  |           Key           |          Usage           |
  |-------------------------|--------------------------|
  |     Win+ScrollLock      |   Suspend All Scripts    |
  | Win+Ctrl+Alt+ScrollLock | Terminate All Scripts    |
  | Win+Ctrl+Alt+R          |      Reload All Scripts  |
  | Win+Ctrl+Alt+W          |    Run Window Spy Script |

- ### PERSONAL KEYWORDS

  - It's a key-value pair. Type the key in the text field to get its corresponding value.

    |       Key       |        Usage         |
    |------------|-----------------------------|
    | ValueOfPie      | 3.141592653589793238 |
    | e1.             | demo@example.com (email 1) |
    | e2.             | demo2@example.com (email 2) |
    | c1.             | +1-555-0100 (contact 1) |

- ### FORCE CLOSE PROGRAMS
  - For programs that go to the system tray when closed by pressing the close button

    |     Key      |             Usage             |
    |--------------|-------------------------------|
    | Alt+Ctrl+F4  |       Close All Programs      |
    |    Alt+F4    | Close Currently Active Screen |

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
