# AutoHotKey Fleet: AI Handoff & Session Context

This document is the operational scratchpad for AI coding assistants working in this repository. It provides an immediate mental model of the fleet topology, verified runtime state, and development conventions without needing to parse the full 500-line ARCHITECTURE.md.

---

## 1. Project Purpose

Personal Windows 10 and 11 automation fleet providing global productivity hotkeys, screen-streaming optimizations (Sunshine and Moonlight), display topology auto-switching, Simple Sticky Notes auto-arrangement, DRM video streaming mode, Skills Vault protection, and wireless ADB file pushing to mobile devices. Orchestrated by a single master startup script compiled into `AllScripts/StartupScript.exe`.

---

## 2. Fleet Topology

The fleet runs under AutoHotkey v2.0. Every script starts with `#Requires AutoHotkey v2.0`; the master binary compiles against `AutoHotkey\v2\AutoHotkey64.exe` (see `build_startup_exe.ps1`). The v1->v2 migration is complete and merged - see `Official Documentation/AHK-v1-to-v2-Migration-Notes.md` for every language-level gotcha found along the way.

| Process / Script | Role | Lifecycle | Key Invariants |
| :--- | :--- | :--- | :--- |
| `AllScripts/StartupScript.exe` | Master Orchestrator | Windows Task Scheduler logon task (30s delay) | Compiles from `StartupScript.ahk`. Owns the single master tray icon, global suspend toggle (`Win+ScrollLock`), and child process supervisor. |
| `AllScripts/BasicTasks.ahk` | Productivity Hotkeys | Child process managed by master | App launchers, tab navigation, clipboard utilities, DRM mode (Tray toggle), wireless phone push (`Win+Alt+T`). |
| `AllScripts/BackgroundAutomations.ahk` | Window Focus Watcher | Child process managed by master | Focus watcher for Org Safe Mode (locks personal skills when Claude is focused, unlocks when Antigravity is focused). |
| `AllScripts/SunshineDisplayWatchdog.ahk` | Streaming & Display Manager | Child process managed by master (pinned tray icon) | Controls display topologies (PC Screen Only, Tablet Only, Extend, Duplicate), hotkeys (`Win+Alt+P`, `Win+Alt+Shift+P`), instant mouse speed sync, Sunshine log/Tailscale monitoring, hardware event recovery, and Simple Sticky Notes geometry. |
| `AllScripts/SharedHelpers.ahk` | Shared Function Library | Included by children (`Persistent()` call for its own standalone tray item) | HUD badges (`ShowBottomRightBadge`), named mutex (`AcquireNamedMutex`), debounce timers (`DebounceArmTimer`), and tray manifest publishing. |
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
2. **Callback Parameter Counts Matter**: `OnMessage()` and `Menu.Add()` callbacks hang at the registration call itself (not at call time) if the handler has fewer parameters than the callback contract expects and no `*` catch-all - confirmed empirically across this fleet, see Migration-Notes.md SS18.16-18.17. A plain label can no longer be passed as a `SetTimer`/`OnMessage` target at all in v2 - it must be a real function reference.
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
