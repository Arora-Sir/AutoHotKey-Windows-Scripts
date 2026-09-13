# Sunshine Remote Desktop Architecture and Migration Guide

This directory contains the core orchestration scripts, lifecycle hooks, and automated configuration tools for the workstation remote desktop pipeline connecting the host PC to the client tablet (Samsung Galaxy Tab S10 Ultra streaming via Moonlight).

## Architecture Overview

The remote streaming system operates across multiple distinct hardware layers and software components:

1. **Host Workstation Hardware**:
   - **Internal Panel (DISPLAY1)**: 1920x1080 @ 144Hz, driven by integrated Intel UHD Graphics (Adapter 0).
   - **HDMI Dummy Plug (DISPLAY4)**: 2560x1600 @ 120Hz EDID profile matching the native resolution of the Galaxy Tab S10 Ultra, driven directly by dedicated NVIDIA GeForce GTX 1650 Ti (Adapter 1).
   - **Hardware Video Acceleration**: NVIDIA NVENC HEVC 10-bit encoder (hevc_nvenc) async encoding pipeline with hardware GPU scheduling (HAGS).

2. **Host Streaming Server (Sunshine)**:
   - Installed as a Windows Service (SunshineService) at C:\Program Files\Sunshine\.
   - Captures frames via DirectX Desktop Duplication API (DXGI) and streams ultra-low latency video/audio to Moonlight over LAN or Tailscale.

3. **Orchestration Layer (SunshineDisplayWatchdog.ahk)**:
   - Consolidated AutoHotkey daemon running under StartupScript.exe.
   - Manages four display topologies: PC Screen Only, Tablet Only, Extend Displays, and Duplicate Displays.
   - Synchronizes Win32 mouse speeds (10 for laptop, 20 for tablet) and pointer precision.
   - Restores laptop panel upon lid open (WM_DISPLAYCHANGE), Modern Standby resume (WM_POWERBROADCAST), and session unlock (WM_WTSSESSION_CHANGE).
   - Automatically repositions Simple Sticky Notes (ssn.exe) across differing logical geometries.

## File Manifest

- set_fast.ps1: Executed by Sunshine on stream start (prep-command do).
  - Sets mouse speed to maximum (20) via Win32 SystemParametersInfo(SPI_SETMOUSESPEED, 0, 20, 3).
  - Disables pointer precision acceleration via Win32 SystemParametersInfo(SPI_SETMOUSE, 0, [6, 10, 0], 3) for 1:1 stylus and touch fidelity.
  - Creates the .fast_since timestamp marker file read by SunshineDisplayWatchdog.ahk.
  - Clears any stale .session_quit signal from prior sessions.

- set_normal.ps1: Executed by Sunshine on stream termination (prep-command undo).
  - Restores mouse speed to default (10) via Win32 SystemParametersInfo(SPI_SETMOUSESPEED, 0, 10, 3).
  - Re-enables pointer precision acceleration via Win32 SystemParametersInfo(SPI_SETMOUSE, 0, [6, 10, 1], 3).
  - Deletes the .fast_since marker file.
  - Creates the .session_quit signal file, enabling an instant display restore without debounce delay.

- update_sunshine_apps.ps1: Automated profile generator.
  - Writes the complete apps.json profile structure directly to C:\Program Files\Sunshine\config\apps.json.
  - Automatically isolates display output bindings between Desktop (primary) and Desktop (Extended Tab) (\\.\DISPLAY4).
  - Automatically restarts SunshineService to apply changes immediately.

- update_sunshine_apps.bat: Elevation wrapper.
  - Double-clickable batch file that requests Administrator UAC elevation and executes update_sunshine_apps.ps1.

## Display Topologies and Hotkey Matrix

| Mode | Target Resolution | Primary Display | Mouse Speed | Pointer Precision | Hotkey / Trigger |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PC Screen Only** | 1080p @ 144Hz | Internal (DISPLAY1) | 10 (Normal) | Enabled | Win+Alt+P |
| **Tablet Only** | 2560x1600 @ 120Hz | Dummy Plug (DISPLAY4) | 20 (Fast) | Disabled | Win+Alt+P |
| **Extend Displays** | Dual (1080p + 2560x1600) | Laptop (DISPLAY1) | 10 (Normal) | Enabled | Win+Alt+Shift+P |
| **Duplicate Displays** | Mirrored 1080p / 1600p | Laptop (DISPLAY1) | 20 (Fast) | Disabled | Win+Alt+Shift+P |

### Key Operational Rules

1. **Keep Windows Primary Display on the Laptop (DISPLAY1)**:
   - The Windows primary display anchors the Windows Shell taskbar notification area, system clock, tray flyouts, and desktop widgets.
   - Setting the dummy plug as Primary Display strips tray icons from the physical laptop screen.
   - In Extend Displays mode, the laptop remains the primary display with all tray controls intact.

2. **Display Capture Isolation in Moonlight**:
   - When connecting in **Duplicate Mode** or **Tablet Only Mode**: select Desktop in Moonlight.
   - When connecting in **Extend Mode**: select Desktop (Extended Tab) in Moonlight. This directly streams \\.\DISPLAY4 from the NVIDIA GPU, displaying the extended secondary screen on the tablet while the laptop shows the primary screen.

3. **Never Hardcode output_name in sunshine.conf**:
   - Setting a global output_name = \\.\DISPLAY4 in sunshine.conf causes SunshineService to crash on Windows boot if the dummy plug is detached or if the discrete GPU is in cold sleep.
   - sunshine.conf must remain free of static display output overrides. All display targeting is handled per-application in apps.json.

4. **Closed-Loop Extend Handshake and Stream Teardown**:
   - On hybrid dual-GPU systems, extending the desktop directly across distinct GPU adapters fails unless an active stream consumer is established on the secondary discrete GPU dummy plug first.
   - When switching to Extend Displays from PC Screen Only or Duplicate mode, SunshineDisplayWatchdog.ahk initiates Tablet Only mode (`DisplaySwitch.exe /external`).
   - If an existing tablet stream session was active, the display disconnects from the laptop first so Sunshine releases its prior DXGI capture context.
   - The watchdog dispatches an ADB command over Tailscale to wake the tablet and launch Moonlight.
   - Once Sunshine logs `CLIENT CONNECTED` and the video pipeline stabilizes for 1000ms, the watchdog invokes `DisplaySwitch.exe /extend` and restores normal mouse speed 10.

## Fresh Machine Setup and Disaster Recovery Guide

Follow these sequential steps to recreate the entire streaming environment from scratch on a new machine.

### Step 1: Hardware and Driver Setup

1. Insert the HDMI dummy plug into the workstation HDMI port (must connect to discrete GPU).
2. Open Windows Display Settings and verify two monitors appear:
   - Display 1: Internal Laptop Screen
   - Display 2 (or 4): Virtual HDMI Display
3. If the dummy plug defaults to 1080p or 4K instead of 2560x1600:
   - Download Custom Resolution Utility (CRU) or open NVIDIA Control Panel -> Change Resolution.
   - Create custom resolution: 2560 x 1600 at 120Hz (or 60Hz), CVT-RB timing.
   - Restart the graphics driver using Win+Ctrl+Shift+B or restart the PC.

### Step 2: Sunshine Installation and Configuration

1. Download and install the latest Sunshine release from GitHub (LizardByte/Sunshine).
2. Verify SunshineService is running:
   `powershell
   Get-Service -Name SunshineService
   `
3. Open Sunshine Web UI in browser: https://localhost:47990/.
4. Set up username and password on first login.
5. In Configuration -> Audio/Video:
   - Set Video Codec: HEVC (H.265).
   - Verify Audio Sink is set to default virtual or stereo endpoint.
   - Keep Display output blank (do not set a global display).

### Step 3: Moonlight Pairing on Tablet

1. Install Moonlight Game Streaming on Samsung Galaxy Tab S10 Ultra (Google Play Store or GitHub).
2. Connect both devices to the same local network or connect via Tailscale.
3. In Moonlight, add host PC IP address (LAN IP or Tailscale IP e.g. 100.x.y.z).
4. Enter the 4-digit PIN displayed on the tablet into Sunshine Web UI -> PIN.
5. In Moonlight client settings on the tablet:
   - Resolution: 2560x1600 (Native 16:10).
   - Frame Rate: 120 FPS (or matching tablet display refresh rate).
   - Bitrate: 50 Mbps to 80 Mbps for local gigabit / Wi-Fi 6.

### Step 4: AutoHotkey Fleet Setup

1. Verify AutoHotkey v1.1.37+ is installed.
2. In AllScripts/, copy LocalPaths.ahk.example to LocalPaths.ahk.
3. Configure PATH_SUNSHINE_SCRIPTS in LocalPaths.ahk to point to this directory:
   ```ahk
   PATH_SUNSHINE_SCRIPTS := "D:\Path\To\Your\AutoHotKey\AllScripts\PowerShell\Sunshine"
   SUNSHINE_TABLET_TAILSCALE_IP := "100.x.y.z"
   PATH_SUNSHINE_LOG := "C:\Program Files\Sunshine\config\sunshine.log"
   ```
4. Rebuild the master startup binary:
   `powershell
   .\build_startup_exe.ps1 -Relaunch
   `

### Step 5: Provision Sunshine Application Profiles

1. Run update_sunshine_apps.bat as Administrator (or execute update_sunshine_apps.ps1 from an elevated PowerShell window).
2. Inspect C:\Program Files\Sunshine\config\apps.json to verify Desktop and Desktop (Extended Tab) are registered.
3. Verify update_sunshine_apps.log in AllScripts/Logs/ reports successful write and service restart.

### Step 6: Simple Sticky Notes Alignment Calibration

1. Ensure Simple Sticky Notes (ssn.exe) is running.
2. The coordinate engine in pply_ssn_layout.ps1 handles two deterministic geometries:
   - Laptop: 1536x864 DIPs (1920x1080 @ 125%). Notes align to Column 0 (X=0), Column 1 (X=728), Column 2 (X=968), and Column 3 (X=1268, ends at 1536px edge).
   - Tablet: 1463x914 DIPs (2560x1600 @ 175%). Notes align to Column 0 (X=0), Column 1 (X=640), Column 2 (X=885), and Column 3 (X=1190, ends at 1458px edge).
3. Test alignment anytime by running:
   `powershell
   powershell.exe -ExecutionPolicy Bypass -File .\apply_ssn_layout.ps1 -Mode Auto
   `

## Troubleshooting

### Mouse Speed Stays at 20 on Laptop
- Check if dummy plug is still the only active display. Press Win+Alt+P to switch back to PC Screen Only.
- SunshineDisplayWatchdog.ahk includes an Active Topology Guard that suppresses speed 20 when on single internal display. If needed, click the tray icon -> Reload Display Watchdog.

### Tablet Shows Duplicate Instead of Extended Screen
- In Moonlight, launch Desktop (Extended Tab) instead of Desktop.
- Verify dummy plug is identified as DISPLAY4 via displayswitch.exe or dxdiag. If on a different index, update output: \\\\.\\DISPLAYx in update_sunshine_apps.ps1 and re-run.

### Sunshine Service Does Not Start
- Check C:\Program Files\Sunshine\config\sunshine.log.
- Verify sunshine.conf does not contain invalid output_name directives.
- Restart service via elevated PowerShell: Restart-Service SunshineService -Force.
