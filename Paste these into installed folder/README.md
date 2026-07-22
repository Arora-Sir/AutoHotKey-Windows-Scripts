# Installed Utilities & Helpers

This directory contains external utility binaries and scripts required by the AutoHotkey scripts in this repository.

## Installation Instructions

When setting up this repository on a new machine:

1. Copy all contents of this directory:
   - `nircmd.exe`
   - `nircmdc.exe`
   - `NirCmd.chm`
   - `WindowSpy.ahk`
2. Paste them into your main AutoHotkey installation directory:
   - Default 64-bit path: `C:\Program Files\AutoHotkey\`
   - Default 32-bit path: `C:\Program Files (x86)\AutoHotkey\`

---

## Utility Overview

| Utility | Description | Used By |
| :--- | :--- | :--- |
| `nircmd.exe` | Command-line utility to perform system tasks (volume, display, power, window management) without user interface. | System scripts (`Brightness.ahk`, volume tasks) |
| `nircmdc.exe` | Console version of NirCmd for command-line output. | System diagnostics |
| `NirCmd.chm` | Compiled HTML Help documentation for NirCmd commands. | Reference & offline documentation |
| `WindowSpy.ahk` | AutoHotkey window inspection script for detecting window titles, controls, text, and mouse coordinates. | Hotkey development & debugging (`Startup_Script.ahk`) |

---

## References

- [NirCmd Official Documentation](https://www.nirsoft.net/utils/nircmd.html)
- [AutoHotkey Official Website](https://www.autohotkey.com/)
