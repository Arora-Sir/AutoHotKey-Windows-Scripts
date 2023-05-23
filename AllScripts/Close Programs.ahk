; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; Alt+F4 --> Close currently active program
; Alt+Shift+F4 --> Close specific active program
; Alt+Ctr+F4 --> Close All Programs

;Anydesk CiscoWebx Cortana Discord Filmora HotspotSheild IDM Opera MicrosoftTeams Skype Stremio Telegram UnityHub uTorrent wps Zoom

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

;Ensures that programs also gets killed from the background processes
CLoseCurrentlyActiveScreen()
{
    WinGet, Active_ID, ID, A
    WinGet, Active_Process, ProcessName, ahk_id %Active_ID%

    switch Active_Process
    {
        Case "AnyDesk.exe": Run cmd.exe /c taskkill /F /IM AnyDesk.exe ,,Hide
        Case "CiscoCollabHost.exe": Run cmd.exe /c taskkill /F /IM Ciscowebexstart.exe & taskkill /F /IM CiscoCollabHost.exe & taskkill /F /IM webexmta.exe & taskkill /F /IM washost.exe & taskkill /F /IM atmgr.exe & taskkill /F /IM webex.exe ,,Hide
        Case "ApplicationFrameHost.exe": Run cmd.exe /c taskkill /F /IM Cortana.exe ,,Hide ;Cortana
        Case "Discord.exe": Run cmd.exe /c taskkill /F /IM Discord.exe ,,Hide
        Case "IDMan.exe": Run cmd.exe /c taskkill /F /IM IDMan.exe ,,Hide
        Case "Opera.exe": Run cmd.exe /c taskkill /F /IM Opera.exe & taskkill /F /IM browser_assistant.exe,,Hide
        Case "Teams.exe": Run cmd.exe /c taskkill /F /IM Teams.exe ,,Hide
        Case "msteams.exe": Run cmd.exe /c taskkill /F /IM msteams.exe ,,Hide
        Case "stremio.exe": Run cmd.exe /c taskkill /F /IM stremio.exe ,,Hide
        Case "Skype.exe": Run cmd.exe /c taskkill /F /IM Skype.exe ,,Hide
        Case "Telegram.exe": Run cmd.exe /c taskkill /F /IM Telegram.exe ,,Hide
        Case "Unity Hub.exe": Run cmd.exe /c taskkill /F /IM "Unity Hub.exe" ,,Hide
        Case "uTorrent.exe": Run cmd.exe /c taskkill /F /IM uTorrent.exe ,,Hide
        Case "Wondershare Filmora X.exe": Run cmd.exe /c taskkill /F /IM WSHelper.exe ,,Hide
        Case "wps.exe": Run cmd.exe /c taskkill /F /IM wpscenter.exe & taskkill /F /IM wpscloudsvr.exe,,Hide
        Case "Zoom.exe": Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
 	    Case "hsscp.exe": Run cmd.exe /c taskkill /F /IM hsscp.exe ,,Hide ;HotSpot Sheild
        Default:
    }
    
    send !{F4}
    return
}
CLoseAllPrograms()
{
    DetectHiddenWindows, on
    CLoseSpecificPrograms()
    DetectHiddenWindows, off
    WinGet, mylist, list, , , ,Program Manager
    str := ""
    Loop % mylist {
        hwnd := mylist%A_Index%
        WinGetTitle, title, % "ahk_id " hwnd
        if (title == "")
        {
            continue
        }
        msgbox % str
        str .= "HWND: " hwnd ", Title: " title "`n"
        WinClose % "ahk_id " hwnd
        }
        ; msgbox % str
    return

    ; IfEqual, AppName, "AutoHotKey.exe"
    ; Winget,AppName,ProcessName,ahk_id %this_id%
    ; if AppName = "AutoHotkey.exe"
    ; {
    ;     MsgBox, [ Options, Title, Text, Timeout]
    ;     Continue
    ; }
    ; else if AppName = "Zoom.exe"
    ; {
    ;     Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
    ;     Continue
    ; }
}

CLoseSpecificPrograms()
{
    ; WinClose, ahk_exe stremio.exe
    if WinExist("ahk_exe IDMan.exe")
    {
        Run cmd.exe /c taskkill /F /IM IDMan.exe ,,Hide
    }

    if WinExist("ahk_exe stremio.exe")
    {
        Run cmd.exe /c taskkill /F /IM stremio.exe ,,Hide
    }

    if WinExist("ahk_exe uTorrent.exe") or WinExist("ahk_exe utorrentie.exe") or WinExist("ahk_exe utorrent.exe")
    {
        Run cmd.exe /c taskkill /F /IM uTorrent.exe & taskkill /F /IM utorrentie.exe & taskkill /F /IM utorrent.exe,,Hide
    }

    if WinExist("ahk_exe wps.exe") or WinExist("ahk_exe wpscloudsvr.exe")
    {
        Run cmd.exe /c taskkill /F /IM wpscenter.exe,,Hide
        Run cmd.exe /c taskkill /F /IM wpscloudsvr.exe,,Hide
    }

    if WinExist("ahk_exe Teams.exe")
    {
        Run cmd.exe /c taskkill /F /IM Teams.exe ,,Hide
    }

    if WinExist("ahk_exe Zoom.exe")
    {
        Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
    }

    ; if WinExist("ahk_class ZPPTMainFrmWndClassEx.exe")
    ; {
    ;     Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
    ; }
    return
}


$!F4:: CLoseCurrentlyActiveScreen() ;{ <-- CLose Currently Active Screen
$!+F4:: CLoseSpecificPrograms() ;{ <-- CLose Specific Programs
$!^F4:: CLoseAllPrograms() ;{ <-- CLose All Program