#Requires AutoHotkey v1.1

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; NumLock AlwaysOn && ScrollLock Always Off
; Double tap Caps lock to activate/deactivate Caps lock
; Taskbar Mouse Scroll to Increase/Decrease volume

; Win+F --> Run FireFox
; Win+C --> Run Calculator
; Win+M --> Minimize Active window
; Win+F8 --> Bluetooth On/Off
; Win+Del --> Empty Recycle Bin
; Win+Shift+A --> Open Notification center
; Win+Shift+E --> (Folder) Open Downloads (My Screenshots) folder
; Win+Shift+J --> (Folder) Open Java Course
; Win+Alt+C --> Run Alarm Clock
; Win+Alt+Ctr+C --> Open PowerShell
; Win+Alt+Ctr+K --> Click Center of Screen (Disabled)
; Win+Alt+X --> (Script) Reconnect Cloudflare Network
; Win+Alt+N --> Clear Notification center
; Alt+X --> Open Today Calendar
; Alt+D --> Open ChatGPT
; Alt+Shift+T --> Active window Always on Top (Disabled -> Using PowerToys)

; Alt+G --> Copy the content, Open Monica & Grammar Correction
; Alt+Shift+S ---> Copy the content, Open Monica & Summarize Content

; Alt+Ctr+D --> Sort Folder content by date
; Alt+Ctr+E --> Enable/Disable file extension
; Alt+Ctr+H --> Enable/Disable hidden files
; Alt+Ctr+MouseLButton --> Move Background Apps
; Ctr+G --> Search the selected/clipboard text
; Ctr+C --> OneNote copy text instead of SS of some text
; Ctr+T+T --> Open new Tab from anywhere (In browser)
; Ctr+J+J --> Close downloads bar at bottom (In browser)
; Ctr+Y+T --> Open Youtube (In browser: maximum 0.15s second gap between Y & T)
; Ctr+Shift+V --> Browser to go to previous tab when taking a screenshot
; MouseLButton --> Double Click Functions (Taskbar Show/Hide; ) -->> Doing this with WindHawk Now

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#Include *i ..\local_paths.ahk ; Include local custom paths if present (ignored by Git)
EnvGet, UserProfile, USERPROFILE ; Get Windows UserProfile directory (AHK v1 compatibility)
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

; Auto-start / reload GravityBridge Proxy Server & CopyClip
; Named per-project so Task Manager's Name column shows "CopyClip_Python.exe" /
; "GravityBridge_Python.exe" instead of an anonymous "pythonw.exe" you can't tell apart.
RestartNamedPythonServer("GravityBridge", PATH_GRAVITY_BRIDGE "\proxy.py")
RestartNamedPythonServer("CopyClip", PATH_COPYCLIP "\copyclip.py")

; Auto-start Tailscale's tray app in the same burst as the scripts above, deterministically,
; instead of racing 14+ other Startup-folder apps through Explorer with no ordering
; guarantee. tailscaled itself (the actual VPN backend CopyClip depends on) is a Windows
; service and starts independently of this either way -- this only affects how soon the
; tray icon shows up. Guarded so a plain AHK reload doesn't relaunch an already-running copy.
TailscaleExe := "C:\Program Files\Tailscale\tailscale-ipn.exe"
Process, Exist, tailscale-ipn.exe
if (!ErrorLevel && FileExist(TailscaleExe))
    Run, %TailscaleExe%


SetNumlockState, AlwaysOn ; Set Lock keys permanently
; SetScrollLockState, AlwaysOff ;Commented this as scrollLock key is now being used to suspend & terminate AHK Scripts
; SetCapsLockState, AlwaysOff

#If MouseIsOver("ahk_class Shell_TrayWnd")
    ;   WheelUp::SoundSet +1   ;Hide OSD
    ;   WheelDown::SoundSet -1 ;Hide OSD
    WheelUp::Send {Volume_Up}
    WheelDown::Send {Volume_Down}
#If

; Text box created (UI) see in ToggleFileExt or HideFiles
text(a,t:="",x:="",y:="")
{
    c:=d:=e:=0, strReplace(a,"`n",,b), g:=strSplit(a,"`n","`r")[1], strReplace(g," ",,h)
    While !(f="" && a_index<>1)
    {
        f := subStr(g,a_index,1)
        (regExMatch(f, "[a-z]") ? c++ : f="@" ? e++ : d++)
    }
    SplashTextOn, % 150 + c*6.5 + d*12 + e*13 - h*8, % 30 + b*20, Yipiee..., % a
    If (x<>"" || y<>"")
        WinMove, Yipiee...,, x, y
    If (t<>"") {
        Sleep, t*1000
        WinClose, Yipiee...
    }
}

MouseIsOver(WinTitle)
{
    MouseGetPos,,, Win
    Return WinExist(WinTitle . " ahk_id " . Win)
}

HideFiles()
{
    RegRead, ValorHidden, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced, Hidden
    if ValorHidden = 2
    {
        RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced, Hidden, 1
        RefreshExplorer()
        text("Show Files",1)
        RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced, Hidden, 1
        RefreshExplorer()
    }
    else
    {

        RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced, Hidden, 2
        RefreshExplorer()
        text("Hide Files",1)
        RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced, Hidden, 2
        RefreshExplorer()

    }
    return
}

ToggleFileExt()
{
    Global lang_ToggleFileExt, lang_ShowFileExt, lang_HideFileExt
    RootKey = HKEY_CURRENT_USER
    SubKey = Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
    RegRead, HideFileExt , % RootKey, % SubKey, HideFileExt
    if HideFileExt = 1
    {
        ;MsgBox, Show Extentions
        ;IfMsgBox Yes
        ;{
        RegWrite, REG_DWORD, % RootKey, % SubKey, HideFileExt, 0
        RefreshExplorer()
        text("Show Extentions",1)
        RegWrite, REG_DWORD, % RootKey, % SubKey, HideFileExt, 0
        RefreshExplorer()
        ;}
    }
    else
    {
        ;MsgBox, Hide Extentions
        ;MsgBox, 4131,, Hide Extentions
        ;IfMsgBox Yes
        ;{
        RegWrite, REG_DWORD, % RootKey, % SubKey, HideFileExt, 1
        RefreshExplorer()
        text("Hide Extentions",1)
        RegWrite, REG_DWORD, % RootKey, % SubKey, HideFileExt, 1
        RefreshExplorer()
        ;}
    }
    return
}

RefreshExplorer()
{
    WinGet, id, ID, ahk_class Progman
    SendMessage, 0x111, 0x1A220,,, ahk_id %id%
    WinGet, id, List, ahk_class CabinetWClass
    Loop, %id%
    {
        id := id%A_Index%
        SendMessage, 0x111, 0x1A220,,, ahk_id %id%
    }
    WinGet, id, List, ahk_class ExploreWClass
    Loop, %id%
    {
        id := id%A_Index%
        SendMessage, 0x111, 0x1A220,,, ahk_id %id%
    }
    WinGet, id, List, ahk_class #32770
    Loop, %id%
    {
        id := id%A_Index%
        ControlGet, w_CtrID, Hwnd,, SHELLDLL_DefView1, ahk_id %id%
        if w_CtrID !=
            SendMessage, 0x111, 0x1A220,,, ahk_id %w_CtrID%
    }
    return
}

OpenActionCenter()
{
    send {LWin down}{n down}
    send {LWin up}{n up}
    return
}

; DoubleCapsHit := false
DoubleTapCapsLock()
{
    ; if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 200 && DoubleCapsHit = false){
    if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250){
        setcapslockstate, % (GetKeyState("CapsLock", "T") ? "Off" : "On")
        ; SetCapsLockState on
        ; DoubleCapsHit := True
    }
    ; else if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 200 && DoubleCapsHit = true){
    ; 	SetCapsLockState off
    ; 	DoubleCapsHit := false
    ; }
    return
}

CloseBrowserBottomDownloadsBar()
{
    if (WinActive("ahk_exe chrome.exe") || WinActive("ahk_exe brave.exe"))
    {
        Send, ^j ; Open downloads tab (Normal Functionality)
        if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250){
            Sleep, 100
            Send, ^w ; close the tab
        }
    }
    else
    {
        Send, ^j ; Normal Functionality
    }
    return
}

ClearNotificaitons()
{
    Send #n
    Sleep, 1000
    if WinActive("ahk_exe Shellexperiencehost.exe")
    {
        Send {Tab} {Space} {Esc}
    }
    return
}

ClipboardSearch()
{
        ; If (WinExist ("ahk_exe brave.exe"))
        ; {
        Sleep, 100
        GoogleSearchEngine := "https://www.google.com/search?q="
        send, ^c
        Sleep, 100

        ; WinActivate, ahk_exe brave.exe
        ; Sleep, 200

        LatestCopiedClipboard := Clipboard
        securedAddress := "https://"
        UnsecuredAddress := "www."
        if(SubStr(LatestCopiedClipboard,1,8) = securedAddress or SubStr(LatestCopiedClipboard,1,4) = UnsecuredAddress)
        {
            Send, ^t ; Open new tab
            Sleep, 100
            Send, ^v ; Paste the URL
            Send, {Enter} ; Hit Enter
        }
        else
        {
            CompleteURL = %GoogleSearchEngine%%LatestCopiedClipboard%
            ; MsgBox,4, Options, Testing, %url%, 3 ; For Debugging
            Run, %CompleteURL%
        }
    ; }
    return
}

; BluetoothToggle()
; {
; Method 1
; Run, ms-settings:bluetooth
; ; Wait for the Bluetooth settings window to open
; WinWait, Settings
; WinActivate
; Sleep, 2000
; Send, {Tab}{Tab}{Tab}{Space}
; ; Close the Bluetooth settings window
; Send, !{F4}
; send {LWinDown}{a down}
; Sleep, 800
; send {Down}{Right}{Enter}{Esc}

; Method 2
; MaxTime = 5	; Max Seconds to wait
; StartTime := A_TickCount
; WinID = ahk_exe ShellExperienceHost.exe ahk_class Windows.UI.Core.CoreWindow
; WinActivate %WinID%
; WinWaitActive %WinID%,, %MaxTime% - ((%A_TickCount% - %StartTime%) / 1000)
; If ErrorLevel
; {
;     MsgBox, WinWait timed out.
; }
;     else
; {
;     Sleep, 600
;     send {Down}
;     send {Down}
;     Sleep, 1000
;     send {Right}
;     Sleep, 100
;     send {Enter}{Esc}
; }
; send {Click 1650 690}
; return
; }

; DoubleClick(action)
; {
;     If (A_PriorHotKey = A_ThisHotKey and A_TimeSincePriorHotkey < 500)
;     {
;         WinGetClass, Class, A

;         ; Show/Hide Taskbar on Double click on taskbar
;         If Class = Shell_TrayWnd ; or ( Class = "Progman" )
;         {
;             static ABM_SETSTATE := 0xA, ABS_AUTOHIDE := 0x1, ABS_ALWAYSONTOP := 0x2
;             VarSetCapacity(APPBARDATA, size := 2*A_PtrSize + 2*4 + 16 + A_PtrSize, 0)
;             NumPut(size, APPBARDATA), NumPut(WinExist("ahk_class Shell_TrayWnd"), APPBARDATA, A_PtrSize)
;             NumPut(action ? ABS_AUTOHIDE : ABS_ALWAYSONTOP, APPBARDATA, size - A_PtrSize)
;             DllCall("Shell32\SHAppBarMessage", UInt, ABM_SETSTATE, Ptr, &APPBARDATA)
;             Return
;         }
;     }
;     return
; }

MoveBGApp()
{
    MouseGetPos,oldmx,oldmy,mwin,mctrl
    Loop
    {
        GetKeyState,lbutton,LButton,P
        GetKeyState,alt,Alt,P
        If (lbutton="U" Or alt="U")
            Break
        MouseGetPos,mx,my
        WinGetPos,wx,wy,ww,wh,ahk_id %mwin%
        wx:=wx+mx-oldmx
        wy:=wy+my-oldmy
        WinMove,ahk_id %mwin%,,%wx%,%wy%
        oldmx:=mx
        oldmy:=my
    }
    return
}

OpenYoutube()
{
    ; For more tweak read this : https://www.autohotkey.com/boards/viewtopic.php?t=86160

    if WinActive("ahk_exe chrome.exe") || WinActive("ahk_exe brave.exe")
    {
        if(openYT())
        {
            Sleep, 600
            send {LCtrl down}{LShift down}{Tab down}
            send {LCtrl up}{LShift up}{Tab up}
            send {LCtrl down}{w down}
            send {LCtrl up}{w up}
        }
    }
    else{
        openYT()
    }
}

openYT()
{
    KeyWait, t, DT0.20 ; wait a 0.20 second to see if t is pressed
    ; Input, UserInput, T0.7 L4, {enter}.{esc}{tab}, t
    ; if(ErrorLevel = "Timeout") ; y not pressed in time
    if ErrorLevel ; t not pressed in time
    {
        return false
        ;ignore as of now as it was intrupting normal functionality
        ;Send, ^y ; send ^y by itself so it's still usable
    }
    else {
        YoutubeURL := "https://www.youtube.com/"
        Run, %YoutubeURL%
    }
    return true
    ; if (UserInput = t){
    ;     YoutubeURL := "https://www.youtube.com/"
    ;     Run, %YoutubeURL%
    ; }
}

OpenNewTab()
{
    ; If youtube is going to active then disable opening new tab and open YT instead
    if (A_PriorHotkey != "~^Y")
    {
        if (WinActive("ahk_exe chrome.exe") || WinActive("ahk_exe brave.exe"))
        {
            ; MsgBox, [ Options, %A_PriorHotkey%, %ErrorLevel%, Timeout]
            Send ^t
        }
        else If (WinExist ("ahk_exe brave.exe")) && A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250
        {
            WinActivate, ahk_exe brave.exe
            Sleep, 250
            Send ^t
        }
        else If (WinExist ("ahk_exe chrome.exe")) && A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250
        {
            WinActivate, ahk_exe chrome.exe
            Sleep, 250
            Send ^t
        }
        else if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250){
            Run, brave.exe
            Sleep, 250
            Send ^t
        }
    }
    return
}

OpenCalculator()
{
    If WinExist("Calculator")
    {
        WinActivate

        ;To open another instance if need
        If (A_PriorHotKey = A_ThisHotKey and A_TimeSincePriorHotkey < 500)
        {
            Run calc.exe
        }
    }
    else{
        Run calc.exe
    }

    return
}

RunPowerShellAsAdministrator()
{
    Send, #x ;Window Start Menu
    Sleep, 1000
    Send, a ;a as Admin

    ; Run, powershell
    ; Run, "C:\Program Files\PowerShell\7\pwsh.exe"
    ; WinWait, ahk_class CASCADIA_HOSTING_WINDOW_CLASS
    ; Sleep, 1100
    ; Send, ^+2 ;Open as Admin

    ; Sleep, 1000
    ; WinActivate, ahk_class CASCADIA_HOSTING_WINDOW_CLASS
    ; Sleep, 100
    ; Send, !{Tab} ;Previous Instance without admin rights
    ; Sleep, 100
    ; Send, !{F4}
}

ClickCenterOfScreen()
{
    CoordMode, Mouse, Screen
    MouseMove, A_ScreenWidth / 2, A_ScreenHeight / 2
    Click
    return
}

SortFolderByDate()
{
    ; if WinActive("ahk_class ExploreWClass"){
    if WinActive("ahk_exe explorer.exe"){
        WinGet, hWnd, ID, A
        for oWin in ComObjCreate("Shell.Application").Windows
        {
            if (oWin.HWND = hWnd)
            {
                ; MsgBox, % oWin.Document.SortColumns ;show current sort columns
                if(oWin.Document.SortColumns == "prop:-System.DateModified;")
                {
                    oWin.Document.SortColumns := "prop:+System.DateModified;" ;sort by date modified descending (newest first)
                }
                else
                {
                    oWin.Document.SortColumns := "prop:-System.DateModified;" ;sort by date modified ascending (oldest first)
                }
                ;oWin.Document.SortColumns := "prop:+System.ItemNameDisplay;" ;sort by name ascending (A-Z)
                ;oWin.Document.SortColumns := "prop:-System.ItemNameDisplay;" ;sort by name descending (A-Z)
                ; break
            }
        }
        oWin := ""
    }
    return
}

; F8::clickEnter() ;{ <-- Delete Recycle Bin Data

; clickEnter(){
;     while,1
;         {

;             Sleep, 100
;             send {Click}
;             Sleep, 100
;             send {Enter}
;         }
; }

; Already working through PowerToys!
; MuteMic()
; {
; local MM
; SoundSet, +1, MASTER:1, MUTE, 2
; SoundGet, MM, MASTER:1, MUTE, 2
; #Persistent
; ToolTip, % (MM == "On" ? "Microphone muted" : "Microphone online")
; SetTimer, RemoveMuteMicTooltip, 700
; return

; nircmd.exe waitprocess firefox.exe speak text "Firefox was closed"

; Run nircmd.exe mutesysvolume 2 microphone
;     Return
; }
; RemoveMuteMicTooltip:
; 	SetTimer, RemoveMuteMicTooltip, Off
; 	ToolTip
; 	return

; YugenAnime()
; {
;     send {Click 1020 451};
;     Sleep, 300
;     send, ^l
;     ; Sleep, 100
;     send, ^c
;     Sleep, 600
;     YugenAnimeEngine := "https://yugenanime.tv/"
;     LatestCopiedClipboard := Clipboard
;     yugenSubstring := SubStr(LatestCopiedClipboard,1,22)
;     if( yugenSubstring != YugenAnimeEngine)
;     {
;         Send, ^w
;         Sleep, 200
;         Send, f
;         Sleep, 100
;         Send, Space
;     }else{
;         Send, {Esc down}
;         Sleep, 200
;         Send, {Esc down}
;         Sleep, 200
;         Send, f
;         ; Sleep, 200
;         ; Send, Space
;     }
; }

OpenCalendar(){
    if (WinActive("ahk_exe brave.exe") || WinActive("ahk_exe chrome.exe"))
    {
        Send !x
    }
    else If (WinExist ("ahk_exe brave.exe"))
    {
        WinActivate, ahk_exe brave.exe
        ; Sleep, 250
        Send !x
    }
    else If (WinExist ("ahk_exe chrome.exe"))
    {
        WinActivate, ahk_exe chrome.exe
        ; Sleep, 100
        Send !x
    }
}

OpenChatGPT(){
        ; if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250){
        if (WinActive("ahk_exe brave.exe") || WinActive("ahk_exe chrome.exe"))
        {
            Run, https://chatgpt.com
        }
        else If (WinExist ("ahk_exe brave.exe"))
        {
            ; WinActivate, ahk_exe brave.exe
            Run, https://chatgpt.com

        }
        else If (WinExist ("ahk_exe chrome.exe"))
        {
            ; WinActivate, ahk_exe chrome.exe
            Run, https://chatgpt.com
        }
    ; }
}

CopyToClipboard()
{
    Send, ^c
    ClipWait, 1

    ; Sleep, 500
    ; Send, ^c

    if ErrorLevel
    {
        ; MsgBox, Copying to clipboard failed.
        return
    }

    WinGet, current_application, ProcessName, A
    WinGetTitle, current_window_title, A

    if (current_application = "ApplicationFrameHost.exe" && InStr(current_window_title, "OneNote"))
    {
        if DllCall("IsClipboardFormatAvailable", "uint", 1)
        {
            clipboard := clipboard  ; Convert to text-only, removing formatting.
            ClipWait, 1
            if ErrorLevel
            {
                ; MsgBox, Failed to process clipboard data.
            }
        }
    }

    return
}

RevertVideoIntruption() {
    ; Hotkey, ^+v, Off
    ; Send, ^+v
    ; Hotkey, ^+v, On
    if (WinActive("ahk_exe chrome.exe") || WinActive("ahk_exe brave.exe"))
    {
        ; static prevURL := ""
        ; Get the URL of the active tab
        ; ControlGetText, url, Edit1, ahk_class Chrome_WidgetWin_1
        ; if InStr(url, "file:///")
        ; {
        ;     ; Close the local file tab
        ;     Send, ^w
        ;     Sleep, 500 ; Give some time for the tab to close
        ; }

        Sleep, 1000
        send {LCtrl down}{LShift down}{tab down}
        send {LCtrl up}{LShift up}{tab up}
        Sleep,600
        Send, f

        ; ControlGetText, url, Edit1, ahk_class Chrome_WidgetWin_1
        ; MsgBox, %url%

        ; if InStr(url, "youtube.com")
        ; {
        ; }
    }
    return
    ; Sleep, 500
    ; Send, ^l
    ; ; Sleep, 10
    ; Send, ^c
    ; ClipWait, 1

    ; ChromeExtension := "chrome-extension://"
    ; LatestCopiedClipboard := Clipboard
    ; ; MsgBox, %LatestCopiedClipboard%

    ; chromeExtensionSubstring := SubStr(LatestCopiedClipboard, 1, 19)
    ; if (ChromeExtension == chromeExtensionSubstring) {
    ;     send {LCtrl down}{LShift down}{tab down}
    ;     send {LCtrl up}{LShift up}{tab up}
    ;     Sleep,400
    ;     Send, f
    ; }
}

; MonicaQuickAccess() ;Grammar Correction
; {
;     Send, ^c
;     Sleep, 100
;     Send, !^f ;Shortcut to Open Monica
;     Sleep, 500
;     Send, {Tab} ;Going to Grammar section
;     Send, {Enter}
; }

MonicaGrammarCorrection() ;Grammar Correction
{
    Send, ^c
    Sleep, 100
    Send, !f ;Shortcut to Open Monica
    Sleep, 500
    ; Send, {Tab} ;Going to Grammar section
    Send, {Enter}
}

MonicaSummary() ;Summary
{
    Send, ^c
    Sleep, 100
    Send, !f ;Shortcut to Open Monica
    Sleep, 500
    Send, {Tab} ;Going to Summry section
    ; Send, {Tab} ;Going to Summry section
    Send, {Enter}
}

; Alt+Ctr+Z ShareX Image Editor
~!^Z:: ImageEditor() ;{ <-- ShareX Image Editor

ImageEditor()
{
    ; Send, ^c
    ; MouseClick, left, 902, 471

    Send, ^c
    ; ClipWait, 1
    Run, "C:\Program Files\ShareX\ShareX.exe" -ImageEditor
    ; Sleep, 500
    MouseClick, left, 902, 471
}

; Ctr+Shift+V in browser to go to previous tab when taking a screenshot
~^+v:: RevertVideoIntruption() ;{ <-- Brave AwesomeSreenshot Intruption Stop

; #IfWinActive, ahk_exe EXCEL.EXE  ; This directive targets Microsoft Excel
; !f::  ; This is the hotkey Alt+F
;     send {LAlt down}{LAlt up}
;     send {h down}{h up}
;     send {f down}{f up}
;     send {p down}{p up}
;     return
; #IfWinActive  ; This closes the Excel-specific directive

; Ctr+C OneNote copy text instead of SS of some text
$^c::CopyToClipboard() ;{ <-- OneNote Copy Mechanism Handeling (instead of SS)

; Alt+F11 Hide Window top bar
!F11:: WinSet, Style, ^0xC00000, A ;{ <-- Hide Window top bar

; Win+M Minimize window
#M::WinMinimize, A ;{ <-- Minimize Active Window

; Win+F8 --> Bluetooth On/Off
; #F8::BluetoothToggle() ;{ <-- Bluetooth Toggle [Discard]

; MouseLButton DoubleClick Show/Hide Taskbar;
; ~LButton::DoubleClick(hide := !hide) ;{ <-- Double Click Functions (WindHawk Now)

; Alt+MouseLButton Move background apps
^!LButton::MoveBGApp() ;{ <-- Move BG Apps

; Win+F Run FireFox
#f::Run Firefox ;{ <-- Open FireFox

; Ctr+G Select text to search in browser
^G:: ClipboardSearch() ;{ <-- Search the selected/clipboard text

; Win+C Run Calculator
#c:: OpenCalculator() ;{ <-- Open calculaor

; Win+Ctr+Alt+M Mute/Unmute Microphone
; #^!M:: MuteMic() ;{ <-- Mute/Unmute Microphone

; Win+Alt+C Run Alarm Clock
#!c:: Run "shell:Appsfolder\Microsoft.WindowsAlarms_8wekyb3d8bbwe!App" ;{ <-- Open clock

; Win+Alt+Ctrl+C Open Powershell
#!^c:: RunPowerShellAsAdministrator() ;{ <-- Open Powershell
;Run "C:\Program Files\PowerShell\7\pwsh.exe" -WorkingDirectory ~

; Win+Alt+Ctrl+K --> Click Center of Screen
;#!^k:: ClickCenterOfScreen() ;{ <-- Click Center of Screen

; Win+Shift+E --> (Folder) Open Downloads (My Screenshots) folder
#+e::Run "%UserProfile%\Pictures\Screenshots" ;{ <-- Open Screenshots Folder

; Win+Shift+J --> (Folder) Open Java Course
#+j::Run "%PATH_JAVA_COURSE%" ;{ <-- Open Java Course

; Win+Del Empty Recycle Bin
#Del::FileRecycleEmpty ;{ <-- Delete Recycle Bin Data

; Win+Shift+A Open Notification center
#+A::OpenActionCenter() ;{ <-- Open Notification center

; Win+Alt+N Clear Notification center
#!N::ClearNotificaitons() ;{ <-- Clear Notifications (Win 11)

; Alt+Shift+T Active window Always on Top
; !+T:: Winset, Alwaysontop, , A ;{ <-- This Winodw Always on Top

; Alt+Ctr+J Testing Automation
; $!^J:: TestingAutomation() ;{ <-- Testing Automation

; Alt+G Copy the content, Open Monica & Grammar Correction
!G:: MonicaGrammarCorrection() ;{ <-- Monica Grammar Correction

; Alt+Shift+S Copy the content, Open Monica & Summarize Content
!+S:: MonicaSummary() ;{ <-- Monica Summarize Content

; Alt+Ctr+E Enable/Disable file extension
$!^E:: ToggleFileExt() ;{ <-- Show/Hide Extenstions

; Alt+Ctr+D Sort Folder content by date
$!^D:: SortFolderByDate() ;{ <-- Sort Folder content by date

; Alt+Ctr+H Enable/Disable hidden files
$!^H:: HideFiles() ;{ <-- Show/Hide Hidden Files

; Alt+X --> Open Today Calendar
$!X:: OpenCalendar() ;{ <-- Open Calender after Browser opening

; Alt+D --> Open ChatGPT
$!D:: OpenChatGPT() ;{ <-- Open ChatGPT

; Double Tap caps lock to on and off
*CapsLock::DoubleTapCapsLock() ;{ <-- Double Tap To Activate/Deactivate

; #IfWinActive ahk_class Shell_TrayWnd
; Ctr+J+J in browser to close downloads bar at bottom
$^J::CloseBrowserBottomDownloadsBar() ;{ <-- Close browser downloads bar at bottom
; #IfWinActive

; Ctr+Y+T in browser to open Youtube
~^Y::OpenYoutube() ;{ <-- Open Youtube

; Ctr+T+T in browser to open new Tab from anywhere
~^T::OpenNewTab() ;{ <-- open browser tab from anywhere

; Win+Alt+X --> (Script) Reconnect Cloudfare Network
#!x::Run "%PATH_IP_ROTATOR%" ;{ <-- Reconnect Cloudfare Network

;Turn Caps Lock into a Shift key
; Capslock::Shift

;F1:: send {Left}
; +NumpadAdd:: Send {Volume_Up}
; +NumpadSub:: Send {Volume_Down}
; break::Send {Volume_Mute}
; return

; #LAlt::^#Right ; switch to next desktop with Windows key + Left Alt key -> Original is Win + Ctr + Right
; #LCtrl::^#Left ; switch to next desktop with Windows key + Left CTRL key -> Original is Win r+ Ctr + Left

; Launches a Python script under a per-project renamed copy of pythonw.exe, so Task
; Manager's Name column shows e.g. "CopyClip_Python.exe" instead of an anonymous
; "pythonw.exe" indistinguishable from every other Python process on the machine.
;
; Verified before wiring this in: a bare copy of pythonw.exe, renamed and placed in an
; arbitrary directory (no DLLs alongside it), runs correctly -- this Python install
; resolves its interpreter DLL and stdlib via PATH/registry, not relative to the exe's own
; location, so the renamed copy does not need to live next to python3XX.dll.
;
; The copy is cached under AllScripts\PythonExes\ and only made once; it is not
; auto-refreshed on a Python upgrade. Delete that folder (or a project's one *_Python.exe)
; to force a fresh copy on the next call.
RestartNamedPythonServer(ProjectName, ScriptPath, WorkingDir:="", PythonExe:="") {
    global PATH_PYTHON_EXE

    ScriptPath := Trim(ScriptPath, """")
    if (!ScriptPath || !FileExist(ScriptPath))
        return false

    SplitPath, ScriptPath, FileName, Directory
    if (!WorkingDir)
        WorkingDir := Directory
    if (!PythonExe)
        PythonExe := PATH_PYTHON_EXE ? PATH_PYTHON_EXE : "pythonw.exe"
    PythonExe := Trim(PythonExe, """")

    NamedExeDir := A_ScriptDir "\PythonExes"
    if !FileExist(NamedExeDir)
        FileCreateDir, %NamedExeDir%
    NamedExeName := ProjectName "_Python.exe"
    NamedExePath := NamedExeDir "\" NamedExeName
    if !FileExist(NamedExePath)
        FileCopy, %PythonExe%, %NamedExePath%

    ; Skip the kill+relaunch entirely when a single, correctly-named instance is already
    ; running and no stray/duplicate process exists. Killing and relaunching an
    ; already-healthy daemon here serves no purpose except interrupting it -- for
    ; CopyClip specifically, that resets its in-memory "have I seen this device before"
    ; state and makes it silently drop the next clip as an unsynced baseline instead of
    ; syncing it (see bugs/ in the CopyClip repo, restart-drops-baseline). Restart is
    ; still correct, and happens below exactly as before, whenever this ISN'T true:
    ; nothing running yet, a stray duplicate under a different name exists, or somehow
    ; more than one correctly-named instance is running.
    NamedCount := 0, StrayCount := 0
    CountQuery := "SELECT ProcessId,Name,CommandLine FROM Win32_Process WHERE Name = '" NamedExeName "' OR Name LIKE 'python%'"
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery(CountQuery)
        {
            if (proc.Name = NamedExeName)
                NamedCount++
            else if InStr(proc.CommandLine, FileName)
                StrayCount++
        }
    }
    if (NamedCount = 1 && StrayCount = 0)
        return true

    ; Kill any existing instance of this script, however it was launched. Two match rules,
    ; either one is enough:
    ;   1. Name = the renamed exe -- catches a previous run under this same named scheme.
    ;   2. A generic 'python%' process whose CommandLine names this exact script file --
    ;      catches anything still running under the OLD generic pythonw.exe name (this
    ;      migration's own leftover), and any other way this script might get launched
    ;      (Desktop shortcut, a bare "python script.py", etc. -- see bugs/BUG-003 in the
    ;      CopyClip repo for why relying on only one launch path here is exactly how a
    ;      duplicate daemon slips in). Rule 1 alone would miss anything not already
    ;      launched by this function, which is precisely the gap that let a stray old
    ;      pythonw.exe survive a reload during testing and run alongside the new one.
    KillQuery := "SELECT ProcessId,Name,CommandLine FROM Win32_Process WHERE Name = '" NamedExeName "' OR Name LIKE 'python%'"
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery(KillQuery)
            if (proc.Name = NamedExeName) || InStr(proc.CommandLine, FileName)
                Process, Close, % proc.ProcessId
    }
    Sleep, 200

    ; Launch silently - the renamed pythonw.exe copy never creates a console window either
    Run, "%NamedExePath%" "%ScriptPath%", %WorkingDir%, Hide
    return true
}
