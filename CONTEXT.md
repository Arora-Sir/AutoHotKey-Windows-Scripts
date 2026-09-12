# AutoHotKey Fleet: AI Handoff & Session Context

This document is the operational scratchpad for AI coding assistants working in this repository. It provides an immediate mental model of the fleet topology, verified runtime state, and development conventions without needing to parse the full 500-line ARCHITECTURE.md.

---

## 1. Project Purpose

Personal Windows 10 and 11 automation fleet providing global productivity hotkeys, screen-streaming optimizations (Sunshine and Moonlight), display topology auto-switching, Simple Sticky Notes auto-arrangement, DRM video streaming mode, Skills Vault protection, and wireless ADB file pushing to mobile devices. Orchestrated by a single master startup script compiled into `AllScripts/StartupScript.exe`.

---

## 2. Fleet Topology

The fleet runs under AutoHotkey v1.1. Do not convert scripts to v2.

| Process / Script | Role | Lifecycle | Key Invariants |
| :--- | :--- | :--- | :--- |
| `AllScripts/StartupScript.exe` | Master Orchestrator | Windows Task Scheduler logon task (30s delay) | Compiles from `StartupScript.ahk`. Owns the single master tray icon, global suspend toggle (`Win+ScrollLock`), and child process supervisor. |
| `AllScripts/BasicTasks.ahk` | Productivity Hotkeys | Child process managed by master | App launchers, tab navigation, clipboard utilities, DRM mode (Tray toggle), tablet toggle (`Win+Alt+P`), wireless phone push (`Win+Alt+T`). |
| `AllScripts/BackgroundAutomations.ahk` | Window Focus Watcher | Child process managed by master | Focus watcher for Org Safe Mode (locks personal skills when Claude is focused, unlocks when Antigravity is focused). |
| `AllScripts/SunshineMouseWatchdog.ahk` | Streaming Watchdog | Child process managed by master | Monitors Sunshine logs and Tailscale ping to auto-revert mouse speed (20 to 10) and display mode when tablet disconnects. |
| `AllScripts/SharedHelpers.ahk` | Shared Function Library | Included by children (`#Persistent` standalone tray item) | HUD badges (`ShowBottomRightBadge`), named mutex (`AcquireNamedMutex`), debounce timers (`DebounceArmTimer`), and tray manifest publishing. |
| `AllScripts/PowerShell/SendToDevice_Adb.ps1` | Wireless ADB Pusher | Spawned asynchronously by `BasicTasks.ahk` | Fast .NET socket probe (500ms), dual-IP failover (Tailscale to local Wi-Fi), non-destructive duplicate auto-numbering, Android MediaScanner broadcast. |
| `AllScripts/PowerShell/apply_ssn_layout.ps1` | Sticky Notes Engine | Spawned on display changes | Uses native Win32 `OpenDesktop` and thread enumeration to lock Simple Sticky Notes into deterministic pixel columns. |

---

## 3. Current Runtime State

- **Fleet Health**: All 12 AHK and PowerShell background processes are verified live and stable.
- **Master Tray Reflection**: Scripts publish custom menus via `PublishTrayMenuManifest`. `StartupScript.ahk` reflects them under separate submenus.
- **Git Hook Quality Gate**: `.githooks/pre-commit` enforces 3 checks (private path leak prevention, prohibited file staging, and language-aware dash linting via `scripts/clean_dashes.py`).
- **Developer Tooling**: `scripts/clean_dashes.py` is staged for tracking and tested clean across all repo files.

---

## 4. Critical Engineering Invariants

1. **Explicit Include Prefix**: Always use `#Include %A_ScriptDir%\SharedHelpers.ahk`. Never use a bare `#Include SharedHelpers.ahk` (relative paths break if the working directory differs).
2. **Auto-Execute Integrity**: In included files, all timers and callbacks must be **zero-parameter functions**, never plain labels. Plain labels terminate auto-execute scanning prematurely.
3. **Named Mutex Over Lock Files**: Cross-process exclusion must use `AcquireNamedMutex(name, timeoutMs)` so crashed processes do not leave stuck lock files on disk.
4. **Debounce Slow Operations**: Any operation taking over 100ms (such as `icacls` sweeps or ADB queries) must use the two-phase debounce pattern (`DebounceArmTimer` and `DebounceTryBeginCommit`) to keep the UI non-blocking.
5. **Punctuation Standards**: Zero em-dashes (`\u2014`), zero en-dashes (`\u2013`), zero double-hyphens (`--`) in comments or documentation. Always run `python scripts/clean_dashes.py --check` before committing.

---

## 5. Where to Start Reading

1. For hotkeys and user-facing shortcuts: read `AllScripts/BasicTasks.ahk`.
2. For shared utility functions and badge HUD: read `AllScripts/SharedHelpers.ahk`.
3. For master process supervisor and tray menu: read `AllScripts/StartupScript.ahk`.
4. For deep architecture rationale: read `ARCHITECTURE.md`.

---

## 6. Common Development Commands

```powershell
# Recompile master binary and restart the entire fleet seamlessly
.\build_startup_exe.ps1 -Relaunch

# Reload all child scripts without recompiling StartupScript.exe
Press Win+Ctrl+Alt+R (or Master Tray -> Reload All)

# Check staged files for punctuation and formatting violations
python scripts/clean_dashes.py --check

# Auto-repair dash violations across staged files
python scripts/clean_dashes.py --staged
```
