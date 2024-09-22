; Script Link: https://www.autohotkey.com/boards/viewtopic.php?f=6&t=788&p=5942#p5942

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; Win+Fn+ScrollLock  --> Suspend AutoHotkey
; Win+Fn+Alt+Ctr+ScrollLock --> Terminate All AHK Scripts
; Win+Ctr+Alt+R --> Reload All Scripts
; Win+Ctr+Alt+W --> Run Window Spy Script

; AHK Startup
; Fanatic Guru
;
; Version: 2023 03 16
;
; Startup Script for Startup Folder to Run on Bootup.
;{-----------------------------------------------
; Runs the Scripts Defined in the Files Array
; Removes the Scripts' Tray Icons leaving only AHK Startup
; Creates a ToolTip for the One Tray Icon Showing the Startup Scripts
; If AHK Startup is Exited All Startup Scripts are Exited
; Includes a "Load" menu for a list of scripts that are not currently loaded
; Includes flags to allow for running of both v1 and v2 scripts
;}

; INITIALIZATION - ENVIROMENT
;{-----------------------------------------------
;
#Requires AutoHotkey v1.1.33
#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On
;}

; INITIALIZATION - VARIABLES
;{-----------------------------------------------
; Folder: all files in that folder and subfolders
; Relative Paths: .\ at beginning is the folder of the script, each additional . steps back one folder
; Wildcards: * and ? can be used
; Flags to the right are used to indicate additional instructions, can use tabs for readability
; "/noload" indicates to not load the script initially but add to Load submenu
; "/v1" or no version flag indicates to run with AutoHotkey v1 exe
; "/v2" indicates to run with AutoHotkey v2 exe

; Additional Startup Files and Folders Can Be Added Here
Script_1=%a_scriptdir%\Brightness.ahk
Script_2=%a_scriptdir%\Close Programs.ahk
Script_3=%a_scriptdir%\Basic Tasks.ahk
Script_4=%a_scriptdir%\Personal Keywords.ahk
Script_5=%a_scriptdir%\HotkeyHelp.ahk

Files := []
Files.Push(Script_1)
Files.Push(Script_2)
Files.Push(Script_3)
Files.Push(Script_4)
Files.Push(Script_5)

; Loop, 1
; {
;     FilePath := "Script_" . %A_Index%
;     MsgBox, FilePath
; }
;}

; Previously Used
; Files := [
; (Join, 
; "Add Path to the AHK FILE"
; )]

; Define Path to AutoHotkey.exe for v1 and v2
RunPathV1 := A_AhkPath
RunPathV2 := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey.exe"
;}

; AUTO-EXECUTE
;{-----------------------------------------------
;
if FileExist(RegExReplace(A_ScriptName,"(.*)\..*","$1.txt")) ; Look for text file with same name as script
	Loop, Read, % RegExReplace(A_ScriptName,"(.*)\..*","$1.txt")
		if A_LoopReadLine
			Files.Insert(A_LoopReadLine)

Scripts := {}
For index, File in Files
{
	if File ~= "/noload"
		Status := false
	else
		Status := true
	if File ~= "/v2"
		RunPath := RunPathV2
	else
		RunPath := RunPathV1
	File := RegExReplace(File, "/noload|/v1|/v2")
	RegExMatch(File,"^(\.*)\\",Match), R := StrLen(Match1) ; Look for relative pathing
	if (R=1)
		File := A_ScriptDir SubStr(File,R+1)
	else if (R>1)
		File := SubStr(A_ScriptDir,1,InStr(A_ScriptDir,"\",,0,R-1)) SubStr(File,R+2)

	if RegExMatch(File,"\\$") ; If File ends in \ assume it is a folder
		Loop, %File%*.*,,1 ; Get full path of all files in folder and subfolders
		{
			SplitPath, % A_LoopFileFullPath,,,, Script_Name
			Scripts[Script_Name, "Path"] := A_LoopFileFullPath
			Scripts[Script_Name, "Status"] := Status
			Scripts[Script_Name, "RunPath"] := RunPath
		}
	else
		if RegExMatch(File,"\*|\?") ; If File contains wildcard
			Loop, %File%,,1 ; Get full path of all matching files in folder and subfolders
			{
				SplitPath, % A_LoopFileFullPath,,,, Script_Name
				Scripts[Script_Name, "Path"] := A_LoopFileFullPath
				Scripts[Script_Name, "Status"] := Status
				Scripts[Script_Name, "RunPath"] := RunPath
			}
		else
		{
			SplitPath, % File,,,, Script_Name
			Scripts[Script_Name, "Path"] := File
			Scripts[Script_Name, "Status"] := Status
			Scripts[Script_Name, "RunPath"] := RunPath
		}
}

; Run All the Scripts with Status true, Keep Their Pid
for Script_Name, Script in Scripts
{
	if !Script.Status
		continue
	; Use same AutoHotkey version to run scripts as this current script is using
	; Required to deal with 'launcher' that was introduced when Autohotkey v2 is installed
	; Requires literal quotes around variables to handle spaces in file paths/names
	Run, % """" Script.RunPath """ """ Script.Path """",,, Pid ; specify Autohotkey version
	Scripts[Script_Name,"Pid"] := Pid
}

; Shortcut Trick to Get Windows 7 to Update Hidden Tray (Uncomment if needed)
; Send {LWin Down}b{LWin Up}{Enter}{Escape} 

OnExit, ExitSub ; Gosub to ExitSub when this Script Exits

; Build Menu and TrayTip then Remove Tray Icons
gosub TrayTipBuild
gosub MenuBuild
OnMessage(0x404, "AHK_NOTIFYICON") ; Hook Events for Tray Icon (used for Tray Icon cleanup on mouseover)
OnMessage(0x7E, "AHK_DISPLAYCHANGE") ; Hook Events for Display Change (used for Tray Icon cleanup on resolution change)
TrayIconRemove(10)

;
;}-----------------------------------------------
; END OF AUTO-EXECUTE

; HOTKEYS
;{-----------------------------------------------
;
;Win+ScrollLock Suspend AutoHotkey
#ScrollLock::Suspend ;{ +Fn <-- Suspend All Scripts
#^!ScrollLock::ExitApp ;{ +Fn <-- Terminate All Scripts
#^!R::Reload ;{ <-- Reload All Scripts
#^!W::Run "C:\Program Files\AutoHotkey\WindowSpy.ahk" ;{ <-- Run Window Spy Script
;}

; SUBROUTINES
;{-----------------------------------------------
;
TrayTipBuild:
	Tip_Text := ""
	for Script_Name, Script in Scripts
		if Script.Status
			Tip_Text .= Script_Name "`n"
	Sort, Tip_Text
	Tip_Text := TrimAtDelim(Trim(Tip_Text, " `n"))
	Menu, Tray, Tip, %Tip_Text% ; Tooltip is limited to first 127 characters
return

; Stop All the Scripts with Status true (Called When this Scripts Exits)
ExitSub:
	for Script_Name, Script in Scripts
	{
		WinGet, hWnds, List, % "ahk_pid " Script.Pid
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
	try Menu, SubMenu_Load, DeleteAll ; SubMenu_Load does not always exist
	Menu, Tray, DeleteAll
	for Script_Name, Script in Scripts
		if Script.Status
		{
			PID := Script.PID
			try Menu, SubMenu_%PID%, DeleteAll
			Menu, SubMenu_%PID%, Add, View Lines, ScriptCommand
			Menu, SubMenu_%PID%, Add, View Variables, ScriptCommand
			Menu, SubMenu_%PID%, Add, View Hotkeys, ScriptCommand
			Menu, SubMenu_%PID%, Add, View Key History, ScriptCommand
			Menu, SubMenu_%PID%, Add
			Menu, SubMenu_%PID%, Add, &Open, ScriptCommand
			Menu, SubMenu_%PID%, Add, &Edit, ScriptCommand
			Menu, SubMenu_%PID%, Add, &Pause, ScriptCommand
			Menu, SubMenu_%PID%, Add, &Suspend, ScriptCommand
			Menu, SubMenu_%PID%, Add, &Reload, ScriptCommand
			Menu, SubMenu_%PID%, Add, &Exit, ScriptCommand
			Menu, Tray, Add, %Script_Name%, :SubMenu_%PID%
		}
		else
			Menu, SubMenu_Load, Add, % Script_Name, ScriptCommand_Load

	Menu, Tray, NoStandard
	Menu, Tray, Add
	try Menu, Tray, Add, Load, :SubMenu_Load ; SubMenu_Load does not always exist
	Menu, Tray, Standard
	try Menu, Tray, Default, Load ; SubMenu_Load does not always exist
return

ScriptCommand:
	Cmd_Open			= 65300
	Cmd_Reload			= 65400
	Cmd_Edit			= 65401
	Cmd_Pause			= 65403
	Cmd_Suspend			= 65404
	Cmd_Exit			= 65405
	Cmd_ViewLines		= 65406
	Cmd_ViewVariables	= 65407
	Cmd_ViewHotkeys		= 65408
	Cmd_ViewKeyHistory	= 65409
	Pid := RegExReplace(A_ThisMenu,"SubMenu_(\d*)$","$1") ; each SubMenu name included Pid
    cmd := RegExReplace(A_ThisMenuItem, "[^\w#@$?\[\]]") ; strip invalid chars

	; if Cmd_Reload, simulate by exiting and running again with captured Pid
	if (cmd = "Reload")
	{
		for Script_Name, Script in Scripts ; find Script by Pid
			if (Script.Pid = Pid)
				break
		Menu, SubMenu_%PID%, DeleteAll ; delete Tray SubMenu of old Pid (use 'try' just in case)
		PostMessage, 0x111, Cmd_Exit,,,ahk_pid %Pid%
		Run, % """" Script.RunPath """ """ Script.Path """",,, Pid ; specify Autohotkey version
		Scripts[Script_Name,"Pid"] := Pid
		gosub MenuBuild ; need to rebuild menu because changed Pid is used in menu names
		TrayIconRemove(8) ; need to remove new icon
	}
	else
	{
	    if (cmd = "Pause" or cmd = "Suspend")
			Menu, SubMenu_%PID%, ToggleCheck, %A_ThisMenuItem%
		cmd := Cmd_%cmd%
		PostMessage, 0x111, %cmd%,,,ahk_pid %Pid%
	}

	; If Cmd_Exit then Set Status to false
	if (cmd = 65405)
	{
		for Script_Name, Script in Scripts
			if (Script.Pid = Pid)
				break
		Scripts[Script_Name, "Status"] := false

		; Rebuild Menu and TrayTip
		gosub MenuBuild
		gosub TrayTipBuild
	}
return

ScriptCommand_Load:
	; Run Script and Keep Info
	Run, % """" Scripts[A_ThisMenuItem].RunPath """ """ Scripts[A_ThisMenuItem].Path """",,, Pid ; specify Autohotkey version
	Scripts[A_ThisMenuItem, "Pid"] := Pid
	Scripts[A_ThisMenuItem, "Status"] := true

	; Rebuild Menu and TrayTip then Remove Tray Icon
	gosub MenuBuild
	gosub TrayTipBuild
	TrayIconRemove(8)
return

;}

; FUNCTIONS
;{-----------------------------------------------
;
TrayIconRemove(Attempts)
{
	global Scripts
	Loop, % Attempts	; Try To Remove Over Time Because Icons May Lag Especially During Bootup
	{
		for Script_Name, Script in Scripts
			if Script.Status
			{
				WinGet, hWnds, List, % "ahk_pid " Script.Pid
				Loop % hWnds
				{
					hWnd := hWnds%A_Index%
					KillTrayIcon(hWnd)
				}
			}
		Sleep A_index**2 * 200
	}
	return
}

; Lexikos 
KillTrayIcon(scriptHwnd) {
    static NIM_DELETE := 2, AHK_NOTIFYICON := 1028
    VarSetCapacity(nic, size := 936+4*A_PtrSize)
    NumPut(size, nic, 0, "uint")
    NumPut(scriptHwnd, nic, A_PtrSize)
    NumPut(AHK_NOTIFYICON, nic, A_PtrSize*2, "uint")
    return DllCall("Shell32\Shell_NotifyIcon", "uint", NIM_DELETE, "ptr", &nic)
}

TrimAtDelim(String,Length:=124,Delim:="`n",Tail:="...")
{
	if (StrLen(String)>Length)
		RegExMatch(SubStr(String, 1, Length+1),"(.*)" Delim, Match), Result := Match Tail
	else
		Result := String
	return Result
}

AHK_NOTIFYICON(wParam, lParam, uMsg, hWnd) ; OnMessage(0x404, "AHK_NOTIFYICON")
{
	; Cleanup Tray Icons on MouseOver
	if (lParam = 0x200) ; WM_MOUSEMOVE := 0x200
		TrayIconRemove(1)
}

AHK_DISPLAYCHANGE(wParam, lParam) ; OnMessage(0x7E, "AHK_DISPLAYCHANGE")
{
	; Cleanup Tray Icons on Resolution Change
	TrayIconRemove(8) ; Resolution Change can take a moment so try over time
}
;}