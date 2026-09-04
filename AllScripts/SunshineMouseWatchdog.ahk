#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\local_paths.ahk ; SUNSHINE_TABLET_TAILSCALE_IP lives here (gitignored)
#SingleInstance force
DetectHiddenWindows, On

; Safety net for the Sunshine mouse-speed boost (set_fast.ps1/set_normal.ps1 under
; the Sunshine scripts directory). Those two scripts already handle
; the normal tablet connect/quit cycle correctly via Sunshine's own prep-cmd do/undo hooks
; -- this script exists for the case that leaves it stuck fast: Sunshine deliberately
; keeps a dropped session resumable rather than firing "undo" (confirmed against
; LizardByte/Sunshine's own docs), and separately, Moonlight backgrounding/pausing on the
; tablet does not disconnect it from the network at all -- confirmed live: sunshine.log
; shows "CLIENT DISCONNECTED" for a paused session while "tailscale status" simultaneously
; still shows the tablet as fully "active" with live tx/rx traffic. Tailscale reachability
; CANNOT see a Sunshine-level pause; it only helps for a true network-level drop (this
; machine's own earlier test: the TV genuinely goes "offline" in Tailscale when powered
; off, so that check stays in as a second, independent trigger, not the primary one).
;
; PRIMARY signal: tail sunshine.log for the most recent "CLIENT CONNECTED" vs
; "CLIENT DISCONNECTED" line. This is Sunshine's own authoritative event, not an inferred
; proxy, and is what actually fires the instant a session pauses -- unlike Tailscale
; reachability, which the live test above proved does not change during a pause at all.
;
; SECONDARY signal: tablet's Tailscale peer offline for RequiredOfflineStreak consecutive
; polls -- kept as a second, independent path in case the log is ever unreadable/rotated.
;
; TERTIARY/last-resort: fast-mode older than MaxFastHours regardless of the above, in case
; both signals above somehow miss it. Set generously since long legitimate remote-desktop
; sessions are the normal case here, not the exception.
;
; BI-DIRECTIONAL: a RESUMED session (tapping the Desktop tile again after a pause) does
; NOT re-fire prep-cmd's "do" -- confirmed against the full live sunshine.log across 6
; real disconnect/reconnect cycles today, 3 of them resumes (one after a 7m51s gap), every
; one logging "CLIENT CONNECTED" with zero "Executing Do Cmd" line. So this script also
; forces FAST when the marker is absent (mouse currently normal) and the log's latest
; event is CONNECTED -- symmetric with the existing force-normal path, same log signal,
; same authoritative reasoning. This can never double-fire on a genuinely fresh connect:
; prep-cmd's own "do" always creates the marker 2-5s before CLIENT CONNECTED logs
; (confirmed timing, every observed fresh-start cycle), so by the time this script would
; see CONNECTED, the marker already exists and the "marker absent" precondition is false.
;
; RACE FIX: that same 2-5s Do-to-Connected gap is a hazard in the OTHER direction too --
; if a poll lands in that gap, the marker exists (just created) but the log's latest event
; is still the PREVIOUS session's DISCONNECTED, which would incorrectly force-normal a
; session that's still starting up. MinFastAgeSec below skips both disconnect-checks
; entirely until the marker is old enough that this can't happen.
;
; The marker file IS the fast/normal state, no separate variable needed: set_fast.ps1
; creates it, set_normal.ps1 deletes it.
;
; Loop+Sleep rather than SetTimer, deliberately: mirrors Watchdog.ahk, whose own comment
; documents a SetTimer-based version measured to not stay resident reliably for a script
; this minimal (nothing else in its auto-execute section keeping it alive).
; BackgroundAutomations.ahk's SetTimer usage is fine specifically because that script has
; other things (OnMessage hooks etc.) keeping it resident -- not a contradiction, a
; different situation.

SunshineScriptsDir      := PATH_SUNSHINE_SCRIPTS ? PATH_SUNSHINE_SCRIPTS : "D:\Software\0_Settings\Windows 11\Scripts\sunshine"
MarkerFile              := SunshineScriptsDir "\.fast_since"
NormalScript            := SunshineScriptsDir "\set_normal.ps1"
SunshineLog             := "C:\Program Files\Sunshine\config\sunshine.log"
LogsDir                 := A_ScriptDir "\Logs"
if !FileExist(LogsDir)
    FileCreateDir, %LogsDir%
LogFile                 := LogsDir "\SunshineMouseWatchdog.log"
CheckIntervalMs         := 15000
MaxFastHours            := 8
MinFastAgeSec           := 20 ; grace period after marker creation before disconnect-checks may act (see RACE FIX above)
RequiredLogStreak       := 1 ; log event is authoritative -- act on first confirmed read
RequiredOfflineStreak   := 2 ; Tailscale is a weaker signal -- require ~30s of continuous offline
RequiredConnectStreak   := 1 ; symmetric with RequiredLogStreak -- CLIENT CONNECTED is equally authoritative

LogDisconnectedStreak := 0
OfflineStreak := 0
ConnectStreak := 0

Loop
{
    if FileExist(MarkerFile)
    {
        FileGetTime, FastSince, %MarkerFile%, M
        NowCopy := A_Now
        EnvSub, NowCopy, %FastSince%, Hours

        if (NowCopy >= MaxFastHours)
        {
            SunshineWatchdog_ForceNormal("stuck fast " NowCopy "h+, past the " MaxFastHours "h ceiling")
            LogDisconnectedStreak := 0, OfflineStreak := 0
            Sleep, % CheckIntervalMs
            continue
        }

        FastAgeSec := A_Now
        EnvSub, FastAgeSec, %FastSince%, Seconds
        if (FastAgeSec < MinFastAgeSec)
        {
            ; too fresh to trust either disconnect-check yet -- see RACE FIX above
            LogDisconnectedStreak := 0, OfflineStreak := 0
            Sleep, % CheckIntervalMs
            continue
        }

        ; Primary: Sunshine's own log
        LastEvent := SunshineWatchdog_LastClientEvent()
        if (LastEvent = "DISCONNECTED")
        {
            LogDisconnectedStreak++
            if (LogDisconnectedStreak >= RequiredLogStreak)
            {
                SunshineWatchdog_ForceNormal("sunshine.log shows CLIENT DISCONNECTED as the latest event")
                LogDisconnectedStreak := 0, OfflineStreak := 0
                Sleep, % CheckIntervalMs
                continue
            }
        }
        else
            LogDisconnectedStreak := 0

        ; Secondary: tablet's Tailscale reachability (independent path, weaker signal)
        if SunshineWatchdog_TabletReachable()
            OfflineStreak := 0
        else
        {
            OfflineStreak++
            if (OfflineStreak >= RequiredOfflineStreak)
            {
                SunshineWatchdog_ForceNormal("tablet unreachable on Tailscale for " (OfflineStreak * CheckIntervalMs / 1000) "s+")
                LogDisconnectedStreak := 0, OfflineStreak := 0
            }
        }
        ConnectStreak := 0 ; not relevant while marker is present
    }
    else
    {
        ; Marker absent (mouse currently normal) -- check for a RESUME that prep-cmd's own
        ; "do" never re-triggered on (see BI-DIRECTIONAL above).
        LogDisconnectedStreak := 0, OfflineStreak := 0
        LastEvent := SunshineWatchdog_LastClientEvent()
        if (LastEvent = "CONNECTED")
        {
            ConnectStreak++
            if (ConnectStreak >= RequiredConnectStreak)
            {
                SunshineWatchdog_ForceFast("sunshine.log shows CLIENT CONNECTED while mouse was normal (resume without a fresh prep-cmd do)")
                ConnectStreak := 0
            }
        }
        else
            ConnectStreak := 0
    }

    Sleep, % CheckIntervalMs
}

; Returns "CONNECTED", "DISCONNECTED", or "" (log missing/unreadable/no event found yet --
; caller treats "" as fail-open, i.e. does not count toward the disconnected streak).
; Reads only the log's tail rather than the whole file, since sunshine.log grows
; unbounded across the service's lifetime.
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

; Reads Tailscale's own view of the tablet's reachability via "tailscale status" text
; (confirmed live to correctly show the TV as "offline" on a real power-off -- but also
; confirmed live to show the tablet as "active" straight through a Sunshine-level pause,
; which is exactly why this is the secondary signal, not the primary one).
SunshineWatchdog_TabletReachable() {
    global SUNSHINE_TABLET_TAILSCALE_IP
    if (!SUNSHINE_TABLET_TAILSCALE_IP)
        return true ; not configured in local_paths.ahk -- fail open, rely on the other signals

    TailscaleExe := "C:\Program Files\Tailscale\tailscale.exe"
    if !FileExist(TailscaleExe)
        return true ; can't check -- fail open rather than false-trigger

    TmpFile := A_Temp "\sunshine_watchdog_ts_status.tmp"
    RunWait, %ComSpec% /c ""%TailscaleExe%" status > "%TmpFile%" 2>&1",, Hide
    StatusOutput := ""
    FileRead, StatusOutput, %TmpFile%
    FileDelete, %TmpFile%

    if !InStr(StatusOutput, SUNSHINE_TABLET_TAILSCALE_IP)
        return true ; peer not found in status output at all -- fail open

    Loop, Parse, StatusOutput, `n, `r
        if InStr(A_LoopField, SUNSHINE_TABLET_TAILSCALE_IP)
            return !InStr(A_LoopField, "offline")

    return true
}

SunshineWatchdog_ForceNormal(reason) {
    global NormalScript, LogFile
    RunWait, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%NormalScript%",, Hide
    FileAppend, % A_Now " - forced normal: " reason "`n", %LogFile%
}

SunshineWatchdog_ForceFast(reason) {
    global SunshineScriptsDir, LogFile
    FastScript := SunshineScriptsDir "\set_fast.ps1"
    RunWait, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%FastScript%",, Hide
    FileAppend, % A_Now " - forced FAST: " reason "`n", %LogFile%
}
