#Requires AutoHotkey v1.1
#NoEnv
#NoTrayIcon
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\LocalPaths.ahk ; SUNSHINE_TABLET_TAILSCALE_IP lives here (gitignored)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Supplies IsExternalDisplayActive(), ShowBottomRightBadge()
#SingleInstance force
DetectHiddenWindows, On

; -----------------------------------------------------------------------------
; SUNSHINE DISPLAY WATCHDOG & DISPLAY MANAGER
; -----------------------------------------------------------------------------
; Consolidated control center for Windows display topologies and Sunshine streaming:
; 1. Display Topologies:
;    - PC Screen Only: Internal 1080p @ 144Hz panel (Win+Alt+P, mouse speed 10)
;    - Tablet Only: Second screen dummy plug 2560x1600 @ 120Hz (Win+Alt+P, mouse speed 20)
;    - Extend Displays: Laptop Main + Tablet Extended (Win+Alt+Shift+P, mouse speed 10)
;    - Duplicate Displays: Mirrored screens (Win+Alt+Shift+P, mouse speed 20)
; 2. Instant Mouse Speed Synchronization:
;    - Manual hotkeys switch mouse speed in 0 milliseconds.
;    - Active topology guard: Dynamically tracks Sunshine streaming state and Windows topology.
;      Boosts mouse speed to 20 during active streaming across default mirror, duplicate, and tablet modes.
;    - Automatic pause/exit restores mouse speed 10 within 1.5 seconds (streak = 1 poll).
; 3. Visual Feedback:
;    - Modern rounded bottom-right toast badge via SharedHelpers.ahk (ShowBottomRightBadge).
;    - Dedicated standalone taskbar tray icon with dynamic tooltip and full context menu.
; 4. Hardware Reliability:
;    - Automatic lid-open recovery, power broadcast wake-recovery, and session unlock checks.
;    - Simple Sticky Notes auto-repositioning for laptop vs tablet geometries.
; -----------------------------------------------------------------------------

global SunshineScriptsDir      := PATH_SUNSHINE_SCRIPTS
global MarkerFile              := SunshineScriptsDir "\.fast_since"
global NormalScript            := SunshineScriptsDir "\set_normal.ps1"
global FastScript              := SunshineScriptsDir "\set_fast.ps1"
global SunshineLog             := PATH_SUNSHINE_LOG
global LogsDir                 := A_ScriptDir "\Logs"
if !FileExist(LogsDir)
    FileCreateDir, %LogsDir%
global LogFile                 := LogsDir "\SunshineDisplayWatchdog.log"
global ManualFlag              := A_Temp "\sunshine_manual_switch.flag"
global QuitFlag                := SunshineScriptsDir "\.session_quit"

global CheckIntervalMs         := 1500
global MaxFastHours            := 8
global RequiredLogStreak       := 1  ; Reduced from 16 to 1: instant pause/exit restore (under 1.5s)
global RequiredOfflineStreak   := 10 ; Tailscale secondary signal
global RequiredConnectStreak   := 1  ; Instant boost on reconnect

global LogDisconnectedStreak   := 0
global OfflineStreak           := 0
global ConnectStreak           := 0
global g_LastWakeLogSize       := 0
global g_LastManualDisplaySwitch := 0
global g_LastManualMouseSwitch   := 0
global g_ManualMouseOverride     := false
global g_ManualOverrideConnectId := ""
global PATH_HIBERNATE_ICO      := A_ScriptDir "\..\AutoHotkey Companion Files\tablet_hibernate.ico"
global g_HibernateCountdownSec := 0
global g_HibernateCountdownActive := false
global g_CurrentDisplayModeLabel := "Unknown"
global g_CurrentMouseSpeedLabel  := ""

; Closed-loop handshake state for Extend Displays mode
global g_ExtendPendingConnect := false
global g_ExtendTargetLogSize := 0
global g_ExtendConnectTimeoutTicks := 0
global g_ExtendNotesDelayMs := 1200

; Publish manifest for StartupScript master tray integration
PublishSunshineTrayManifest()

; Win32 hardware event hooks
OnMessage(0x0218, "SunshineDisplay_WM_POWERBROADCAST")
OnMessage(0x007E, "SunshineDisplay_WM_DISPLAYCHANGE")
DllCall("wtsapi32.dll\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
OnMessage(0x02B1, "SunshineDisplay_WM_WTSSESSION_CHANGE")
global g_hPowerNotify := DllCall("RegisterSuspendResumeNotification", "Ptr", A_ScriptHwnd, "UInt", 0, "Ptr")
WM_TASKBARCREATED := DllCall("RegisterWindowMessage", "str", "TaskbarCreated")
OnMessage(WM_TASKBARCREATED, "SunshineDisplay_WM_TASKBARCREATED")
OnExit("SunshineDisplay_Cleanup")

; Initial status refresh
UpdateTrayStatusAndTooltip()

; Automatically align Simple Sticky Notes to current display mode on startup
AutoApplyStickyNotesLayout(1500)

; Start background watchdog loop via SetTimer to keep hotkeys and messages fully responsive
SetTimer, SunshineWatchdogTick, %CheckIntervalMs%
return

; =============================================================================
; HOTKEY BINDINGS
; =============================================================================

; Win+Alt+P: Toggle between Laptop Only and Tablet Only
#!p::ToggleLaptopVsTablet() ;{ <- Toggle Display (Laptop 1080p <-> Tablet 1600p)

; Win+Alt+Shift+P: Toggle between Extend and Duplicate
#!+p::ToggleExtendVsDuplicate() ;{ <- Toggle Dual Display (Extend <-> Duplicate)


#If (g_HibernateCountdownActive)
Escape::CancelHibernateCountdown()
Delete::CancelHibernateCountdown()
~LButton::
    MouseGetPos,,, clickedHwnd
    WinGetClass, clickedClass, ahk_id %clickedHwnd%
    if (clickedClass = "AutoHotkeyGUI")
        CancelHibernateCountdown()
return
#If


; =============================================================================
; DISPLAY SWITCHING FUNCTIONS & TOASTS
; =============================================================================

; Renders an elegant bottom-right toast badge using SharedHelpers.
; Display mode transitions hold for 5500ms so the user can read the new resolution,
; mouse speed, and topology feedback before the toast auto-dismisses.
ShowDisplayBadge(modeTag, titleText, detailText, bgColorHex := "1A3A5A", displayMs := 5500) {
    fullMsg := modeTag " " titleText "`n" detailText
    ShowBottomRightBadge(fullMsg, bgColorHex, displayMs)
}

; Toggles cleanly between Laptop Only and Tablet Only
ToggleLaptopVsTablet() {
    if (IsSecondScreenActive())
        SwitchToLaptopOnlyMode(1200)
    else
        SwitchToTabletOnlyMode(1200)
}

; Toggles cleanly between Extend and Duplicate
ToggleExtendVsDuplicate() {
    if (!HasSecondDisplayConnected()) {
        ShowDisplayBadge("[ALERT]", "No Second Display Detected", "Please attach tablet dummy plug.", "7A3B00")
        return
    }

    topo := GetCurrentDisplayTopology()
    ; If currently in Extend mode (topo 4), switch to Duplicate
    if (topo == 4)
        SwitchToDuplicateMode(1200)
    ; Otherwise (whether Duplicate, PC Only, or Tablet Only), switch to Extend
    else
        SwitchToExtendMode(1200)
}

; Switches host to PC Screen Only mode (1080p @ 144Hz, mouse speed 10)
SwitchToLaptopOnlyMode(delayNotesMs := 1200, skipNotes := false, isBlocking := false) {
    global g_LastManualDisplaySwitch, MarkerFile, LogFile
    global g_ManualMouseOverride, g_ManualOverrideConnectId
    g_LastManualDisplaySwitch := A_TickCount
    g_ManualMouseOverride := false
    g_ManualOverrideConnectId := ""

    ; 1. Win32 instant mouse speed set to 10 (normal) and acceleration ON (0 ms)
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 2. Clear marker files
    if (MarkerFile)
        FileDelete, %MarkerFile%
    FileDelete, % A_Temp "\sunshine_manual_switch.flag"

    ; 3. Execute display switch to internal laptop panel
    ; In blocking mode (such as pre-suspend), RunWait guarantees driver completes topology switch before sleep
    if (isBlocking)
        RunWait, %A_WinDir%\System32\DisplaySwitch.exe /internal,, Hide
    else
        Run, %A_WinDir%\System32\DisplaySwitch.exe /internal,, Hide

    ; 4. Visual toast notification (skip if blocking or pre-suspend)
    if (!isBlocking)
        ShowDisplayBadge("[PC ONLY]", "Laptop Display (1080p @ 144Hz)", "Mouse: Normal (10) | Precision: ON", "1A3A5A")

    ; 5. Restore Simple Sticky Notes layout once 1080p DWM settles
    if (!skipNotes && !isBlocking)
        ApplyLaptopStickyNotesLayout(delayNotesMs)

    ; 6. Re-cycle keyboard hook to guarantee hotkeys stay responsive
    wasSuspended := A_IsSuspended
    Suspend, On
    Sleep, 50
    if (!wasSuspended)
        Suspend, Off

    UpdateTrayStatusAndTooltip()
    SunshineDisplay_Log("Switched to PC Screen Only (1080p @ 144Hz, mouse speed 10, blocking=" (isBlocking ? "true" : "false") ")")
}

; Switches host to Tablet Only mode (2560x1600 @ 120Hz, mouse speed 20)
SwitchToTabletOnlyMode(delayNotesMs := 1200) {
    global g_LastManualDisplaySwitch, MarkerFile, LogFile
    global g_ManualMouseOverride, g_ManualOverrideConnectId
    if (!HasSecondDisplayConnected()) {
        ShowDisplayBadge("[ALERT]", "No Second Display Detected", "Please attach tablet dummy plug.", "7A3B00")
        return
    }

    g_LastManualDisplaySwitch := A_TickCount
    g_ManualMouseOverride := false
    g_ManualOverrideConnectId := ""

    ; 1. Win32 instant boost of mouse speed to 20 and acceleration OFF (0 ms)
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(0, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 2. Create marker files with "manual" content and grace window
    FileDelete, %MarkerFile%
    FileAppend, manual, %MarkerFile%
    if (QuitFlag)
        FileDelete, %QuitFlag%
    manualFlag := A_Temp "\sunshine_manual_switch.flag"
    FileDelete, %manualFlag%
    FileAppend, % A_TickCount, %manualFlag%

    ; 3. Native Win32 SetDisplayConfig call (0x88 = SDC_APPLY | SDC_TOPOLOGY_EXTERNAL)
    DllCall("SetDisplayConfig", "UInt", 0, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0x00000088, "UInt")
    Run, %A_WinDir%\System32\DisplaySwitch.exe /external,, Hide

    ; 4. Visual toast notification
    ShowDisplayBadge("[TABLET ONLY]", "Tablet Display (2560x1600 @ 120Hz)", "Mouse: Fast (20) | Precision: OFF", "4A1A6E")

    ; 5. Apply tablet sticky notes layout once 2560x1600 DWM settles
    ApplyTabletStickyNotesLayout(delayNotesMs)

    UpdateTrayStatusAndTooltip()
    SunshineDisplay_Log("Manual switch to Tablet Only (2560x1600 @ 120Hz, mouse speed 20)")

    ; 6. Schedule post-switch settling timers to re-assert mouse speed 20 after DWM re-enumeration
    SetTimer, SunshineDisplay_EnforceTabletMouseSpeed, -1200
    SetTimer, SunshineDisplay_EnforceTabletMouseSpeed, -2500
}

; Switches host to Extend Displays mode (Laptop Primary + Tablet Secondary)
SwitchToExtendMode(delayNotesMs := 1200) {
    global g_LastManualDisplaySwitch, MarkerFile, LogFile, SunshineLog
    global g_ExtendPendingConnect, g_ExtendTargetLogSize, g_ExtendConnectTimeoutTicks, g_ExtendNotesDelayMs
    global PATH_ADB_EXE, SUNSHINE_TABLET_TAILSCALE_IP
    global g_ManualMouseOverride, g_ManualOverrideConnectId

    if (!HasSecondDisplayConnected()) {
        ShowDisplayBadge("[ALERT]", "No Second Display Detected", "Please attach tablet dummy plug.", "7A3B00")
        return
    }

    g_LastManualDisplaySwitch := A_TickCount
    g_ManualMouseOverride := false
    g_ManualOverrideConnectId := ""
    g_ExtendNotesDelayMs := delayNotesMs

    topo := GetCurrentDisplayTopology()

    ; Case A: If already in Second Screen Only (topo 8), or already in Extend (topo 4),
    ; the secondary display surface is already active. Directly apply /extend.
    if (topo == 8 || topo == 4)
    {
        ; 1. Normal mouse speed for precision on primary laptop display
        DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
        VarSetCapacity(accel, 12, 0)
        NumPut(6, accel, 0, "Int")
        NumPut(10, accel, 4, "Int")
        NumPut(1, accel, 8, "Int")
        DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

        if (MarkerFile)
            FileDelete, %MarkerFile%

        manualFlag := A_Temp "\sunshine_manual_switch.flag"
        FileDelete, %manualFlag%
        FileAppend, % A_TickCount, %manualFlag%

        Run, %A_WinDir%\System32\DisplaySwitch.exe /extend,, Hide

        ShowDisplayBadge("[EXTEND]", "Dual Extended Displays", "Laptop: Main (Tray) | Tablet: Extended", "1A6E3C")
        ApplyLaptopStickyNotesLayout(delayNotesMs)
        UpdateTrayStatusAndTooltip()
        SunshineDisplay_Log("Direct switch to Extend Displays (from topo=" topo ", mouse speed 10)")
        return
    }

    ; Case B: Coming from PC Screen Only (topo 1) or Duplicate (topo 2).
    ; Closed-loop handshake with session teardown:
    ; 1. Convert host display to Second Screen Only (Tablet Only) so dummy plug becomes the active surface.
    ;    Any prior tablet stream session disconnects from the laptop first, prompting Sunshine to release its
    ;    previous DXGI capture adapter context.
    ; 2. Record current sunshine.log position so historical connection markers are ignored.
    ; 3. Dispatch background ADB command to wake the tablet and launch Moonlight fresh via ShortcutTrampoline.
    ; 4. Poll until Sunshine confirms CLIENT CONNECTED and the stream window is open on the tablet.
    ; 5. Pause 1000ms for video decoding stabilization, then switch Windows to Extend Displays (/extend).

    ; Step 1: Switch host to Tablet Only mode
    SwitchToTabletOnlyMode(delayNotesMs)
    ShowDisplayBadge("[EXTEND]", "Connecting Tablet...", "Waking tablet and launching Moonlight", "1A3A5A")

    ; Step 2: Record current sunshine.log size so we only trigger on a fresh connection
    g_ExtendTargetLogSize := 0
    if (SunshineLog && FileExist(SunshineLog))
    {
        file := FileOpen(SunshineLog, "r")
        if IsObject(file)
        {
            g_ExtendTargetLogSize := file.Length
            file.Close()
        }
    }

    ; Step 3: Dispatch ADB wake and connect intent in background
    if (PATH_ADB_EXE && FileExist(PATH_ADB_EXE) && SUNSHINE_TABLET_TAILSCALE_IP)
    {
        adbArgs := "-s " SUNSHINE_TABLET_TAILSCALE_IP ":5555 shell ""input keyevent KEYCODE_WAKEUP && am start -n com.limelight/.ShortcutTrampoline -e Name " A_ComputerName " -e AppName Desktop"""
        RunSilentProcess(PATH_ADB_EXE, adbArgs)
        SunshineDisplay_Log("Extend handshake: Dispatched ADB wake and connect intent to tablet.")
    }
    else
    {
        SunshineDisplay_Log("Extend handshake: ADB not configured. Waiting for tablet connection.")
    }

    ; Step 4: Arm 20-second connection watcher
    g_ExtendPendingConnect := true
    g_ExtendConnectTimeoutTicks := A_TickCount + 20000
    SetTimer, SunshineDisplay_WaitTabletConnectForExtend, 500
}

; Polling timer for closed-loop Extend handshake
SunshineDisplay_WaitTabletConnectForExtend:
    global g_ExtendPendingConnect, g_ExtendTargetLogSize, g_ExtendConnectTimeoutTicks, g_ExtendNotesDelayMs
    global SunshineLog, LogFile, MarkerFile

    if (!g_ExtendPendingConnect)
    {
        SetTimer, SunshineDisplay_WaitTabletConnectForExtend, Off
        return
    }

    ; Check timeout (20 seconds)
    if (A_TickCount > g_ExtendConnectTimeoutTicks)
    {
        SetTimer, SunshineDisplay_WaitTabletConnectForExtend, Off
        g_ExtendPendingConnect := false
        ShowDisplayBadge("[EXTEND]", "Tablet Connection Timed Out", "Workstation remaining in Tablet Only mode", "7A3B00")
        SunshineDisplay_Log("Extend handshake timed out after 20s. Remaining in Tablet Only mode.")
        return
    }

    ; Check if Sunshine has logged a fresh CLIENT CONNECTED event past g_ExtendTargetLogSize
    hasConnected := false
    if (SunshineLog && FileExist(SunshineLog))
    {
        file := FileOpen(SunshineLog, "r")
        if IsObject(file)
        {
            currLen := file.Length
            if (currLen > g_ExtendTargetLogSize)
            {
                readBytes := currLen - g_ExtendTargetLogSize
                file.Seek(g_ExtendTargetLogSize, 0)
                newText := file.Read(readBytes)
                if InStr(newText, "CLIENT CONNECTED")
                    hasConnected := true
            }
            file.Close()
        }
    }

    if (hasConnected)
    {
        SetTimer, SunshineDisplay_WaitTabletConnectForExtend, Off
        g_ExtendPendingConnect := false

        SunshineDisplay_Log("Extend handshake: Tablet connection confirmed! Settling 1000ms before /extend...")
        ShowDisplayBadge("[EXTEND]", "Tablet Connected!", "Switching to Dual Extended Displays", "1A6E3C")

        ; Arm a one-shot settlement timer to let the video frame presentation stabilize before /extend
        SetTimer, SunshineDisplay_ApplyExtendAfterConnect, -1000
    }
return

; Applies /extend once the tablet stream has stabilized
SunshineDisplay_ApplyExtendAfterConnect:
    global g_ExtendNotesDelayMs, MarkerFile, LogFile

    ; Normal mouse speed for precision on primary laptop display
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    if (MarkerFile)
        FileDelete, %MarkerFile%

    manualFlag := A_Temp "\sunshine_manual_switch.flag"
    FileDelete, %manualFlag%
    FileAppend, % A_TickCount, %manualFlag%

    Run, %A_WinDir%\System32\DisplaySwitch.exe /extend,, Hide

    ShowDisplayBadge("[EXTEND]", "Dual Extended Displays", "Laptop: Main (Tray) | Tablet: Extended", "1A6E3C")
    ApplyLaptopStickyNotesLayout(g_ExtendNotesDelayMs)
    UpdateTrayStatusAndTooltip()
    SunshineDisplay_Log("Extend handshake complete: Dual extended displays active, mouse speed 10.")
return

; Switches host to Duplicate Displays mode (Mirrors screens)
SwitchToDuplicateMode(delayNotesMs := 1200) {
    global g_LastManualDisplaySwitch, MarkerFile, LogFile
    global g_ManualMouseOverride, g_ManualOverrideConnectId
    if (!HasSecondDisplayConnected()) {
        ShowDisplayBadge("[ALERT]", "No Second Display Detected", "Please attach tablet dummy plug.", "7A3B00")
        return
    }

    g_LastManualDisplaySwitch := A_TickCount
    g_ManualMouseOverride := false
    g_ManualOverrideConnectId := ""

    ; 1. Boost mouse speed to 20 for streaming canvas navigation
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(0, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    FileDelete, %MarkerFile%
    FileAppend, manual, %MarkerFile%
    manualFlag := A_Temp "\sunshine_manual_switch.flag"
    FileDelete, %manualFlag%
    FileAppend, % A_TickCount, %manualFlag%

    ; 2. Native Win32 SetDisplayConfig call (0x82 = SDC_APPLY | SDC_TOPOLOGY_CLONE)
    DllCall("SetDisplayConfig", "UInt", 0, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0x00000082, "UInt")
    Run, %A_WinDir%\System32\DisplaySwitch.exe /clone,, Hide

    ; 3. Visual toast notification
    ShowDisplayBadge("[DUPLICATE]", "Mirrored Displays", "Mouse: Fast (20) | Displays Cloned", "1A5A5A")

    ; 4. Apply tablet layout once DWM settles
    ApplyTabletStickyNotesLayout(delayNotesMs)

    UpdateTrayStatusAndTooltip()
    SunshineDisplay_Log("Manual switch to Duplicate Displays (Mirrored, mouse speed 20)")
}

; Helper to detect whether Windows is currently in Clone/Duplicate topology
IsDisplayTopologyDuplicate() {
    return (GetCurrentDisplayTopology() == 2)
}

; Checks if system is on Second Screen Only (laptop panel missing/detached)
IsSecondScreenActive() {
    return IsSecondScreenOnly()
}


; =============================================================================
; TRAY MENU AND STATUS UPDATER
; =============================================================================

UpdateTrayStatusAndTooltip(forceRefresh := false) {
    global g_CurrentDisplayModeLabel
    topo := GetCurrentDisplayTopology()
    isTabletOnly := false

    if (topo == 8) {
        modeText := "Tablet Only (2560x1600 @ 120Hz)"
        isTabletOnly := true
    } else if (topo == 2) {
        modeText := "Duplicate Displays (Mirror)"
    } else if (topo == 4) {
        modeText := "Extend Displays (Dual Screens)"
    } else if (topo == 1) {
        modeText := "PC Screen Only (1080p @ 144Hz)"
    } else {
        if (IsSecondScreenOnly()) {
            modeText := "Tablet Only (2560x1600 @ 120Hz)"
            isTabletOnly := true
        } else {
            modeText := "PC Screen Only (1080p @ 144Hz)"
        }
    }

    g_CurrentDisplayModeLabel := modeText
    UpdateTabletHibernateTrayIcon(isTabletOnly, forceRefresh)
    PublishSunshineTrayManifest()
}

UpdateTabletHibernateTrayIcon(isTabletOnly, forceRefresh := false) {
    global PATH_HIBERNATE_ICO
    static s_iconVisible := false
    static s_lastMouseLabel := ""

    if (forceRefresh)
        s_iconVisible := false

    curSpeed := GetCurrentMouseSpeed()
    mouseLabel := (curSpeed >= 20) ? "Mouse Speed: Fast (20) [Click for Normal]" : "Mouse Speed: Normal (10) [Click for Fast]"

    if (isTabletOnly) {
        if (!s_iconVisible) {
            iconFile := PATH_HIBERNATE_ICO
            if (!FileExist(iconFile))
                iconFile := A_ScriptDir "\..\AutoHotkey Companion Files\tablet_hibernate.ico"

            Menu, Tray, NoStandard
            Menu, Tray, DeleteAll
            Menu, Tray, Add, Hibernate Workstation (5s Countdown), Menu_TriggerHibernateCountdown
            Menu, Tray, Default, Hibernate Workstation (5s Countdown)
            Menu, Tray, Add, Hibernate Immediately, Menu_HibernateImmediately
            Menu, Tray, Add, Cancel Countdown, Menu_CancelHibernateCountdown
            Menu, Tray, Add
            Menu, Tray, Add, %mouseLabel%, Action_ToggleMouseSpeed
            Menu, Tray, Add
            Menu, Tray, Add, Restore Laptop Display (Win+Alt+P), Menu_SwitchLaptopOnly

            if (FileExist(iconFile))
                Menu, Tray, Icon, %iconFile%

            Menu, Tray, Tip, Hibernate Workstation`nDouble-click to start 5s countdown
            Menu, Tray, Icon
            s_iconVisible := true
            s_lastMouseLabel := mouseLabel
        } else if (s_lastMouseLabel != mouseLabel) {
            try Menu, Tray, Rename, %s_lastMouseLabel%, %mouseLabel%
            s_lastMouseLabel := mouseLabel
        }
    } else {
        if (s_iconVisible) {
            Menu, Tray, NoIcon
            s_iconVisible := false
            s_lastMouseLabel := ""
        }
    }
}

SunshineDisplay_WM_TASKBARCREATED(wParam, lParam) {
    UpdateTrayStatusAndTooltip(true)
}

Menu_TriggerHibernateCountdown:
    TriggerHibernateCountdown()
return

Menu_CancelHibernateCountdown:
    CancelHibernateCountdown()
return

Menu_HibernateImmediately:
    global g_HibernateCountdownActive
    SetTimer, HibernateCountdownTick, Off
    g_HibernateCountdownActive := false
    ExecuteSafeHibernate()
return

TriggerHibernateCountdown() {
    global g_HibernateCountdownSec, g_HibernateCountdownActive

    ; If countdown is already active, double-clicking again cancels it
    if (g_HibernateCountdownActive) {
        CancelHibernateCountdown()
        return
    }

    g_HibernateCountdownSec := 5
    g_HibernateCountdownActive := true
    ShowHibernateCountdownBadge(g_HibernateCountdownSec)
    SetTimer, HibernateCountdownTick, 1000
}

HibernateCountdownTick:
    global g_HibernateCountdownSec, g_HibernateCountdownActive

    if (!g_HibernateCountdownActive) {
        SetTimer, HibernateCountdownTick, Off
        return
    }

    g_HibernateCountdownSec--
    if (g_HibernateCountdownSec > 0) {
        ShowHibernateCountdownBadge(g_HibernateCountdownSec)
    } else {
        SetTimer, HibernateCountdownTick, Off
        g_HibernateCountdownActive := false
        ExecuteSafeHibernate()
    }
return

CancelHibernateCountdown() {
    global g_HibernateCountdownActive
    if (g_HibernateCountdownActive) {
        SetTimer, HibernateCountdownTick, Off
        g_HibernateCountdownActive := false
        HideBottomRightBadge()
        ShowBottomRightBadge("[CANCELED] Hibernation Aborted`nWorkstation remains active.", "3A3D40", 2500)
    }
}

ExecuteSafeHibernate() {
    ShowBottomRightBadge("[HIBERNATING] Restoring Laptop Panel...`nCommitting session to disk.", "1A5A3A", 3000)
    SwitchToLaptopOnlyMode(0, true, true)
    Sleep, 200
    Run, %A_WinDir%\System32\shutdown.exe /h,, Hide
}

ShowHibernateCountdownBadge(sec) {
    title := "[HIBERNATE] Workstation Hibernating in " sec "s..."
    detail := "Restoring laptop display panel. Press Esc, Del, or click to Cancel."
    ShowBottomRightBadge(title "`n" detail, "B33A00", 1500)
}

TrayShowStatusToast:
    DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "UIntP", curSpeed, "UInt", 0)
    ShowDisplayBadge("[STATUS]", g_CurrentDisplayModeLabel, "Mouse Speed: " curSpeed, "1A3A5A")
return

Menu_SwitchLaptopOnly:
    SwitchToLaptopOnlyMode()
return

Menu_SwitchTabletOnly:
    SwitchToTabletOnlyMode()
return

Menu_SwitchExtend:
    SwitchToExtendMode()
return

Menu_SwitchDuplicate:
    SwitchToDuplicateMode()
return

TrayReload:
    Reload
return


; =============================================================================
; WATCHDOG TICK (Instant Mouse Speed & Active Topology Guard)
; =============================================================================

SunshineWatchdogTick:
    ; PRIORITY 0: Sunshine undo hook fired (stream session ended)
    if FileExist(QuitFlag)
    {
        FileDelete, %QuitFlag%
        LogDisconnectedStreak := 0
        OfflineStreak := 0
        if (g_ManualMouseOverride)
        {
            g_ManualMouseOverride := false
            g_ManualOverrideConnectId := ""
            SunshineDisplay_Log("Sunshine session ended (.session_quit): Cleared manual mouse override.")
        }
        SunshineDisplay_Log("Sunshine session ended (undo hook processed)")
        UpdateTrayStatusAndTooltip()
    }

    ; Query current hardware display topology via native Windows engine
    topo := GetCurrentDisplayTopology()

    ; Query streaming status and connection event identifiers from sunshine.log
    lastConnectId := ""
    lastDisconnectId := ""
    LastEvent := SunshineWatchdog_LastClientEvent(lastConnectId, lastDisconnectId)
    isStreaming := (LastEvent = "CONNECTED")

    ; Reset manual mouse override on session boundary:
    ; 1. Stream disconnected
    ; 2. Fresh stream reconnection (new CLIENT CONNECTED timestamp signature)
    if (g_ManualMouseOverride)
    {
        if (LastEvent = "DISCONNECTED")
        {
            g_ManualMouseOverride := false
            g_ManualOverrideConnectId := ""
            SunshineDisplay_Log("Disconnection event: Cleared manual mouse override. Automatic mode restored.")
        }
        else if (isStreaming && lastConnectId != "" && g_ManualOverrideConnectId != "" && lastConnectId != g_ManualOverrideConnectId)
        {
            g_ManualMouseOverride := false
            g_ManualOverrideConnectId := ""
            SunshineDisplay_Log("Reconnection detected (" lastConnectId "): Cleared manual mouse override. Automatic mode restored.")
        }
    }

    ; Manual display switch grace check (20s)
    isManualGrace := false
    if FileExist(ManualFlag)
    {
        FileGetTime, manualTime, %ManualFlag%, M
        manualAgeSec := A_Now
        EnvSub, manualAgeSec, %manualTime%, Seconds
        if (manualAgeSec < 20)
            isManualGrace := true
        else
            FileDelete, %ManualFlag%
    }

    ; -------------------------------------------------------------------------
    ; 1. CLIENT CONNECTED: Active streaming session (Tablet Moonlight)
    ; -------------------------------------------------------------------------
    if (isStreaming)
    {
        if FileExist(ManualFlag)
            FileDelete, %ManualFlag%

        LogDisconnectedStreak := 0
        OfflineStreak := 0

        ; If user manually toggled mouse speed, hold that choice without reverting
        if (g_ManualMouseOverride)
        {
            ConnectStreak := 0
        }
        ; In Extend Displays mode (topo 4), the laptop screen is the primary display
        ; with physical controls, so mouse speed remains normal (10).
        else if (topo == 4)
        {
            if (GetCurrentMouseSpeed() > 10)
                SunshineWatchdog_RestoreMouseNormal("Topology Guard: Extend mode enforced speed 10")
        }
        else
        {
            ; For PC Screen Only (topo 1, default laptop mirror), Duplicate (topo 2),
            ; or Tablet Only (topo 8): user is actively controlling the desktop from tablet.
            ; Ensure mouse speed is FAST (20) with precision acceleration disabled.
            if (!FileExist(MarkerFile) || GetCurrentMouseSpeed() < 20)
            {
                isStalePreWake := false
                if (g_LastWakeLogSize > 0)
                {
                    currLogSize := 0
                    file := FileOpen(SunshineLog, "r")
                    if IsObject(file)
                    {
                        currLogSize := file.Length
                        file.Close()
                    }
                    if (currLogSize <= g_LastWakeLogSize)
                        isStalePreWake := true
                    else
                        g_LastWakeLogSize := 0
                }

                if (!isStalePreWake)
                {
                    ConnectStreak++
                    if (ConnectStreak >= RequiredConnectStreak)
                    {
                        SunshineWatchdog_ForceFast("Active Sunshine stream (topo=" topo "): boosted mouse speed to 20")
                        ConnectStreak := 0
                    }
                }
            }
            else
                ConnectStreak := 0
        }
    }
    ; -------------------------------------------------------------------------
    ; 2. CLIENT DISCONNECTED: Stream paused or closed on tablet
    ; -------------------------------------------------------------------------
    else if (LastEvent = "DISCONNECTED")
    {
        ConnectStreak := 0
        if (g_ManualMouseOverride)
        {
            g_ManualMouseOverride := false
            g_ManualOverrideConnectId := ""
            SunshineDisplay_Log("Disconnection event: Cleared manual mouse override.")
        }

        if (!isManualGrace)
        {
            LogDisconnectedStreak++
            ; RequiredLogStreak is 1: restores mouse normal on very first tick (under 1.5s)
            if (LogDisconnectedStreak >= RequiredLogStreak)
            {
                ; On PC Screen Only (topo 1), Duplicate (topo 2), or Extend (topo 4),
                ; the user is using the laptop display locally; restore normal speed 10.
                if (topo == 1 || topo == 2 || topo == 4)
                {
                    if (FileExist(MarkerFile) || GetCurrentMouseSpeed() > 10)
                    {
                        SunshineWatchdog_RestoreMouseNormal("sunshine.log shows CLIENT DISCONNECTED on topo " topo " (stream paused/ended)")
                    }
                }
                else if (topo == 8 || (topo == 0 && IsSecondScreenOnly()))
                {
                    ; Tablet Only mode: laptop screen is off. Clear MarkerFile without oscillating.
                    if FileExist(MarkerFile)
                        FileDelete, %MarkerFile%
                }
                LogDisconnectedStreak := 0
                OfflineStreak := 0
            }
        }
        else
            LogDisconnectedStreak := 0
    }
    ; -------------------------------------------------------------------------
    ; 3. IDLE / FALLBACK: No active stream events in recent log window
    ; -------------------------------------------------------------------------
    else
    {
        ConnectStreak := 0
        ; When stream is idle and workstation is on PC Screen Only or Extend, enforce normal speed 10
        if (!g_ManualMouseOverride && (topo == 1 || topo == 4))
        {
            if (GetCurrentMouseSpeed() > 10)
                SunshineWatchdog_RestoreMouseNormal("Topology Guard: Idle mode (topo=" topo ") enforced speed 10")
            if FileExist(MarkerFile)
                FileDelete, %MarkerFile%
        }
        else if (!isManualGrace && IsSecondScreenOnly())
        {
            ; In Tablet Only mode with no stream events, check Tailscale reachability
            if SunshineWatchdog_TabletReachable()
            {
                OfflineStreak := 0
                ; Ensure speed 20 is active for tablet display if not in manual override
                if (!g_ManualMouseOverride && GetCurrentMouseSpeed() < 20)
                    SetMouseSpeedFast("Topology Guard: Tablet Only mode asserted speed 20")
            }
            else
            {
                OfflineStreak++
                if (OfflineStreak >= RequiredOfflineStreak)
                {
                    if (g_ManualMouseOverride)
                    {
                        g_ManualMouseOverride := false
                        g_ManualOverrideConnectId := ""
                        SunshineDisplay_Log("Tablet unreachable on Tailscale: Cleared manual mouse override.")
                    }
                    SunshineWatchdog_ForceNormal("tablet unreachable on Tailscale for " (OfflineStreak * CheckIntervalMs / 1000) "s+")
                    LogDisconnectedStreak := 0
                    OfflineStreak := 0
                }
            }
        }
        else
            OfflineStreak := 0
    }

    ; 4. Safety net ceiling: stuck fast past MaxFastHours regardless
    if FileExist(MarkerFile)
    {
        FileGetTime, FastSince, %MarkerFile%, M
        NowCopy := A_Now
        EnvSub, NowCopy, %FastSince%, Hours
        if (NowCopy >= MaxFastHours)
        {
            g_ManualMouseOverride := false
            g_ManualOverrideConnectId := ""
            SunshineWatchdog_ForceNormal("stuck fast " NowCopy "h+, past the " MaxFastHours "h ceiling")
            LogDisconnectedStreak := 0
            OfflineStreak := 0
        }
    }

    UpdateTrayStatusAndTooltip()
return


; =============================================================================
; HELPER FUNCTIONS (Watchdog & Streaming)
; =============================================================================

SunshineWatchdog_LastClientEvent(ByRef outConnectId := "", ByRef outDisconnectId := "") {
    global SunshineLog
    outConnectId := ""
    outDisconnectId := ""
    if (!SunshineLog || !FileExist(SunshineLog))
        return ""

    file := FileOpen(SunshineLog, "r")
    if !IsObject(file)
        return ""

    LogLength := file.Length
    ReadLength := 65536
    if (LogLength > ReadLength)
        file.Seek(LogLength - ReadLength, 0)

    Text := file.Read()
    file.Close()

    if (Text = "")
        return ""

    LastConnectedPos := 0, LastDisconnectedPos := 0, SearchPos := 1
    Loop
    {
        FoundPos := InStr(Text, "CLIENT CONNECTED",, SearchPos)
        if !FoundPos
            break
        LastConnectedPos := FoundPos
        SearchPos := FoundPos + 1
    }
    SearchPos := 1
    Loop
    {
        FoundPos := InStr(Text, "CLIENT DISCONNECTED",, SearchPos)
        if !FoundPos
            break
        LastDisconnectedPos := FoundPos
        SearchPos := FoundPos + 1
    }

    if (LastConnectedPos > 0)
    {
        lineStart := InStr(SubStr(Text, 1, LastConnectedPos), "`n", false, 0)
        lineStart := (lineStart > 0) ? lineStart + 1 : 1
        lineEnd := InStr(Text, "`n", false, LastConnectedPos)
        lineLen := (lineEnd > 0) ? (lineEnd - lineStart) : (StrLen(Text) - lineStart + 1)
        outConnectId := Trim(SubStr(Text, lineStart, lineLen), "`r`n ")
    }

    if (LastDisconnectedPos > 0)
    {
        lineStart := InStr(SubStr(Text, 1, LastDisconnectedPos), "`n", false, 0)
        lineStart := (lineStart > 0) ? lineStart + 1 : 1
        lineEnd := InStr(Text, "`n", false, LastDisconnectedPos)
        lineLen := (lineEnd > 0) ? (lineEnd - lineStart) : (StrLen(Text) - lineStart + 1)
        outDisconnectId := Trim(SubStr(Text, lineStart, lineLen), "`r`n ")
    }

    if (LastConnectedPos = 0 && LastDisconnectedPos = 0)
        return ""
    return (LastDisconnectedPos > LastConnectedPos) ? "DISCONNECTED" : "CONNECTED"
}

SunshineWatchdog_TabletReachable() {
    global SUNSHINE_TABLET_TAILSCALE_IP, PATH_TAILSCALE_EXE
    if (!SUNSHINE_TABLET_TAILSCALE_IP)
        return true

    TailscaleExe := PATH_TAILSCALE_EXE
    if (!TailscaleExe || !FileExist(TailscaleExe))
        return true

    TmpFile := A_Temp "\sunshine_watchdog_ts_status.tmp"
    RunWait, %ComSpec% /c ""%TailscaleExe%" status > "%TmpFile%" 2>&1",, Hide
    StatusOutput := ""
    FileRead, StatusOutput, %TmpFile%
    FileDelete, %TmpFile%

    if !InStr(StatusOutput, SUNSHINE_TABLET_TAILSCALE_IP)
        return true

    Loop, Parse, StatusOutput, `n, `r
        if InStr(A_LoopField, SUNSHINE_TABLET_TAILSCALE_IP)
            return !InStr(A_LoopField, "offline")

    return true
}

SunshineDisplay_Log(msg) {
    global LogFile
    FormatTime, ts, , yyyy-MM-dd HH:mm:ss
    FileAppend, % "[" ts "] " msg "`n", %LogFile%
}

SunshineWatchdog_ForceNormal(reason, skipScript := false) {
    global MarkerFile

    ; 1. Instant Win32 restore of mouse speed to 10
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 2. Clean up marker files
    if (MarkerFile)
        FileDelete, %MarkerFile%
    FileDelete, % A_Temp "\sunshine_manual_switch.flag"

    SunshineDisplay_Log("Forced normal mouse speed: " reason)
}

SunshineWatchdog_ForceFast(reason) {
    SetMouseSpeedFast("Watchdog force fast: " reason)
}

SunshineWatchdog_RestoreMouseNormal(reason) {
    SetMouseSpeedNormal("Watchdog restore normal: " reason)
}

; -----------------------------------------------------------------------------
; MOUSE SPEED ENGINE AND FAILSAFE TRAY ACTIONS
; -----------------------------------------------------------------------------

GetCurrentMouseSpeed() {
    curSpeed := 0
    DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "UIntP", curSpeed, "UInt", 0)
    return curSpeed
}

SetMouseSpeedFast(reason := "") {
    global MarkerFile
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(0, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    if (MarkerFile) {
        FileDelete, %MarkerFile%
        FileAppend, manual, %MarkerFile%
    }

    if (reason)
        SunshineDisplay_Log("Set mouse speed FAST (20): " reason)
    UpdateTrayStatusAndTooltip()
}

SetMouseSpeedNormal(reason := "") {
    global MarkerFile
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    if (MarkerFile)
        FileDelete, %MarkerFile%
    FileDelete, % A_Temp "\sunshine_manual_switch.flag"

    if (reason)
        SunshineDisplay_Log("Set mouse speed NORMAL (10): " reason)
    UpdateTrayStatusAndTooltip()
}

Action_ToggleMouseSpeed:
    ToggleMouseSpeed()
return

ToggleMouseSpeed() {
    global g_LastManualMouseSwitch, g_ManualMouseOverride, g_ManualOverrideConnectId
    g_LastManualMouseSwitch := A_TickCount
    g_ManualMouseOverride := true

    ; Capture active connection signature to detect any subsequent reconnection
    curConnectId := ""
    curDisconnectId := ""
    SunshineWatchdog_LastClientEvent(curConnectId, curDisconnectId)
    g_ManualOverrideConnectId := curConnectId

    curSpeed := GetCurrentMouseSpeed()
    if (curSpeed >= 20) {
        SetMouseSpeedNormal("Manual tray toggle (override engaged)")
        ShowDisplayBadge("[MOUSE]", "Mouse Speed: Normal (10)", "Manual Override Active`nHeld until reconnect or disconnect", "1A3A5A", 3500)
    } else {
        SetMouseSpeedFast("Manual tray toggle (override engaged)")
        ShowDisplayBadge("[MOUSE]", "Mouse Speed: Fast (20)", "Manual Override Active`nHeld until reconnect or disconnect", "4A1A6E", 3500)
    }
}

PublishSunshineTrayManifest() {
    global g_CurrentMouseSpeedLabel
    curSpeed := GetCurrentMouseSpeed()
    speedLabel := (curSpeed >= 20) ? "Mouse Speed: Fast (20)`tClick for Normal" : "Mouse Speed: Normal (10)`tClick for Fast"
    g_CurrentMouseSpeedLabel := speedLabel
    PublishTrayMenuManifest([ ["PC Screen Only (1080p @ 144Hz)`tWin+Alt+P", "Menu_SwitchLaptopOnly"]
                            , ["Tablet Only (2560x1600 @ 120Hz)`tWin+Alt+P", "Menu_SwitchTabletOnly"]
                            , ["Extend Displays (Dual Screens)`tWin+Alt+Shift+P", "Menu_SwitchExtend"]
                            , ["Duplicate Displays (Mirror)`tWin+Alt+Shift+P", "Menu_SwitchDuplicate"]
                            , ["-"]
                            , [speedLabel, "Action_ToggleMouseSpeed"] ])
}

SunshineDisplay_EnforceTabletMouseSpeed:
    global g_ManualMouseOverride
    if (!g_ManualMouseOverride && (IsSecondScreenOnly() || GetCurrentDisplayTopology() == 8)) {
        if (GetCurrentMouseSpeed() != 20)
            SetMouseSpeedFast("Post-switch settling enforcement")
    }
return


; =============================================================================
; HARDWARE EVENT HANDLERS (PowerBroadcast, DisplayChange, SessionChange)
; =============================================================================

SunshineDisplay_WM_POWERBROADCAST(wParam, lParam) {
    global g_LastWakeLogSize, SunshineLog, g_ManualMouseOverride, g_ManualOverrideConnectId
    g_ManualMouseOverride := false
    g_ManualOverrideConnectId := ""

    ; wParam 4: PBT_APMSUSPEND (system is preparing to suspend or hibernate)
    if (wParam = 4)
    {
        if (IsSecondScreenActive()) {
            SunshineDisplay_Log("Pre-suspend (wParam=4): Second screen active. Synchronously restoring laptop panel before sleep.")
            SwitchToLaptopOnlyMode(0, true, true)
        } else {
            SunshineDisplay_Log("Pre-suspend (wParam=4): Laptop panel already active. No switch required.")
        }
    }
    ; wParam 18 (PBT_APMRESUMEAUTOMATIC) or 7 (PBT_APMRESUMESUSPEND)
    else if (wParam = 18 || wParam = 7)
    {
        SunshineDisplay_Log("Wake broadcast (wParam=" wParam "): Arming 3-wave recovery timers.")
        if (SunshineLog && FileExist(SunshineLog))
        {
            file := FileOpen(SunshineLog, "r")
            if IsObject(file)
            {
                g_LastWakeLogSize := file.Length
                file.Close()
            }
        }

        ; Staggered triple-wave recovery to overcome slow GPU re-enumeration after Modern Standby or Hibernate
        SetTimer, SunshineDisplay_ResumeWakeWave1, -500
        SetTimer, SunshineDisplay_ResumeWakeWave2, -2000
        SetTimer, SunshineDisplay_ResumeWakeWave3, -4000
    }
}

SunshineDisplay_ResumeWakeWave1:
    if (IsSecondScreenActive()) {
        SunshineDisplay_Log("Wake Wave 1 (500ms): Second screen active. Restoring laptop display mode.")
        SwitchToLaptopOnlyMode(1200)
    }
    ; Re-cycle keyboard hook to guarantee hotkeys respond after wake
    wasSuspended := A_IsSuspended
    Suspend, On
    Sleep, 50
    if (!wasSuspended)
        Suspend, Off
return

SunshineDisplay_ResumeWakeWave2:
    if (IsSecondScreenActive()) {
        SunshineDisplay_Log("Wake Wave 2 (2000ms): Second screen still active. Re-applying restore.")
        SwitchToLaptopOnlyMode(1200)
    }
return

SunshineDisplay_ResumeWakeWave3:
    if (IsSecondScreenActive()) {
        SunshineDisplay_Log("Wake Wave 3 (4000ms): Second screen still active. Final fail-safe restore.")
        SwitchToLaptopOnlyMode(1200)
    }
return

SunshineDisplay_WM_DISPLAYCHANGE(wParam, lParam, msg, hwnd) {
    AutoApplyStickyNotesLayout(1200)
    UpdateTrayStatusAndTooltip()
}

SunshineDisplay_WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
    ; wParam 8 = WTS_SESSION_UNLOCK
    if (wParam = 8)
    {
        ; Re-cycle keyboard hook to guarantee hotkeys respond after unlock
        wasSuspended := A_IsSuspended
        Suspend, On
        Sleep, 50
        if (!wasSuspended)
            Suspend, Off
    }
}

SunshineDisplay_Cleanup(ExitReason, ExitCode) {
    global g_hPowerNotify
    if (g_hPowerNotify) {
        DllCall("UnregisterSuspendResumeNotification", "Ptr", g_hPowerNotify)
        g_hPowerNotify := 0
    }
}
