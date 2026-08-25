#Requires AutoHotkey v1.1
#NoEnv
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
#Include *i %A_ScriptDir%\..\local_paths.ahk ; Include local custom paths if present (ignored by Git)
#SingleInstance force
DetectHiddenWindows, On

; Generic multi-app watchdog. Polls every CheckIntervalMs and relaunches any app configured
; in WATCHDOG_APPS (defined in local_paths.ahk, gitignored -- keeps personal folder paths
; out of git) that isn't currently running. One always-running process cheaply polls all
; configured apps via Process,Exist, instead of one blocking Process,WaitClose sub-process
; per app -- the latter would require N instances of this same script file, which collides
; both with #SingleInstance's path-only dedup and with StartupScript.ahk's own WinClose
; dedup (also path+class keyed), so it isn't a clean fit here. Lower CheckIntervalMs instead
; of switching designs if faster reaction is ever needed.
;
; Loop+Sleep rather than SetTimer deliberately: a SetTimer-based version was measured to
; not stay resident reliably (process observed exiting right after auto-execute completed,
; timer never fired) -- a real blocking loop, matching the pattern the original
; TrafficMonitorWatchdog.ahk used, was confirmed to actually stay running.
CheckIntervalMs := 10000

if !IsObject(WATCHDOG_APPS)
    WATCHDOG_APPS := [] ; no local_paths.ahk / nothing configured -> idle, watches nothing

Loop
{
    for index, app in WATCHDOG_APPS
    {
        if !(app.name && app.path) ; skip malformed entries instead of erroring on blank Run
            continue
        appName := app.name
        Process, Exist, %appName%
        if !ErrorLevel
        {
            cmd := app.path
            exeOnly := cmd
            if RegExMatch(cmd, "^""([^""]+)""", match)
                exeOnly := match1
            else if RegExMatch(cmd, "^(.*?\.exe)(?:\s|$)", match)
                exeOnly := match1
            SplitPath, exeOnly, , appDir

            if (SubStr(cmd, 1, 1) != """" && InStr(cmd, " "))
                cmd := """" cmd """"
            try Run, % cmd, % appDir
        }
    }
    Sleep, % CheckIntervalMs
}
