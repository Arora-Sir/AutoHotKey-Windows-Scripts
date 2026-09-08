# Architecture

This document covers the shared library (`AllScripts/SharedHelpers.ahk`), the debounce pattern it provides as a reusable template, the bottom-right badge system, and the local-path leak prevention setup.
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
  PublishTrayMenuManifest([["Display Label 1", "TrayLabel1"],
                            ["Display Label 2", "TrayLabel2"]])
  ```
  - Each script gets its own manifest file (`%A_Temp%\ahk_traymenu_<ScriptName>.txt`, keyed by that script's own filename), so sharing this one function across multiple processes is safe - there's no cross-process state beyond the convention of one manifest file per script.
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

| Color | Hex | Meaning |
|---|---|---|
| Deep green | `1A6E3C` | Unlocked / open / permissive state |
| Deep red | `8B1A1A` | Locked / restricted state |
| Deep blue | `0D4F8B` | Automatic / focus-driven state |
| Amber | `6E5A00` | Work in progress ("applying...") - not an error |
| Dark orange | `7A3B00` | Error |

**The DPI subtlety `ShowBottomRightBadge` encodes:**

- Under Windows display scaling above 100%, a `Gui` requested at `w300 h46` can *render* larger than requested, inflated by the DPI scale factor (e.g. 125% scaling inflates it to `375x58`), even though the requested x/y *position* matches the actual rendered position exactly (position passes through unscaled; size does not).
- A clamp computed against the nominal 300x46 size would not catch this - it would still overflow using the real, larger rect.
- **The fix**: measure the actual post-creation rect via `WinGetPos` and correct against *that*, position-only.
  Re-specifying w/h in the correction step recompounds the same inflation (a second explicit w/h compounds `375→469`, not back down to 300).
- If you copy this pattern for a new kind of popup, keep the measure-then-correct-position-only structure; don't simplify it back to a pre-computed clamp.
- This measure-and-correct block only runs once, at first creation (see below); it is never re-triggered by a later color/text update, so the inflation can never recompound in normal use.

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

Not every shared state goes through `SharedHelpers.ahk`. `AllScripts/SunshineMouseWatchdog.ahk` and `AllScripts/BasicTasks.ahk` (Win+Shift+P's `ToggleTabletDisplayMode`) coordinate the Sunshine fast/normal mouse-speed state through one plain marker file (`.fast_since`) instead, since two independent PowerShell scripts (`set_fast.ps1`/`set_normal.ps1`) already owned it before the AHK-side manual toggle existed.

- The marker's mere existence means "fast mode"; its content distinguishes *why*: empty means a real Sunshine session set it (`set_fast.ps1`), `"manual"` means the Win+Shift+P toggle did.
- `SunshineMouseWatchdog.ahk` defers entirely to a `"manual"` marker, skipping its own sunshine.log/Tailscale disconnect checks - those answer "did the old session end," not "does the user still want tablet mode," and would otherwise clobber a deliberate toggle off stale data.
- See that file's own comments (`MANUAL OVERRIDE`) for the full reasoning.

## Why ToggleTabletDisplayMode() has three keybinds

`BasicTasks.ahk` binds `Win+Shift+P`, `Ctrl+Shift+P`, and `Win+Alt+P` to the same `ToggleTabletDisplayMode()` call. This isn't redundancy for its own sake - it's the result of researching whether any of them could be triggered remotely from the Galaxy Tab S10 Ultra during a Moonlight session, so the display could be toggled without walking over to the PC.

- Android intercepts recognized modifier-key combos (Alt+Tab, the Windows key, Ctrl+S, etc.) at the OS level before any app - Moonlight included - ever sees them, redirecting to Android's own system actions instead. This is a documented, still-open limitation in Moonlight Android (see its GitHub issues #840 and #975), not something fixable from this repo's side.
- This applies to both a physical/case Bluetooth keyboard and the tablet's own on-screen Samsung Keyboard - the latter's own Ctrl+A/Ctrl+C-style "shortcuts" are local Android text-editing actions, not genuine key events that would traverse to a remote session at all.
- Settings > General Management > Physical Keyboard > Keyboard Shortcuts on the tablet only affects an attached physical keyboard, not the on-screen one, and doesn't fix this either way.
- All three keybinds are confirmed manual, PC-side-only options as a result - none of them are expected to work when sent from the tablet. The confirmed-working remote path is touching the PC's tray items (Toggle Display Mode, Duplicate Only, under `BasicTasks.ahk`'s tray submenu) directly through the Moonlight stream, since that involves no keyboard at all.
