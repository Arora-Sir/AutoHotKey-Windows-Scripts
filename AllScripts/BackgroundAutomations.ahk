#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
EnvGet, UserProfile, USERPROFILE ; Get Windows UserProfile directory (AHK v1 compatibility)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Functions shared across scripts - see ARCHITECTURE.md
#SingleInstance force
DetectHiddenWindows, On

; Always-on background automation with no hotkey trigger: things that should just be running, not things a keypress does.
; BasicTasks.ahk stays hotkey-only; everything here starts at boot (via StartupScript.ahk) and keeps running unattended for the rest of the session.
;
; OVERVIEW (detail lives in each section below):
;   Tailscale                - launches its tray app in the same startup burst as the other scripts, skips it if already running
;   Google Drive             - launches it silently (--startup_mode), independent of Task Manager's Startup Apps toggle
;   GravityBridge / CopyClip - launches both Python servers under renamed pythonw.exe copies; ForceRestart=true here so an edited .py picks up on boot/reload
;   Sefirah                  - reconnects after sleep/wake and keeps SEFIRAH_PRIORITY_TARGET as the active device whenever it's reachable
;   (WSL ext4 Backup SSD auto-mount/eject now lives entirely in AllScripts/Ext4SsdManager.ahk)

; Auto-start Tailscale's tray app in the same burst as the other scripts, deterministically, instead of racing 14+ other Startup-folder apps through Explorer with no ordering guarantee.
; tailscaled itself (the actual VPN backend CopyClip depends on) is a Windows service and starts independently of this either way - this only affects how soon the tray icon shows up.
; Guarded so a plain AHK reload doesn't relaunch an already-running copy.
Process, Exist, tailscale-ipn.exe
if (!ErrorLevel && PATH_TAILSCALE_IPN_EXE && FileExist(PATH_TAILSCALE_IPN_EXE))
    Run, %PATH_TAILSCALE_IPN_EXE%

; Auto-start Google Drive in the same burst, silently.
; Its own native Run-key entry keeps getting toggled off in Task Manager's Startup Apps behind our backs (found disabled twice now), so this no longer depends on that staying on.
; GoogleDrivePath (LocalPaths.ahk) is the exact same registry-resolved, --startup_mode-flagged command the Run key itself uses, self-healing against Drive version bumps: launching it here just stops relying on a Windows toggle that doesn't reliably stay where we leave it.
; Guarded the same way as Tailscale above, so a plain AHK reload doesn't relaunch an already-running copy.
Process, Exist, GoogleDriveFS.exe
if (!ErrorLevel && GoogleDrivePath)
    Run, %GoogleDrivePath%,, Hide

; Auto-start / reload GravityBridge Proxy Server & CopyClip.
; Named per-project so Task Manager's Name column shows "CopyClip_Python.exe" / "GravityBridge_Python.exe" instead of an anonymous "pythonw.exe" you can't tell apart.
; ForceRestart=true here on purpose: this call only runs at boot or when you hit the global reload hotkey, both are moments you'd want an edited proxy.py/copyclip.py picked up, so it always kills and relaunches rather than skipping an already-healthy instance.
RestartNamedPythonServer("GravityBridge", PATH_GRAVITY_BRIDGE "\proxy.py",,, true)
RestartNamedPythonServer("CopyClip", PATH_COPYCLIP "\windows_app\tray.py",,, true) ; Can also use "Safirah"

; =============================================================================
; SEFIRAH - Phone Link Alternative (Sleep Auto-Reconnect + Phone Priority)
; [START: Sefirah WM_POWERBROADCAST hook + priority poll]
;
; On Windows wake-from-sleep, Sefirah's TCP socket on port 5150 is killed by the OS and the Android client does not auto-reconnect.
; This block registers a Win32 WM_POWERBROADCAST (0x0218) listener that fires a one-shot timer 4 seconds after wake, then sends a foreground-service CONNECT intent via ADB to every device listed in SEFIRAH_ADB_TARGETS (defined in LocalPaths.ahk, never hardcoded).
;
; Sefirah itself has no concept of a "preferred device" (checked upstream, in NetworkService.cs): ActiveDevice is set unconditionally on every successful (re)authentication, so whichever device most recently finished authenticating simply becomes active, silently overwriting whatever was selected before.
; That means the phone can only "win" by being the LAST one to (re)authenticate, not by any setting, so both the wake hook and the poll below always reconnect SEFIRAH_PRIORITY_TARGET last / on its own, deliberately.
; The poll also hands ActiveDevice to whatever else is reachable in SEFIRAH_ADB_TARGETS the moment the priority target drops, so it doesn't sit "Selected" but unreachable indefinitely.
;
; Pairs with the CopyClip Python server which handles clipboard / notification sync.
; Together they replace Microsoft Phone Link on this machine.
;
; Dependencies (all from LocalPaths.ahk):
;   PATH_ADB_EXE             - full path to adb.exe
;   SEFIRAH_ADB_TARGETS      - space-separated "ip:port" list of every Android target
;   SEFIRAH_PRIORITY_TARGET  - the one "ip:port" that should win ActiveDevice whenever reachable
; =============================================================================

OnMessage(0x0218, "Sefirah_WM_POWERBROADCAST")

; Independent of laptop sleep/wake: catches the priority device (phone) reconnecting for any other reason (e.g. it left/rejoined Wi-Fi on its own, with the laptop never sleeping at all).
; Edge-triggered on the unreachable -> reachable transition only, so steady state costs two quick local `adb` calls per tick (one RunWait, see Sefirah_IsReachable) and nothing more: no busy loop (SetTimer is the same native, ~0%-idle-CPU mechanism Watchdog.ahk already uses at a 10s interval), no repeated re-authentication churn while nothing has changed.
; Also handles the reverse edge: the moment the priority target drops, hand ActiveDevice to whatever else is still reachable in SEFIRAH_ADB_TARGETS, so it doesn't sit "Selected" but unreachable.
SefirahPriorityWasReachable := false
SetTimer, Sefirah_PollPriorityTarget, 30000

; Skills Vault Auto-Focus Watcher
; claude.exe focus -> lock personal vaults (org safe); Antigravity.exe focus -> unlock. All other apps leave vault state unchanged. Silent: no popup, no console window.
; Debounce: app must appear on two consecutive 1500ms ticks (~3s) before PS1 fires.
; Dedup: skips if the same app was already the last to trigger (state-transition only).
; Seeded at load time by probing the physical NTFS state so reloads don't trigger spurious transitions.
global g_SkillsLastTriggered := IsSkillsVaultUnlocked() ? "antigravity" : "claude"
global g_SkillsCandidate     := ""   ; debounce accumulator
; Flip to false to go back to a fully silent watcher (no popup, no console window) - the only thing WatchSkillsLock checks before showing/hiding its applying badge.
global g_SkillsAutoWatcherShowBadge := true
if (PATH_SKILLS_LOCK_SCRIPT && PATH_SKILLS_UNLOCK_SCRIPT)
    SetTimer, WatchSkillsLock, 1500
return ; End of auto-execute section

; WM_POWERBROADCAST handler - must stay lightweight; called on the AHK message pump.
;   wParam 18 (0x12) = PBT_APMRESUMEAUTOMATIC  (any system wake, incl. Modern Standby)
;   wParam  7 (0x07) = PBT_APMRESUMESUSPEND    (user-initiated resume after suspend)
Sefirah_WM_POWERBROADCAST(wParam, lParam) {
    if (wParam = 18 || wParam = 7)
        SetTimer, Sefirah_DoReconnect, -4000      ; one-shot, 4s after wake
}

; Fires once, ~4s after wake.
; Reconnects every non-priority target first (order doesn't matter, fire-and-forget), then the priority target last and BLOCKING so it is guaranteed to be the last one to finish authenticating - that's what wins it ActiveDevice.
; Do not "simplify" this back into one parallel loop; the ordering is the entire point (see the block comment above).
Sefirah_DoReconnect() {
    global PATH_ADB_EXE, SEFIRAH_ADB_TARGETS, SEFIRAH_PRIORITY_TARGET

    ; Guard: bail silently when LocalPaths.ahk is absent or variables not set
    if (!PATH_ADB_EXE || !SEFIRAH_ADB_TARGETS)
        return

    ; %A_Space% is the correct AHK v1 delimiter token for Loop Parse
    Loop, Parse, SEFIRAH_ADB_TARGETS, %A_Space%
    {
        target := Trim(A_LoopField)
        if (target = "" || target = SEFIRAH_PRIORITY_TARGET)
            continue
        if Sefirah_IsReachable(target)
            Sefirah_ClaimActive(target, false)
    }

    if (SEFIRAH_PRIORITY_TARGET != "" && Sefirah_IsReachable(SEFIRAH_PRIORITY_TARGET))
        Sefirah_ClaimActive(SEFIRAH_PRIORITY_TARGET, true)
}

; Cheap reachability probe for one target.
; Reuses the same "connect, then run a second adb command" skeleton as the CONNECT intent below, but chained with `get-state` instead.
; Its exit code (propagated through cmd's && chain into ErrorLevel) is 0 iff the target is actually connected, which is a more reliable signal across adb versions than matching on adb connect's own printed text.
Sefirah_IsReachable(target) {
    global PATH_ADB_EXE
    if (!PATH_ADB_EXE || !target)
        return false
    RunWait, %ComSpec% /c ""%PATH_ADB_EXE%" connect %target% && "%PATH_ADB_EXE%" -s %target% get-state",, Hide
    return (ErrorLevel = 0)
}

; Fires the foreground-service CONNECT intent alone - this is what Sefirah's NetworkService treats as a fresh authentication, and therefore an ActiveDevice claim.
; wait=true blocks until it completes (used when this must finish last); wait=false is fire-and-forget (used for targets where order doesn't matter).
Sefirah_ClaimActive(target, wait) {
    global PATH_ADB_EXE
    if (wait)
        RunWait, %ComSpec% /c ""%PATH_ADB_EXE%" -s %target% shell am start-foreground-service -a CONNECT -n com.castle.sefirah/sefirah.network.NetworkService",, Hide
    else
        Run, %ComSpec% /c ""%PATH_ADB_EXE%" -s %target% shell am start-foreground-service -a CONNECT -n com.castle.sefirah/sefirah.network.NetworkService",, Hide
}

; Independent of laptop sleep/wake: catches the priority device (phone) reconnecting for any other reason (e.g. it left/rejoined Wi-Fi on its own, with the laptop never sleeping at all).
; Edge-triggered on the unreachable -> reachable transition only, so steady state costs two quick local `adb` calls per tick (one RunWait, see Sefirah_IsReachable) and nothing more: no busy loop (SetTimer is the same native, ~0%-idle-CPU mechanism Watchdog.ahk already uses at a 10s interval), no repeated re-authentication churn while nothing has changed.
; Also handles the reverse edge: the moment the priority target drops, hand ActiveDevice to whatever else is still reachable in SEFIRAH_ADB_TARGETS, so it doesn't sit "Selected" but unreachable.
Sefirah_PollPriorityTarget() {
    global SEFIRAH_PRIORITY_TARGET, SefirahPriorityWasReachable
    if (!SEFIRAH_PRIORITY_TARGET)
        return
    isReachable := Sefirah_IsReachable(SEFIRAH_PRIORITY_TARGET)
    if (isReachable && !SefirahPriorityWasReachable)
        Sefirah_ClaimActive(SEFIRAH_PRIORITY_TARGET, true)   ; phone back -> reclaim
    else if (!isReachable && SefirahPriorityWasReachable)
        Sefirah_ClaimFallback()                               ; phone gone -> hand to tablet
    SefirahPriorityWasReachable := isReachable
}

; Hands ActiveDevice to whichever other configured target is currently reachable, used when the priority target just dropped.
; Sequential/blocking like the priority claim above - for the common two-device case there's only one candidate, but this stays correct if a third device is ever added to SEFIRAH_ADB_TARGETS.
Sefirah_ClaimFallback() {
    global SEFIRAH_ADB_TARGETS, SEFIRAH_PRIORITY_TARGET
    Loop, Parse, SEFIRAH_ADB_TARGETS, %A_Space%
    {
        target := Trim(A_LoopField)
        if (target = "" || target = SEFIRAH_PRIORITY_TARGET)
            continue
        if Sefirah_IsReachable(target)
            Sefirah_ClaimActive(target, true)
    }
}

; [END: Sefirah WM_POWERBROADCAST hook + priority poll]

; The WSL ext4 backup SSD auto-mount/eject system (device-plug watcher, wake recheck, tray items, and the Windows "Problem Ejecting" dialog auto-resolver) now lives entirely in AllScripts/Ext4SsdManager.ahk.

; HandleRemoteTrayMenuTrigger now lives in SharedHelpers.ahk (registered automatically by PublishTrayMenuManifest near the top of this file).

; =============================================================================
; PYTHON SERVER LAUNCH HELPER
;
; Launches a Python script under a per-project renamed copy of pythonw.exe, so Task Manager's Name column shows e.g. "CopyClip_Python.exe" instead of an anonymous "pythonw.exe" indistinguishable from every other Python process on the machine.
;
; A bare copy of pythonw.exe, renamed and placed in an arbitrary directory (no DLLs alongside it), runs correctly.
; This Python install resolves its interpreter DLL and stdlib via PATH/registry, not relative to the exe's own location, so the renamed copy does not need to live next to python3XX.dll.
;
; The copy is cached under AllScripts\PythonExes\ and only made once; it is not auto-refreshed on a Python upgrade. Delete that folder (or a project's one *_Python.exe) to force a fresh copy on the next call.
;
; Self-guards against redundant restarts (see the WMI check below), which is also what makes it safe to reuse from Watchdog.ahk's WATCHDOG_APPS for mid-session crash recovery, not just this file's one-shot boot-time calls above.
;
; ForceRestart (default false) skips that self-guard and always kills+relaunches, even if a single healthy instance is already running.
; The boot/reload calls above pass true, since that's exactly when you want an edited .py file picked up; leave it false anywhere else, a mid-session caller has no reason to disrupt an already-healthy server.
; =============================================================================
RestartNamedPythonServer(ProjectName, ScriptPath, WorkingDir:="", PythonExe:="", ForceRestart:=false) {
    global PATH_PYTHON_EXE

    ScriptPath := Trim(ScriptPath, """")
    if (!ScriptPath || !FileExist(ScriptPath))
        return false

    SplitPath, ScriptPath, FileName, Directory
    if (!WorkingDir)
        WorkingDir := Directory
    if (!PythonExe)
        PythonExe := PATH_PYTHON_EXE ? PATH_PYTHON_EXE : "pythonw.exe"
    PythonExe := Trim(PythonExe, """")

    NamedExeDir := A_ScriptDir "\PythonExes"
    if !FileExist(NamedExeDir)
        FileCreateDir, %NamedExeDir%
    NamedExeName := ProjectName "_Python.exe"
    NamedExePath := NamedExeDir "\" NamedExeName
    if !FileExist(NamedExePath)
        FileCopy, %PythonExe%, %NamedExePath%

    ; Skip the kill+relaunch entirely when a single, correctly-named instance is already running and no stray/duplicate process exists.
    ; Killing and relaunching an already-healthy daemon here serves no purpose except interrupting it - for CopyClip specifically, that resets its in-memory "have I seen this device before" state and makes it silently drop the next clip as an unsynced baseline instead of syncing it (see bugs/ in the CopyClip repo, restart-drops-baseline).
    ; Restart is still correct, and happens below exactly as before, whenever this ISN'T true: nothing running yet, a stray duplicate under a different name exists, or somehow more than one correctly-named instance is running.
    NamedCount := 0, StrayCount := 0
    CountQuery := "SELECT ProcessId,Name,CommandLine FROM Win32_Process WHERE Name = '" NamedExeName "' OR Name LIKE 'python%'"
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery(CountQuery)
        {
            if (proc.Name = NamedExeName)
                NamedCount++
            else if InStr(proc.CommandLine, FileName)
                StrayCount++
        }
    }
    if (NamedCount = 1 && StrayCount = 0 && !ForceRestart)
        return true

    ; Kill any existing instance of this script, however it was launched. Two match rules, either one is enough:
    ;   1. Name = the renamed exe: catches a previous run under this same named scheme.
    ;   2. A generic 'python%' process whose CommandLine names this exact script file: catches anything still running under the OLD generic pythonw.exe name (this migration's own leftover), and any other way this script might get launched (Desktop shortcut, a bare "python script.py", etc. - see bugs/BUG-003 in the CopyClip repo for why relying on only one launch path here is exactly how a duplicate daemon slips in).
    ;   Rule 1 alone would miss anything not already launched by this function, which is precisely the gap that let a stray old pythonw.exe survive a reload during testing and run alongside the new one.
    KillQuery := "SELECT ProcessId,Name,CommandLine FROM Win32_Process WHERE Name = '" NamedExeName "' OR Name LIKE 'python%'"
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery(KillQuery)
            if (proc.Name = NamedExeName) || InStr(proc.CommandLine, FileName)
                Process, Close, % proc.ProcessId
    }
    Sleep, 200

    ; Launch silently - the renamed pythonw.exe copy never creates a console window either
    Run, "%NamedExePath%" "%ScriptPath%", %WorkingDir%, Hide
    return true
}

; =============================================================================
; [START: Skills Vault Auto-Focus Watcher]
; Fires every 1500ms via SetTimer (registered in auto-execute above).
; WinGet ProcessName is one Win32 call with no I/O - CPU cost is negligible, so on the vast majority of ticks (no transition) this returns in under a millisecond.
; On a confirmed app transition, the lock/unlock PS1 is launched BLOCKING (shell.Run flag 0=hidden, true=wait) so the cross-process mutex's held duration spans the real icacls work, not just the dispatch - this subroutine can therefore take as long as one icacls sweep (roughly hundreds of ms) on that rare tick.
; =============================================================================
WatchSkillsLock:
    global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT, PATH_PWSH_EXE, g_SkillsAutoWatcherShowBadge
    if (!PATH_SKILLS_LOCK_SCRIPT || !PATH_SKILLS_UNLOCK_SCRIPT)
        return

    ; Cross-process mutex: guards against TogglePersonalSkillsLock() (a separate OS process in BasicTasks.ahk) reading/acting on the same mode file and running the same lock/unlock scripts concurrently with this watcher - without it, both processes can launch overlapping icacls sweeps against the same folder.
    ; Fail-fast (3s) rather than the hotkey path's patient 10s - this subroutine runs inside the same single-threaded process as the other background watchers, so it should retry on the next 1500ms tick rather than stalling unrelated automations.
    hMutex := AcquireNamedMutex("SkillsVaultLock_AHK_v1", 3000)
    if (!hMutex)
        return

    ; Check if Skills Vault is in manual override mode (locked / unlocked).
    ; If forced, pause auto-watcher focus detection until user switches back to Auto.
    modeFile := A_Temp "\skills_vault_mode.flag"
    if FileExist(modeFile) {
        FileRead, curSkillsMode, %modeFile%
        curSkillsMode := Trim(curSkillsMode)
        if (curSkillsMode = "locked" || curSkillsMode = "unlocked") {
            g_SkillsCandidate := ""
            g_SkillsLastTriggered := ""
            ReleaseNamedMutex(hMutex)
            return
        }
    }

    WinGet, g_SkillsCurExe, ProcessName, A

    ; Map exe -> app token. Anything else = neutral, reset debounce and exit.
    if (g_SkillsCurExe = "claude.exe")
        newApp := "claude"
    else if (g_SkillsCurExe = "Antigravity.exe" || g_SkillsCurExe = "agy.exe" || g_SkillsCurExe = "Antigravity IDE.exe")
        newApp := "antigravity"
    else {
        g_SkillsCandidate := ""      ; reset debounce - neutral window broke the run
        ReleaseNamedMutex(hMutex)
        return
    }

    ; Debounce: must see the same app on two back-to-back ticks (~3s) before acting.
    if (g_SkillsCandidate != newApp) {
        g_SkillsCandidate := newApp  ; first sighting - just store and wait
        ReleaseNamedMutex(hMutex)
        return
    }

    ; Dedup: already triggered for this app, nothing changed - skip the PS1 entirely.
    if (g_SkillsLastTriggered = newApp) {
        ReleaseNamedMutex(hMutex)
        return
    }

    ; Physical state check: if the vault is ALREADY in the requested physical state,
    ; adopt the state silently without running the script or flashing badges.
    isUnlocked := IsSkillsVaultUnlocked()
    if (newApp = "antigravity" && isUnlocked) {
        g_SkillsLastTriggered := newApp
        g_SkillsCandidate     := ""
        ReleaseNamedMutex(hMutex)
        return
    }
    if (newApp = "claude" && !isUnlocked) {
        g_SkillsLastTriggered := newApp
        g_SkillsCandidate     := ""
        ReleaseNamedMutex(hMutex)
        return
    }

    ; Transition confirmed - update state and fire PS1 synchronously (blocking - required so the mutex hold spans the real icacls work, not just dispatch).
    g_SkillsLastTriggered := newApp
    g_SkillsCandidate     := ""

    targetScript := (newApp = "claude") ? PATH_SKILLS_LOCK_SCRIPT : PATH_SKILLS_UNLOCK_SCRIPT
    if (!FileExist(targetScript)) {
        ReleaseNamedMutex(hMutex)
        return
    }

    pwsh := (PATH_PWSH_EXE && FileExist(PATH_PWSH_EXE)) ? PATH_PWSH_EXE : "pwsh.exe"
    shell := ComObjCreate("WScript.Shell")
    ; Applying badge before the blocking call, THEN a real [LOCKED]/[UNLOCKED] confirmation afterward (via the shared ShowSkillsStatusBadge, which auto-dismisses itself after 3000ms - no explicit hide needed).
    ; Unlike the manual Win+Alt+L path, this watcher never shows an upfront "requested state" badge (it's a silent focus-change timer, not a keypress) - the applying flash is the ONLY signal the user gets before this point, so a done confirmation here is genuinely new information, not a redundant repeat the way it would be on the manual path.
    ; Gated by g_SkillsAutoWatcherShowBadge (declared above, near the other Skills Vault globals) - flip that one line to go back to a fully silent watcher instead of touching this logic again.
    if (g_SkillsAutoWatcherShowBadge)
        ShowBottomRightBadge("[APPLYING...] " (newApp = "claude" ? "Locking" : "Unlocking") " Skills Vault (Auto)", "6E5A00", 15000)
    shell.Run("""" pwsh """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ targetScript """ -Silent", 0, true)
    if (g_SkillsAutoWatcherShowBadge)
        ShowSkillsStatusBadge((newApp = "claude") ? "[LOCKED] Skills Vault (Auto)" : "[UNLOCKED] Skills Vault (Auto)")
    ReleaseNamedMutex(hMutex)
return

; AcquireSkillsVaultLock/ReleaseSkillsVaultLock now live in SharedHelpers.ahk as the generalized AcquireNamedMutex/ReleaseNamedMutex.
; [END: Skills Vault Auto-Focus Watcher]
