#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Functions shared across scripts - see ARCHITECTURE.md
#SingleInstance force
DetectHiddenWindows, On

; =============================================================================
; WSL EXT4 BACKUP SSD - MOUNT, UNMOUNT, AUTO-MOUNT, SAFE EJECT
;
; Everything related to the ext4 backup SSD lives in this one script: the manual Win+Alt+M/U hotkeys, the auto-mount-on-plug watcher, the wake-from-sleep remount check, the tray menu items, and the Windows "Problem Ejecting" dialog auto-resolver.
; Previously split across BasicTasks.ahk (hotkeys) and BackgroundAutomations.ahk (everything else) purely because both needed the same mount/unmount logic - not because this is a cross-cutting utility like the debounce pattern or the badge system (those are genuinely shared across unrelated features).
; Consolidated here to match the single-feature-script convention already used by Brightness.ahk/ClosePrograms.ahk.
;
; MountExt4Ssd()/UnmountExt4Ssd() are defined directly below in this file - the two divergences between the old BasicTasks.ahk/BackgroundAutomations.ahk copies (debounce thresholds, the showFeedback parameter) were already reconciled when they were briefly staged in SharedHelpers.ahk; see the comment above each function for that history.
; SharedHelpers.ahk still supplies RunSilentPowerShell()/ShowTimedToolTip() (generic infrastructure) via the #Include below.
; =============================================================================

; Auto-mount & Watchdog for ext4 Backup SSD
OnMessage(0x0219, "WM_DEVICECHANGE_SSD")
SetTimer, ReconcileExt4SsdState, 5000
SetTimer, ReconcileExt4SsdState, -500 ; Fast initial check on boot/reload
SetTimer, AutoResolveEjectConflict, 400 ; Auto-intercept Windows 'Problem Ejecting' dialog
global g_Ext4SsdMounted := false

; Independent WM_POWERBROADCAST listener for wake-from-sleep remount checks.
; Windows broadcasts this to every listener, not just one - BackgroundAutomations.ahk has its own separate listener for Sefirah's reconnect logic; no cross-process signaling is needed for two scripts to each react to the same system event.
OnMessage(0x0218, "SsdManager_WM_POWERBROADCAST")

; System Tray menu integration for Pixel SSD
Menu, Tray, Add
Menu, Tray, Add, Mount Pixel SSD (P:), TrayMountPixelSsd
Menu, Tray, Add, Eject Pixel SSD Safely, TrayEjectPixelSsd
Menu, Tray, Add, Register Zero-UAC Tasks, TrayRegisterAdminTasks

; Publish the 3 custom items above so StartupScript.ahk's master submenu can mirror them generically (it just reads this file -- no item names/IDs hardcoded on that side).
; If the Menu,Add lines above ever change, update this list to match; nothing else needs touching.
; (see SharedHelpers.ahk - this also registers the shared HandleRemoteTrayMenuTrigger)
PublishTrayMenuManifest([["Mount Pixel SSD (P:)", "TrayMountPixelSsd"], ["Eject Pixel SSD Safely", "TrayEjectPixelSsd"], ["Register Zero-UAC Tasks", "TrayRegisterAdminTasks"]])
return ; End of auto-execute section

; -----------------------------------------------------------------------------
; WSL EXT4 BACKUP SSD - mount / unmount
; -----------------------------------------------------------------------------
; Previously duplicated in BasicTasks.ahk (manual hotkey path) and BackgroundAutomations.ahk (auto-mount-on-plug watcher) with two real divergences, both reconciled here rather than just picked arbitrarily:
;   - debounce thresholds differed per operation (looked like accidental drift, not intentional design).
;     The LARGER of each pair is kept, since a longer cooldown is strictly safer against a double-trigger race than a marginally snappier response is worth.
;   - the manual path showed a tooltip on manual mount, the silent auto-mount-on-plug path never did (a real, intentional behavioral fork, documented at its own call site as "100% silently in background").
;     showFeedback is its own independent parameter (mirroring how UnmountExt4Ssd already had one), decoupled from openExplorer, so each caller states its own intent explicitly and neither existing caller's behavior changes.
MountExt4Ssd(openExplorer := false, showFeedback := false) {
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
    if (now - lastMountTick < 6000)
        return
    lastMountTick := now
    g_Ext4SsdMounted := true

    psScript := A_ScriptDir "\PowerShell\mount_wsl_ssd.ps1"
    if !FileExist(psScript)
        return
    args := openExplorer ? "-OpenExplorer" : ""
    ; Run 100% silent with CREATE_NO_WINDOW to prevent conhost window flashing and focus theft
    RunSilentPowerShell(psScript, args)

    if (showFeedback) {
        label := EXT4_SSD_LABEL ? EXT4_SSD_LABEL : "Linux Backup SSD"
        ShowTimedToolTip("Opening " label "...", 1500)
    }
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
    ; Run 100% silent with CREATE_NO_WINDOW to prevent conhost window flashing and focus theft
    RunSilentPowerShell(psScript, args)

    if (showFeedback) {
        label := EXT4_SSD_LABEL ? EXT4_SSD_LABEL : "Linux Backup SSD"
        ShowTimedToolTip(label " is now safe to unplug.", 2500)
    }
}

; wParam 18 (0x12) = PBT_APMRESUMEAUTOMATIC (any system wake, incl. Modern Standby)
; wParam  7 (0x07) = PBT_APMRESUMESUSPEND    (user-initiated resume after suspend)
SsdManager_WM_POWERBROADCAST(wParam, lParam) {
    if (wParam = 18 || wParam = 7)
        SetTimer, ResumeExt4SsdOnWake, -4500 ; check/restore ext4 SSD mount 4.5s after wake
}

ResumeExt4SsdOnWake:
    MountExt4Ssd(false) ; Silent reconnect check after laptop sleep/wake
return

; [START: WSL ext4 Backup SSD Management Hotkeys]
; Manual hotkeys for mounting and unmounting the ext4 backup SSD
; Unattended background auto-mount on boot/plug is handled below in this same script.
; Hotkeys:
;   Win+Alt+M -> Mount ext4 SSD & Open in Explorer
;   Win+Alt+U -> Unmount ext4 SSD safely

#!m::MountExt4Ssd(true, true) ; Win+Alt+M -> Manual Mount & Open (openExplorer + tooltip feedback)
#!u::UnmountExt4Ssd(true)     ; Win+Alt+U -> Manual Unmount (tooltip feedback)
; [END: WSL ext4 Backup SSD Management Hotkeys]

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
        ; Physical presence: hardware plugged in CRITICAL: NEVER call FileExist() or any file I/O on a network path (P:\...) directly from the main AHK thread!
        ; If the network connection was severed or stalled, the Windows kernel SMB redirector (mrxsmb.sys) blocks the thread for up to 60 seconds waiting for timeout, completely freezing AutoHotkey!
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
        return false ; Not configured in LocalPaths.ahk
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

TrayMountPixelSsd:
    MountExt4Ssd(true)
return

TrayEjectPixelSsd:
    UnmountExt4Ssd(true, false)
return

; Auto-intercept Windows 'Problem Ejecting USB Attached SCSI (UAS) Mass Storage Device' dialog.
; When the user clicks Windows 'Safely Remove Hardware' on the taskbar while WSL has the drive open, Windows displays this #32770 dialog.
; This watcher catches the dialog within 400ms, closes it immediately, and runs our clean unmount + hardware safe ejection pipeline so the user is never stuck with the error!
AutoResolveEjectConflict:
    if WinExist("Problem Ejecting ahk_class #32770") {
        WinGetTitle, eTitle, Problem Ejecting ahk_class #32770
        if (InStr(eTitle, "USB Attached SCSI") || InStr(eTitle, "Mass Storage")) {
            WinClose, Problem Ejecting ahk_class #32770
            label := EXT4_SSD_LABEL ? EXT4_SSD_LABEL : "Linux Backup SSD"
            ShowTimedToolTip(label " in use by WSL. Safely unmounting and ejecting...", 4500)
            UnmountExt4Ssd(false, false)
        }
    }
return

TrayRegisterAdminTasks:
    batScript := A_ScriptDir "\PowerShell\Install_WSL_Mount_Tasks.bat"
    Run, *RunAs "%batScript%"
return
; [END: WSL ext4 Backup SSD Auto-Mount]
