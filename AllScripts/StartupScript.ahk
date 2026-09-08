; Script Link: https://www.autohotkey.com/boards/viewtopic.php?f=6&t=788&p=5942#p5942

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; Win+Fn+ScrollLock  --> Suspend All Scripts' Hotkeys (background timers/watchers keep running)
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

; Enable dark-mode support for the native tray popup menu (follows Windows' current theme).
; Undocumented but stable/widely-used uxtheme.dll ordinals: 135=SetPreferredAppMode, 136=FlushMenuThemes.
; Must run before the menu is ever shown for the first time.
hUxtheme := DllCall("GetModuleHandle", "str", "uxtheme.dll", "ptr")
if (hUxtheme) {
	pSetPreferredAppMode := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 135, "ptr")
	pFlushMenuThemes     := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 136, "ptr")
	if (pSetPreferredAppMode && pFlushMenuThemes) {
		DllCall(pSetPreferredAppMode, "int", 1) ; 1 = AllowDark (follow system, not force)
		DllCall(pFlushMenuThemes)
	}
}

; INITIALIZATION - VARIABLES
;{-----------------------------------------------
; Folder: all files in that folder and subfolders
; Relative Paths: .\ at beginning is the folder of the script, each additional . steps back one folder
; Wildcards: * and ? can be used
; Flags to the right are used to indicate additional instructions, can use tabs for readability
; "/noload" indicates to not load the script initially but add to Load submenu
; "/v1" or no version flag indicates to run with AutoHotkey v1 exe
; "/v2" indicates to run with AutoHotkey v2 exe
; Known limitation: a script run this way doesn't behave correctly in the tray submenu below (Edit/Exit/View Key History, plus the global Suspend Hotkeys/Exit actions all PostMessage v1-specific tray command IDs to the target process).
; That's why every script in this project stays on v1.1 for now instead of using /v2.

; Additional Startup Files and Folders Can Be Added Here
Script_1=%a_scriptdir%\Brightness.ahk
Script_2=%a_scriptdir%\ClosePrograms.ahk
Script_3=%a_scriptdir%\BasicTasks.ahk
Script_4=%a_scriptdir%\PersonalKeywords.ahk
Script_5=%a_scriptdir%\HotkeyHelp.ahk
Script_7=%a_scriptdir%\Watchdog.ahk
Script_8=%a_scriptdir%\BackgroundAutomations.ahk
Script_9=%a_scriptdir%\LocalPaths.ahk
Script_10=%a_scriptdir%\SunshineMouseWatchdog.ahk
Script_11=%a_scriptdir%\Ext4SsdManager.ahk
Script_12=%a_scriptdir%\SharedHelpers.ahk

Files := []
Files.Push(Script_1)
Files.Push(Script_2)
Files.Push(Script_3)
Files.Push(Script_4)
Files.Push(Script_5)
Files.Push(Script_7)
Files.Push(Script_8)
Files.Push(Script_9)
Files.Push(Script_10)
Files.Push(Script_11)
Files.Push(Script_12)

; Scripts pinned to the top of the tray menu's per-script list, in display order.
; Everything else falls back to the normal (alphabetical-looking) order below them.
; Add or remove a name here to change what's pinned - MenuBuild: below needs no other change.
PinnedScripts := ["BasicTasks", "PersonalKeywords"]

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
RunPathV1 := FileExist("C:\Program Files\AutoHotkey\AutoHotkeyU64.exe") ? "C:\Program Files\AutoHotkey\AutoHotkeyU64.exe" : (FileExist("C:\Program Files\AutoHotkey\AutoHotkey.exe") ? "C:\Program Files\AutoHotkey\AutoHotkey.exe" : A_AhkPath)

RunPathV2 := FileExist("C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe") ? "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" : "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"
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
	File := Trim(RegExReplace(File, "/noload|/v1|/v2"))
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
	; Terminate any existing instance running this script path before spawning
	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	WinClose, % Script.Path " ahk_class AutoHotkey"

	; Use same AutoHotkey version to run scripts as this current script is using
	; Required to deal with 'launcher' that was introduced when Autohotkey v2 is installed
	; Requires literal quotes around variables to handle spaces in file paths/names
	Run, % """" Script.RunPath """ """ Script.Path """",, Hide, Pid ; specify Autohotkey version
	Scripts[Script_Name,"Pid"] := Pid
}

; Shortcut Trick to Get Windows 7 to Update Hidden Tray (Uncomment if needed)
; Send {LWin Down}b{LWin Up}{Enter}{Escape}

OnExit, ExitSub ; Gosub to ExitSub when this Script Exits

; Register TaskbarCreated event to automatically restore tray icon if Explorer restarts or loads late
WM_TASKBARCREATED := DllCall("RegisterWindowMessage", "str", "TaskbarCreated")
OnMessage(WM_TASKBARCREATED, "AHK_TASKBARCREATED")

; Allow Explorer (Medium integrity) to send TaskbarCreated & Tray notification messages across UIPI elevation boundaries
DllCall("User32\ChangeWindowMessageFilterEx", "ptr", A_ScriptHwnd, "uint", WM_TASKBARCREATED, "uint", 1, "ptr", 0) ; MSGFLT_ALLOW := 1
DllCall("User32\ChangeWindowMessageFilterEx", "ptr", A_ScriptHwnd, "uint", 0x0404, "uint", 1, "ptr", 0) ; 0x0404 AHK_NOTIFYICON
DllCall("User32\ChangeWindowMessageFilterEx", "ptr", A_ScriptHwnd, "uint", 0x007E, "uint", 1, "ptr", 0) ; 0x007E WM_DISPLAYCHANGE

; Ensure Master Tray Icon is explicitly visible
if FileExist(A_ScriptDir "\..\StartupScript.ico")
	Menu, Tray, Icon, % A_ScriptDir "\..\StartupScript.ico"
else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
	Menu, Tray, Icon, % A_ScriptDir "\..\Startup_Script.ico"
else
	Menu, Tray, Icon

; Global hotkey-suspend state - see SuspendAllToggle: below.
; A plain single-process boolean is the source of truth; the PostMessage cascade to every child is a one-way toggle with no way to query a remote process's real suspend state, so this variable (not the children's own internal state) is what the tray checkmark reflects.
GlobalHotkeysSuspended := false
MenuText_SuspendAll    := "Suspend Hotkeys" ; must match byte-for-byte at every Check/UnCheck
MenuText_ExitAll       := "Exit"
Cmd_Suspend_Global     := 65404 ; ID_FILE_SUSPEND - AutoHotkey's own reserved tray-command ID

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
; No Suspend,Permit/exemption mechanism needed here.
; SuspendAllToggle below only ever PostMessages to the 12 managed child scripts (Scripts[]) - it never touches this master script's own native suspend flag.
; So none of these 4 hotkeys can ever actually become suspended in the first place.
;Win+ScrollLock Suspend All Scripts' Hotkeys
#ScrollLock::gosub SuspendAllToggle ;{ +Fn <-- Suspend All Scripts' Hotkeys
#^!ScrollLock::ExitApp ;{ +Fn <-- Terminate All Scripts
#^!R::gosub ReloadAll ;{ <-- Reload All Scripts Cleanly
#^!W::Run "C:\Program Files\AutoHotkey\WindowSpy.ahk" ;{ <-- Run Window Spy Script
;}

; SUBROUTINES
;{-----------------------------------------------
;
ReloadAll:
	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	for Script_Name, Script in Scripts
	{
		if Script.Path
			WinClose, % Script.Path " ahk_class AutoHotkey"
		if Script.Pid
		{
			Process, Close, % Script.Pid
			Process, WaitClose, % Script.Pid, 1
		}
	}
	Sleep, 100
	Reload
return

; Cascades a real Suspend-Hotkeys toggle to every managed CHILD script (never the master itself - this cascade never targets the master's own window, so its 4 hotkeys stay reachable regardless).
; Targets by path+class, not ahk_pid: a script that has ever shown a SharedHelpers.ahk badge Gui (Hide, not Destroy, after use) can own a second hidden top-level window, and ahk_pid would non-deterministically match either one - only the true main window actually handles this reserved command ID.
; Entry point for both the tray item and the hotkey.
SuspendAllToggle:
	Critical ; a second cascade must never interleave with this one mid-toggle
	GlobalHotkeysSuspended := !GlobalHotkeysSuspended
	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	for Script_Name, Script in Scripts
	{
		if (!Script.Status || !Script.Path)
			continue
		PostMessage, 0x111, %Cmd_Suspend_Global%,,, % Script.Path " ahk_class AutoHotkey"
	}
	gosub SuspendAllCheckSync
	; Toast feedback for the actual toggle only (not the MenuBuild resync below, which would
	; otherwise fire this on every unrelated per-script Exit/Load while suspend happens to be on)
	ToolTip, % GlobalHotkeysSuspended ? "All script hotkeys suspended" : "All script hotkeys resumed"
	SetTimer, RemoveSuspendToggleToolTip, -1500
return

RemoveSuspendToggleToolTip:
	ToolTip
return

; Keeps the tray item's checkmark in sync with GlobalHotkeysSuspended.
; Never use ToggleCheck/%A_ThisMenuItem% for this - A_ThisMenuItem isn't reliably cleared when this is reached via the hotkey rather than a menu click, so a blind toggle could tick the wrong item.
; Called both from the toggle above and from MenuBuild (menu rebuilds wipe the checkmark along with the item).
SuspendAllCheckSync:
	if GlobalHotkeysSuspended
		Menu, Tray, Check, %MenuText_SuspendAll%
	else
		Menu, Tray, UnCheck, %MenuText_SuspendAll%
return

; Thin wrapper, deliberately not a direct "gosub ExitSub" - going through ExitApp lets AHK's own OnExit re-entrancy guard ensure the WinClose/Process,Close cascade in ExitSub runs exactly once.
; Entering ExitSub directly here would let its own trailing ExitApp re-run the whole cascade a second time against now-dead or Windows-recycled PIDs.
ExitAll:
	ExitApp
return

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
	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	for Script_Name, Script in Scripts
	{
		if Script.Path
			WinClose, % Script.Path " ahk_class AutoHotkey"
		if Script.Pid
		{
			Process, Close, % Script.Pid
			Process, WaitClose, % Script.Pid, 1
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
	HasLoadSubmenu := false ; Tracks whether any script landed in SubMenu_Load below.
	                        ; Keeps the separators around it from being added unpaired - this was the cause of the doubled blank separator seen when nothing is unloaded.
	Pinned := {} ; Script_Name -> true for everything already placed by the pinned pass below

	; Build every loaded script's own submenu (Edit/Restart/Exit/etc.) - same for pinned and unpinned scripts alike.
	; Top-level placement (pinned first, then the rest) happens after.
	for Script_Name, Script in Scripts
		if Script.Status
		{
			PID := Script.PID
			try Menu, SubMenu_%PID%, DeleteAll
			Menu, SubMenu_%PID%, Add, View Key History, ScriptCommand
			Menu, SubMenu_%PID%, Add, Edit, ScriptCommand
			Menu, SubMenu_%PID%, Add, Restart, ScriptCommand
			Menu, SubMenu_%PID%, Add, Exit, ScriptCommand

			; Mirror any custom tray items this script has published for itself (generic -- no per-script names/IDs hardcoded here; see BackgroundAutomations.ahk for the publishing side of this).
			; Scripts that don't publish a manifest are unaffected.
			CustomManifest := A_Temp "\ahk_traymenu_" Script_Name ".txt"
			if FileExist(CustomManifest)
			{
				Menu, SubMenu_%PID%, Add
				Loop, Read, %CustomManifest%
				{
					StringSplit, CustomItem, A_LoopReadLine, |
					if (CustomItem0 >= 1 && CustomItem1 != "")
						Menu, SubMenu_%PID%, Add, % CustomItem1, RemoteMenuCommand
				}
			}
		}
		else
		{
			Menu, SubMenu_Load, Add, % Script_Name, ScriptCommand_Load
			HasLoadSubmenu := true
		}

	; Pinned scripts first, in the order listed in PinnedScripts (top of file).
	; Add a name there and it moves to the top automatically - no other change needed.
	HasPinned := false
	for Index, Script_Name in PinnedScripts
		if (Scripts[Script_Name, "Status"])
		{
			PID := Scripts[Script_Name, "PID"]
			Menu, Tray, Add, %Script_Name%, :SubMenu_%PID%
			Pinned[Script_Name] := true
			HasPinned := true
		}
	if (HasPinned)
		Menu, Tray, Add ; separator between pinned scripts and everything else

	; Everything else, in whatever order Scripts naturally enumerates (unchanged from before).
	for Script_Name, Script in Scripts
		if (Script.Status && !Pinned[Script_Name])
		{
			PID := Script.PID
			Menu, Tray, Add, %Script_Name%, :SubMenu_%PID%
		}

	Menu, Tray, NoStandard
	if (HasLoadSubmenu)
	{
		Menu, Tray, Add
		Menu, Tray, Add, Load, :SubMenu_Load
	}
	Menu, Tray, Add
	Menu, Tray, Add, Reload All, ReloadAll
	Menu, Tray, Add, %MenuText_SuspendAll%, SuspendAllToggle
	Menu, Tray, Add, %MenuText_ExitAll%, ExitAll
	gosub SuspendAllCheckSync ; must come AFTER the Add above - Check on a not-yet-added item errors
	; Deliberately NOT calling Menu, Tray, Standard here - it would re-add AHK's own native "Suspend Hotkeys"/"Pause Script"/"Exit" trio, which only ever act on this master script's own 4 hotkeys.
	; Pure clutter alongside the real actions above, which are the ones that actually affect every managed child script.
	if (HasLoadSubmenu)
		Menu, Tray, Default, Load

	if FileExist(A_ScriptDir "\..\StartupScript.ico")
		Menu, Tray, Icon, % A_ScriptDir "\..\StartupScript.ico"
	else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
		Menu, Tray, Icon, % A_ScriptDir "\..\Startup_Script.ico"
	else
		Menu, Tray, Icon
return

ScriptCommand:
	Cmd_Edit			= 65401
	Cmd_Exit			= 65405
	Cmd_ViewKeyHistory	= 65409
	Pid := RegExReplace(A_ThisMenu,"SubMenu_(\d*)$","$1") ; each SubMenu name included Pid
	cmd := RegExReplace(A_ThisMenuItem, "[^\w#@$?\[\]]") ; strip invalid chars

	; Restart has no native reserved command ID (unlike Edit/Exit/ViewKeyHistory, which the
	; child's own AHK runtime already understands) - the master has to do the kill+relaunch
	; itself, so it's handled separately before the generic reserved-ID dispatch below.
	if (cmd = "Restart")
	{
		gosub ScriptCommand_Restart
		return
	}

	cmd := Cmd_%cmd%
	PostMessage, 0x111, %cmd%,,,ahk_pid %Pid%

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

; Kills the script (posting the same reserved Exit command the Exit menu item itself uses) then relaunches it fresh, reusing ScriptCommand_Load's own launch + suspend-resync pattern below.
; Unlike Exit, Status stays true and the script keeps its own top-level tray entry - it never moves to the Load submenu.
; Pid/cmd are still in scope from ScriptCommand above (gosub shares script-level variables, not function-local ones).
ScriptCommand_Restart:
	for Script_Name, Script in Scripts
		if (Script.Pid = Pid)
			break
	if !Script_Name
		return

	OldPath := Scripts[Script_Name].Path
	RunPath := Scripts[Script_Name].RunPath

	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	PostMessage, 0x111, 65405,,, % OldPath " ahk_class AutoHotkey" ; native Exit, same as the Exit item
	WinWaitClose, % OldPath " ahk_class AutoHotkey",, 2

	Run, % """" RunPath """ """ OldPath """",, Hide, NewPid
	Scripts[Script_Name, "Pid"] := NewPid

	; Cmd_Suspend_Global (65404) is a toggle, not a set - mirrors ScriptCommand_Load's own resync below: a freshly-launched script always starts unsuspended, so bring it into sync if global suspend is currently active.
	; WinWait first since Run returns before the new window exists.
	if GlobalHotkeysSuspended
	{
		WinWait, % OldPath " ahk_class AutoHotkey",, 5
		if !ErrorLevel
			PostMessage, 0x111, %Cmd_Suspend_Global%,,, % OldPath " ahk_class AutoHotkey"
	}

	gosub MenuBuild
	gosub TrayTipBuild
return

; Handles clicks on custom items mirrored in from a script's published manifest (see MenuBuild above and BackgroundAutomations.ahk's publishing side).
; Generic -- doesn't know or care which script or which items; just re-reads that PID's manifest to find which line matches the clicked text, then posts that line's 1-based number to the script's own registered remote-trigger message so it can Gosub the right label itself.
RemoteMenuCommand:
	Pid := RegExReplace(A_ThisMenu,"SubMenu_(\d*)$","$1")
	for Script_Name, Script in Scripts
		if (Script.Pid = Pid)
			break
	CustomManifest := A_Temp "\ahk_traymenu_" Script_Name ".txt"
	if !FileExist(CustomManifest)
		return
	LineNum := 0
	Loop, Read, %CustomManifest%
	{
		LineNum++
		StringSplit, CustomItem, A_LoopReadLine, |
		if (CustomItem1 = A_ThisMenuItem)
		{
			RemoteTrayTriggerMsg := DllCall("RegisterWindowMessage", "str", "AHK_RemoteTrayMenuTrigger_v1")
			PostMessage, %RemoteTrayTriggerMsg%, %LineNum%,,,ahk_pid %Pid%
			break
		}
	}
return

ScriptCommand_Load:
	; Run Script and Keep Info
	Run, % """" Scripts[A_ThisMenuItem].RunPath """ """ Scripts[A_ThisMenuItem].Path """",, Hide, Pid ; specify Autohotkey version
	Scripts[A_ThisMenuItem, "Pid"] := Pid
	Scripts[A_ThisMenuItem, "Status"] := true

	; Cmd_Suspend_Global (65404) is a toggle, not a set - a freshly-launched script always starts unsuspended, so if global suspend is currently active, bring this new process into sync with it.
	; Run returns as soon as the process exists, before its window does, so WinWait is required or the PostMessage below would silently miss.
	if GlobalHotkeysSuspended
	{
		DetectHiddenWindows, On
		SetTitleMatchMode, 2
		WinWait, % Scripts[A_ThisMenuItem].Path " ahk_class AutoHotkey",, 5
		if !ErrorLevel
			PostMessage, 0x111, %Cmd_Suspend_Global%,,, % Scripts[A_ThisMenuItem].Path " ahk_class AutoHotkey"
	}

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
					if (hWnd != A_ScriptHwnd)
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
	; Left click shows the tray menu - native default does nothing on a single left click, so no suppression needed here (Menu,Tray,Show is purely additive).
	else if (lParam = 0x202) ; WM_LBUTTONUP
	{
		Menu, Tray, Show
		return 0
	}
	; Right click reloads everything directly instead of the native default of showing the menu.
	; return 0 suppresses that native default - confirmed via AutoHotkey community threads, since this interception isn't covered by the official Menu/OnMessage reference pages.
	else if (lParam = 0x205) ; WM_RBUTTONUP
	{
		gosub ReloadAll
		return 0
	}
}

AHK_DISPLAYCHANGE(wParam, lParam) ; OnMessage(0x7E, "AHK_DISPLAYCHANGE")
{
	; Cleanup Tray Icons on Resolution Change
	TrayIconRemove(8) ; Resolution Change can take a moment so try over time
}

AHK_TASKBARCREATED(wParam, lParam)
{
	gosub TrayTipBuild
	gosub MenuBuild
	if FileExist(A_ScriptDir "\..\StartupScript.ico")
		Menu, Tray, Icon, % A_ScriptDir "\..\StartupScript.ico"
	else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
		Menu, Tray, Icon, % A_ScriptDir "\..\Startup_Script.ico"
	else
		Menu, Tray, Icon
	TrayIconRemove(5)
}
;}