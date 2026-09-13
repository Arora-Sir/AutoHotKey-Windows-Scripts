# Installed Utilities & Helpers

This directory contains external utility binaries and scripts required by the AutoHotkey scripts in this repository.

## Installation Instructions

When setting up this repository on a new machine:

1. Copy all contents of this directory:
   - `nircmd.exe`
   - `nircmdc.exe`
   - `NirCmd.chm`
   - `WindowSpy.ahk`
   - `mic_muted.ico`
2. Paste them into your main AutoHotkey installation directory:
   - Default 64-bit path: `C:\Program Files\AutoHotkey\`
   - Default 32-bit path: `C:\Program Files (x86)\AutoHotkey\`

---

## Utility Overview

| Utility | Description | Used By |
| :--- | :--- | :--- |
| `mic_muted.ico` | Multi-resolution icon (16px to 64px) featuring a solid white microphone silhouette crossed by a neon-red diagonal slash. | Dynamic microphone mute tray indicator displayed by `BasicTasks.ahk` when capture endpoints are muted |
| `nircmd.exe` | Command-line utility to perform system tasks (volume, display, power, window management) without user interface. | Not currently called by any active script, bundled for convenience if you want it (microphone muting now uses native Windows Core Audio WASAPI calls in `SharedHelpers.ahk` instead) |
| `nircmdc.exe` | Console version of NirCmd for command-line output. | Not currently called by any active script, same convenience bundling as `nircmd.exe` |
| `NirCmd.chm` | Compiled HTML Help documentation for NirCmd commands. | Reference & offline documentation |
| `WindowSpy.ahk` | AutoHotkey window inspection script for detecting window titles, controls, text, and mouse coordinates. | Hotkey development & debugging, launched via `Win+Ctrl+Alt+W` in `StartupScript.ahk` |

---

## References

- [NirCmd Official Documentation](https://www.nirsoft.net/utils/nircmd.html)
- [AutoHotkey Official Website](https://www.autohotkey.com/)
