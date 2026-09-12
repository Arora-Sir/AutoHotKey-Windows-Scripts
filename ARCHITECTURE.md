# Architecture

This document covers the shared library (`AllScripts/SharedHelpers.ahk`), the debounce pattern it provides as a reusable template, the bottom-right badge system, the local-path leak prevention setup, the Windows Task Scheduler boot architecture, DRM Video Streaming Mode, the master tray menu, the Sunshine/Moonlight display topology and watchdog lifecycle, and the Simple Sticky Notes multi-resolution layout engine.
Read this before adding a new hotkey or feature that needs any of these.

## Shared helpers (`AllScripts/SharedHelpers.ahk`)

Every script that needs one of these includes it with an **explicit** `%A_ScriptDir%` prefix:

```ahk
#Include %A_ScriptDir%\SharedHelpers.ahk
```

**Never a bare `#Include SharedHelpers.ahk`.**

- AHK v1.1 resolves a bare relative `#Include` path against the *process's initial working directory* at load-time preprocessing, not necessarily the including script's own folder.
- This only "worked" for the pre-existing bare `#Include *i LocalPaths.ahk` because of exactly how `StartupScript.ahk` happens to launch each script.
- Launch a script any other way (a manual reload from a shell with a different working directory, for instance) and a bare include can silently fail to resolve.

`SharedHelpers.ahk` also runs standalone as its own `StartupScript.ahk` tray entry, for quick Edit access (same reason `LocalPaths.ahk` does below).

- This uses a narrow exception to its own "no top-level directives" rule: a single `#Persistent` at the top.
- That's a pure lifecycle flag rather than executable code, so it's a no-op for every `#Include`ing script (they all already stay alive via their own hotkeys/loops).
- It only actually matters for this standalone run.
- The explicit `%A_ScriptDir%\` form is immune to this regardless of how the script is launched.

**Important gotcha: include it *before* any hotkey definition.**

- AHK's auto-execute section ends at the first hotkey/hotstring label, `Return`, or `Exit` encountered during a top-to-bottom load-time scan.
- That scan *skips over function bodies* entirely (recognized and deferred, never executed inline), but does **not** skip over a plain (non-hotkey) label.
- A plain label like `SomeLabel:` followed by code and `return`, if reached by that linear auto-execute scan, executes immediately at load time and ends the auto-execute section right there, before the *including* script's own remaining top-level initialization code ever runs.
- This is why every "auto-dismiss" target in this file (`RemoveBottomRightBadge`, `RemoveTimedToolTip`) is written as a **zero-parameter function**, not a label: `SetTimer` accepts a bare function name exactly like it accepts a label name (AHK v1.1.20+), and a function is correctly skipped during auto-execute scanning.
- If you add a new `SetTimer` target to this file, make it a function for the same reason, never a plain label.

### What's in the file, and why

- **`AcquireNamedMutex(mutexName, timeoutMs)` / `ReleaseNamedMutex(hMutex)`** - cross-process mutual exclusion via a real Win32 named mutex, not a file-existence convention.
  - A plain lock *file* can be left permanently stuck if the owning process crashes mid-critical-section.
    A named mutex cannot: Windows marks it "abandoned" and the next waiter picks it up cleanly.
  - The mutex name is a parameter, not hardcoded, specifically so this is reusable for *any* future resource needing cross-process exclusion, not just one.
  - Pick a distinct, descriptive name per logical resource (e.g. `"SkillsVaultLock_AHK_v1"`); every caller sharing that exact string, across however many separate processes, contends on the same kernel object.

- **`DebounceArmTimer` / `DebounceTryBeginCommit` / `DebounceEndCommit`** - the "settle after N ms of quiet, then act once" pattern. See the worked example below.

- **`ShowBottomRightBadge(msg, bgColorHex, displayMs := 0)` / `HideBottomRightBadge()` / `RemoveBottomRightBadge()`**
  - A colored toast, bottom-right corner, singleton: a second call while one is showing updates its color/text *in place*, never destroys/recreates or stacks.
    The window is created once and reused, so there is no visible gap between transitions.
  - `displayMs := 0` means "stay until the next Show/Hide call"; pass an explicit value for anything that should auto-dismiss on its own.
  - `HideBottomRightBadge()` dismisses immediately without a replacement badge - use it when real work has finished and there's nothing new worth telling the user.
    (See the Skills Vault commit phase in `BasicTasks.ahk`, which hides the "applying" badge on completion instead of showing a third, redundant "done" badge that would just repeat what was already shown at press time.)
  - See the badge section below for the DPI subtlety this encodes.

- **`ShowSkillsStatusBadge(msg)`** - thin color-mapping wrapper over `ShowBottomRightBadge`, specific to the Skills Vault feature (maps a `[LOCKED]`/`[UNLOCKED]`/`[AUTO]`/error-shaped message to its color, shown for 3000ms).
  - Shared by `BasicTasks.ahk` (manual toggle's fast-phase requested-state badge) and `BackgroundAutomations.ahk` (`WatchSkillsLock`'s post-commit confirmation) so the color convention is defined exactly once.

- **`ShowTimedToolTip(msg, displayMs)` / `RemoveTimedToolTip()`** - a native `ToolTip` auto-dismissed after N ms.
  - Use this for simple near-cursor feedback; use `ShowBottomRightBadge` when you want color/fixed-position control.

- **`PublishTrayMenuManifest(itemsArray)` / `HandleRemoteTrayMenuTrigger`** - publishes a script's custom tray-menu items so `StartupScript.ahk`'s master submenu can mirror them generically.
  - Call once per script, right after that script's own `Menu, Tray, Add` lines:
  ```ahk
  PublishTrayMenuManifest([ ["Display Label 1", "TrayLabel1"]
                          , ["-"]
                          , ["Display Label 2", "TrayLabel2"] ])
  ```
  - Each script gets its own manifest file (`%A_Temp%\ahk_traymenu_<ScriptName>.txt`, keyed by that script's own filename), so sharing this one function across multiple processes is safe - there's no cross-process state beyond the convention of one manifest file per script.
  - **Separator Support**: An entry of `["-"]` or a string `"-"` serializes to `"-|"` in the manifest. When `StartupScript.ahk` reads the manifest, any item whose first token is `"-"` (or empty) executes a bare `Menu, SubMenu_%PID%, Add` to insert a native Win32 horizontal separator line, grouping custom items cleanly.
  - If a script stops publishing items it previously did (a feature moved elsewhere, say), delete its stale manifest file once by hand.
    `StartupScript.ahk`'s `HandleRemoteTrayMenuTrigger` guard (`IsLabel`) keeps a leftover manifest from raising an error dialog, but won't clean up the dead entry on its own.

  **Tray menu shape**, built by `StartupScript.ahk`'s `MenuBuild:`:
  - Each managed script's own submenu is deliberately minimal: `View Key History` / `Edit` / `Restart` / `Exit`, plus that script's own published items.
    Pause and Suspend are **not** per-script.
  - `StartupScript.ahk` exposes one global "Suspend Hotkeys" tray item (and matching `Win+ScrollLock` hotkey) that cascades a real Suspend-Hotkeys toggle to every managed script at once, leaving each script's own background timers/watchers running.
    That's why Suspend was chosen over Pause, which would freeze those too.
  - This replaces AutoHotkey's own native Suspend Hotkeys/Pause Script/Exit tray items (which only ever acted on the master script's own hotkeys, not the fleet) rather than sitting alongside them.
    So there is exactly one Suspend action and one Exit action, not two of each.
  - `StartupScript.ahk`'s own 4 hotkeys need no exemption mechanism at all (no `Suspend, Permit`, no v2-only `#SuspendExempt`, which does not exist in v1.1 anyway).
    `SuspendAllToggle` only ever posts to the managed child scripts, never to this master script's own window, so none of its hotkeys can ever actually become suspended.
  - "Restart" kills a script and relaunches it fresh without moving it to the Load submenu (unlike Exit).
    Useful when just one script needs a clean restart without a full fleet reload.

- **`ShowDRMStatusBadge(msg)`** - thin color-mapping wrapper over `ShowBottomRightBadge`, specific to the DRM Video Streaming Mode feature (maps `[ACTIVE]` to deep green `#1A6E3C`, and `[OFF]` to dark slate grey `#3A3D40`, shown for 3000ms).

- **Chromium browser lifecycle helpers (`GetTargetBrowsersForDRM`, `GetBrowserHardwareAcceleration`, `SetBrowserHardwareAcceleration`, `CloseBrowserGracefully`, `LaunchBrowserInstance`)**
  - Cross-cutting utility functions providing graceful session-preserving shutdown, preference parsing, and headless/GPU flag manipulation for Chromium-based browsers (Brave and Google Chrome).
  - Used by `BasicTasks.ahk` for the DRM Video Streaming Mode toggle.

- **`RunSilentPowerShell(scriptPath, args := "")`** - launches a PowerShell script with zero visible window.

`MountExt4Ssd`/`UnmountExt4Ssd` do **not** live here - the ext4 SSD feature (hotkeys, auto-mount watcher, tray items, and these two functions) is fully self-contained in `AllScripts/Ext4SsdManager.ahk`, matching the single-feature-script convention `Brightness.ahk`/`ClosePrograms.ahk` already use.
They only ever lived in this shared file because two other generic scripts happened to both need them, not because the feature is genuinely cross-cutting the way the debounce pattern or badge system are.

## The debounce pattern

**The problem this solves**: a hotkey whose real work is slow (in this repo's case, an `icacls` sweep across 14 folders taking ~2.3-3.5 seconds) needs instant visual feedback on every press.
But it should only actually do that slow work once the user stops pressing - a rapid burst of presses should show a toast every time but commit only the *last* one.

Each feature owns its own state as three plain globals: a pending-value variable, a busy flag, and an interval, passed into the shared functions by name/`ByRef`.
Nothing in `SharedHelpers.ahk` stores any feature-specific state itself.

```ahk
global g_MyFeatureDebounceMs := 2000   ; 2000ms is the default this codebase
                                        ; uses everywhere the pattern appears -
                                        ; keep new features consistent unless
                                        ; you have a specific reason not to.
global g_MyFeaturePendingValue := ""
global g_MyFeatureCommitBusy := false

; Fast phase - the actual hotkey/tray target. Never blocks.
MyFeatureFastPhase() {
    global g_MyFeaturePendingValue, g_MyFeatureDebounceMs

    ; ... cycle/update g_MyFeaturePendingValue however your feature needs ...
    ; ... show instant feedback, e.g. ShowBottomRightBadge(...) ...

    DebounceArmTimer("MyFeatureCommit", g_MyFeatureDebounceMs)
}

; Commit phase - a LABEL (not a function - this one legitimately needs to be
; a label, since it's the actual SetTimer target application code reaches
; via Gosub-like dispatch, not a zero-param helper living in the shared
; library before any hotkey exists). Reached only via the timer armed above.
MyFeatureCommit:
    global g_MyFeaturePendingValue, g_MyFeatureCommitBusy, g_MyFeatureDebounceMs

    if !DebounceTryBeginCommit(g_MyFeatureCommitBusy, "MyFeatureCommit", g_MyFeatureDebounceMs)
        return

    snapshotValue := g_MyFeaturePendingValue
    ; ... do the real (slow) work using snapshotValue ...

    DebounceEndCommit(g_MyFeaturePendingValue, snapshotValue, g_MyFeatureCommitBusy, "MyFeatureCommit", g_MyFeatureDebounceMs)
return
```

**Why this is correct, precisely:**

- `DebounceArmTimer` uses AHK's own documented `SetTimer` "Reset" behavior: a negative period runs once after N ms, and calling `SetTimer` again on an already-pending target cancels that countdown and starts a fresh one rather than stacking a second pending firing.
  So only the *last* press in any rapid run ever reaches the commit label, and only once the interval elapses with zero further presses.
- `DebounceTryBeginCommit`'s busy-guard is defense-in-depth: AHK's timer engine already guarantees at most one concurrently-running instance of a given timer's target, so this should never actually trigger in practice.
- `DebounceEndCommit`'s reconciliation is the subtle but important part:
  - If a press lands *while the commit is already running* (not just within the debounce window, but seconds later while the real work is genuinely mid-flight), that intent can't safely cancel already-dispatched work, so it doesn't try.
  - Instead, comparing the live pending value against a snapshot taken before the slow work started detects the newer press and re-arms one more time, so it gets applied immediately after, never silently dropped.
- **Real commits can't be cancelled once started.** If your feature's "real work" is an external process launch (like `shell.Run(cmd, 0, true)`), killing it partway through to honor a newer press risks leaving it in a half-applied state, worse than letting it finish and following up immediately after.
  Don't try to make commits interruptible; let the reconciliation tail handle catching up instead.

**Why `ByRef` + dynamic `%var%`-label dispatch, not `Func()`/`.Bind()` bound-function timers:**

- Both idioms the debounce helpers rely on are already used elsewhere in this codebase: `ByRef` in `Brightness.ahk` and `HotkeyHelp.ahk`; dynamic `%var%` label dispatch for `Gosub` in the tray manifest handlers.
- Bound-function timers are supported since AHK v1.1.20, but require rebuilding the bound object on every re-arm (an object-target timer is deleted after firing, unlike a label/string timer which just goes `Off` and can be reused).
  They also aren't used anywhere in this repo for a `SetTimer` target.
- Reusing an idiom this codebase already demonstrably understands beats introducing a new one for marginal benefit.

## The bottom-right badge system

Colors follow a simple convention - pick from these when adding a new message, or extend `ShowSkillsStatusBadge` (a `SharedHelpers.ahk` wrapper over `ShowBottomRightBadge` that maps a `[LOCKED]`/`[UNLOCKED]`/`[AUTO]`/error message to its color automatically, shared by both `BasicTasks.ahk`'s manual toggle and `BackgroundAutomations.ahk`'s auto watcher) if you need new ones:

| Color       | Hex      | Meaning                                         |
| :---------- | :------- | :---------------------------------------------- |
| Deep green  | `1A6E3C` | Unlocked / open / permissive state              |
| Deep red    | `8B1A1A` | Locked / restricted state                       |
| Deep blue   | `0D4F8B` | Automatic / focus-driven state                  |
| Amber       | `6E5A00` | Work in progress ("applying...") - not an error |
| Dark orange | `7A3B00` | Error                                           |

**The DPI subtlety `ShowBottomRightBadge` encodes:**

- Under Windows display scaling above 100%, AHK v1's default Gui coordinate space is DPI-virtualized: a `Gui`'s rendered size can be inflated by the DPI scale factor relative to what was requested, even though `x`/`y` position values pass through unscaled.
- **The fix**: the `Gui` is created with `-DPIScale`, which maps every coordinate and dimension AHK sets or reads for that Gui 1:1 to physical screen pixels - the inflation problem is avoided at the root instead of being measured and corrected after the fact.
- Because sizing is physical-pixel-exact, the badge can be sized directly from a live GDI `DrawTextW` (`DT_CALCRECT`) measurement of the actual message text, taken fresh on every call, rather than created at a fixed nominal size and corrected afterward. This is also what makes the auto-sizing pill shape possible: badge width tracks the measured text width, falling back to a word-wrapped box only for messages too long to fit inline.
- `GetToastTargetMonitor()` re-resolves which monitor is under the cursor on every call, and the work area (`SysGet MonitorWorkArea`) is recalculated every call too - together these keep the badge anchored to the monitor actually in use (and its exact bottom-right work-area corner) across a Sunshine/Moonlight display-topology switch, rather than to a monitor index that goes stale the moment the active display changes.
- If you copy this pattern for a new kind of popup, keep `-DPIScale` plus a live text measurement on every call; don't fall back to a fixed nominal size with an after-the-fact position correction, which can't follow a monitor change or a message-length change without recomputing everything anyway.

**Create once, update in place - no destroy/recreate:**

- Destroying and rebuilding the whole `Gui` on every call (`Destroy` → `Sleep` → rebuild) produces a visible blank gap between badge transitions.
- `ShowBottomRightBadge` instead creates the window once (guarded by a `static created` flag) and every later call just does `Gui, ...: Color`, `GuiControl` on the text, and re-`Show`s if hidden - no destroy, no sleep, no rebuild, so transitions are instant.
- Dismissal (both the timer-driven path and the explicit `HideBottomRightBadge()`) uses `Gui, ...: Hide`, never `Destroy`, so the window stays alive and ready for the next instant update.
- Keep this create-once/update-in-place shape for any similar popup; reintroducing Destroy/Sleep brings the visible gap back.

**Use `Hwnd`, never `v`, for a Gui control created inside a function:**

- On AHK v1.1.37.02, `Gui, Name: Add, Text, ... vSomeVar, text` hangs indefinitely (not an error, no dialog, just a dead thread) the instant that `Add` line executes *from inside a user-defined function*.
- The exact same line at top-level auto-execute scope works instantly, independent of `BackgroundTrans` or of the function's name matching the Gui's name.
- **The fix**: use an `Hwnd` option instead (`... BackgroundTrans HwndhTextCtl, text`), store the resulting HWND in a `static`, and address the control later via `GuiControl, Name:, %hTextCtl%, newText`.
  AHK v1 accepts a bare HWND value as a ControlID just as readily as a `v`-variable name, and this path never hangs.
- `ShowBottomRightBadge` in `SharedHelpers.ahk` does exactly this.
  If you add a new Gui-based helper function to this file, use `Hwnd`, not `v`, for any control you'll need to reference again later.

## Path-leak prevention

This repo is **public** (`Arora-Sir/AutoHotKey-Windows-Scripts`). Three files hold real local machine paths and are gitignored, each with a tracked `.example` counterpart carrying generic placeholders:

- `AllScripts/LocalPaths.ahk`
- `AllScripts/PersonalKeywords.ahk`
- `AllScripts/PowerShell/ssd_config.json`

Two independent layers guard against a real path leaking into a tracked file anyway:

1. **`.githooks/pre-commit`** (local, tracked, fully generic: derives this machine's username/computer name from the environment at commit time rather than hardcoding them, since hardcoding them into a tracked file would itself be the exact leak this prevents).
   - Hard-blocks committing any of the 3 real config files if ever force-staged.
   - Hard-blocks any *other* staged file containing this machine's username, computer name, or a generic per-user Windows profile path pattern.
   - Warns (non-blocking) if a real config file has grown a variable/key its tracked `.example` hasn't caught up to yet.
   - Activated via a **local-only** git config: `git config core.hooksPath .githooks` (not itself tracked - a fresh clone needs to run this once).
2. **`.github/workflows/no-local-path-leak.yml`** - a server-side backstop, since the local hook alone is bypassable (`--no-verify`, or simply never configuring `core.hooksPath`).
   Can only check the same generic per-user Windows profile path pattern, never this machine's specific values (a CI runner has no legitimate way to know them, and a tracked workflow file embedding them would defeat the purpose).

A local, gitignored `CLAUDE.md` at the repo root carries additional contributor/tooling notes specific to this machine - not tracked, so not reproduced here.

## Cross-file state via a shared marker file

Not every shared state goes through `SharedHelpers.ahk`. `AllScripts/SunshineMouseWatchdog.ahk` and `AllScripts/BasicTasks.ahk` (Win+Shift+P's `ToggleTabletDisplayMode`) coordinate the Sunshine fast/normal mouse-speed state through plain marker files instead, since Sunshine's own prep-cmd hooks - `AllScripts/PowerShell/Sunshine/set_fast.ps1` (`do`) / `set_normal.ps1` (`undo`), run directly by Sunshine on stream start/end, independent of any AHK script - already owned this convention before the AHK-side manual toggle existed.

- **`.fast_since`** - the marker's mere existence means "fast mode"; its content distinguishes *why*: empty means a real Sunshine session set it (`set_fast.ps1`), `"manual"` means the Win+Shift+P toggle did.
- **`sunshine_manual_switch.flag`** (in `%A_Temp%`, separate from `.fast_since`) - a 20-second-bounded grace window armed by the manual toggle itself. `SunshineMouseWatchdog.ahk` skips its sunshine.log/Tailscale disconnect checks entirely while this flag is younger than 20s - those checks answer "did the old session end," not "has the user had time to open Moonlight yet," and would otherwise revert a deliberate toggle before the user even connects. Bounded rather than indefinite, so toggling to tablet mode and never actually streaming doesn't permanently disable the disconnect checks. See that file's own `MANUAL OVERRIDE` comments for the full reasoning.
- **`.session_quit`** - written by `set_normal.ps1` only when Sunshine's own `undo` prep-cmd hook fires (an explicit Moonlight quit), never by the watchdog. Lets `SunshineMouseWatchdog.ahk` short-circuit straight to a ~1.5s display restore instead of waiting out the normal multi-poll debounce/settle window that exists to avoid reacting to a transient back-gesture/app-switch.

## Why ToggleTabletDisplayMode() is bound to Win+Shift+P

`BasicTasks.ahk` binds `Win+Shift+P` to `ToggleTabletDisplayMode()`. Previously, alternate bindings (`Ctrl+Shift+P` and `Win+Alt+P`) were tested in an attempt to trigger the toggle remotely from the Galaxy Tab S10 Ultra during a Moonlight session without walking over to the PC.

- Android intercepts recognized modifier-key combos (Alt+Tab, the Windows key, Ctrl+S, etc.) at the OS level before any app - Moonlight included - ever sees them, redirecting to Android's own system actions instead. This is a documented, still-open limitation in Moonlight Android (see its GitHub issues #840 and #975), not something fixable from this repo's side.
- This applies to both a physical/case Bluetooth keyboard and the tablet's own on-screen Samsung Keyboard - the latter's own Ctrl+A/Ctrl+C-style "shortcuts" are local Android text-editing actions, not genuine key events that would traverse to a remote session at all.
- Alternate keybinds like `Ctrl+Shift+P` also collided with universal editor shortcuts (Command Palette in VS Code / Antigravity), while `Win+Alt+P` belongs to Bitwarden Vault (Password Manager) in `PersonalKeywords.ahk`. Both were retired, leaving `Win+Shift+P` as the sole PC shortcut.
- The confirmed-working remote path remains touching the PC's tray items (Toggle Display Mode, Duplicate Only, under `BasicTasks.ahk`'s tray submenu) directly through the Moonlight stream, since that involves no keyboard at all.

## Windows Task Scheduler boot architecture

The AutoHotkey fleet is launched on Windows boot via a dedicated scheduled task named `"AHK Startup Script"`, managed by `setup_startup_task.ps1` (with Explorer-friendly 1-click batch wrappers `Install_Startup_Task.bat` and `Uninstall_Startup_Task.bat`).

- **30-Second Logon Delay (`PT30S`)**:
  - Task Scheduler is deliberately chosen over Windows Startup (`shell:startup` or registry `Run` keys) because of startup race conditions.
  - On modern Windows 10/11 installations, audio endpoints, network adapters (Tailscale/Wi-Fi), graphics drivers, and the Windows Explorer shell initialize concurrently across multiple worker threads at user logon.
  - Launching the AHK fleet instantaneously on logon causes tray icons to fail to register with `Shell_NotifyIcon`, display topology queries to return incomplete monitor arrays, and background network checks to throw spurious errors.
  - A 30-second delay (`PT30S`) ensures the entire desktop subsystem has settled before `StartupScript.exe` executes.

- **Elevated Task Creation vs. Standard User Execution (`RunLevel Limited`)**:
  - Registering or modifying tasks in the Task Scheduler root (`\`) requires Administrator privileges. Therefore, `Install_Startup_Task.bat` and `setup_startup_task.ps1` self-elevate via PowerShell `Start-Process -Verb RunAs` if executed un-elevated.
  - However, the task itself is registered with `Principal.RunLevel = Limited` under the user's standard account (`$env:USERNAME`).
  - Running as a standard user is critical: running AHK elevated would trigger UAC confirmation prompts on every boot, isolate window messages (UIPI blocks un-elevated apps from sending messages to elevated windows), and alter file virtualization paths.

- **Battery Resilience & Infinite Execution**:
  - Registered with `Settings.AllowStartIfOnBatteries = $true` and `Settings.DontStopIfGoingOnBatteries = $true`.
  - Windows Task Scheduler defaults to stopping background tasks when a laptop disconnects from AC power; these flags guarantee continuous background automation on laptops.
  - `ExecutionTimeLimit = PT0S` (zero timeout) prevents Windows from terminating the fleet after the default 3-day task limit.

- **Recompilation & Relaunch Integration**:
  - `build_startup_exe.ps1` checks for the existence of `"AHK Startup Script"` in Task Scheduler.
  - When invoked with `-Relaunch` (or when triggered via the tray menu's "Recompile Startup" item), it first stops `StartupScript.exe` to release file locks, compiles a fresh binary via `Ahk2Exe`, and triggers `schtasks /run /tn "AHK Startup Script"` to restart the master process seamlessly in the user's active session without command prompt flashes. If the scheduled task is not registered on that machine, it gracefully falls back to `Start-Process`.

## DRM Video Streaming Mode architecture

When streaming desktop video to a tablet (such as Samsung Galaxy Tab S10 Ultra) or handheld device via Moonlight and Sunshine, hardware-accelerated video playback on Chromium browsers (Brave, Google Chrome) results in a black video screen for DRM-protected content (Netflix, Amazon Prime Video, Disney+ Hotstar, Udemy, etc.).

- **The Root Cause**:
  - Protected media playback utilizes Windows Hardware DRM / Protected Media Path (PMP) surfaces within Chromium's GPU process.
  - Desktop duplication APIs (Direct3D Desktop Duplication / DXGI) used by Sunshine and Moonlight cannot capture protected Direct3D surfaces while GPU compositing is active, outputting solid black frames for the video area while subtitles and browser UI remain visible.

- **The Architecture Solution (`BasicTasks.ahk` + `SharedHelpers.ahk`)**:
  - Rather than switching monitor topologies or disabling system-wide virtual display drivers, the toggle operates strictly at the browser application level via `ToggleDRMStreamingMode()`:
  1. **Target Browser Resolution**: Detects whether Brave or Chrome is the active focused window. If neither is active, it inspects running background processes, falling back to Brave as default.
  2. **Graceful Shutdown (`CloseBrowserGracefully`)**: Sends `WM_CLOSE` to all top-level windows (`WinClose ahk_id %this_id%`). This allows Chromium to write open tabs, history, and active sessions to disk cleanly. Lingering background watcher processes are terminated to release file locks on Chromium profile files.
  3. **Atomic `Local State` Modification (`SetBrowserHardwareAcceleration`)**: Reads Chromium's root `Local State` JSON file in UTF-8. Atomically sets `"hardware_acceleration_mode": {"enabled": false}` (and updates `hardware_acceleration_mode_previous`). Writes to a `.tmp` file and performs an atomic replace (`FileMove ... 1`) to eliminate corruption risks.
  4. **Targeted Relaunch (`LaunchBrowserInstance`)**: Relaunches the browser with:
     - `--disable-gpu`: Disables the GPU process, forcing software rasterization for video presentation surfaces.
     - `--restore-last-session`: Automatically restores all previously open tabs without requiring manual user intervention.
     - `--disable-session-crashed-bubble`: Suppresses the "Restore pages? Chromium didn't shut down correctly" warning bubble.
  5. **Status Badge & Tray Menu Sync**: Displays `ShowDRMStatusBadge("[ACTIVE] DRM Streaming: ... (HW Accel OFF)")` and updates the tray menu item label dynamically via `UpdateDRMTrayStatus`.
  6. **Reversion**: Clicking the toggle again reverses the JSON preference (`"enabled": true`), closes the browser gracefully, and relaunches with normal GPU hardware acceleration restored.

## Master tray menu architecture

`StartupScript.ahk` provides a centralized system tray interface for the entire script fleet, ensuring that multiple background scripts do not clutter the Windows notification area with redundant icons.

- **Unified Single Tray Icon**:
  - On startup and resolution changes, `TrayIconRemove` iterates through all child script processes and calls `Shell32\Shell_NotifyIcon` with `NIM_DELETE` on their notification handles.
  - The master script keeps only its own single tray icon active. Mouseover (`WM_MOUSEMOVE` `0x200`) proactively cleans up any ghost icons left by terminated child processes.

- **Click Action Dispatch (`AHK_NOTIFYICON`)**:
  - Tray interactions are intercepted via `OnMessage(0x404, "AHK_NOTIFYICON")`:
    - **Left-Click (`WM_LBUTTONUP` `0x202`) & Right-Click (`WM_RBUTTONUP` `0x205`)**: Both left-click and right-click open the master tray context menu (`Menu, Tray, Show`).
    - **Hover Tooltip (`WM_MOUSEMOVE` `0x200`)**: Displays a dynamic sorted list of all active scripts and cleans up any ghost tray icons.

- **Menu Hierarchy & Pinned Scripts**:
  - **Pinned Scripts**: Scripts listed in `PinnedScripts` (`BasicTasks`, `PersonalKeywords`) are rendered directly at the top level of the master tray menu for immediate 1-click submenu access.
  - **Additional Scripts Submenu**: All remaining active background scripts (`BackgroundAutomations`, `Brightness`, `ClosePrograms`, `Ext4SsdManager`, `HotkeyHelp`, `SunshineMouseWatchdog`, `Watchdog`) are cleanly consolidated into an expandable "Additional Scripts" submenu, preventing vertical menu overflow.
  - **Child Submenu Structure**: Each managed script submenu provides standard management actions (`View Key History`, `Edit`, `Restart`, `Exit`), followed by a horizontal separator line and any custom items published by that script.
  - **Global Actions**: Positioned at the bottom of the master menu: "Reload All", "Recompile Startup", "Suspend Hotkeys" (global cascade toggle), and "Exit".

## Sunshine & Moonlight display topology and watchdog lifecycle architecture

This system orchestrates high-performance, low-latency remote desktop streaming from the host laptop to a Samsung Galaxy Tab S10 Ultra using Sunshine, Moonlight, and an HDMI dummy plug, coordinated by `SunshineMouseWatchdog.ahk` and `BasicTasks.ahk`.

### Hardware topology & display modes

```mermaid
flowchart TD
    subgraph Host ["Host Laptop (Acer Predator Helios 300)"]
        Internal["DISPLAY1: Internal Panel (1920x1080 @ 144Hz, 16:9)"]
        DummyPlug["DISPLAY4: HDMI Dummy Plug (2560x1600 @ 120Hz, 16:10)"]
    end

    subgraph Client ["Client Device (Samsung Galaxy Tab S10 Ultra)"]
        TabletScreen["OLED Panel (2560x1600 Native, 16:10 Aspect Ratio)"]
    end

    subgraph Modes ["Display Topologies"]
        PC_Only["PC Screen Only (DisplaySwitch 1): DISPLAY1 Active, DISPLAY4 Off, Mouse Speed 10"]
        Tab_Only["Tablet Mode / Second Screen Only (DisplaySwitch 4): DISPLAY1 Off, DISPLAY4 Active, Mouse Speed 20"]
        Duplicate["Duplicate Mode (DisplaySwitch 2): DISPLAY1 Cloned with DISPLAY4, Mouse Speed 20"]
    end

    DummyPlug -. Matches Aspect Ratio .-> TabletScreen
    PC_Only --> Internal
    Tab_Only --> DummyPlug
    Duplicate --> Internal
    Duplicate --> DummyPlug
```

### Complete lifecycle, race conditions, and disconnect flap hazard

```mermaid
sequenceDiagram
    autonumber
    actor User as User (Tablet / Laptop)
    participant Moonlight as Moonlight (Tab S10 Ultra)
    participant Sunshine as Sunshine Server (Windows Service)
    participant Watchdog as SunshineMouseWatchdog.ahk (Interactive Session)
    participant Win11 as Windows 11 Display Engine (DisplaySwitch)

    Note over User,Win11: Phase 1: Initiation & Streaming
    User->>Win11: Win+Shift+P or Tray Menu (Toggle Tablet Mode)
    Win11-->>User: DisplaySwitch 4 (DISPLAY4 2560x1600 Active, Laptop Screen OFF, mouse speed boosted to 20 and 20s manual grace window armed directly by the toggle itself - not the Watchdog)
    User->>Moonlight: Open Desktop Stream
    Moonlight->>Sunshine: Connect Stream (Tailscale 100.x.y.z)
    Sunshine->>Sunshine: DXGI Desktop Duplication on DISPLAY4 (2560x1600 @ 60/120Hz)
    Sunshine->>Watchdog: Log "CLIENT CONNECTED"
    Watchdog->>Watchdog: Clears manual grace flag (mouse speed was already boosted at the manual toggle above; ForceFast only re-boosts here for a resumed session where the marker was absent)

    Note over User,Win11: Phase 2: Disconnect vs. Transient Back Button Flap
    User->>Moonlight: Press Android Back / Switch Tablet App / Screen Timeout
    Moonlight->>Sunshine: Disconnect Session
    Sunshine->>Watchdog: Log "CLIENT DISCONNECTED"
    Sunshine->>Sunshine: Start Undo Cmd countdown (5s-20s exit timeout)

    alt Explicit Quit (Sunshine's own undo hook fires)
        Sunshine->>Watchdog: set_normal.ps1 (Sunshine's undo prep-cmd, not a Watchdog action) writes .session_quit
        Watchdog->>Win11: Instant restore (~1.5s) - bypasses the debounce/settle window below entirely
    else Aggressive Immediate Trigger (< 3s)
        Watchdog->>Win11: DisplaySwitch 1 (Switches back to DISPLAY1 1080p)
        Win11-->>Watchdog: Internal Screen ON, DISPLAY4 Deactivated
        Note over User,Win11: Hazard: User returns to Moonlight after 3 seconds
        User->>Moonlight: Re-tap Desktop Stream
        Moonlight->>Sunshine: Connect while Windows is on DISPLAY1 (1080p)
        Sunshine->>Sunshine: DXGI tries to capture DISPLAY1, races display topology, or hangs in duplicate window!
    else Reconnect within Settle Window (< 3s or Debounce Window)
        User->>Moonlight: Re-tap Desktop Stream within settle grace
        Moonlight->>Sunshine: Re-connect before Watchdog switches display
        Sunshine->>Sunshine: DISPLAY4 still active at 2560x1600, stream resumes smoothly without hang!
    end

    Note over User,Win11: Phase 3: Hardware Lid-Open Safety Net
    User->>Host: Physically lift laptop lid while streaming
    Host->>Watchdog: WM_DISPLAYCHANGE (0x007E) triggered by DISPLAY1 wake
    Watchdog->>Win11: DisplaySwitch 1 (Restores PC Screen Only, mouse speed 10)
```

### State matrix and trade-off analysis

| State / Event | Trigger | Intended Outcome | Potential Hazard / Consequence | Design Mitigation |
| :--- | :--- | :--- | :--- | :--- |
| **Manual Tablet Toggle** | `Win+Shift+P` / Tray Menu | Switches to `DisplaySwitch 4`, mouse speed 20. | Sunshine log tail still shows old `CLIENT DISCONNECTED`. | 20s manual grace window (`sunshine_manual_switch.flag`) prevents watchdog revert. |
| **Moonlight Connect** | Moonlight app taps "Desktop" | Sunshine captures `DISPLAY4` at 2560x1600. | Auto-switching to `DisplaySwitch 4` on connect races with Sunshine DXGI and hangs. | Connect-side stays manual; watchdog only auto-boosts mouse speed if normal. |
| **Transient Disconnect** | Android back gesture / app switch | User intends to pause or check another tablet app for 5-15s. | Watchdog immediately reverts to `DisplaySwitch 1` in 3s, deactivating `DISPLAY4`. | Disconnect debounce / settle period prevents flap hang on prompt reconnect. |
| **Permanent Disconnect** | User finishes work, closes Moonlight | Laptop screen turns back on (`DisplaySwitch 1`), mouse speed 10. | Laptop screen stays black if watchdog fails to detect disconnect. | Multi-signal detection: Sunshine log (`CLIENT DISCONNECTED`), Tailscale peer offline, and 8h ceiling. |
| **Explicit Quit** | Sunshine's own undo prep-cmd hook fires (`set_normal.ps1`) | `.session_quit` written, mouse speed and display restored almost immediately. | The normal ~24s debounce (`RequiredLogStreak` polls) would otherwise delay an already-confirmed quit for no reason. | Watchdog treats `.session_quit` as an instant (~1.5s) signal, bypassing the debounce entirely, and deletes it immediately after consuming it so it can't re-trigger. |
| **Lid Open While Streaming** | User opens laptop lid | Immediate return to Laptop Mode (`DisplaySwitch 1`), mouse speed 10. | Infinite loop if display change re-triggers lid handler. | Guard 1 (4s manual toggle lock) + Guard 2 (only acts if `.fast_since` exists). |

---

## Simple Sticky Notes Multi-Resolution Layout Architecture

This section documents the dual deterministic desktop positioning system for Simple Sticky Notes (`ssn.exe`), implemented in `AllScripts/PowerShell/apply_ssn_layout.ps1` and wired into `AllScripts/SharedHelpers.ahk`, `AllScripts/BasicTasks.ahk`, and `AllScripts/SunshineMouseWatchdog.ahk`.

### Display Geometry & Mathematical Model

The workstation alternates between two distinct physical display surfaces:

1. **Host Laptop Screen (`DISPLAY1`)**:
   - Physical Resolution: $1920 \times 1080$ @ 144Hz (16:9 aspect ratio)
   - Windows DPI Scale: 125%
   - Logical Workspace (DIP): $1536 \times 864$

2. **Tablet Screen via HDMI Dummy Plug (`DISPLAY4`)**:
   - Physical Resolution: $2560 \times 1600$ @ 120Hz (16:10 aspect ratio)
   - Windows DPI Scale: 175%
   - Logical Workspace (DIP): $1463 \times 914$

### The 73px Deficit Problem

$$\Delta\text{Width} = 1536\text{px (Laptop)} - 1463\text{px (Tablet)} = 73\text{px}$$

On the laptop, notes span across 4 columns ending flush at the right bezel:
- Column 0: $X = 0, W = 240$
- Column 1: $X = 728, W = 240$ (ends at 968px)
- Column 2: $X = 968, W = 300$ (ends at 1268px)
- Column 3: $X = 1268, W = 268$ (ends at 1536px)

When Windows switches to Tablet Mode (`DisplaySwitch 4`), Column 3 extends 73 pixels beyond the tablet screen edge ($1536 > 1463$). Windows and Simple Sticky Notes detect the boundary breach and clamp Column 3 leftward into Column 2, which then collides with Column 1, destroying the layout.

### Deterministic Pixel Profiles

Instead of dynamic runtime snapshots (which capture corrupted positions during transitions), the engine enforces two mathematically calculated deterministic layouts:

| Column | Dimensions ($W \times H$) | Description | Laptop ($X, Y$) | Tablet ($X, Y$) |
| :--- | :--- | :--- | :--- | :--- |
| **Col 0** | $240 \times 240$ | Far Left Bottom Note | $X = 0, Y = 576$ | $X = 0, Y = 576$ |
| **Col 1** | $240 \times 120$ | Top Small Note | $X = 728, Y = 0$ | $X = 640, Y = 0$ |
| **Col 1** | $240 \times 240$ | Bottom Square Note | $X = 728, Y = 120$ | $X = 640, Y = 120$ |
| **Col 2** | $300 \times 240$ | Top Medium Note | $X = 968, Y = 0$ | $X = 885, Y = 0$ |
| **Col 2** | $300 \times 183$ | Middle Note | $X = 968, Y = 240$ | $X = 885, Y = 240$ |
| **Col 2** | $300 \times 236$ | Bottom Medium Note | $X = 968, Y = 423$ | $X = 885, Y = 423$ |
| **Col 3** | $268 \times 548$ | "Today" Expanded Note | $X = 1268, Y = 0$ | $X = 1190, Y = 0$ |
| **Col 3** | $268 \times 32$ | Minimized Title Bars (x5) | $X = 1268, Y = 548, 580, \dots$ | $X = 1190, Y = 548, 580, \dots$ |

- **Laptop Column 3 Edge**: $1268 + 268 = 1536\text{px}$ (flush against laptop right boundary).
- **Tablet Column 3 Edge**: $1190 + 268 = 1458\text{px}$ (safe 5px margin before 1463px tablet edge, zero cut-off).

### Lifecycle & Multi-Trigger Execution

The positioning engine is triggered automatically across all display transition pathways:

1. **Manual Hotkey (`Win+Shift+P`)**:
   - `ToggleTabletDisplayMode()` in `AllScripts/BasicTasks.ahk`: Executes `DisplaySwitch 4` or `1`, and calls `ApplyTabletStickyNotesLayout(1500)` or `ApplyLaptopStickyNotesLayout(1500)`.
2. **Duplicate Mode (`Win+Ctrl+Shift+P`)**:
   - `SwitchToDuplicateDisplayMode()`: Sets `DisplaySwitch 2` and re-applies layout.
3. **Sunshine Watchdog Auto-Revert**:
   - `SunshineWatchdog_ForceNormal()` in `AllScripts/SunshineMouseWatchdog.ahk`: When Moonlight disconnects or session times out, reverts to `DisplaySwitch 1` and calls `ApplyLaptopStickyNotesLayout(2000)`.
4. **Hardware Lid Reopen (`WM_DISPLAYCHANGE 0x007E`)**:
   - `OnDisplayChange_LidRecovery` in `AllScripts/BasicTasks.ahk`: Catches physical lid reopening during stream and restores laptop layout.
5. **Fleet Startup / User Logon**:
   - `StartupScript.ahk` auto-execute: Evaluates current screen width and applies the matching layout.

### Win32 Native Implementation (`apply_ssn_layout.ps1`)

The script avoids AutoHotkey desktop isolation and DWM race conditions via:
- **Thread Desktop Attachment**: Uses `OpenDesktop("Default", ...)` and `SetThreadDesktop` to access the interactive surface.
- **Process Thread Enumeration**: Calls `EnumThreadWindows` across `ssn.exe` threads rather than `EnumWindows`.
- **Dimension Signature Matching**: Matches windows by width and height rather than volatile HWNDs.
- **Dual-Wave Locking**: Performs an active polling loop (up to 6s at 300ms intervals) followed by a secondary `SetWindowPos` pass 1.2s later to defeat late DWM refreshes.
---

## Key Design Decisions

Architectural decisions in this fleet prioritize reliability, non-blocking responsiveness, and resilience against Windows OS quirks.

### 1. Win32 Named Mutex Over Lock Files (`AcquireNamedMutex`)
- **Context**: Heavy cross-process operations (such as `icacls` permission sweeps during Skills Vault toggles) require mutual exclusion across multiple independent scripts.
- **Alternative**: Creating a lock file on disk (`%TEMP%\vault.lock`).
- **Decision**: Win32 named kernel mutex (`CreateMutex`, `WaitForSingleObject`).
- **Rationale**: If an AHK process crashes or is forcefully terminated mid-operation, a lock file remains orphaned on disk, permanently wedging future operations. The Windows kernel automatically marks a named mutex as abandoned when its owning thread terminates, allowing the next waiting process to acquire it cleanly.

### 2. 30-Second Task Scheduler Delay Over `shell:startup`
- **Context**: The fleet must auto-start on user logon.
- **Alternative**: Placing shortcuts in the Windows startup folder (`shell:startup`).
- **Decision**: Windows Task Scheduler trigger with a 30-second logon delay (`PT30S`) and `RunLevel Limited`.
- **Rationale**: At user logon, Windows Explorer, graphics drivers, audio services, and network adapters (Tailscale/Wi-Fi) initialize concurrently across multiple CPU threads. Launching immediately causes race conditions, missing system tray icons, and failed IPC registrations. A 30-second delay guarantees the desktop shell has completely settled. `RunLevel Limited` under the standard user account prevents boot UAC prompts while maintaining proper window message routing.

### 3. AutoHotkey v1.1 Retention Over v2 Migration
- **Context**: Upgrading the codebase to AutoHotkey v2.
- **Alternative**: Rewriting all scripts to AHK v2 syntax.
- **Decision**: Explicit `#Requires AutoHotkey v1.1` across the entire fleet.
- **Rationale**: `StartupScript.exe` relies on dynamic runtime Win32 tray menu reflection (`Menu, SubMenu_%PID%, Add`), cross-process label triggers, and specific Win32 API structures that behave differently under v2. The fleet is stable, fully debugged, and heavily integrated with Win32 message routing. Rewriting to v2 would break master tray submenu mirroring without functional benefit.

### 4. Global Hotkey Suspension Over Script Pausing (`SuspendAllToggle`)
- **Context**: Providing a single kill-switch hotkey (`Win+ScrollLock`) to disable productivity hotkeys during gaming or full-screen apps.
- **Alternative**: Pausing all child scripts (`Pause, Toggle`).
- **Decision**: Cascading hotkey suspension (`PostMessage, 0x111, 65305`) while keeping script event loops running.
- **Rationale**: Pausing a script freezes its underlying timers, watchdog threads, and window message handlers. Background watchdogs (such as `SunshineMouseWatchdog.ahk` and `WatchSkillsLock`) must continue monitoring system state even when typing shortcuts are suspended. Hotkey suspension disables keyboard hooks while leaving background automation fully operational.

### 5. Debounced Commit Pattern for Slow Workflows
- **Context**: Operations requiring slow disk or permission changes (such as the 2.3-3.5 second `icacls` folder sweep).
- **Alternative**: Executing the slow command on every hotkey press, or queuing sequential runs.
- **Decision**: Two-phase settle architecture (`DebounceArmTimer` and `DebounceTryBeginCommit`).
- **Rationale**: Every keypress provides instant user feedback by updating a colored HUD badge in place, but defers execution by resetting a 2000ms countdown timer. Rapid successive presses update state in memory without locking the desktop. The heavy system command executes exactly once after the user stops pressing.

### 6. Deterministic Layout Profiles Over Dynamic Window Snapshots
- **Context**: Repositioning Simple Sticky Notes (`ssn.exe`) when switching between laptop screen and headless tablet display.
- **Alternative**: Capturing window coordinates dynamically before display transitions and restoring them afterward.
- **Decision**: Enforcing mathematically calculated pixel coordinates (`apply_ssn_layout.ps1`) based on detected screen width.
- **Rationale**: Dynamic coordinate snapshots captured during display mode switches frequently record corrupted, intermediate positions caused by DWM boundary clamping (the 73px width deficit between laptop 1536px and tablet 1463px). Hardcoded coordinate tables guarantee pixel-perfect placement flush against screen bezels on every switch.

### 7. Non-Blocking TCP Pre-Check Before ADB Connections
- **Context**: Wireless ADB file transfer to mobile devices via Tailscale or local Wi-Fi.
- **Alternative**: Invoking `adb connect <ip>:5555` directly.
- **Decision**: Probing port 5555 with a .NET `TcpClient` socket using a 500ms timeout prior to invoking ADB.
- **Rationale**: Native `adb connect` has a hardcoded 21.1-second timeout when an IP is offline. Probing the port via a raw TCP handshake detects unreachable endpoints in 500ms, enabling instant failover from Tailscale to local Wi-Fi without locking Windows Explorer.

### 8. Keyword Expansion Engine and Settle Delay in PersonalKeywords.ahk
- **Context**: Expanding short keywords into email addresses, website URLs, government IDs, and large multi-line AI reasoning prompt directives.
- **Problem**: When `:X*:` hotstrings for URLs used clipboard pasting (`PasteText()`), typing `linpro.` in Chromium address bars (Chrome/Brave) caused the URL to collapse into `://` and produce an invalid scheme navigation error.
- **Root Cause**: AutoHotkey sends 7 backspaces to erase `linpro.`. In `PasteText()`, dispatching `SendInput, ^v` with 0 ms delay created a race condition: Chromium was still draining backspaces from the Windows input queue when `Ctrl+V` landed. Two backspaces drained before the paste, and the remaining 5 backspaces drained after `https://` was pasted, deleting `https` (5 characters) and leaving only `://`.
- **Decision**: Added a 50 ms backspace-drain settle delay (`Sleep, 50`) inside `PasteText()` before `SendInput, ^v`:
  1. **URLs, Emails, and AI Prompts (`PasteText()`)**:
     - Uses `ClipboardAll` backup, sets clipboard, waits via `ClipWait, 1`, sleeps 50 ms to allow the target window's message loop to completely drain all backspaces, issues `SendInput, ^v`, and waits 100 ms before restoring previous clipboard content.
     - Provides instant expansion (0 ms visual feel) across both browser Omnibox fields and rich text editors with zero character loss or scheme corruption.
  2. **Government IDs and Tax Numbers (`AadharNo.`, `PanNo.`) via Native Keystrokes (`:*:`)**:
     - Indian banking, tax, and government KYC portals frequently enforce JavaScript paste blockers (`onpaste="return false;"`).
     - Keystroke simulation bypasses paste restrictions; `Ctrl+V` clipboard pasting is actively rejected.

### 9. Arrow Notation & Hotkey Help Comment Architecture
- **Context**: In-file documentation comments, header shortcut summaries, and the two-column GUI built by `HotkeyHelp.ahk`.
- **Problem**: Historical scripts mixed multi-hyphen arrows (`-->` forward and `<--` backward). The double-hyphen substring created friction with the zero double-hyphens documentation invariant and risked false positives in automated linters. Additionally, hotkeys defined without an inline semicolon comment (such as multi-line declarations `$!F4::` or taskbar wheel controls `WheelUp::Send {Volume_Up}`) caused `HotkeyHelp.ahk` to display blank descriptions in the GUI because its parser searches specifically for `::.*?;(.*)`.
- **Decision**: Standardized all arrow symbols across the repository to single-hyphen notation without exceptions:
  1. **Header & Block Comments (`->`)**:
     - Format: `; Key -> Action` (e.g. `; Win+F -> Run Firefox`).
     - Uses single-hyphen right arrow `->` to represent causal triggers cleanly while completely eliminating ASCII double-hyphens.
  2. **Hotkey Help Inline Comments (`<-`)**:
     - Format: `Key::Action ;{ <- Description` (e.g. `WheelUp::Send {Volume_Up} ;{ <- (Taskbar) Volume Up`).
     - `HotkeyHelp.ahk` splits output into two columns: Hotkey Name (padded to 25 characters on the left) and Description (on the right). The single-hyphen left arrow `<-` visually points back toward the hotkey name, preserving intuitive layout cues with zero double-hyphens.
     - Multi-line hotkeys and context-sensitive directives require an explicit inline comment on the hotkey declaration line so `RegExMatch(File_Line, "::.*?;(.*)", Match)` captures the intended description.

---

## Developer Tooling & Quality Standards

To ensure high documentation quality, prevent data leaks, and avoid AI slop in public commits, the repository incorporates autonomous validation tooling.

### Language-Aware Dash Cleaner (`scripts/clean_dashes.py`)

A zero-dependency Python script that scans tracked and staged files for prohibited punctuation:
- Detects and auto-repairs unicode em-dashes, en-dashes, and comment double-hyphens.
- Enforces natural human punctuation (commas, colons, periods, parentheses).
- Respects syntax exceptions: decrement operators (`i--`, `counter--`), CLI flags (`--staged`, `--check`), CSS custom properties (`--var`), and `@vendored` annotations.

**Usage Commands**:
```bash
# Check staged files (exit code 1 if violations found)
python scripts/clean_dashes.py --check

# Auto-repair all staged files before committing
python scripts/clean_dashes.py --staged

# Scan and auto-repair all tracked repository files
python scripts/clean_dashes.py --all
```

### Multi-Stage Pre-Commit Hook (`.githooks/pre-commit`)

Configured via `git config core.hooksPath .githooks`. Runs three validation checks before any commit is accepted:
1. **Check 1: Private Path & Secret Leak Protection**: Scans staged content against `LocalPaths.ahk.example` to ensure personal absolute paths, usernames, and private credentials are never committed.
2. **Check 2: Prohibited File Staging**: Prevents staging unencrypted sensitive files, lock files, or temporary manifests.
3. **Check 3: Dash Linting & Anti-Slop Enforcement**: Runs `python scripts/clean_dashes.py --check` across staged files. If violations exist, commit is blocked with instructions to run `python scripts/clean_dashes.py --staged`.
