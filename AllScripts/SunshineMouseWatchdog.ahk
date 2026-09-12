#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\LocalPaths.ahk ; SUNSHINE_TABLET_TAILSCALE_IP lives here (gitignored)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Supplies IsExternalDisplayActive()
#SingleInstance force
DetectHiddenWindows, On

; Safety net for the Sunshine mouse-speed boost (set_fast.ps1/set_normal.ps1 under the Sunshine scripts directory).
; Those two scripts already handle the normal tablet connect/quit cycle correctly via Sunshine's own prep-cmd do/undo hooks - this script exists only for the cases that leave it stuck fast:
;
; - Sunshine deliberately keeps a dropped session resumable rather than firing "undo" (per LizardByte/Sunshine's own docs).
; - Moonlight backgrounding/pausing on the tablet does not disconnect it from the network at all - sunshine.log can show "CLIENT DISCONNECTED" for a paused session while "tailscale status" simultaneously still shows the tablet as fully "active" with live tx/rx traffic.
;   Tailscale reachability CANNOT see a Sunshine-level pause; it only helps for a true network-level drop (e.g. a device going fully offline when powered off), so that check stays in as a second, independent trigger, not the primary one.
;
; Detection signals, in priority order:
;
; - PRIMARY: tail sunshine.log for the most recent "CLIENT CONNECTED" vs "CLIENT DISCONNECTED" line.
;   This is Sunshine's own authoritative event, not an inferred proxy, and fires the instant a session pauses - unlike Tailscale reachability, which does not change during a pause at all.
; - SECONDARY: tablet's Tailscale peer offline for RequiredOfflineStreak consecutive polls.
;   Kept as a second, independent path in case the log is ever unreadable/rotated.
; - TERTIARY/last resort: fast-mode older than MaxFastHours regardless of the above, in case both signals above somehow miss it.
;   Set generously since long legitimate remote-desktop sessions are the normal case here, not the exception.
;
; BI-DIRECTIONAL: a RESUMED session (tapping the Desktop tile again after a pause) does NOT re-fire prep-cmd's "do" - sunshine.log logs "CLIENT CONNECTED" for a resume with no matching "Executing Do Cmd" line.
; So this script also forces FAST when the marker is absent (mouse currently normal) and the log's latest event is CONNECTED - symmetric with the existing force-normal path, same log signal, same authoritative reasoning.
; This can never double-fire on a genuinely fresh connect: prep-cmd's own "do" always creates the marker a few seconds before CLIENT CONNECTED logs, so by the time this script would see CONNECTED, the marker already exists and the "marker absent" precondition is false.
;
; RACE FIX: that same do-to-connected gap is a hazard in the OTHER direction too. If a poll lands in that gap, the marker exists (just created) but the log's latest event is still the PREVIOUS session's DISCONNECTED, which would incorrectly revert a session that's still starting up.
; The 24-second disconnect streak requirement (RequiredLogStreak := 16 polls x 1.5s) safely absorbs this startup gap before any action is taken.
;
; DISPLAY AUTO-SWITCH ON CONNECT: tried and reverted (2026-09-08).
; Switching to tablet mode (DisplaySwitch.exe 4) in this same fresh-marker window caused a hang, because Sunshine's own connect-time transition briefly puts the display in Duplicate mode first and the two display changes appear to race.
; Connect-side switching stays manual (Win+Alt+P / the BasicTasks tray items) for this reason.
; On explicit quit (.session_quit), sustained Tailscale offline, or 8h ceiling, full display switch back to PC Screen Only (DisplaySwitch.exe 1) and Sticky Notes layout restoration are executed.
; For transient disconnects/pauses (CLIENT DISCONNECTED without explicit quit), only the mouse speed is restored to normal 10 via SunshineWatchdog_RestoreMouseNormal (without switching display topology), keeping the tablet dummy plug display alive so resuming the stream avoids DXGI display mode thrashing or capture hangs.
;
; MANUAL OVERRIDE: BasicTasks.ahk's Win+Alt+P (ToggleTabletDisplayMode) also owns this marker, for a manual tablet-mode toggle that has nothing to do with an actual Sunshine session.
; It writes "manual" as the marker's content (set_fast.ps1 leaves it empty), and this script defers entirely to that - skipping the log/Tailscale checks below, which would otherwise be answering "did the OLD session end" instead of "did the user still want tablet mode" - until the user toggles back or the lid-reopen recovery in BasicTasks.ahk fires.
; MaxFastHours above still applies regardless of manual vs. session-driven origin, as the leave-it-on-forever safety net.
;
; The marker file IS the fast/normal state, no separate variable needed: set_fast.ps1/ToggleTabletDisplayMode create it, set_normal.ps1/ToggleTabletDisplayMode delete it.
;
; Loop+Sleep rather than SetTimer, deliberately: mirrors Watchdog.ahk, whose own comment explains why a SetTimer-based version doesn't stay resident reliably for a script this minimal (nothing else in its auto-execute section keeping it alive).
; BackgroundAutomations.ahk's SetTimer usage is fine specifically because that script has other things (OnMessage hooks etc.) keeping it resident - not a contradiction, a different situation.

SunshineScriptsDir      := PATH_SUNSHINE_SCRIPTS
MarkerFile              := SunshineScriptsDir "\.fast_since"
NormalScript            := SunshineScriptsDir "\set_normal.ps1"
SunshineLog             := PATH_SUNSHINE_LOG
LogsDir                 := A_ScriptDir "\Logs"
if !FileExist(LogsDir)
    FileCreateDir, %LogsDir%
LogFile                 := LogsDir "\SunshineMouseWatchdog.log"
ManualFlag              := A_Temp "\sunshine_manual_switch.flag"
QuitFlag                := SunshineScriptsDir "\.session_quit"
CheckIntervalMs         := 1500  ; halved: faster quit-flag detection (1.5s) without hammering the CPU
MaxFastHours            := 8
MinFastAgeSec           := 5 ; grace period after marker creation before disconnect-checks may act
RequiredLogStreak       := 16 ; 16 polls x 1.5s = 24s grace window so Pause/Back doesn't trigger a restore; Quit bypasses this via QuitFlag
RequiredOfflineStreak   := 10 ; Tailscale is a weaker signal, require ~15s of continuous offline
RequiredConnectStreak   := 1 ; symmetric with RequiredLogStreak: CLIENT CONNECTED is equally authoritative

LogDisconnectedStreak := 0
OfflineStreak := 0
ConnectStreak := 0

global g_LastWakeLogSize := 0
OnMessage(0x0218, "SunshineWatchdog_WM_POWERBROADCAST")

Loop
{
    ; PRIORITY 0: Sunshine undo hook fired = explicit session Quit (instant restore, no streak needed).
    ; set_normal.ps1 creates this flag only when called by Sunshine's own undo hook, never by this watchdog.
    ; skipScript:=true prevents ForceNormal from re-invoking set_normal.ps1, which would re-create the flag and cause a cascade loop.
    if FileExist(QuitFlag)
    {
        FileDelete, %QuitFlag%
        SunshineWatchdog_ForceNormal("Sunshine executed undo hook: explicit Quit", true)
        LogDisconnectedStreak := 0
        OfflineStreak := 0
        Sleep, % CheckIntervalMs
        continue
    }

    ; MANUAL OVERRIDE: BasicTasks.ahk's Win+Alt+P (ToggleTabletDisplayMode) writes this separate
    ; ManualFlag file (A_Temp\sunshine_manual_switch.flag) the instant the user manually switches
    ; into tablet mode - a manual toggle isn't tied to a Sunshine session at all, so the log/
    ; Tailscale checks below would be answering the wrong question ("did the OLD session end")
    ; when what actually matters is "has the user had time to open Moonlight yet". A 20s bounded
    ; window (not indefinite-until-toggled-back) is enough to cover that startup gap without
    ; permanently disabling the disconnect checks if the user toggles to tablet mode and never
    ; actually streams.
    ; Check manual switch grace flag (gives user 20s to connect Moonlight after manual toggle)
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

    LastEvent := SunshineWatchdog_LastClientEvent()

    ; 1. CLIENT CONNECTED: active streaming session
    if (LastEvent = "CONNECTED")
    {
        if FileExist(ManualFlag)
            FileDelete, %ManualFlag%

        LogDisconnectedStreak := 0
        OfflineStreak := 0

        ; If mouse is currently normal (marker absent), boost it to fast for this session
        if (!FileExist(MarkerFile))
        {
            ; Suppress stale pre-wake CONNECTED log events until new log lines are written after wake
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
                    g_LastWakeLogSize := 0 ; Fresh post-wake activity logged, clear snapshot
            }

            if (isStalePreWake)
            {
                ConnectStreak := 0
            }
            else
            {
                ConnectStreak++
                if (ConnectStreak >= RequiredConnectStreak)
                {
                    SunshineWatchdog_ForceFast("sunshine.log shows CLIENT CONNECTED while mouse was normal (resume without a fresh prep-cmd do)")
                    ConnectStreak := 0
                }
            }
        }
        else
            ConnectStreak := 0
    }
    ; 2. CLIENT DISCONNECTED: stream paused or terminated on tablet
    else if (LastEvent = "DISCONNECTED")
    {
        ConnectStreak := 0

        if (!isManualGrace)
        {
            LogDisconnectedStreak++
            if (LogDisconnectedStreak >= RequiredLogStreak)
            {
                ; If mouse is fast (MarkerFile exists), restore mouse speed to 10 without forcing a display switch
                if FileExist(MarkerFile)
                {
                    SunshineWatchdog_RestoreMouseNormal("sunshine.log shows CLIENT DISCONNECTED (stream paused/ended)")
                }
                LogDisconnectedStreak := 0
                OfflineStreak := 0
            }
        }
        else
            LogDisconnectedStreak := 0
    }
    ; 3. Fallback: Tailscale reachability check when log has no active answer.
    ; Secondary, weaker signal - only consulted when the log has no authoritative answer this tick
    ; (skipped when CONNECTED, since that stronger signal must never be overridden by the flappier
    ; Tailscale read; also skipped during isManualGrace for the same "wrong question" reason as the
    ; DISCONNECTED branch above).
    ; Tailscale can read this tablet offline for 30-45s roughly every 45-90s even while the session
    ; never actually disconnects per sunshine.log - left unguarded, this flapped forced-normal/
    ; forced-FAST repeatedly over several hours while CONNECTED held the whole time.
    ; RequiredOfflineStreak restores that original intent (secondary path only fires once the
    ; offline reading is sustained, not on ordinary Tailscale noise), not a new behavior.
    else
    {
        ConnectStreak := 0
        if (!isManualGrace && (FileExist(MarkerFile) || IsExternalDisplayActive()))
        {
            if SunshineWatchdog_TabletReachable()
                OfflineStreak := 0
            else
            {
                OfflineStreak++
                if (OfflineStreak >= RequiredOfflineStreak)
                {
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
            SunshineWatchdog_ForceNormal("stuck fast " NowCopy "h+, past the " MaxFastHours "h ceiling")
            LogDisconnectedStreak := 0
            OfflineStreak := 0
        }
    }

    Sleep, % CheckIntervalMs
}

; Returns "CONNECTED", "DISCONNECTED", or "" (log missing/unreadable/no event found yet - caller treats "" as fail-open, i.e. does not count toward the disconnected streak).
; Reads only the log's tail rather than the whole file, since sunshine.log grows unbounded across the service's lifetime.
SunshineWatchdog_LastClientEvent() {
    global SunshineLog
    if !FileExist(SunshineLog)
        return ""

    file := FileOpen(SunshineLog, "r")
    if !IsObject(file)
        return ""
    Len := file.Length
    TailBytes := 20000 ; generous margin for the setup-line burst Sunshine logs between connect/disconnect events
    SeekTo := (Len > TailBytes) ? (Len - TailBytes) : 0
    file.Seek(SeekTo, 0)
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

    if (LastConnectedPos = 0 && LastDisconnectedPos = 0)
        return ""
    return (LastDisconnectedPos > LastConnectedPos) ? "DISCONNECTED" : "CONNECTED"
}

; Reads Tailscale's own view of the tablet's reachability via "tailscale status" text.
; Correctly shows a device as "offline" on a real power-off, but stays "active" straight through a Sunshine-level pause - exactly why this is the secondary signal, not the primary one.
SunshineWatchdog_TabletReachable() {
    global SUNSHINE_TABLET_TAILSCALE_IP, PATH_TAILSCALE_EXE
    if (!SUNSHINE_TABLET_TAILSCALE_IP)
        return true ; not configured in LocalPaths.ahk - fail open, rely on the other signals

    TailscaleExe := PATH_TAILSCALE_EXE
    if (!TailscaleExe || !FileExist(TailscaleExe))
        return true ; can't check - fail open rather than false-trigger

    TmpFile := A_Temp "\sunshine_watchdog_ts_status.tmp"
    RunWait, %ComSpec% /c ""%TailscaleExe%" status > "%TmpFile%" 2>&1",, Hide
    StatusOutput := ""
    FileRead, StatusOutput, %TmpFile%
    FileDelete, %TmpFile%

    if !InStr(StatusOutput, SUNSHINE_TABLET_TAILSCALE_IP)
        return true ; peer not found in status output at all - fail open

    Loop, Parse, StatusOutput, `n, `r
        if InStr(A_LoopField, SUNSHINE_TABLET_TAILSCALE_IP)
            return !InStr(A_LoopField, "offline")

    return true
}

SunshineWatchdog_ForceNormal(reason, skipScript := false) {
    global NormalScript, LogFile, MarkerFile

    ; 1. Immediate native display switch back to PC Screen Only (1 = Internal 1080p @ 144Hz panel)
    ; Runs in the interactive user session so the laptop screen re-engages the moment the stream ends
    Run, DisplaySwitch.exe 1,, Hide

    ; 2. Instant Win32 restore of mouse speed to 10 and acceleration ON (avoids PowerShell startup delay)
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 3. Clean up marker and manual grace files immediately
    if (MarkerFile)
        FileDelete, %MarkerFile%
    FileDelete, % A_Temp "\sunshine_manual_switch.flag"

    ; 4. Asynchronously invoke set_normal.ps1 to keep Sunshine script state synchronized.
    ;    Skipped when called from the quit-flag path (skipScript=true): set_normal.ps1 already ran
    ;    (it created the quit flag), so calling it again would re-create the flag and cause a cascade loop.
    if (!skipScript && NormalScript && FileExist(NormalScript))
        Run, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%NormalScript%",, Hide

    ; 5. Restore Simple Sticky Notes to exact laptop coordinates once 1080p DWM settles
    ApplyLaptopStickyNotesLayout(1200)

    FileAppend, % A_Now " - forced normal: " reason "`n", %LogFile%
}

SunshineWatchdog_ForceFast(reason) {
    global SunshineScriptsDir, LogFile, MarkerFile

    ; 1. Instant Win32 boost of mouse speed to 20 and acceleration OFF (avoids PowerShell startup delay)
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(0, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 2. Touch marker file immediately
    if (MarkerFile) {
        FileDelete, %MarkerFile%
        FileAppend,, %MarkerFile%
    }

    ; 3. Asynchronously invoke set_fast.ps1 to keep Sunshine script state synchronized
    FastScript := SunshineScriptsDir "\set_fast.ps1"
    if (FileExist(FastScript))
        Run, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%FastScript%",, Hide

    FileAppend, % A_Now " - forced FAST: " reason "`n", %LogFile%
}

; Restores mouse speed to 10 and acceleration ON (pointer precision ON) without touching displays or Sticky Notes layout.
; Used during Sunshine pause / disconnect streaks so the host laptop mouse is immediately usable at normal speed.
SunshineWatchdog_RestoreMouseNormal(reason) {
    global LogFile, MarkerFile

    ; 1. Instant Win32 restore of mouse speed to 10 and acceleration ON (avoids PowerShell startup delay)
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(1, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; 2. Clean up marker and manual grace files immediately
    if (MarkerFile)
        FileDelete, %MarkerFile%
    FileDelete, % A_Temp "\sunshine_manual_switch.flag"

    FileAppend, % A_Now " - mouse restored normal: " reason "`n", %LogFile%
}

; Win32 WM_POWERBROADCAST (0x0218) handler: snapshots log file size on wake to suppress stale pre-wake CONNECTED events
SunshineWatchdog_WM_POWERBROADCAST(wParam, lParam) {
    global g_LastWakeLogSize, SunshineLog
    if (wParam = 18 || wParam = 7)
    {
        if (SunshineLog && FileExist(SunshineLog))
        {
            file := FileOpen(SunshineLog, "r")
            if IsObject(file)
            {
                g_LastWakeLogSize := file.Length
                file.Close()
            }
        }
    }
}


