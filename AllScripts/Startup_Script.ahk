; AHK Startup
; Fanatic Guru
; 2018 11 21
;
; Startup Script for Startup Folder to Run on Bootup.
;{-----------------------------------------------
; Runs the Scripts Defined in the Files Array
; Removes the Scripts' Tray Icons leaving only AHK Startup
; Creates a ToolTip for the One Tray Icon Showing the Startup Scripts
; If AHK Startup is Exited All Startup Scripts are Exited
;}

; INITIALIZATION - ENVIROMENT
;{-----------------------------------------------
;
#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On
;}

; INITIALIZATION - VARIABLES
;{-----------------------------------------------
;
Files := [	; Additional Startup Files and Folders Can Be Added Between the ( Continuations  ) Below
(Join, 
"D:\Software\Programming\AutoHotKey\AllScripts\Brightness.ahk"
"D:\Software\Programming\AutoHotKey\AllScripts\Close Programs.ahk"
"D:\Software\Programming\AutoHotKey\AllScripts\Basic Tasks.ahk"
"D:\Software\Programming\AutoHotKey\AllScripts\Personal_Keywords.ahk"
"D:\Software\Programming\AutoHotKey\AllScripts\HotkeyHelp.ahk"
)]
;}


; AUTO-EXECUTE
;{-----------------------------------------------
;
if FileExist(RegExReplace(A_ScriptName,"(.*)\..*","$1.txt")) ; Look for text file with same name as script
    Loop, Read, % RegExReplace(A_ScriptName,"(.*)\..*","$1.txt")
    if A_LoopReadLine
    Files.Insert(A_LoopReadLine)

Scripts := {}
For key, File in Files
{
    RegExMatch(File,"^(\.*)\\",Match), R := StrLen(Match1) ; Look for relative pathing
    if (R=1) 
        File_Exp := A_ScriptDir SubStr(File,R+1)
    else if (R>1)
        File_Exp := SubStr(A_ScriptDir,1,InStr(A_ScriptDir,"\",,0,R-1)) SubStr(File,R+2)
    else
        File_Exp := File
    if RegExMatch(File_Exp,"\\$") ; If File ends in \ assume it is a folder
        Loop, %File_Exp%*.*,,1 ; Get full path of all files in folder and subfolders
        Scripts.Insert(A_LoopFileFullPath)
    else
        if RegExMatch(File_Exp,"\*|\?") ; If File contains wildcard
        Loop, %File_Exp%,,1 ; Get full path of all matching files in folder and subfolders
        Scripts.Insert(A_LoopFileFullPath)
    else
        Scripts.Insert(File_Exp)
}

Startup := {}
for index, Script in Scripts ; Run All the Scripts, Keep Their PID, Keep Info for Tooltip Text
{
    RegExMatch(Script,"([^\\]*)\..*$", Match), Script_Name := Match1
    Run, %Script%,,, pid
    Startup[Script_Name,"PID"] := pid
    Tip_Text .= Script_Name "`n"
}

Sort, Tip_Text ; Create the Tooltip
Tip_Text := TrimAtDelim(Trim(Tip_Text, " `n"))
Menu, Tray, Tip, %Tip_Text% ; Tooltip is limited to first 127 characters

; Shortcut Trick to Get Windows 7 to Update Hidden Tray (Uncomment if needed)
; Send {LWin Down}b{LWin Up}{Enter}{Escape} 

Sleep 500
gosub MenuBuild

OnExit, ExitSub ; Gosub to ExitSub when this Script Exits

Tray_Icons := {}
Loop, 10	; Try To Remove Over Time Because Icons May Lag During Bootup
{
    Tray_Icons := TrayIcon_GetInfo()
    for index, Script in Startup
        for index2, Icon in Tray_Icons
        If (Script.Pid = Icon.Pid)
        TrayIcon_Remove(Icon.hWnd, Icon.uID)
    Sleep A_index**2 * 200
}
;
;}-----------------------------------------------
; END OF AUTO-EXECUTE

; HOTKEYS
;{-----------------------------------------------
; 
;Win+ScrollLock Suspend AutoHotkey
#ScrollLock::Suspend ;{ +Fn <-- Suspend All Scripts
~#^!ScrollLock::ExitApp ;{ +Fn <-- Terminate All Scripts
~#^!r::Reload ;{ +Fn <-- Reload All Scripts
;}

; SUBROUTINES
;{-----------------------------------------------
;
ExitSub: ; Stop All the Startup Scripts (Called When this Scripts Exits)
    for index, Script in Startup
    {
        WinGet, hWnds, List, % "ahk_pid " Script.PID
        Loop % hWnds
        {
            hWnd := hWnds%A_Index%
            WinKill, % "ahk_id " hWnd	
        }
    }
ExitApp
return
;}

; SUBROUTINES - GUI
;{-----------------------------------------------
;
MenuBuild:	
    for index, Script in Startup
    {	
        PID := Script.PID
        Menu, SubMenu_%PID%, Add, View Lines, ScriptCommand
        Menu, SubMenu_%PID%, Add, View Variables, ScriptCommand
        Menu, SubMenu_%PID%, Add, View Hotkeys, ScriptCommand
        Menu, SubMenu_%PID%, Add, View Key History, ScriptCommand
        Menu, SubMenu_%PID%, Add
        Menu, SubMenu_%PID%, Add, &Open, ScriptCommand
        Menu, SubMenu_%PID%, Add, &Edit, ScriptCommand
        Menu, SubMenu_%PID%, Add, &Exit, ScriptCommand
    }

    for index, Script in Startup
    {	
        PID := Script.PID
        Menu, Tray, Add, %index%, :SubMenu_%PID%
    }

    Menu, Tray, NoStandard
    Menu, Tray, Add
    Menu, Tray, Standard
return

ScriptCommand:
    Cmd_Open = 65300
    Cmd_Edit = 65401
    Cmd_Exit = 65405
    Cmd_ViewLines = 65406
    Cmd_ViewVariables = 65407
    Cmd_ViewHotkeys = 65408
    Cmd_ViewKeyHistory = 65409
    PID := RegExReplace(A_ThisMenu,"SubMenu_(\d*)$","$1")
    cmd := RegExReplace(A_ThisMenuItem, "[^\w#@$?\[\]]") ; strip invalid chars
    cmd := Cmd_%cmd%
    PostMessage, 0x111, %cmd%,,,ahk_pid %PID%
    if (cmd = 65405)
    {
        for index, Script in Startup
            if (Script.PID = PID)
        {
            Startup.Remove(index)
            break
        }
        Menu, Tray, Delete, %index%
        Tip_Text := RegExReplace(Tip_Text,index "\v?")
        Menu, Tray, Tip, %Tip_Text%
    }
return
;}

; FUNCTIONS
;{-----------------------------------------------
;
TrimAtDelim(String,Length:=124,Delim:="`n",Tail:="...")
{
    if (StrLen(String)>Length)
        RegExMatch(SubStr(String, 1, Length+1),"(.*)" Delim, Match), Result := Match Tail
    else
        Result := String
return Result
}
;}

; FUNCTIONS - LIBRARY
;{-----------------------------------------------
;

TrayIcon_GetInfo(sExeName := "")
{
DetectHiddenWindows, % (Setting_A_DetectHiddenWindows := A_DetectHiddenWindows) ? "On" :
    oTrayIcon_GetInfo := {}
    For key, sTray in ["Shell_TrayWnd", "NotifyIconOverflowWindow"]
    {
        idxTB := TrayIcon_GetTrayBar(sTray)
        WinGet, pidTaskbar, PID, ahk_class %sTray%

        hProc := DllCall("OpenProcess", UInt, 0x38, Int, 0, UInt, pidTaskbar)
        pRB := DllCall("VirtualAllocEx", Ptr, hProc, Ptr, 0, UPtr, 20, UInt, 0x1000, UInt, 0x4)

        SendMessage, 0x418, 0, 0, ToolbarWindow32%idxTB%, ahk_class %sTray% ; TB_BUTTONCOUNT

        szBtn := VarSetCapacity(btn, (A_Is64bitOS ? 32 : 20), 0)
        szNfo := VarSetCapacity(nfo, (A_Is64bitOS ? 32 : 24), 0)
        szTip := VarSetCapacity(tip, 128 * 2, 0)

        Loop, %ErrorLevel%
        {
            SendMessage, 0x417, A_Index - 1, pRB, ToolbarWindow32%idxTB%, ahk_class %sTray% ; TB_GETBUTTON
            DllCall("ReadProcessMemory", Ptr, hProc, Ptr, pRB, Ptr, &btn, UPtr, szBtn, UPtr, 0)

            iBitmap := NumGet(btn, 0, "Int")
            IDcmd := NumGet(btn, 4, "Int")
            statyle := NumGet(btn, 8)
            dwData := NumGet(btn, (A_Is64bitOS ? 16 : 12))
            iString := NumGet(btn, (A_Is64bitOS ? 24 : 16), "Ptr")

            DllCall("ReadProcessMemory", Ptr, hProc, Ptr, dwData, Ptr, &nfo, UPtr, szNfo, UPtr, 0)

            hWnd := NumGet(nfo, 0, "Ptr")
            uID := NumGet(nfo, (A_Is64bitOS ? 8 : 4), "UInt")
            msgID := NumGet(nfo, (A_Is64bitOS ? 12 : 8))
            hIcon := NumGet(nfo, (A_Is64bitOS ? 24 : 20), "Ptr")

            WinGet, pID, PID, ahk_id %hWnd%
            WinGet, sProcess, ProcessName, ahk_id %hWnd%
            WinGetClass, sClass, ahk_id %hWnd%

            If !sExeName || (sExeName = sProcess) || (sExeName = pID)
            {
                DllCall("ReadProcessMemory", Ptr, hProc, Ptr, iString, Ptr, &tip, UPtr, szTip, UPtr, 0)
                Index := (oTrayIcon_GetInfo.MaxIndex()>0 ? oTrayIcon_GetInfo.MaxIndex()+1 : 1)
                oTrayIcon_GetInfo[Index,"idx"] := A_Index - 1
                oTrayIcon_GetInfo[Index,"IDcmd"] := IDcmd
                oTrayIcon_GetInfo[Index,"pID"] := pID
                oTrayIcon_GetInfo[Index,"uID"] := uID
                oTrayIcon_GetInfo[Index,"msgID"] := msgID
                oTrayIcon_GetInfo[Index,"hIcon"] := hIcon
                oTrayIcon_GetInfo[Index,"hWnd"] := hWnd
                oTrayIcon_GetInfo[Index,"Class"] := sClass
                oTrayIcon_GetInfo[Index,"Process"] := sProcess
                oTrayIcon_GetInfo[Index,"Tooltip"] := StrGet(&tip, "UTF-16")
                oTrayIcon_GetInfo[Index,"Tray"] := sTray
            }
        }
        DllCall("VirtualFreeEx", Ptr, hProc, Ptr, pRB, UPtr, 0, Uint, 0x8000)
        DllCall("CloseHandle", Ptr, hProc)
    }
    DetectHiddenWindows, %Setting_A_DetectHiddenWindows%
Return oTrayIcon_GetInfo
}

TrayIcon_GetTrayBar(Tray:="Shell_TrayWnd")
{
DetectHiddenWindows, % (Setting_A_DetectHiddenWindows := A_DetectHiddenWindows) ? "On" :
    WinGet, ControlList, ControlList, ahk_class %Tray%
    RegExMatch(ControlList, "(?<=ToolbarWindow32)\d+(?!.*ToolbarWindow32)", nTB)
    Loop, %nTB%
    {
        ControlGet, hWnd, hWnd,, ToolbarWindow32%A_Index%, ahk_class %Tray%
        hParent := DllCall( "GetParent", Ptr, hWnd )
        WinGetClass, sClass, ahk_id %hParent%
        If !(sClass = "SysPager" or sClass = "NotifyIconOverflowWindow" )
            Continue
        idxTB := A_Index
        Break
    }
    DetectHiddenWindows, %Setting_A_DetectHiddenWindows%
Return idxTB
}

TrayIcon_Remove(hWnd, uID)
{
    NumPut(VarSetCapacity(NID,(A_IsUnicode ? 2 : 1) * 384 + A_PtrSize * 5 + 40,0), NID)
    NumPut(hWnd , NID, (A_PtrSize == 4 ? 4 : 8 ))
    NumPut(uID , NID, (A_PtrSize == 4 ? 8 : 16 ))
Return DllCall("shell32\Shell_NotifyIcon", "Uint", 0x2, "Uint", &NID)
}

;}