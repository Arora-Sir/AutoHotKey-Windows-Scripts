# Workstation setup and disaster recovery guide

This guide documents the complete procedure to configure, provision, and recover the AutoHotkey automation fleet, Sunshine streaming server, multi-GPU display pipeline, and tablet workstation setup from scratch on Windows 11.

---

## System prerequisites

- **Operating system**: Windows 11 (Version 23H2 or 24H2)
- **Runtimes**:
  - AutoHotkey v1.1.37.02 (installed in C:\Program Files\AutoHotkey\)
  - PowerShell 7 (pwsh.exe)
- **Host hardware**:
  - Acer Predator Helios 300 (or equivalent dual-GPU architecture)
  - Integrated GPU: Intel UHD Graphics (Adapter 0, drives internal 1080p panel)
  - Dedicated GPU: NVIDIA GeForce GTX 1650 Ti (Adapter 1, drives HDMI port)
  - HDMI 4K dummy plug
- **Client device**:
  - Samsung Galaxy Tab S10 Ultra (2560x1600 @ 120Hz native AMOLED panel)
  - Tailscale mesh VPN installed on both host and tablet

---

## Step 1: AutoHotkey fleet deployment

1. Clone or place the repository at your preferred path (e.g. D:\Path\To\Your\AutoHotKey).
2. Create AllScripts\LocalPaths.ahk by copying AllScripts\LocalPaths.ahk.example:
   ```powershell
   Copy-Item 'AllScripts\LocalPaths.ahk.example' 'AllScripts\LocalPaths.ahk'
   ```
3. Edit AllScripts\LocalPaths.ahk and configure workstation paths:
   ```ahk
   PATH_SUNSHINE_SCRIPTS := "D:\Path\To\Your\AutoHotKey\AllScripts\PowerShell\Sunshine"
   SUNSHINE_TABLET_TAILSCALE_IP := "100.x.y.z"
   PATH_SUNSHINE_LOG := "C:\Program Files\Sunshine\config\sunshine.log"
   PATH_ADB_EXE := "D:\Path\To\Your\adb.exe"
   SEFIRAH_ADB_TARGETS := "100.x.y.w:5555 100.x.y.z:5555"
   SEFIRAH_PRIORITY_TARGET := "100.x.y.w:5555"
   ```
4. Register the automatic boot task in Windows Task Scheduler:
   `powershell
   powershell.exe -ExecutionPolicy Bypass -File .\setup_startup_task.ps1
   `
   This registers the scheduled task AHK Startup Script to execute AllScripts\StartupScript.exe with highest privileges on user logon.
5. Compile and launch the master executable:
   `powershell
   powershell.exe -ExecutionPolicy Bypass -File .\build_startup_exe.ps1 -Relaunch
   `

---

## Step 2: HDMI dummy plug and custom resolution setup

1. Insert the HDMI dummy plug into the workstation HDMI port. Because the port is wired to the discrete NVIDIA GPU, it appears as an external monitor on Adapter 1.
2. If the dummy plug does not automatically present 2560x1600 resolution:
   - Open NVIDIA Control Panel -> Display -> Change resolution.
   - Click Customize -> Create Custom Resolution.
   - Set Horizontal pixels: 2560, Vertical lines: 1600, Refresh rate: 120Hz (or 60Hz), Standard: CVT Reduced Blanking (CVT-RB).
   - Test and save the resolution profile.
3. If using Custom Resolution Utility (CRU):
   - Add a Detailed Resolution entry: 2560x1600 at 120Hz with CVT-RB timing.
   - Restart the display driver using estart64.exe or press Win+Ctrl+Shift+B.

---

## Step 3: Sunshine host streaming server installation

1. Download and run the Sunshine Windows installer (LizardByte/Sunshine).
2. Verify SunshineService is installed and running:
   `powershell
   Get-Service -Name SunshineService
   `
3. Open the Sunshine Web UI at https://localhost:47990/ and configure administrative credentials.
4. Open Configuration -> Audio/Video:
   - **Video Codec**: HEVC (H.265).
   - **NVENC Preset**: P1 (low latency) or default.
   - **Display Output**: Leave blank.
5. **Critical configuration rule**: Do not set output_name in sunshine.conf. Setting a global display output causes SunshineService to terminate on startup if the dummy plug is detached or if the discrete GPU is in cold sleep.

---

## Step 4: Sunshine application profiles provisioning

1. Run the administrative provisioning script:
   `powershell
   Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File AllScripts\PowerShell\Sunshine\update_sunshine_apps.ps1' -Verb RunAs
   `
   Or double-click AllScripts\PowerShell\Sunshine\update_sunshine_apps.bat.
2. This script writes C:\Program Files\Sunshine\config\apps.json with two desktop streaming profiles:
   - **Desktop**: Captures primary display (DISPLAY1), used for PC Screen Only and Duplicate modes.
   - **Desktop (Extended Tab)**: Explicitly targets output: \\\\.\\DISPLAY4, capturing the dummy plug directly from the NVIDIA encoder.
   - **Prep commands**: Both profiles attach set_fast.ps1 on stream start and set_normal.ps1 on stream termination.
3. The script automatically restarts SunshineService to load the updated profiles.

---

## Step 5: Moonlight pairing on tablet

1. Install Moonlight Game Streaming on the Samsung Galaxy Tab S10 Ultra.
2. Connect both devices to Tailscale or the same local network.
3. In Moonlight, add the host workstation IP (e.g. host LAN IP or Tailscale IP 100.x.y.w).
4. Enter the 4-digit pairing PIN into Sunshine Web UI -> PIN.
5. In Moonlight client settings on the tablet:
   - **Resolution**: 2560x1600 (Native 16:10).
   - **Frame rate**: 120 FPS (or 60 FPS).
   - **Bitrate**: 50 Mbps to 80 Mbps.
   - **Touch mode**: Touchpad or Remote Desktop.

---

## Step 6: Display topologies and hotkey operation

All display modes and mouse speed settings are synchronized by SunshineDisplayWatchdog.ahk:

| Mode | Windows Topology | Primary Screen | Mouse Speed | Pointer Precision | Hotkey / Trigger | Moonlight App |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **PC Screen Only** | Single internal | Internal (DISPLAY1) | 10 (Normal) | Enabled | Win+Alt+P | None |
| **Tablet Only** | Single external | Dummy (DISPLAY4) | 20 (Fast) | Disabled | Win+Alt+P | Desktop |
| **Extend Displays** | Dual desktop | Laptop (DISPLAY1) | 10 (Normal) | Enabled | Win+Alt+Shift+P | Desktop (Extended Tab) |
| **Duplicate Displays** | Mirrored | Laptop (DISPLAY1) | 20 (Fast) | Disabled | Win+Alt+Shift+P | Desktop |

### Operational rules for extend mode

1. **Laptop remains primary display**: Windows keeps DISPLAY1 as the primary screen. This ensures the Windows Shell taskbar, system tray notification area, clock, and background flyouts remain on the physical laptop.
2. **Automated closed-loop handshake and stream teardown**: When switching to Extend Displays from PC Screen Only or Duplicate mode, the automated watchdog temporarily transitions the system through Tablet Only mode (`DisplaySwitch.exe /external`) to activate the NVIDIA dummy plug. If an existing stream session was running, the tablet display disconnects from the laptop first so Sunshine resets its capture pipeline. Moonlight then connects fresh via an automated ADB launch intent, confirming `CLIENT CONNECTED` before Windows 11 extends the desktop across both screens.
3. **Launch Desktop (Extended Tab) on tablet**: Connecting to this application profile in Moonlight captures DISPLAY4 directly, rendering the extended secondary screen on the tablet while the laptop shows the primary desktop.

---

## Step 7: Simple Sticky Notes layout calibration

1. Launch Simple Sticky Notes (ssn.exe).
2. Notes are repositioned deterministically by AllScripts\PowerShell\apply_ssn_layout.ps1:
   - **Laptop geometry (1536x864 DIPs)**: Column 0 at X=0, Column 1 at X=728, Column 2 at X=968, Column 3 at X=1268 (ends flush at 1536px).
   - **Tablet geometry (1463x914 DIPs)**: Column 0 at X=0, Column 1 at X=640, Column 2 at X=885, Column 3 at X=1190 (ends at 1458px with a 5px margin).
3. Test alignment by executing:
   `powershell
   powershell.exe -ExecutionPolicy Bypass -File .\AllScripts\PowerShell\apply_ssn_layout.ps1 -Mode Auto
   `

---

## Step 8: Master tray menu organization

All fleet scripts run under a single master tray icon:
- **Pinned order**:
  1. BasicTasks (productivity launchers, Skills Vault mode indicator, and single-line browser graphics acceleration status)
  2. PersonalKeywords (hotstrings and text expansions)
  3. SunshineDisplayWatchdog (display switcher with dynamic active-mode checkmark)
- **Additional scripts**:
  - BackgroundAutomations, Brightness, ClosePrograms, Ext4SsdManager, HotkeyHelp, LocalPaths, SharedHelpers, Watchdog.
  - StartupScript submenu located inside Additional Scripts: provides Edit, Recompile & Relaunch, and View Key History without cluttering the main tray menu.
- **Global actions**: Reload All, Recompile Startup, Suspend Hotkeys, Exit.

---

## Step 9: Verification and disaster recovery checklist

Run these diagnostic commands to verify workstation health:

1. **Verify fleet processes**:
   `powershell
   Get-Process -Name 'AutoHotkey*', 'StartupScript*' | Format-Table Id, ProcessName
   `
   Expect exactly 11 AutoHotkeyU64 child processes and 1 StartupScript master process.

2. **Verify live mouse speed**:
   `powershell
   python -c import ctypes; speed = ctypes.c_int(); ctypes.windll.user32.SystemParametersInfoW(0x0070, 0, ctypes.byref(speed), 0); print('Mouse Speed:', speed.value)
   `
   Expect 10 when on PC Screen Only or Extend mode; 20 when on Tablet Only or Duplicate mode.

3. **Verify active monitor count**:
   ```powershell
   python -c "import ctypes; print('Monitors:', ctypes.windll.user32.GetSystemMetrics(80))"
   ```
   Expect 1 when on PC Screen Only, Tablet Only, or Duplicate mode; 2 when on Extend mode.

4. **Verify Sunshine service status**:
   `powershell
   Get-Service SunshineService
   `

5. **Restart fleet cleanly**:
   `powershell
   powershell.exe -ExecutionPolicy Bypass -File .\build_startup_exe.ps1 -Relaunch
   `
