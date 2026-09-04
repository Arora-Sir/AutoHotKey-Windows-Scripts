#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\local_paths.ahk ; Include local custom paths if present (ignored by Git)
#SingleInstance force
DetectHiddenWindows, On

; Auto-mount & Watchdog for ext4 Backup SSD (Registered first for immediate responsiveness)
OnMessage(0x0219, "WM_DEVICECHANGE_SSD")
SetTimer, ReconcileExt4SsdState, 5000
SetTimer, ReconcileExt4SsdState, -500 ; Fast initial check on boot/reload
SetTimer, AutoResolveEjectConflict, 400 ; Auto-intercept Windows 'Problem Ejecting' dialog
global g_Ext4SsdMounted := false

; System Tray menu integration for Pixel SSD
Menu, Tray, Add
Menu, Tray, Add, Mount Pixel SSD (P:), TrayMountPixelSsd
Menu, Tray, Add, Eject Pixel SSD Safely, TrayEjectPixelSsd
Menu, Tray, Add, Register Zero-UAC Tasks, TrayRegisterAdminTasks

; Always-on background automation with no hotkey trigger: things that should just be running, not things a keypress does. BasicTasks.ahk stays hotkey-only;
; everything here starts at boot (via StartupScript.ahk) and keeps running unattended for the rest of the session.
;
; OVERVIEW (detail lives in each section below):
;   Tailscale                - launches its tray app in the same startup burst as the other scripts, skips it if already running
;   Google Drive             - launches it silently (--startup_mode), independent of Task Manager's Startup Apps toggle
;   GravityBridge / CopyClip - launches both Python servers under renamed pythonw.exe copies; ForceRestart=true here so an edited .py picks up on boot/reload
;   Sefirah                  - reconnects after sleep/wake and keeps SEFIRAH_PRIORITY_TARGET as the active device whenever it's reachable
;   WSL ext4 Backup SSD      - auto-mounts ext4 SSD on boot and on USB plug (DBT_DEVICEARRIVAL), cleans up on unplug

; Auto-start Tailscale's tray app in the same burst as the other scripts, deterministically, instead of racing 14+ other Startup-folder apps through Explorer with no ordering guarantee.
; tailscaled itself (the actual VPN backend CopyClip depends on) is a Windows service and starts independently of this either way, this only affects how soon the tray icon shows up. Guarded so a plain AHK reload doesn't relaunch an already-running copy.
TailscaleExe := "C:\Program Files\Tailscale\tailscale-ipn.exe"
Process, Exist, tailscale-ipn.exe
if (!ErrorLevel && FileExist(TailscaleExe))
    Run, %TailscaleExe%

; Auto-start Google Drive in the same burst, silently. Its own native Run-key entry keeps
; getting toggled off in Task Manager's Startup Apps behind our backs (found disabled twice
; now), so this no longer depends on that staying on. GoogleDrivePath (local_paths.ahk) is
; the exact same registry-resolved, --startup_mode-flagged command the Run key itself uses,
; self-healing against Drive version bumps -- launching it here just stops relying on a
; Windows toggle that doesn't reliably stay where we leave it. Guarded the same way as
; Tailscale above, so a plain AHK reload doesn't relaunch an already-running copy.
Process, Exist, GoogleDriveFS.exe
if (!ErrorLevel && GoogleDrivePath)
    Run, %GoogleDrivePath%

; Auto-start / reload GravityBridge Proxy Server & CopyClip. Named per-project so Task Manager's Name column shows "CopyClip_Python.exe" / "GravityBridge_Python.exe" instead of an anonymous "pythonw.exe" you can't tell apart.
; ForceRestart=true here on purpose: this call only runs at boot or when you hit the global reload hotkey, both are moments you'd want an edited proxy.py/copyclip.py picked up, so it always kills and relaunches rather than skipping an already-healthy instance.
RestartNamedPythonServer("GravityBridge", PATH_GRAVITY_BRIDGE "\proxy.py",,, true)
RestartNamedPythonServer("CopyClip", PATH_COPYCLIP "\windows_app\tray.py",,, true) ; Can also use "Safirah"

; =============================================================================
; SEFIRAH - Phone Link Alternative (Sleep Auto-Reconnect + Phone Priority)
; [START: Sefirah WM_POWERBROADCAST hook + priority poll]
;
; On Windows wake-from-sleep, Sefirah's TCP socket on port 5150 is killed by the OS and the Android client does not auto-reconnect. This block registers a Win32 WM_POWERBROADCAST (0x0218) listener that fires a one-shot timer 4 seconds after wake, then sends a foreground-service CONNECT intent via ADB to every device listed in SEFIRAH_ADB_TARGETS (defined in local_paths.ahk, never hardcoded).
;
; Sefirah itself has no concept of a "preferred device" (checked upstream, in NetworkService.cs): ActiveDevice is set unconditionally on every successful (re)authentication, so whichever device most recently finished authenticating simply becomes active, silently overwriting whatever was selected before.
; That means the phone can only "win" by being the LAST one to (re)authenticate, not by any setting, so both the wake hook and the poll below always reconnect SEFIRAH_PRIORITY_TARGET last / on its own, deliberately. The poll also hands ActiveDevice to whatever else is reachable in SEFIRAH_ADB_TARGETS the moment the priority target drops, so it doesn't sit "Selected" but unreachable indefinitely.
;
; Pairs with the CopyClip Python server which handles clipboard / notification sync. Together they replace Microsoft Phone Link on this machine.
;
; Dependencies (all from local_paths.ahk):
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
return ; End of auto-execute section

; WM_POWERBROADCAST handler - must stay lightweight; called on the AHK message pump.
;   wParam 18 (0x12) = PBT_APMRESUMEAUTOMATIC  (any system wake, incl. Modern Standby)
;   wParam  7 (0x07) = PBT_APMRESUMESUSPEND    (user-initiated resume after suspend)
Sefirah_WM_POWERBROADCAST(wParam, lParam) {
    if (wParam = 18 || wParam = 7) {
        SetTimer, Sefirah_DoReconnect, -4000      ; one-shot, 4s after wake
        SetTimer, ResumeExt4SsdOnWake, -4500     ; check/restore ext4 SSD mount 4.5s after wake
    }
}

ResumeExt4SsdOnWake:
    MountExt4Ssd(false) ; Silent reconnect check after laptop sleep/wake
return

; Fires once, ~4 s after wake. Reconnects every non-priority target first (order doesn't matter, fire-and-forget), then the priority target last and BLOCKING so it is guaranteed to be the last one to finish authenticating, that's what wins it ActiveDevice.
; Do not "simplify" this back into one parallel loop; the ordering is the entire point (see the block comment above).
Sefirah_DoReconnect() {
    global PATH_ADB_EXE, SEFIRAH_ADB_TARGETS, SEFIRAH_PRIORITY_TARGET

    ; Guard: bail silently when local_paths.ahk is absent or variables not set
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

; Cheap reachability probe for one target. Reuses the same "connect, then run a second adb command" skeleton as the CONNECT intent below, but chained with `get-state` instead, its exit code (propagated through cmd's && chain into ErrorLevel) is 0 iff the target is actually connected, which is a more reliable signal across adb versions than matching on adb connect's own printed text.
Sefirah_IsReachable(target) {
    global PATH_ADB_EXE
    if (!PATH_ADB_EXE || !target)
        return false
    RunWait, %ComSpec% /c ""%PATH_ADB_EXE%" connect %target% && "%PATH_ADB_EXE%" -s %target% get-state",, Hide
    return (ErrorLevel = 0)
}

; Fires the foreground-service CONNECT intent alone, this is what Sefirah's NetworkService treats as a fresh authentication, and therefore an ActiveDevice claim.
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
; Sequential/blocking like the priority claim above, for the common two-device case there's only one candidate, but this stays correct if a third device is ever added to SEFIRAH_ADB_TARGETS.
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

; =============================================================================
; WSL EXT4 BACKUP SSD AUTO-MOUNT & MANAGEMENT
; [START: WSL ext4 Backup SSD Auto-Mount]
;
; Automates mounting and unmounting of the ext4 backup SSD
;   - Auto-mounts on boot / AHK reload if the SSD is already connected
;   - Auto-mounts when plugged in (DBT_DEVICEARRIVAL 0x8000 via WM_DEVICECHANGE)
;   - Cleans up shortcut and unmounts on unplug (DBT_DEVICEREMOVECOMPLETE 0x8004)
;   - Two-tier recovery: mounts attached VM block device as guest root, or elevates wsl --mount
;   - Resolves PhysicalDrive number dynamically and creates Network Shortcut
; =============================================================================

WM_DEVICECHANGE_SSD(wParam, lParam, msg, hwnd) {
    ; Intercept DBT_DEVNODES_CHANGED (0x0007), DBT_DEVICEARRIVAL (0x8000), DBT_DEVICEREMOVECOMPLETE (0x8004)
    if (wParam = 0x0007 || wParam = 0x8000 || wParam = 0x8004) {
        ; Reconcile state after brief bus enumeration delay
        SetTimer, ReconcileExt4SsdState, -1000
    }
    return true
}

ReconcileExt4SsdState:
    connected := IsPixelSsdConnected()
    ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
    isManuallyEjected := FileExist(ejectedFlag)

    driveLetter := EXT4_SSD_DRIVE_LETTER ? EXT4_SSD_DRIVE_LETTER : "P:"
    targetDrive := SubStr(driveLetter, 1, 1) ":"
    DriveGet, pType, Type, %targetDrive%
    isDriveMapped := (pType = "Network")

    if (!connected) {
        ; Physical absence: hardware removed
        if (isManuallyEjected)
            FileDelete, %ejectedFlag%
        if (isDriveMapped || g_Ext4SsdMounted) {
            g_Ext4SsdMounted := false
            UnmountExt4Ssd(false, true)
        }
    }
    else {
        ; Physical presence: hardware plugged in
        ; CRITICAL: NEVER call FileExist() or any file I/O on a network path (P:\...) directly
        ; from the main AHK thread! If the network connection was severed or stalled, the Windows
        ; kernel SMB redirector (mrxsmb.sys) blocks the thread for up to 60 seconds waiting for
        ; timeout, completely freezing AutoHotkey!
        ; Drive mapping state is queried non-blockingly via DriveGet above.
        if (!isDriveMapped && !isManuallyEjected) {
            g_Ext4SsdMounted := true
            MountExt4Ssd(true) ; Runs 100% silently in background, opens Explorer only when fully finished
        }
        else if (isDriveMapped) {
            g_Ext4SsdMounted := true
        }
    }
return

IsPixelSsdConnected() {
    global EXT4_SSD_MODEL_SUBSTRINGS
    filter := EXT4_SSD_MODEL_SUBSTRINGS
    if (!filter)
        return false ; Not configured in local_paths.ahk
    try {
        for disk in ComObjGet("winmgmts:").ExecQuery("SELECT Model FROM Win32_DiskDrive") {
            m := disk.Model
            Loop, Parse, filter, `,
            {
                sub := Trim(A_LoopField)
                if (sub != "" && InStr(m, sub))
                    return true
            }
        }
    }
    return false
}

MountExt4Ssd(openExplorer := false) {
    global g_Ext4SsdMounted, EXT4_SSD_LABEL
    ; Guard: do not spawn if mount or unmount is actively in progress
    if FileExist(A_Temp "\mount_wsl_ssd.lock") || FileExist(A_Temp "\unmount_wsl_ssd.lock")
        return

    ; Clear manual ejection flag so state reconciler tracks active drive
    ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
    if FileExist(ejectedFlag)
        FileDelete, %ejectedFlag%

    static lastMountTick := 0
    now := A_TickCount
    if (now - lastMountTick < 5000)
        return
    lastMountTick := now
    g_Ext4SsdMounted := true

    psScript := A_ScriptDir "\PowerShell\mount_wsl_ssd.ps1"
    if !FileExist(psScript)
        return
    args := openExplorer ? "-OpenExplorer" : ""
    ; Run 100% silent with CREATE_NO_WINDOW via WScript.Shell to prevent conhost window flashing and focus theft
    RunSilentPowerShell(psScript, args)
}

UnmountExt4Ssd(showFeedback := false, onlyIfDisconnected := false) {
    global g_Ext4SsdMounted, EXT4_SSD_LABEL
    ; Guard: do not spawn if unmount is actively in progress
    if FileExist(A_Temp "\unmount_wsl_ssd.lock")
        return

    ; If manual unmount while SSD is still plugged in, set flag to prevent watchdog re-mount
    if (!onlyIfDisconnected) {
        ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
        FileDelete, %ejectedFlag%
        FileAppend, %A_Now%, %ejectedFlag%
    }

    static lastUnmountTick := 0
    now := A_TickCount
    if (now - lastUnmountTick < 6000)
        return
    lastUnmountTick := now
    g_Ext4SsdMounted := false

    psScript := A_ScriptDir "\PowerShell\unmount_wsl_ssd.ps1"
    if !FileExist(psScript)
        return
    args := onlyIfDisconnected ? "-OnlyIfDisconnected" : ""
    ; Run 100% silent with CREATE_NO_WINDOW via WScript.Shell to prevent conhost window flashing and focus theft
    RunSilentPowerShell(psScript, args)

    if (showFeedback) {
        label := EXT4_SSD_LABEL ? EXT4_SSD_LABEL : "Linux Backup SSD"
        ToolTip, % label " is now safe to unplug."
        SetTimer, RemoveSsdToolTip, -2500
    }
}

RunSilentPowerShell(scriptPath, args := "") {
    runSilentExe := A_ScriptDir "\PowerShell\run_silent.exe"
    if FileExist(runSilentExe) {
        cmd := """" runSilentExe """ powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ scriptPath """" (args != "" ? " " args : "")
        Run, %cmd%,, Hide
        return true
    }
    cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ scriptPath """" (args != "" ? " " args : "")
    try {
        shell := ComObjCreate("WScript.Shell")
        shell.Run(cmd, 0, false)
        return true
    } catch {
        Run, %cmd%,, Hide
        return false
    }
}

RemoveSsdToolTip:
    ToolTip
return

TrayMountPixelSsd:
    MountExt4Ssd(true)
return

TrayEjectPixelSsd:
    UnmountExt4Ssd(true, false)
return

; Auto-intercept Windows 'Problem Ejecting USB Attached SCSI (UAS) Mass Storage Device' dialog.
; When the user clicks Windows 'Safely Remove Hardware' on the taskbar while WSL has the drive open,
; Windows displays this #32770 dialog. This watcher catches the dialog within 400ms, closes it immediately,
; and runs our clean unmount + hardware safe ejection pipeline so the user is never stuck with the error!
AutoResolveEjectConflict:
    if WinExist("Problem Ejecting ahk_class #32770") {
        WinGetTitle, eTitle, Problem Ejecting ahk_class #32770
        if (InStr(eTitle, "USB Attached SCSI") || InStr(eTitle, "Mass Storage")) {
            WinClose, Problem Ejecting ahk_class #32770
            label := EXT4_SSD_LABEL ? EXT4_SSD_LABEL : "Linux Backup SSD"
            ToolTip, % label " in use by WSL. Safely unmounting and ejecting..."
            SetTimer, RemoveSsdToolTip, -4500
            UnmountExt4Ssd(false, false)
        }
    }
return

TrayRegisterAdminTasks:
    batScript := A_ScriptDir "\PowerShell\Install_WSL_Mount_Tasks.bat"
    Run, *RunAs "%batScript%"
return
; [END: WSL ext4 Backup SSD Auto-Mount]

; =============================================================================
; PYTHON SERVER LAUNCH HELPER
;
; Launches a Python script under a per-project renamed copy of pythonw.exe, so Task Manager's Name column shows e.g. "CopyClip_Python.exe" instead of an anonymous "pythonw.exe" indistinguishable from every other Python process on the machine.
;
; Verified before wiring this in: a bare copy of pythonw.exe, renamed and placed in an arbitrary directory (no DLLs alongside it), runs correctly, this Python install resolves its interpreter DLL and stdlib via PATH/registry, not relative to the exe's own location, so the renamed copy does not need to live next to python3XX.dll.
;
; The copy is cached under AllScripts\PythonExes\ and only made once; it is not auto-refreshed on a Python upgrade. Delete that folder (or a project's one *_Python.exe) to force a fresh copy on the next call.
;
; Self-guards against redundant restarts (see the WMI check below), which is also what makes it safe to reuse from Watchdog.ahk's WATCHDOG_APPS for mid-session crash recovery, not just this file's one-shot boot-time calls above.
;
; ForceRestart (default false) skips that self-guard and always kills+relaunches, even if a single healthy instance is already running. The boot/reload calls above pass true, since that's exactly when you want an edited .py file picked up; leave it false anywhere else, a mid-session caller has no reason to disrupt an already-healthy server.
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

    ; Skip the kill+relaunch entirely when a single, correctly-named instance is already running and no stray/duplicate process exists. Killing and relaunching an already-healthy daemon here serves no purpose except interrupting it, for CopyClip specifically, that resets its in-memory "have I seen this device before" state and makes it silently drop the next clip as an unsynced baseline instead of syncing it (see bugs/ in the CopyClip repo, restart-drops-baseline).
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
    ;   1. Name = the renamed exe, catches a previous run under this same named scheme.
    ;   2. A generic 'python%' process whose CommandLine names this exact script file, catches anything still running under the OLD generic pythonw.exe name (this migration's own leftover), and any other way this script might get launched (Desktop shortcut, a bare "python script.py", etc., see bugs/BUG-003 in the CopyClip repo for why relying on only one launch path here is exactly how a duplicate daemon slips in). Rule 1 alone would miss anything not already launched by this function, which is precisely the gap that let a stray old pythonw.exe survive a reload during testing and run alongside the new one.
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
