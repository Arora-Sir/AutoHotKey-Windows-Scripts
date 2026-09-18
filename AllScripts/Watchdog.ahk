#Requires AutoHotkey v2.0
; Suppress individual child tray icon so only StartupScript.ahk's master icon is visible.
#NoTrayIcon
; v2: #Persistent removed as a directive, replaced by the Persistent() function (see LocalPaths.ahk for the empirical note on why).
Persistent()
SendMode("Input")
SetWorkingDir(A_ScriptDir)
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
; v2: SharedHelpers.ahk included directly (not just transitively through LocalPaths.ahk, which is
; gitignored/optional) so this script keeps its fleet control handler even if LocalPaths.ahk is ever
; absent. Its own independent HandleFleetControlMessage copy (previously here) was removed: having both
; this include and that copy in the same merged script broke load with "function declaration conflicts
; with an existing Func". See LocalPaths.ahk for the full explanation.
#Include %A_ScriptDir%\SharedHelpers.ahk
#SingleInstance force
DetectHiddenWindows(true)

; Generic multi-app watchdog.
; Polls every CheckIntervalMs and relaunches any app configured in WATCHDOG_APPS (defined in LocalPaths.ahk, gitignored: keeps personal folder paths out of git) that isn't currently running.
; One always-running process cheaply polls all configured apps via ProcessExist, instead of one blocking ProcessWaitClose sub-process per app (the latter would require N instances of this same script file, which collides both with #SingleInstance's path-only dedup and with StartupScript.ahk's own WinClose dedup, so it isn't a clean fit here).
; Lower CheckIntervalMs instead of switching designs if faster reaction is ever needed.
;
; Loop+Sleep rather than SetTimer deliberately: a SetTimer-based version does not stay resident reliably for a script this minimal (the process exits right after auto-execute completes, before the timer ever fires).
; A real blocking loop, matching the pattern the original TrafficMonitorWatchdog.ahk used, stays running correctly.
;
; This whole polling approach replaced an earlier attempt using Task Scheduler's own RestartOnFailure action: it correctly detected a crash's failure exit code but never actually queued the restart: unreliable in practice, not just here.
CheckIntervalMs := 10000

global g_IsWatchdogSessionEnding := false

OnMessage(0x0011, Watchdog_WM_QUERYENDSESSION)
OnMessage(0x0016, Watchdog_WM_ENDSESSION)
OnExit(Watchdog_OnExit)

Watchdog_WM_QUERYENDSESSION(wParam, lParam, *) {
    global g_IsWatchdogSessionEnding
    g_IsWatchdogSessionEnding := true
    ExitApp()
    return true
}

Watchdog_WM_ENDSESSION(wParam, lParam, *) {
    global g_IsWatchdogSessionEnding
    g_IsWatchdogSessionEnding := true
    ExitApp()
}

Watchdog_OnExit(ExitReason, ExitCode) {
    global g_IsWatchdogSessionEnding
    g_IsWatchdogSessionEnding := true
}

if !IsObject(WATCHDOG_APPS)
    WATCHDOG_APPS := [] ; no LocalPaths.ahk / nothing configured -> idle, watches nothing

Loop
{
    if (g_IsWatchdogSessionEnding)
        break

    for index, app in WATCHDOG_APPS
    {
        if (g_IsWatchdogSessionEnding)
            break
        if !(app.name && app.path) ; skip malformed entries instead of erroring on blank Run
            continue
        appName := app.name
        if !ProcessExist(appName)
        {
            cmd := app.path
            exeOnly := cmd
            if RegExMatch(cmd, '^"([^"]+)"', &match)
                exeOnly := match[1]
            else if RegExMatch(cmd, "^(.*?\.exe)(?:\s|$)", &match)
                exeOnly := match[1]
            SplitPath(exeOnly, , &appDir)

            if (SubStr(cmd, 1, 1) != '"' && InStr(cmd, " "))
                cmd := '"' cmd '"'
            try Run(cmd, appDir, "Hide")
        }
    }
    Sleep(CheckIntervalMs)
}
