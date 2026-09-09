# Sunshine Remote Desktop Mouse Speed Hooks

This directory contains the PowerShell prep-command hooks configured in Sunshine (`apps.json`) for tablet remote desktop sessions (e.g., Samsung Galaxy Tab S10 Ultra streaming via Moonlight).

## Files

- `set_fast.ps1`: Executed by Sunshine on stream start (prep-cmd `do`).
  - Sets mouse speed to maximum (20) via Win32 `SystemParametersInfo(SPI_SETMOUSESPEED, 0, 20, 3)`.
  - Disables "Enhance pointer precision" (pointer acceleration) via Win32 `SystemParametersInfo(SPI_SETMOUSE, 0, [6, 10, 0], 3)` for 1:1 physical pen and touch tracking.
  - Creates the `.fast_since` timestamp marker used by `SunshineMouseWatchdog.ahk`.
  - Deletes any leftover `.session_quit` signal from prior sessions.

- `set_normal.ps1`: Executed by Sunshine on stream termination (prep-cmd `undo`).
  - Restores mouse speed to default (10) via Win32 `SystemParametersInfo(SPI_SETMOUSESPEED, 0, 10, 3)`.
  - Re-enables "Enhance pointer precision" via Win32 `SystemParametersInfo(SPI_SETMOUSE, 0, [6, 10, 1], 3)`.
  - Clears the `.fast_since` marker file.
  - Creates the `.session_quit` signal file, allowing `SunshineMouseWatchdog.ahk` to trigger an instant (~1.5s) display restore on explicit Moonlight quit without waiting for streak debounce windows.

## Live Deployment Path

In live operation, Sunshine executes these scripts from the path configured in the gitignored `LocalPaths.ahk` (`PATH_SUNSHINE_SCRIPTS`) - see `LocalPaths.ahk.example` for the placeholder (`D:\Path\To\Your\Sunshine\Scripts`) and point Sunshine's own `apps.json` prep-cmd `do`/`undo` hooks at wherever you set that to on your own machine.

The copies here are version-controlled, portable, and contain zero personal identifiers or machine-specific credentials.
