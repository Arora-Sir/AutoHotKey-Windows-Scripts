# How to Use AHK Scripts (for Windows 10 & 11)

- **Install AutoHotKey (v2 Dual-Runtime Recommended)**:
  - Install AutoHotkey v2 via [Official Installer](https://www.autohotkey.com/) or PowerShell:
    ```powershell
    winget install AutoHotkey.AutoHotkey
    ```
  - The AHK v2 installer automatically sets up the **AutoHotkey Launcher**, which seamlessly runs both v1 and v2 scripts side-by-side based on the `#Requires` directive at the top of each script.
- **Version Directives (`#Requires`)**:
  - Legacy scripts in `AllScripts/` use `#Requires AutoHotkey v1.1` to ensure the launcher uses the v1 interpreter without breaking functionality.
  - Any new scripts can use `#Requires AutoHotkey v2.0` to take advantage of modern v2 features.
- Add the scripts directory to `Startup_Script.ahk` to run all scripts at once.
- **Local Custom Paths**: Copy `local_paths.ahk.example` to `local_paths.ahk` in the root directory to define your machine-specific paths (e.g. custom courses or scripts). `local_paths.ahk` is automatically ignored by Git to keep your folder structure private.
- **Personal Keywords & Privacy**: Copy `AllScripts/Personal Keywords.ahk.example` to `AllScripts/Personal Keywords.ahk` to define your private hotstrings, passwords, and shortcuts. `Personal Keywords.ahk` is automatically ignored by Git to prevent accidental data leaks.

## To Create the EXE from Script (with Custom Icon)

### Method 1: Using Ahk2Exe GUI
1. Right-click any `.ahk` script (e.g. `Startup_Script.ahk`) in File Explorer and select **Compile Script (GUI)** (or launch `C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe`).
2. **Source**: Select your `.ahk` script file.
3. **Destination**: Select the output `.exe` filename (e.g. `Startup_Script.exe`).
4. **Custom Icon (.ico)**: Click **Browse** and select your `.ico` file.
5. **Base Bin**: Select `Unicode 64-bit.bin` (for v1) or v2 binary base.
6. **Compression (Optional)**: Set the UPX path to `upx-3.95-win64\upx.exe` for executable compression.
7. Click **Convert**.

### Method 2: Using Command Line
Run the following command in PowerShell / CMD to compile with a custom icon:
```powershell
& "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" /in "AllScripts\Startup_Script.ahk" /out "AllScripts\Startup_Script.exe" /icon "path\to\custom_icon.ico"
```

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

- ### FORCE CLOSE PROGRAMS
  - For programs that go to the system tray when closed by pressing the close button
  
    |     Key      |             Usage             |
    |--------------|-------------------------------|
    | Alt+Ctrl+F4  |       Close All Programs      |
    |    Alt+F4    | Close Currently Active Screen |

## Get Installed Apps List and Run Apps
  - Get Installed Apps names (Powershell): 
    ```powershell
    Get-StartApps | Sort-Object Name | Format-Table -Property Name, AppID
    ```
  - Open the app in AHK:
    ```ahk
    Run, shell:AppsFolder\SamsungNotes_8wekyb3d8bbwe!App
    ```

## License

[MIT LICENSE](LICENSE)

<br />

---

<h3>
  <p align="center">
    :exclamation::exclamation: Reload the script `Startup_Scripts.ahk` after any edit in ".ahk" file :smile:
  </p>
</h3>

---
