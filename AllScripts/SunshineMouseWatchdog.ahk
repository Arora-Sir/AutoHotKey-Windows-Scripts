#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\LocalPaths.ahk ; SUNSHINE_TABLET_TAILSCALE_IP lives here (gitignored)
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
; RACE FIX: that same do-to-connected gap is a hazard in the OTHER direction too. If a poll lands in that gap, the marker exists (just created) but the log's latest event is still the PREVIOUS session's DISCONNECTED, which would incorrectly force-normal a session that's still starting up.
; MinFastAgeSec below skips both disconnect-checks entirely until the marker is old enough that this can't happen.
;
; DISPLAY AUTO-SWITCH ON CONNECT: tried and reverted (2026-09-08).
; Switching to tablet mode (DisplaySwitch.exe 4) in this same fresh-marker window caused a hang, because Sunshine's own connect-time transition briefly puts the display in Duplicate mode first and the two display changes appear to race.
; Connect-side switching stays manual (Win+Shift+P / the BasicTasks tray items) for this reason.
; Only the disconnect-side auto-switch-to-laptop below survived, since a disconnect never coincides with an in-flight Sunshine display transition the same way.
;
; MANUAL OVERRIDE: BasicTasks.ahk's Win+Shift+P (ToggleTabletDisplayMode) also owns this marker, for a manual tablet-mode toggle that has nothing to do with an actual Sunshine session.
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
SunshineLog             := "C:\Program Files\Sunshine\config\sunshine.log"
LogsDir                 := A_ScriptDir "\Logs"
if !FileExist(LogsDir)
    FileCreateDir, %LogsDir%
LogFile                 := LogsDir "\SunshineMouseWatchdog.log"
CheckIntervalMs         := 15000
MaxFastHours            := 8
MinFastAgeSec           := 20 ; grace period after marker creation before disconnect-checks may act (see RACE FIX above)
RequiredLogStreak       := 1 ; log event is authoritative -- act on first confirmed read
RequiredOfflineStreak   := 8 ; Tailscale is a weaker signal require ~2min of continuous offline. Was 2 (~30s) until 2026-09-06.
                             ; Tailscale can flap this tablet "offline" for 30-45s roughly every 45-90s even mid-session, so 30s was firing on pure noise.
                             ; The LastEvent != "CONNECTED" gate below is the primary fix; this bump is defense-in-depth.
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

        ; MANUAL OVERRIDE: BasicTasks.ahk's Win+Shift+P (ToggleTabletDisplayMode) writes "manual" into this same marker instead of leaving it empty the way set_fast.ps1 does.
        ; A manual toggle isn't tied to a Sunshine session at all, so the log/Tailscale checks below would be answering the wrong question ("did the OLD session end") and could clobber a deliberate choice off a stale sunshine.log entry or a flaky Tailscale read.
        ; Deferred to entirely until the user toggles back (or the lid-reopen recovery in BasicTasks.ahk fires) - MaxFastHours above still applies regardless, as the leave-it-on-forever safety net.
        MarkerContent := ""
        FileRead, MarkerContent, %MarkerFile%
        if (MarkerContent = "manual")
        {
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

        ; Secondary: tablet's Tailscale reachability (independent path, weaker signal).
        ; Only consulted when the log itself has no authoritative answer this tick - skip entirely when the log's latest event is CONNECTED, since that stronger signal must never be overridden by the flappier Tailscale read.
        ; Tailscale can read this tablet offline for 30-45s roughly every 45-90s even while the session never actually disconnects per sunshine.log, which left unguarded can flap forced-normal/forced-FAST repeatedly over several hours while CONNECTED holds the whole time.
        ; This restores the ORIGINAL intent above (secondary path is only for when the log is unreadable/rotated), not a new behavior.
        if (LastEvent != "CONNECTED")
        {
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
        }
        else
            OfflineStreak := 0
        ConnectStreak := 0 ; not relevant while marker is present
    }
    else
    {
        ; Marker absent (mouse currently normal) - check for a RESUME that prep-cmd's own "do" never re-triggered on (see BI-DIRECTIONAL above).
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
    global SUNSHINE_TABLET_TAILSCALE_IP
    if (!SUNSHINE_TABLET_TAILSCALE_IP)
        return true ; not configured in LocalPaths.ahk -- fail open, rely on the other signals

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
    ; Also switches the display back to PC-only, mirroring BasicTasks.ahk's manual Win+Shift+P toggle's own laptop branch (DisplaySwitch.exe 1).
    ; set_normal.ps1 deliberately never touches displays itself - it runs in Sunshine's own service context, where that risks a GUI popup (see the Sunshine scripts README's "black screen" note).
    ; This AHK script runs in the interactive user session instead, same as BasicTasks.ahk, so it can safely do this where set_normal.ps1 cannot.
    ; One-way only: switching TO tablet mode on connect was tried and reverted - it raced with Sunshine's own connect-time Duplicate-mode transition and caused a hang (see DISPLAY AUTO-SWITCH ON CONNECT in the header).
    Run, DisplaySwitch.exe 1,, Hide
    FileAppend, % A_Now " - forced normal: " reason "`n", %LogFile%
}

SunshineWatchdog_ForceFast(reason) {
    global SunshineScriptsDir, LogFile
    FastScript := SunshineScriptsDir "\set_fast.ps1"
    RunWait, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%FastScript%",, Hide
    FileAppend, % A_Now " - forced FAST: " reason "`n", %LogFile%
}

