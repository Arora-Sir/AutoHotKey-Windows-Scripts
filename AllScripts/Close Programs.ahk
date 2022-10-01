; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; Alt+F4 --> Close currently active program
; Alt+Ctr+F4 --> Close All Programs

;Anydesk CiscoWebx Cortana Discord Filmora HotspotSheild IDM Opera MicrosoftTeams Skype Stremio Telegram UnityHub uTorrent wps Zoom

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

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

    ; Previously used like this!!
    ; if WinActive("ahk_exe Zoom.exe")
    ; {
    ;     ;if WinExist("Zoom Meeting")
    ;     ;	{
    ;     ;	    return
    ;     ;	}
    ;     ;else
    ;     ;	{
    ;           Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
    ;     ;	}
    ; }
}

CLoseAllPrograms()
{
    WinGet, id, list, , , Program Manager
    Loop, %id%
    {
        StringTrimRight, this_id, id%a_index%, 0
        WinGetTitle, this_title, ahk_id %this_id%
        winclose,%this_title%
    }
    return
}

CLoseSpecificPrograms()
{
    if WinExist("ahk_exe IDMan.exe")
    {
        Run cmd.exe /c taskkill /F /IM IDMan.exe ,,Hide
    }
    if WinExist("ahk_exe stremio.exe")
    {
        Run cmd.exe /c taskkill /F /IM stremio.exe ,,Hide
    }
    if WinExist("ahk_exe uTorrent.exe")
    {
        Run cmd.exe /c taskkill /F /IM uTorrent.exe ,,Hide
    }
    if WinExist("ahk_exe wps.exe")
    {
        Run cmd.exe /c taskkill /F /IM wpscenter.exe & taskkill /F /IM wpscloudsvr.exe,,Hide
    }
    if WinExist("ahk_exe Teams.exe")
    {
        Run cmd.exe /c taskkill /F /IM Teams.exe ,,Hide
    }
    return
}


$!F4:: CLoseCurrentlyActiveScreen() ;{ <-- CLose Currently Active Screen
$!+F4:: CLoseSpecificPrograms() ;{ <-- CLose Specific Programs
$!^F4:: CLoseAllPrograms() ;{ <-- CLose All Program