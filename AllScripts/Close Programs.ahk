; ^ for Ctrl, ! for Alt, # for Win, + for Shift

; Alt+F4 --> Close currently active program
; Alt+Ctr+F4 --> Close All Programs

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

CLoseCurrentlyActiveScreen()
{
    if WinActive("ahk_exe Teams.exe")
    {
        Run cmd.exe /c taskkill /F /IM Teams.exe ,,Hide
    }

    if WinActive("ahk_exe msteams.exe")
    {
        Run cmd.exe /c taskkill /F /IM msteams.exe ,,Hide
    }

    if WinActive("ahk_exe wps.exe")
    {
        ; Run cmd.exe /c taskkill /F /IM wps.exe ,,Hide
        ; Run cmd.exe /c taskkill /F /IM wpspdf.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM wpscenter.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM wpscloudsvr.exe ,,Hide
    }

    if WinActive("ahk_exe Discord.exe")
    {
        Run cmd.exe /c taskkill /F /IM Discord.exe ,,Hide
    }

    if WinActive("ahk_exe ApplicationFrameHost.exe")
    {
        Run cmd.exe /c taskkill /F /IM Cortana.exe ,,Hide
    }

    if WinActive("ahk_exe Skype.exe")
    {
        Run cmd.exe /c taskkill /F /IM Skype.exe ,,Hide
    }

    if WinActive("ahk_exe Wondershare Filmora X.exe")
    {
        Run cmd.exe /c taskkill /F /IM WSHelper.exe ,,Hide
    }
    if WinActive("ahk_exe Opera.exe")
    {
        Run cmd.exe /c taskkill /F /IM Opera.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM browser_assistant.exe ,,Hide
    }
    if WinActive("ahk_exe uTorrent.exe")
    {
        Run cmd.exe /c taskkill /F /IM uTorrent.exe ,,Hide
    }

    if WinActive("ahk_exe Unity Hub.exe")
    {
        Run cmd.exe /c taskkill /F /IM "Unity Hub.exe" ,,Hide
        ;process,close,Unity Hub.exe
    }

    if WinActive("ahk_exe stremio.exe")
    {
        Run cmd.exe /c taskkill /F /IM stremio.exe ,,Hide

    }

    if WinActive("ahk_exe IDMan.exe")
    {
        Run cmd.exe /c taskkill /F /IM IDMan.exe ,,Hide
    }

    if WinActive("ahk_exe CiscoCollabHost.exe")
    {
        Run cmd.exe /c taskkill /F /IM Ciscowebexstart.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM CiscoCollabHost.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM webexmta.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM washost.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM atmgr.exe ,,Hide
        Run cmd.exe /c taskkill /F /IM webex.exe ,,Hide
    }
    if WinActive("ahk_exe Telegram.exe")
    {
        Run cmd.exe /c taskkill /F /IM Telegram.exe ,,Hide
    }
    if WinActive("ahk_exe AnyDesk.exe")
    {
        Run cmd.exe /c taskkill /F /IM AnyDesk.exe ,,Hide
    }

    if WinActive("ahk_exe Zoom.exe")
    {
        ;if WinExist("Zoom Meeting")
        ;	{
        ;	return
        ;	}
        ;else
        ;	{
        Run cmd.exe /c taskkill /F /IM zoom.exe ,,Hide
        ;	}
    }
    ; else
    ; 	{
    send !{F4}
    ; }
    return
}

;Close All Programs
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

;Zoom CiscoWebx Telegram Anydesk MicrosoftTeams UnityHub Stremio IDM uTorrent opera Discord Cortana
$!F4:: CLoseCurrentlyActiveScreen() ;{ <-- CLose Currently Active Screen
$!^F4:: CLoseAllPrograms() ;{ <-- CLose All Program