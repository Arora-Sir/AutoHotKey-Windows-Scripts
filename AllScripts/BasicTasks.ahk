#Requires AutoHotkey v1.1

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; NumLock AlwaysOn && ScrollLock Always Off
; Double tap Caps lock to activate/deactivate Caps lock
; Taskbar Mouse Scroll to Increase/Decrease volume
; Volume_Up / Volume_Down --> Adjust system volume

; Win+F --> Run FireFox
; Win+C --> Run Calculator
; Win+M --> Minimize Active window
; Win+F8 --> Bluetooth On/Off
; Win+Del --> Empty Recycle Bin
; Win+Shift+A --> Open Notification center
; Win+Shift+E --> (Folder) Open Downloads (My Screenshots) folder
; Win+Shift+J --> (Folder) Open Java Course
; Win+Shift+P --> Toggle Display Mode (Laptop 1080p @ 144Hz <-> Tablet 2560x1600 @ 120Hz)
; Ctrl+Shift+P --> Same, alternate keybind (manual PC-side use, doesn't help from tablet - see ARCHITECTURE.md)
; Win+Alt+P --> Same, third keybind (manual PC-side use)
; Win+Alt+C --> Run Alarm Clock
; Win+Alt+Ctr+C --> Open PowerShell
; Win+Alt+Ctr+K --> Click Center of Screen (Disabled)
; Win+Alt+X --> (Script) Reconnect Cloudflare Network
; Win+Alt+N --> Clear Notification center
; Win+Alt+L --> (Script) Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)
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
; Ctr+J+J --> (Chrome) Close downloads bar at bottom
; Ctr+Y+T --> Open Youtube (In browser: maximum 0.15s second gap between Y & T)
; Win+X+X --> Sleep Laptop
; Ctr+Shift+V --> Browser to go to previous tab when taking a screenshot
; MouseLButton --> Double Click Functions (Taskbar Show/Hide; ) -->> Doing this with WindHawk Now
; Ctr+Shift+WheelUp --> (VS Code) Increase Whole UI Zoom (+0.05)
; Ctr+Shift+WheelDown --> (VS Code) Decrease Whole UI Zoom (-0.05)

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
#Include %A_ScriptDir%\SharedHelpers.ahk ; Functions shared across scripts - see ARCHITECTURE.md
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

SetNumlockState, AlwaysOn ; Set Lock keys permanently
; SetScrollLockState, AlwaysOff ;Commented this as scrollLock key is now being used to suspend & terminate AHK Scripts
; SetCapsLockState, AlwaysOff

; System Tray menu integration for Skills Vault (owned by BasicTasks)
global g_SkillsTrayStatusLabel := "Skills Vault: [AUTO] (focus-driven)"

; --- Manual toggle debounce state (Win+Alt+L) --------------------------------
; Single source of truth for the settle window - referenced everywhere instead
; of a repeated literal.
global g_SkillsDebounceMs := 2000
; In-memory "next mode if committed right now" - the ONLY thing the fast path
; (TogglePersonalSkillsLock) cycles. Distinct from the on-disk modeFile, which
; remains the cross-process state of record and is touched only by the commit
; phase. "" is a one-time sentinel meaning "not yet seeded this process" -
; seeded from modeFile on first use, and reset back to "" once a commit
; settles with nothing newer pending (see CommitPersonalSkillsLock's tail).
global g_SkillsPendingMode := ""
; Defense-in-depth reentrancy guard for the COMMIT phase only. AHK's own timer
; engine already guarantees at most one concurrently-running instance of a
; given timer target, so this should never actually read true in practice.
global g_SkillsCommitBusy := false
Menu, Tray, Add
Menu, Tray, Add, %g_SkillsTrayStatusLabel%, TraySkillsVaultStatus
Menu, Tray, Disable, %g_SkillsTrayStatusLabel%
Menu, Tray, Add, Cycle Skills Vault Mode (Win+Alt+L), TraySkillsVaultCycle
Menu, Tray, Add, Toggle Display Mode (Win+Shift+P), TrayToggleDisplayMode
Menu, Tray, Add, Duplicate Only, TrayDuplicateDisplayMode

; Publish for StartupScript.ahk's master submenu mirroring (see SharedHelpers.ahk)
PublishTrayMenuManifest([["Skills Vault Status (Show Toast)", "TraySkillsVaultStatus"], ["Cycle Skills Vault Mode (Win+Alt+L)", "TraySkillsVaultCycle"], ["Toggle Display Mode (Win+Shift+P)", "TrayToggleDisplayMode"], ["Duplicate Only", "TrayDuplicateDisplayMode"]])

SetTimer, UpdateSkillsTrayStatus, 2000
SetTimer, UpdateSkillsTrayStatus, -100 ; Fast initial update

; Win32 WM_DISPLAYCHANGE (0x007E) - auto-recovery on laptop lid open
global g_LastManualDisplaySwitch := 0
OnMessage(0x007E, "OnDisplayChange_LidRecovery")

#If MouseIsOver("ahk_class Shell_TrayWnd")
    ;   WheelUp::SoundSet +1   ;Hide OSD
    ;   WheelDown::SoundSet -1 ;Hide OSD
    WheelUp::Send {Volume_Up}
    WheelDown::Send {Volume_Down}
#If

Volume_Up::SoundSet, +10 ;{ <-- Volume Up
Volume_Down::SoundSet, -10 ;{ <-- Volume Down

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

; Close legacy bottom downloads shelf in Chrome (Brave uses a modern top toolbar popup, so this issue only applies to Chrome)
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

SleepLaptop()
{
    KeyWait, x
    KeyWait, x, D T0.30
    if (ErrorLevel)
    {
        ; Single tap Win+X: Open standard Windows Quick Link menu
        SendInput, {LWin down}x{LWin up}
    }
    else
    {
        ; Double tap Win+X+X: Open menu and invoke Sleep (Win+X -> u -> s)
        SendInput, {LWin down}x{LWin up}
        Sleep, 150
        SendInput, {LWin up}{RWin up}
        SendInput, u
        Sleep, 100
        SendInput, s
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
    ; *RunAs on pwsh.exe or wt.exe directly, Shell.Application ShellExecute on
    ; shell:AppsFolder package identity, and a Highest-run-level Task Scheduler
    ; task were all tried and rejected: wt.exe is a packaged/MSIX app and none
    ; of those reliably elevate it -- each either spawns and exits within a
    ; second or two, or silently no-ops. This is a genuine Windows limitation
    ; (packaged apps generally can't be launched pre-elevated by external
    ; automation), not fixable by trying yet another external-elevation
    ; variant. *RunAs "...pwsh.exe" DOES elevate reliably on its own, but
    ; opens a plain console host window, not Windows Terminal's tabbed UI.

    ; Launch a Windows Terminal PROFILE that is itself configured to elevate ("PowerShell
    ; (Admin)" in this Terminal install's profile list, normally reached via the dropdown
    ; next to the + tab button, or Ctrl+Shift+6 on this machine's current profile order --
    ; that keybinding is NOT stable across installs/reorders, which is why this targets the
    ; profile by name instead). Terminal handles the elevation internally for a
    ; profile marked this way, the same mechanism the dropdown and Win+X use -- the
    ; resulting window's title reads "Administrator: PowerShell (Admin)".
    ;
    ; SETUP REQUIRED: none, on a reasonably current Windows Terminal -- "<Profile> (Admin)"
    ; entries in that + dropdown are auto-generated by Terminal itself for every detected
    ; shell profile, not something manually added to settings.json. No scheduled task, no
    ; registry change, nothing to run in an elevated terminal first. If "PowerShell (Admin)"
    ; is ever missing from that dropdown on some future machine, that means Terminal itself
    ; doesn't see a "PowerShell" profile to generate the admin variant from (e.g. pwsh not
    ; installed, or Terminal is on an old version predating this feature) -- fix that, not
    ; this line.
    Run, wt.exe -p "PowerShell (Admin)"
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

; Win+Shift+P Toggle Display Mode (Laptop 1080p @ 144Hz <-> Tablet 2560x1600 @ 120Hz)
#+p::ToggleTabletDisplayMode() ;{ <-- Toggle Display Mode

; Ctrl+Shift+P - same toggle, alternate keybind.
; Turned out Android intercepts modifier combos before Moonlight ever forwards them, regardless of which combo, so this doesn't reliably help from the tablet either - kept as a manual PC-side option.
^+p::ToggleTabletDisplayMode() ;{ <-- Toggle Display Mode (Alt keybind)

; Win+Alt+P - same toggle, third keybind, manual PC-side option (no binding existed on this combo yet).
#!p::ToggleTabletDisplayMode() ;{ <-- Toggle Display Mode (Alt keybind 2)

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
; Ctr+J+J (Chrome) Close downloads bar at bottom
$^J::CloseBrowserBottomDownloadsBar() ;{ <-- (Chrome) Close browser downloads bar at bottom
; #IfWinActive

; Ctr+Y+T in browser to open Youtube
~^Y::OpenYoutube() ;{ <-- Open Youtube

; Ctr+T+T in browser to open new Tab from anywhere
~^T::OpenNewTab() ;{ <-- open browser tab from anywhere

; Win+Alt+X --> (Script) Reconnect Cloudfare Network
#!x::Run "%PATH_IP_ROTATOR%" ;{ <-- Reconnect Cloudfare Network

; Win+Alt+L --> (Script) Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)
; Scoped MaxThreads override: the handler makes a BLOCKING shell.Run() across 14
; folders (tens-hundreds of ms, more under disk/AV contention). Without this,
; AHK's default (MaxThreadsPerHotkey=1, Buffer=Off) means a second press while
; the first is still running is SILENTLY DISCARDED - not queued, no error.
; Buffer On + PerHotkey 1 coalesces rapid re-presses into exactly one extra
; run, queued (never concurrent - two icacls sweeps racing the same ACLs is
; unacceptable). Reset back to defaults right after, or every hotkey below
; would inherit this (positional, forward-applying).
#MaxThreadsBuffer On
#MaxThreadsPerHotkey 1
#!l:: TogglePersonalSkillsLock() ;{ <-- Cycle Skills Vault Mode
#MaxThreadsBuffer Off
#MaxThreadsPerHotkey 1

; Win+X+X --> Sleep Laptop
$#x:: SleepLaptop() ;{ <-- Sleep Laptop (Win+X+X)

;Turn Caps Lock into a Shift key
; Capslock::Shift

;F1:: send {Left}
; +NumpadAdd:: Send {Volume_Up}
; +NumpadSub:: Send {Volume_Down}
; break::Send {Volume_Mute}
; return

; #LAlt::^#Right ; switch to next desktop with Windows key + Left Alt key -> Original is Win + Ctr + Right
; #LCtrl::^#Left ; switch to next desktop with Windows key + Left CTRL key -> Original is Win r+ Ctr + Left

; =========================================================================
; [START: VS Code Fine-Grained Whole UI Zoom Hook]
; Hotkey: Ctrl + Shift + MouseWheelUp / MouseWheelDown
; Target: Exclusively active when VS Code (ahk_exe Code.exe) is in the foreground
; Behavior: Smoothly increments/decrements window.zoomLevel in settings.json by 0.05
; Safety: Clamped between -2.0 and 5.0, non-blocking HUD tooltip, isolated to Code.exe
; =========================================================================
#IfWinActive ahk_exe Code.exe
; Ctr+Shift+WheelUp (VS Code) Increase Whole UI Zoom
^+WheelUp::AdjustVsCodeZoom(0.05) ;{ <-- (VS Code) Increase Whole UI Zoom (+0.05)
; Ctr+Shift+WheelDown (VS Code) Decrease Whole UI Zoom
^+WheelDown::AdjustVsCodeZoom(-0.05) ;{ <-- (VS Code) Decrease Whole UI Zoom (-0.05)
#If

AdjustVsCodeZoom(delta) {
    settingsFile := A_AppData "\Code\User\settings.json"
    if !FileExist(settingsFile)
        return

    FileRead, sContent, %settingsFile%
    q := Chr(34)
    pattern := q . "window\.zoomLevel" . q . "\s*:\s*(-?\d+(\.\d+)?)"
    if RegExMatch(sContent, pattern, match) {
        currentZoom := Round(match1 + delta, 2)
        ; Clamp zoom level between -2.0 (minimum) and 5.0 (maximum) for UI safety
        if (currentZoom < -2.0)
            currentZoom := -2.0
        if (currentZoom > 5.0)
            currentZoom := 5.0

        rep := q . "window.zoomLevel" . q . ": " . currentZoom
        newContent := RegExReplace(sContent, pattern, rep)

        File := FileOpen(settingsFile, "w", "UTF-8")
        if IsObject(File) {
            File.Write(newContent)
            File.Close()
        }

        ; Non-intrusive HUD tooltip showing current exact scale factor
        ToolTip, % "VS Code Whole UI Zoom: " . currentZoom
        SetTimer, RemoveVsCodeZoomToolTip, -800
    }
}

RemoveVsCodeZoomToolTip:
    ToolTip
return
; [END: VS Code Fine-Grained Whole UI Zoom Hook]

; Win+Alt+M/U (mount/unmount the ext4 backup SSD) now live in
; AllScripts/Ext4SsdManager.ahk, along with the rest of that feature.

; [START: Personal Skills Lock/Unlock 3-Way Toggle]
; Fast phase - the hotkey/tray target. Cycles the in-memory pending mode, shows instant feedback, and arms the settle timer.
; Nothing here blocks: no mutex, no shell.Run, no filesystem check for the lock/unlock scripts - all of that belongs exclusively to CommitPersonalSkillsLock below.
; A blocking icacls sweep across 14 folders (3-4 icacls calls each) takes ~2.3-3.5s, so this split keeps the toast instant on every press; only the LAST press in a rapid run (g_SkillsDebounceMs of quiet, 2000ms by default) actually triggers the real work.
TogglePersonalSkillsLock() {
    global g_SkillsPendingMode, g_SkillsDebounceMs, g_SkillsCommitBusy
    global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT

    ; While a commit is actively applying (the amber badge is on screen), the hotkey is a silent no-op.
    ; A fresh press here would otherwise clobber the in-flight commit's own badge and then get its OWN commit rejected by DebounceTryBeginCommit anyway, producing a scrambled badge sequence.
    ; Cancelling the in-flight commit instead was considered and rejected: it's a blocking shell.Run of icacls across all 14 real vault folders, and killing it mid-sweep could leave the vault partially locked/unlocked - an inconsistent security state this project cannot risk.
    ; See ARCHITECTURE.md.
    if (g_SkillsCommitBusy)
        return

    if (!PATH_SKILLS_LOCK_SCRIPT || !PATH_SKILLS_UNLOCK_SCRIPT) {
        ShowSkillsStatusBadge("[ERROR] Skills paths not configured")
        return
    }

    ; Seed from the real on-disk mode file only on the first press since this process started (or the first press after a settled commit reset this back to "").
    ; Every press after that cycles purely off the in-memory value, so a rapid burst always advances from what the user just SAW, never from stale disk state a pending/in-flight commit hasn't written yet.
    if (g_SkillsPendingMode = "") {
        modeFile := A_Temp "\skills_vault_mode.flag"
        seedMode := "auto"
        if FileExist(modeFile) {
            FileRead, seedMode, %modeFile%
            seedMode := Trim(seedMode)
            if (seedMode != "locked" && seedMode != "unlocked" && seedMode != "auto")
                seedMode := "auto"
        }
        g_SkillsPendingMode := seedMode
    }

    ; Cycle purely in-memory: auto -> locked -> unlocked -> auto -> ...
    if (g_SkillsPendingMode = "auto")
        g_SkillsPendingMode := "locked"
    else if (g_SkillsPendingMode = "locked")
        g_SkillsPendingMode := "unlocked"
    else
        g_SkillsPendingMode := "auto"

    ; Instant feedback for THIS press's resulting state.
    if (g_SkillsPendingMode = "locked")
        ShowSkillsStatusBadge("[LOCKED] Skills Vault (manual)")
    else if (g_SkillsPendingMode = "unlocked")
        ShowSkillsStatusBadge("[UNLOCKED] Skills Vault (manual)")
    else
        ShowSkillsStatusBadge("[AUTO] Skills Vault (focus-driven)")

    ; Arm/re-arm the settle timer (shared helper - see SharedHelpers.ahk for the Reset-timer mechanics).
    ; Only the LAST press in any rapid run ever reaches CommitPersonalSkillsLock, and only once g_SkillsDebounceMs elapses with zero further presses.
    DebounceArmTimer("CommitPersonalSkillsLock", g_SkillsDebounceMs)
    return
}

; Slow "commit" phase - the ONLY place that touches the mutex, the lock/unlock scripts, or the on-disk mode file.
; Reached exclusively via the settle timer armed above; nothing else Gosubs this label.
CommitPersonalSkillsLock:
    global g_SkillsPendingMode, g_SkillsCommitBusy, g_SkillsDebounceMs
    global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT, PATH_PWSH_EXE

    ; Defense-in-depth only (see g_SkillsCommitBusy's declaration and DebounceTryBeginCommit in SharedHelpers.ahk).
    ; AHK's timer engine already guarantees at most one concurrently-running instance of a given timer's target, so this should never actually read true.
    if !DebounceTryBeginCommit(g_SkillsCommitBusy, "CommitPersonalSkillsLock", g_SkillsDebounceMs)
        return

    ; Snapshot now, before the mutex wait and the blocking work below.
    ; The tail compares the LIVE g_SkillsPendingMode against this snapshot to detect whether a press landed during this invocation, so that press is guaranteed a turn instead of silently lost - see the tail comment.
    targetMode := g_SkillsPendingMode

    ; Cross-process mutex: guards against WatchSkillsLock (a separate OS process in BackgroundAutomations.ahk) reading/acting on the same mode file and running the same lock/unlock scripts concurrently with this commit.
    ; Same patient 10s timeout the hotkey path always used.
    hMutex := AcquireNamedMutex("SkillsVaultLock_AHK_v1", 10000)
    if (!hMutex) {
        ShowSkillsStatusBadge("[ERROR] Vault busy, try again")
    } else {
        pwsh := PATH_PWSH_EXE ? PATH_PWSH_EXE : (FileExist("C:\Program Files\PowerShell\7\pwsh.exe") ? "C:\Program Files\PowerShell\7\pwsh.exe" : "powershell.exe")
        shell := ComObjCreate("WScript.Shell")
        scriptOk := true ; false only if a required script vanished since press time

        if (targetMode = "locked") {
            if (FileExist(PATH_SKILLS_LOCK_SCRIPT)) {
                cmd := """" . pwsh . """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . PATH_SKILLS_LOCK_SCRIPT . """ -Silent"
                ; Amber "applying" badge closes the silent gap between settle and completion (real work takes ~2.3-3.5s).
                ; No third "done" badge afterward - it would just repeat the [LOCKED] badge already shown at press time, conveying nothing new, so the applying badge is explicitly hidden the moment the real work finishes instead.
                ; 15000ms is a safety-net ceiling only, in case the explicit hide below is ever skipped.
                ShowBottomRightBadge("[APPLYING...] Locking Skills Vault", "6E5A00", 15000)
                shell.Run(cmd, 0, true)
                HideBottomRightBadge()
            } else {
                ShowSkillsStatusBadge("[ERROR] Lock script not found")
                scriptOk := false
            }
        } else if (targetMode = "unlocked") {
            if (FileExist(PATH_SKILLS_UNLOCK_SCRIPT)) {
                cmd := """" . pwsh . """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . PATH_SKILLS_UNLOCK_SCRIPT . """ -Silent"
                ShowBottomRightBadge("[APPLYING...] Unlocking Skills Vault", "6E5A00", 15000)
                shell.Run(cmd, 0, true)
                HideBottomRightBadge()
            } else {
                ShowSkillsStatusBadge("[ERROR] Unlock script not found")
                scriptOk := false
            }
        } else { ; targetMode = "auto"
            ; Focus check happens HERE, at commit time, not at press time - "auto" has always meant "whatever's focused NOW" elsewhere in this codebase (WatchSkillsLock's own logic), and the toast shown at press time never promised which script would run, just [AUTO].
            ; modeFile is written to "auto" regardless of which (if any) branch below actually runs - unconditional, matching the pre-debounce behavior.
            WinGet, curExe, ProcessName, A
            if (curExe = "claude.exe") {
                if (FileExist(PATH_SKILLS_LOCK_SCRIPT)) {
                    cmd := """" . pwsh . """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . PATH_SKILLS_LOCK_SCRIPT . """ -Silent"
                    ShowBottomRightBadge("[APPLYING...] Locking Skills Vault (Auto)", "6E5A00", 15000)
                    shell.Run(cmd, 0, true) ; blocking - keep inside the mutex's critical section
                    HideBottomRightBadge()
                }
            } else if (curExe = "Antigravity.exe" || curExe = "agy.exe" || curExe = "Antigravity IDE.exe") {
                if (FileExist(PATH_SKILLS_UNLOCK_SCRIPT)) {
                    cmd := """" . pwsh . """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . PATH_SKILLS_UNLOCK_SCRIPT . """ -Silent"
                    ShowBottomRightBadge("[APPLYING...] Unlocking Skills Vault (Auto)", "6E5A00", 15000)
                    shell.Run(cmd, 0, true) ; blocking - keep inside the mutex's critical section
                    HideBottomRightBadge()
                }
            }
            ; Neither app focused (or its script is missing): fall through silently - no error, no script, but the mode-file write below still happens.
        }

        if (scriptOk) {
            try {
                f := FileOpen(A_Temp "\skills_vault_mode.flag", "w")
                if (f) {
                    f.Write(targetMode)
                    f.Close()
                }
            }
        }
        ReleaseNamedMutex(hMutex)
    }

    ; Reconciliation (shared helper - see SharedHelpers.ahk): if the live pending value still equals what we just pursued, nothing newer happened - drop back to the "" sentinel so the next press re-seeds from disk instead of trusting this value forever.
    ; If it no longer matches, at least one more press landed while this invocation ran (most commonly: while the blocking shell.Run above was still mid-flight, seconds in).
    ; That intent can't safely cancel an already-dispatched icacls sweep, so it waits and gets its own turn immediately after instead of being dropped - re-armed once more so it still gets applied. Also clears g_SkillsCommitBusy.
    DebounceEndCommit(g_SkillsPendingMode, targetMode, g_SkillsCommitBusy, "CommitPersonalSkillsLock", g_SkillsDebounceMs)
    return

; AcquireSkillsVaultLock/ReleaseSkillsVaultLock now live in SharedHelpers.ahk as the generalized AcquireNamedMutex/ReleaseNamedMutex.

TraySkillsVaultStatus:
    modeFile := A_Temp "\skills_vault_mode.flag"
    sMode := "auto"
    if FileExist(modeFile) {
        FileRead, sMode, %modeFile%
        sMode := Trim(sMode)
    }
    if (sMode = "locked")
        ShowSkillsStatusBadge("[LOCKED] Skills Vault (manual)")
    else if (sMode = "unlocked")
        ShowSkillsStatusBadge("[UNLOCKED] Skills Vault (manual)")
    else
        ShowSkillsStatusBadge("[AUTO] Skills Vault (focus-driven)")
return

TraySkillsVaultCycle:
    TogglePersonalSkillsLock()
return

TrayToggleDisplayMode:
    ToggleTabletDisplayMode()
return

TrayDuplicateDisplayMode:
    SwitchToDuplicateDisplayMode()
return

UpdateSkillsTrayStatus:
    global g_SkillsTrayStatusLabel
    modeFile := A_Temp "\skills_vault_mode.flag"
    sMode := "auto"
    if FileExist(modeFile) {
        FileRead, sMode, %modeFile%
        sMode := Trim(sMode)
    }
    if (sMode = "locked")
        newLabel := "Skills Vault: [LOCKED] (manual)"
    else if (sMode = "unlocked")
        newLabel := "Skills Vault: [UNLOCKED] (manual)"
    else
        newLabel := "Skills Vault: [AUTO] (focus-driven)"

    if (newLabel != g_SkillsTrayStatusLabel) {
        try {
            Menu, Tray, Rename, %g_SkillsTrayStatusLabel%, %newLabel%
            g_SkillsTrayStatusLabel := newLabel
            Menu, Tray, Disable, %newLabel%
        }
    }
return

; HandleRemoteTrayMenuTriggerBT replaced by the shared HandleRemoteTrayMenuTrigger
; in SharedHelpers.ahk (the BT suffix existed only to avoid a name collision
; between two file-local copies - no longer needed with one shared function).

; ShowSkillsStatusBadge itself now lives in SharedHelpers.ahk - both this
; file and BackgroundAutomations.ahk's WatchSkillsLock call it, so the
; [LOCKED]/[UNLOCKED]/[AUTO]/error color mapping is defined exactly once.
; [END: Personal Skills Lock/Unlock 3-Way Toggle]

; [START: Tablet Headless Display & Mouse Speed Toggle (Win+Shift+P)]
; Toggles cleanly between PC Screen Only (laptop 1080p @ 144Hz, mouse speed 10) and
; Second Screen Only (tablet dummy plug 2560x1600 @ 120Hz, mouse speed 20).
; Uses native Windows 11 numeric switches (1 vs 4) with zero GUI menus, zero delays,
; and no misplaced toast overlays.
ToggleTabletDisplayMode() {
    global PATH_SUNSHINE_SCRIPTS, g_LastManualDisplaySwitch
    g_LastManualDisplaySwitch := A_TickCount
    markerFile := PATH_SUNSHINE_SCRIPTS ? (PATH_SUNSHINE_SCRIPTS "\.fast_since") : ""

    SysGet, primIndex, MonitorPrimary
    SysGet, monName, MonitorName, %primIndex%

    ; If marker exists OR primary monitor is DISPLAY4 (HDMI dummy plug), we are currently in Tablet Mode
    isTablet := FileExist(markerFile) || InStr(monName, "DISPLAY4")

    if (isTablet) {
        ; --- SWITCH TO LAPTOP MODE ---
        ; 1. Reset mouse speed to 10 (normal) and acceleration to 1 (Enhance pointer precision ON)
        DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
        VarSetCapacity(accel, 12, 0)
        NumPut(6, accel, 0, "Int")
        NumPut(10, accel, 4, "Int")
        NumPut(1, accel, 8, "Int")
        DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

        ; 2. Clear marker file for SunshineMouseWatchdog
        FileDelete, %markerFile%

        ; 3. Native silent switch to PC Screen Only (1 = Internal)
        Run, DisplaySwitch.exe 1,, Hide
    } else {
        ; --- SWITCH TO TABLET MODE ---
        ; Bail out if there's no second display at all. Confirmed (Windows forum reports): DisplaySwitch.exe 4 (Second screen only) with only one monitor connected blanks the screen entirely, recoverable only by a blind Win+P keypress sequence with zero visual feedback.
        SysGet, monCount, MonitorCount
        if (monCount < 2) {
            ShowTimedToolTip("No second display detected - staying on current display.", 2000)
            return
        }

        ; 1. Boost mouse speed to 20 (fast) and acceleration to 0 (Enhance pointer precision OFF)
        DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
        VarSetCapacity(accel, 12, 0)
        NumPut(6, accel, 0, "Int")
        NumPut(10, accel, 4, "Int")
        NumPut(0, accel, 8, "Int")
        DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

        ; 2. Create marker file for SunshineMouseWatchdog - content "manual" (rather than the
        ; empty file set_fast.ps1 creates) lets it tell a deliberate manual toggle apart from a
        ; real Sunshine session, so it never overrides this because of a stale sunshine.log or
        ; Tailscale reading (see SunshineMouseWatchdog.ahk's own comment on this).
        FileAppend, manual, %markerFile%

        ; 3. Native silent switch to Second Screen Only (4 = External)
        Run, DisplaySwitch.exe 4,, Hide
    }
}

; Switches to Duplicate display mode (mirrors the laptop screen onto the tablet's dummy plug).
; Treated the same as ToggleTabletDisplayMode()'s Tablet/Second-screen-only branch for mouse speed and the SunshineMouseWatchdog marker, since the tablet's dummy-plug display is still active while duplicated.
; Self-contained rather than sharing code with that function, so its own behavior stays untouched.
SwitchToDuplicateDisplayMode() {
    global PATH_SUNSHINE_SCRIPTS, g_LastManualDisplaySwitch

    ; Bail out if there's no second display at all - same reasoning as ToggleTabletDisplayMode()'s tablet branch (see that function's own comment on this).
    SysGet, monCount, MonitorCount
    if (monCount < 2) {
        ShowTimedToolTip("No second display detected - staying on current display.", 2000)
        return
    }

    g_LastManualDisplaySwitch := A_TickCount
    markerFile := PATH_SUNSHINE_SCRIPTS ? (PATH_SUNSHINE_SCRIPTS "\.fast_since") : ""

    ; Boost mouse speed to 20 (fast) and acceleration to 0 (Enhance pointer precision OFF) - same treatment as ToggleTabletDisplayMode()'s tablet branch.
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 20, "UInt", 3)
    VarSetCapacity(accel, 12, 0)
    NumPut(6, accel, 0, "Int")
    NumPut(10, accel, 4, "Int")
    NumPut(0, accel, 8, "Int")
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

    ; Create marker file for SunshineMouseWatchdog - same "manual" convention as ToggleTabletDisplayMode()'s tablet branch (see that function's own comment for why).
    FileAppend, manual, %markerFile%

    ; Native silent switch to Duplicate (2 = Duplicate, matching the existing 1/4 convention ToggleTabletDisplayMode() already uses for PC-only/Second-screen-only).
    Run, DisplaySwitch.exe 2,, Hide
}

; Hardware lid-open auto-recovery handler:
; Fires instantaneously on Win32 WM_DISPLAYCHANGE (0x007E) whenever displays change.
; Detects when the laptop lid opens (DISPLAY1 returns) while in tablet streaming mode, restoring mouse speed to 10 and resetting display to PC Screen Only silently.
OnDisplayChange_LidRecovery(wParam, lParam, msg, hwnd) {
    global PATH_SUNSHINE_SCRIPTS, g_LastManualDisplaySwitch
    markerFile := PATH_SUNSHINE_SCRIPTS ? (PATH_SUNSHINE_SCRIPTS "\.fast_since") : ""

    ; Guard 1: Ignore display events triggered by manual Win+Shift+P toggles (within 4s)
    if (g_LastManualDisplaySwitch && (A_TickCount - g_LastManualDisplaySwitch < 4000))
        return

    ; Guard 2: Only act if tablet streaming mode was active (fast marker present)
    if (!markerFile || !FileExist(markerFile))
        return

    ; Check if DISPLAY1 (internal laptop panel) has returned
    SysGet, monCount, MonitorCount
    hasInternal := false
    Loop, %monCount%
    {
        SysGet, mName, MonitorName, %A_Index%
        if InStr(mName, "DISPLAY1")
        {
            hasInternal := true
            break
        }
    }

    ; If internal panel is present while marker exists, the laptop lid was opened
    if (hasInternal)
    {
        g_LastManualDisplaySwitch := A_TickCount ; Prevent loop re-entry

        ; 1. Reset mouse speed to 10 (normal) and acceleration to 1 (Enhance pointer precision ON)
        DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "UInt", 10, "UInt", 3)
        VarSetCapacity(accel, 12, 0)
        NumPut(6, accel, 0, "Int")
        NumPut(10, accel, 4, "Int")
        NumPut(1, accel, 8, "Int")
        DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &accel, "UInt", 3)

        ; 2. Clear marker file for SunshineMouseWatchdog
        FileDelete, %markerFile%

        ; 3. Native silent switch to PC Screen Only (1 = Internal 1080p @ 144Hz)
        Run, DisplaySwitch.exe 1,, Hide
    }
}
; [END: Tablet Headless Display & Mouse Speed Toggle]
