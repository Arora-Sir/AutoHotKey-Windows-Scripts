; ^ for Ctrl, ! for Alt, # for Win, + for Shift

; NumLock AlwaysOn && ScrollLock Always Off
; Double tap Caps lock to activate/deactivate Caps lock

; Wi+F --> Run FireFox
; Win+Shift+E --> Open Downloads (My Screenshots) folder
; Win+Shift+A --> Open Notification center
; Win+Del --> Empty Recycle Bin
; Alt+Shift+T --> Active window Always on Top
; Alt+Ctr+E --> Enable/Disable file extension
; Alt+Ctr+H --> Enable/Disable hidden files

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

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

OpenActionCenter(){
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
    Return
}


; Set Lock keys permanently
SetNumlockState, AlwaysOn ;{ <-- NumLock AlwaysOn & ScrollLock Always Off
; SetScrollLockState, AlwaysOff ;Commented this to use scrollLock for scripts suspend & terminate
; SetCapsLockState, AlwaysOff

; #LAlt::^#Right ; switch to next desktop with Windows key + Left Alt key -> Original is Win + Ctr + Right
; #LCtrl::^#Left ; switch to next desktop with Windows key + Left CTRL key -> Original is Win + Ctr + Left

; Window+F Run FireFox
#f::Run Firefox ;{ <-- Open FireFox

; Win+Shift+E Open Downloads (My Screenshots) folder
#+e::Run "C:\Users\Mohit\Pictures\Screenshots" ;{ <-- Open Screenshots Folder

; Window+Shift+T Active window Always on Top
!+T:: Winset, Alwaysontop, , A ;{ <-- This Winodw Always on Top

; Win+Del Empty Recycle Bin
#Del::FileRecycleEmpty ;{ <-- Delete Recycle Bin Data

; Win+Shift+A Open Notification center
#+A::OpenActionCenter() ;{ <-- Open Notification center

; Alt+Ctr+E Enable/Disable file extension
$!^E:: ToggleFileExt() ;{ <-- Show/Hide Extenstions

; Alt+Ctr+E Enable/Disable hidden files
$!^H:: HideFiles() ;{ <-- Show/Hide Hidden Files

; Double Tap caps lock to on and off
*CapsLock::DoubleTapCapsLock() ;{ <-- Double Tap To Activate/Deactivate

;Turn Caps Lock into a Shift key
; Capslock::Shift

;F1:: send {Left}
; +NumpadAdd:: Send {Volume_Up}
; +NumpadSub:: Send {Volume_Down}
; break::Send {Volume_Mute}
; return