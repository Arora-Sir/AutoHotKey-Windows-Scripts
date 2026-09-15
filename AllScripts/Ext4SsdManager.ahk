#Requires AutoHotkey v2.0
; Suppress individual child tray icon so only StartupScript.ahk's master icon is visible.
#NoTrayIcon
; v2: #Persistent removed as a directive, replaced by the Persistent() function (see LocalPaths.ahk for the empirical note on why).
Persistent()
SendMode("Input")
SetWorkingDir(A_ScriptDir)
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Functions shared across scripts - see ARCHITECTURE.md
#SingleInstance force
DetectHiddenWindows(true)

; v2 fleet control protocol: the g_FleetControlMsg/OnMessage/HandleFleetControlMessage definition now
; lives only in SharedHelpers.ahk (included above): this file used to carry its own independent copy,
; which broke load with "function declaration conflicts with an existing Func" the moment both this
; file's SharedHelpers.ahk include and its own copy landed in the same merged script. See LocalPaths.ahk
; for the full explanation of why this consolidation was needed.

; =============================================================================
; WSL EXT4 BACKUP SSD: MOUNT, UNMOUNT, AUTO-MOUNT, SAFE EJECT
;
; Everything related to the ext4 backup SSD lives in this one script: the manual Win+Alt+M/U hotkeys, the auto-mount-on-plug watcher, the wake-from-sleep remount check, the tray menu items, and the Windows "Problem Ejecting" dialog auto-resolver.
; Consolidated here to match the single-feature-script convention already used by Brightness.ahk/ClosePrograms.ahk.
;
; MountExt4Ssd()/UnmountExt4Ssd() are defined directly below in this file.
; SharedHelpers.ahk supplies RunSilentPowerShell()/ShowBottomRightBadge() via the #Include above.
; =============================================================================

; Auto-mount & Watchdog for ext4 Backup SSD
OnMessage(0x0219, WM_DEVICECHANGE_SSD)
SetTimer(ReconcileExt4SsdState, 5000)
SetTimer(ReconcileExt4SsdState, -500) ; Fast initial check on boot/reload
SetTimer(AutoResolveEjectConflict, 400) ; Auto-intercept Windows 'Problem Ejecting' dialog

g_Ext4SsdMounted := false

; Independent WM_POWERBROADCAST listener for wake-from-sleep remount checks.
OnMessage(0x0218, SsdManager_WM_POWERBROADCAST)

; -----------------------------------------------------------------------------
; TRAY MENU INTEGRATION FOR PIXEL SSD
; Standalone tray items are managed via master submenu in StartupScript.ahk.
; -----------------------------------------------------------------------------
PublishTrayMenuManifest([ ["Mount Pixel SSD (P:)", "TrayMountPixelSsd"]
                        , ["Eject Pixel SSD Safely", "TrayEjectPixelSsd"]
                        , ["-"]
                        , ["Register Zero-UAC Tasks", "TrayRegisterAdminTasks"] ])
return ; End of auto-execute section

; -----------------------------------------------------------------------------
; WSL EXT4 BACKUP SSD: mount / unmount
; -----------------------------------------------------------------------------

IsSsdLockActive(lockPath) {
    if (!FileExist(lockPath))
        return false
    return DateDiff(A_Now, FileGetTime(lockPath), "Seconds") < 15
}

MountExt4Ssd(openExplorer := false, showFeedback := false) {
    global g_Ext4SsdMounted, EXT4_SSD_LABEL
    label := (IsSet(EXT4_SSD_LABEL) && EXT4_SSD_LABEL) ? EXT4_SSD_LABEL : "Pixel 1 Backup SSD"

    ; Guard: check if hardware is physically connected before doing any work
    if (!IsPixelSsdConnected()) {
        if (showFeedback)
            ShowBottomRightBadge(label " is not connected.", "C0392B", 3000)
        return
    }

    ; Guard: do not spawn if mount or unmount is actively in progress
    if (IsSsdLockActive(A_Temp "\mount_wsl_ssd.lock") || IsSsdLockActive(A_Temp "\unmount_wsl_ssd.lock"))
        return

    ; Clear manual ejection flag so state reconciler tracks active drive
    ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
    if FileExist(ejectedFlag)
        FileDelete(ejectedFlag)

    static lastMountTick := 0
    now := A_TickCount
    if (now - lastMountTick < 6000)
        return
    lastMountTick := now

    if (showFeedback)
        ShowBottomRightBadge("Connecting " label "...", "2471A3", 2500)

    psScript := A_ScriptDir "\PowerShell\mount_wsl_ssd.ps1"
    if (!FileExist(psScript))
        return
    args := openExplorer ? "-OpenExplorer" : ""
    RunSilentPowerShell(psScript, args)

    if (showFeedback)
        SetTimer(CheckMountSuccessBadge, 500)
}

CheckMountSuccessBadge() {
    global EXT4_SSD_LABEL, g_Ext4SsdMounted, EXT4_SSD_DRIVE_LETTER
    driveLetter := (IsSet(EXT4_SSD_DRIVE_LETTER) && EXT4_SSD_DRIVE_LETTER) ? EXT4_SSD_DRIVE_LETTER : "P:"
    targetDrive := SubStr(driveLetter, 1, 1) ":"
    if (DriveGetType(targetDrive) = "Network") {
        SetTimer(CheckMountSuccessBadge, 0)
        g_Ext4SsdMounted := true
        label := (IsSet(EXT4_SSD_LABEL) && EXT4_SSD_LABEL) ? EXT4_SSD_LABEL : "Pixel 1 Backup SSD"
        ShowBottomRightBadge("Mounted " label " (" targetDrive ")", "1A6E3C", 2500)
        return
    }
    if (!IsSsdLockActive(A_Temp "\mount_wsl_ssd.lock")) {
        SetTimer(CheckMountSuccessBadge, 0)
    }
}

UnmountExt4Ssd(showFeedback := false, onlyIfDisconnected := false) {
    global g_Ext4SsdMounted, EXT4_SSD_LABEL, EXT4_SSD_DRIVE_LETTER
    label := (IsSet(EXT4_SSD_LABEL) && EXT4_SSD_LABEL) ? EXT4_SSD_LABEL : "Pixel 1 Backup SSD"
    driveLetter := (IsSet(EXT4_SSD_DRIVE_LETTER) && EXT4_SSD_DRIVE_LETTER) ? EXT4_SSD_DRIVE_LETTER : "P:"
    targetDrive := SubStr(driveLetter, 1, 1) ":"
    isDriveMapped := (DriveGetType(targetDrive) = "Network")

    if (!isDriveMapped && !IsPixelSsdConnected() && !onlyIfDisconnected) {
        if (showFeedback)
            ShowBottomRightBadge(label " is not mounted.", "5D6D7E", 2000)
        return
    }

    ; Guard: do not spawn if unmount is actively in progress
    if IsSsdLockActive(A_Temp "\unmount_wsl_ssd.lock")
        return

    ; If manual unmount while SSD is still plugged in, set flag to prevent watchdog re-mount
    if (!onlyIfDisconnected) {
        ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
        try FileDelete(ejectedFlag)
        FileAppend(A_Now, ejectedFlag)
    }

    static lastUnmountTick := 0
    now := A_TickCount
    if (now - lastUnmountTick < 6000)
        return
    lastUnmountTick := now
    g_Ext4SsdMounted := false

    if (showFeedback)
        ShowBottomRightBadge("Safely ejecting " label "...", "D35400", 2000)

    psScript := A_ScriptDir "\PowerShell\unmount_wsl_ssd.ps1"
    if (!FileExist(psScript))
        return
    args := onlyIfDisconnected ? "-OnlyIfDisconnected" : ""
    RunSilentPowerShell(psScript, args)

    if (showFeedback)
        SetTimer(CheckUnmountSuccessBadge, 500)
}

CheckUnmountSuccessBadge() {
    global EXT4_SSD_LABEL, EXT4_SSD_DRIVE_LETTER
    driveLetter := (IsSet(EXT4_SSD_DRIVE_LETTER) && EXT4_SSD_DRIVE_LETTER) ? EXT4_SSD_DRIVE_LETTER : "P:"
    targetDrive := SubStr(driveLetter, 1, 1) ":"
    if (DriveGetType(targetDrive) != "Network" && !IsSsdLockActive(A_Temp "\unmount_wsl_ssd.lock")) {
        SetTimer(CheckUnmountSuccessBadge, 0)
        label := (IsSet(EXT4_SSD_LABEL) && EXT4_SSD_LABEL) ? EXT4_SSD_LABEL : "Pixel 1 Backup SSD"
        ShowBottomRightBadge(label " is safe to unplug.", "1A6E3C", 3000)
    }
}

SsdManager_WM_POWERBROADCAST(wParam, lParam, *) {
    if (wParam = 18 || wParam = 7)
        SetTimer(ResumeExt4SsdOnWake, -4500) ; check/restore ext4 SSD mount 4.5s after wake
}

ResumeExt4SsdOnWake() {
    MountExt4Ssd(false) ; Silent reconnect check after laptop sleep/wake
}

; [START: WSL ext4 Backup SSD Management Hotkeys]
; Hotkeys:
;   Win+Alt+M -> Mount ext4 SSD & Open in Explorer (with status badges)
;   Win+Alt+U -> Unmount ext4 SSD safely (with status badges)

#!m::MountExt4Ssd(true, true)
#!u::UnmountExt4Ssd(true)
; [END: WSL ext4 Backup SSD Management Hotkeys]

; =============================================================================
; WSL EXT4 BACKUP SSD AUTO-MOUNT & MANAGEMENT
; =============================================================================

WM_DEVICECHANGE_SSD(wParam, lParam, msg, hwnd) {
    ; Intercept DBT_DEVNODES_CHANGED (0x0007), DBT_DEVICEARRIVAL (0x8000), DBT_DEVICEREMOVECOMPLETE (0x8004)
    if (wParam = 0x0007 || wParam = 0x8000 || wParam = 0x8004) {
        SetTimer(ReconcileExt4SsdState, -1000)
    }
    return true
}

ReconcileExt4SsdState() {
    global g_Ext4SsdMounted, EXT4_SSD_DRIVE_LETTER
    ; If mount or unmount is actively in progress, skip reconcile cycle to prevent race condition
    if (IsSsdLockActive(A_Temp "\mount_wsl_ssd.lock") || IsSsdLockActive(A_Temp "\unmount_wsl_ssd.lock"))
        return

    connected := IsPixelSsdConnected()
    ejectedFlag := A_Temp "\pixel_ssd_ejected.flag"
    isManuallyEjected := FileExist(ejectedFlag)

    driveLetter := (IsSet(EXT4_SSD_DRIVE_LETTER) && EXT4_SSD_DRIVE_LETTER) ? EXT4_SSD_DRIVE_LETTER : "P:"
    targetDrive := SubStr(driveLetter, 1, 1) ":"
    pType := DriveGetType(targetDrive)
    isDriveMapped := (pType = "Network")

    if (!connected) {
        ; Physical absence: hardware removed
        if (isManuallyEjected)
            FileDelete(ejectedFlag)
        if (isDriveMapped) {
            g_Ext4SsdMounted := false
            UnmountExt4Ssd(false, true)
        }
    }
    else {
        ; Physical presence: hardware plugged in
        if (!isDriveMapped && !isManuallyEjected) {
            MountExt4Ssd(true, false) ; Silent in background so watchdog never spams 'Connecting' toast
        }
        else if (isDriveMapped) {
            g_Ext4SsdMounted := true
        }
    }
}

IsPixelSsdConnected() {
    global EXT4_SSD_MODEL_SUBSTRINGS
    if (!IsSet(EXT4_SSD_MODEL_SUBSTRINGS) || !EXT4_SSD_MODEL_SUBSTRINGS)
        return false ; Not configured in LocalPaths.ahk
    filter := EXT4_SSD_MODEL_SUBSTRINGS
    try {
        ; Check 1: Active disk drives in Windows WMI
        for disk in ComObjGet("winmgmts:").ExecQuery("SELECT Model FROM Win32_DiskDrive") {
            m := disk.Model
            Loop Parse, filter, ","
            {
                sub := Trim(A_LoopField)
                if (sub != "" && InStr(m, sub))
                    return true
            }
        }
        ; Check 2: Dormant or safely ejected USB storage bridge (Realtek RTL9210 VID_0BDA&PID_9210)
        for dev in ComObjGet("winmgmts:").ExecQuery("SELECT DeviceID, Present FROM Win32_PnPEntity WHERE DeviceID LIKE '%VID_0BDA&PID_9210%'") {
            if (dev.Present)
                return true
        }
    }
    return false
}

TrayMountPixelSsd() {
    MountExt4Ssd(true, true)
}

TrayEjectPixelSsd() {
    UnmountExt4Ssd(true, false)
}

AutoResolveEjectConflict() {
    global EXT4_SSD_LABEL
    if WinExist("Problem Ejecting ahk_class #32770") {
        eTitle := WinGetTitle("Problem Ejecting ahk_class #32770")
        if (InStr(eTitle, "USB Attached SCSI") || InStr(eTitle, "Mass Storage")) {
            WinClose("Problem Ejecting ahk_class #32770")
            label := (IsSet(EXT4_SSD_LABEL) && EXT4_SSD_LABEL) ? EXT4_SSD_LABEL : "Pixel 1 Backup SSD"
            ShowBottomRightBadge(label " in use by WSL. Safely unmounting and ejecting...", "D35400", 3500)
            UnmountExt4Ssd(false, false)
        }
    }
}

TrayRegisterAdminTasks() {
    batScript := A_ScriptDir "\PowerShell\Install_WSL_Mount_Tasks.bat"
    Run('*RunAs "' batScript '"')
}
