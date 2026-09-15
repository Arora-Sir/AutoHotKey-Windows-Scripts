; Script Link: https://www.autohotkey.com/boards/viewtopic.php?f=6&t=788&p=5942#p5942

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; Win+Fn+ScrollLock  -> Suspend All Scripts' Hotkeys (background timers/watchers keep running)
; Win+Fn+Alt+Ctr+ScrollLock -> Terminate All AHK Scripts
; Win+Ctr+Alt+R -> Reload All Scripts
; Win+Ctr+Alt+W -> Run Window Spy Script

; AHK Startup
; Fanatic Guru
;
; Version: 2023 03 16 (v2 port)
;
; Startup Script for Startup Folder to Run on Bootup.
;{-----------------------------------------------
; Runs the Scripts Defined in the Files Array
; Removes the Scripts' Tray Icons leaving only AHK Startup
; Creates a ToolTip for the One Tray Icon Showing the Startup Scripts
; If AHK Startup is Exited All Startup Scripts are Exited
; Includes a "Load" menu for a list of scripts that are not currently loaded
;}

; INITIALIZATION - ENVIROMENT
;{-----------------------------------------------
;
#Requires AutoHotkey v2.0
SendMode("Input") ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir(A_ScriptDir) ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows(true)
;}

; Enable dark-mode support for the native tray popup menu (follows Windows' current theme).
; Undocumented but stable/widely-used uxtheme.dll ordinals: 135=SetPreferredAppMode, 136=FlushMenuThemes.
; Must run before the menu is ever shown for the first time.
hUxtheme := DllCall("GetModuleHandle", "Str", "uxtheme.dll", "Ptr")
if (hUxtheme) {
	pSetPreferredAppMode := DllCall("GetProcAddress", "Ptr", hUxtheme, "Ptr", 135, "Ptr")
	pFlushMenuThemes     := DllCall("GetProcAddress", "Ptr", hUxtheme, "Ptr", 136, "Ptr")
	if (pSetPreferredAppMode && pFlushMenuThemes) {
		DllCall(pSetPreferredAppMode, "Int", 1) ; 1 = AllowDark (follow system, not force)
		DllCall(pFlushMenuThemes)
	}
}

; v2 fleet control protocol: replaces v1's PostMessage to AutoHotkey's own reserved tray-command IDs (Edit/Exit/
; ViewKeyHistory/Suspend), which is not guaranteed to carry over to a v2 process. The master only ever SENDS this
; message (every child script both registers and handles it - see SharedHelpers.ahk/LocalPaths.ahk/Watchdog.ahk for
; the receiving side). Registering it here just needs to resolve to the same numeric ID every process gets.
g_FleetControlMsg := DllCall("RegisterWindowMessage", "Str", "AHK_FleetControl_v2", "UInt")
; Codes match every child's own HandleFleetControlMessage: 1=Edit, 2=Exit, 3=ViewKeyHistory, 4=Suspend-toggle.
; "Restart" has no code of its own - it's still master-side orchestration (post code 2, wait, relaunch), same as v1.

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
Script_1 := A_ScriptDir "\Brightness.ahk /v2"
Script_2 := A_ScriptDir "\ClosePrograms.ahk /v2"
Script_3 := A_ScriptDir "\BasicTasks.ahk /v2"
Script_4 := A_ScriptDir "\PersonalKeywords.ahk /v2"
Script_5 := A_ScriptDir "\HotkeyHelp.ahk /v2"
Script_7 := A_ScriptDir "\Watchdog.ahk /v2"
Script_8 := A_ScriptDir "\BackgroundAutomations.ahk /v2"
Script_9 := A_ScriptDir "\LocalPaths.ahk /v2"
Script_10 := A_ScriptDir "\SunshineDisplayWatchdog.ahk /v2"
Script_11 := A_ScriptDir "\Ext4SsdManager.ahk /v2"
Script_12 := A_ScriptDir "\SharedHelpers.ahk /v2"

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
; Add or remove a name here to change what's pinned - MenuBuild() below needs no other change.
PinnedScripts := ["BasicTasks", "PersonalKeywords", "SunshineDisplayWatchdog"]
g_CurrentBasicTasksDrmItem := ""
g_CurrentSunshineMouseSpeedItem := ""
; v2: per-PID Menu objects, replacing v1's dynamically-name-string-addressed "SubMenu_%PID%" system, since v2
; submenus are attached by object reference, not by a constructed name string. Rebuilt fresh every MenuBuild() call.
g_ScriptMenus := Map()
;}

; Define Path to AutoHotkey.exe for v1 and v2
RunPathV1 := FileExist("C:\Program Files\AutoHotkey\AutoHotkeyU64.exe") ? "C:\Program Files\AutoHotkey\AutoHotkeyU64.exe" : (FileExist("C:\Program Files\AutoHotkey\AutoHotkey.exe") ? "C:\Program Files\AutoHotkey\AutoHotkey.exe" : A_AhkPath)

RunPathV2 := FileExist("C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe") ? "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" : "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"

; AUTO-EXECUTE
;{-----------------------------------------------
;
if FileExist(RegExReplace(A_ScriptName, "(.*)\..*", "$1.txt")) ; Look for text file with same name as script
	Loop Read, RegExReplace(A_ScriptName, "(.*)\..*", "$1.txt")
		if A_LoopReadLine
			Files.Push(A_LoopReadLine)

; v2: Scripts is a Map (v1's Scripts[Name,"Key"] multi-key object indexing has no direct v2 equivalent), each value
; a plain object with named properties (.Path/.Status/.RunPath/.Pid), matching how the rest of this file reads them.
Scripts := Map()
; v2: "File" is a reserved built-in class name (the FileOpen() return type) - it cannot be used as a plain variable
; (including a for-loop's iteration variable, which errors at load time with "This Class cannot be used as an output
; variable"), so v1's original "File" variable name throughout this block is renamed to "fileEntry" here.
for index, fileEntry in Files {
	if InStr(fileEntry, "/noload")
		status := false
	else
		status := true
	if InStr(fileEntry, "/v2")
		runPath := RunPathV2
	else
		runPath := RunPathV1
	fileEntry := Trim(RegExReplace(fileEntry, "/noload|/v1|/v2"))
	r := 0
	if RegExMatch(fileEntry, "^(\.*)\\", &match) ; Look for relative pathing
		r := StrLen(match[1])
	if (r = 1)
		fileEntry := A_ScriptDir SubStr(fileEntry, r + 1)
	else if (r > 1)
		fileEntry := SubStr(A_ScriptDir, 1, InStr(A_ScriptDir, "\", , 0, r - 1)) SubStr(fileEntry, r + 2)

	if RegExMatch(fileEntry, "\\$") { ; If fileEntry ends in \ assume it is a folder
		Loop Files, fileEntry "*.*", "R" { ; Get full path of all files in folder and subfolders
			SplitPath(A_LoopFileFullPath, , , , &scriptName)
			Scripts[scriptName] := {Path: A_LoopFileFullPath, Status: status, RunPath: runPath}
		}
	} else if RegExMatch(fileEntry, "\*|\?") { ; If fileEntry contains wildcard
		Loop Files, fileEntry, "R" { ; Get full path of all matching files in folder and subfolders
			SplitPath(A_LoopFileFullPath, , , , &scriptName)
			Scripts[scriptName] := {Path: A_LoopFileFullPath, Status: status, RunPath: runPath}
		}
	} else {
		SplitPath(fileEntry, , , , &scriptName)
		Scripts[scriptName] := {Path: fileEntry, Status: status, RunPath: runPath}
	}
}

; Run All the Scripts with Status true, Keep Their Pid
for scriptName, script in Scripts {
	if !script.Status
		continue
	; Terminate any existing instance running this script path before spawning.
	; v2: WinClose() against a non-existent window hangs indefinitely in this environment (Migration-Notes.md
	; section 18.6) - resolved by guarding with WinExist() first, confirmed to return instantly (falsy) against a
	; non-existent target rather than hanging. Each child's own #SingleInstance force remains the backstop against
	; a genuine duplicate either way.
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	if WinExist(script.Path " ahk_class AutoHotkey")
		WinClose(script.Path " ahk_class AutoHotkey")

	; Use same AutoHotkey version to run scripts as this current script is using
	; Required to deal with 'launcher' that was introduced when Autohotkey v2 is installed
	; Requires literal quotes around variables to handle spaces in file paths/names
	Run('"' script.RunPath '" "' script.Path '"', , "Hide", &pid) ; specify Autohotkey version
	script.Pid := pid
}

; Shortcut Trick to Get Windows 7 to Update Hidden Tray (Uncomment if needed)
; Send("{LWin Down}b{LWin Up}{Enter}{Escape}")

OnExit(ExitSub) ; Call ExitSub when this Script Exits

; Register TaskbarCreated event to automatically restore tray icon if Explorer restarts or loads late
WM_TASKBARCREATED := DllCall("RegisterWindowMessage", "Str", "TaskbarCreated", "UInt")
OnMessage(WM_TASKBARCREATED, AHK_TASKBARCREATED)

; Allow Explorer (Medium integrity) to send TaskbarCreated & Tray notification messages across UIPI elevation boundaries
DllCall("User32\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", WM_TASKBARCREATED, "UInt", 1, "Ptr", 0) ; MSGFLT_ALLOW := 1
DllCall("User32\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", 0x0404, "UInt", 1, "Ptr", 0) ; 0x0404 AHK_NOTIFYICON
DllCall("User32\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", 0x007E, "UInt", 1, "Ptr", 0) ; 0x007E WM_DISPLAYCHANGE

; Ensure Master Tray Icon is explicitly visible
if FileExist(A_ScriptDir "\..\StartupScript.ico")
	TraySetIcon(A_ScriptDir "\..\StartupScript.ico")
else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
	TraySetIcon(A_ScriptDir "\..\Startup_Script.ico")

; Global hotkey-suspend state - see SuspendAllToggle() below.
; A plain single-process boolean is the source of truth; the PostMessage cascade to every child is a one-way toggle with no way to query a remote process's real suspend state, so this variable (not the children's own internal state) is what the tray checkmark reflects.
GlobalHotkeysSuspended     := false
MenuText_SuspendAll        := "Suspend Hotkeys" ; must match byte-for-byte at every Check/UnCheck
MenuText_ExitAll           := "Exit"
MenuText_AdditionalScripts := "Additional Scripts"

; Build Menu and TrayTip then Remove Tray Icons
TrayTipBuild()
MenuBuild()
OnMessage(0x404, AHK_NOTIFYICON) ; Hook Events for Tray Icon (used for Tray Icon cleanup on mouseover)
OnMessage(0x7E, AHK_DISPLAYCHANGE) ; Hook Events for Display Change (used for Tray Icon cleanup on resolution change)
TrayIconRemove(10)

;
;}-----------------------------------------------
; END OF AUTO-EXECUTE

; HOTKEYS
;{-----------------------------------------------
;
; No Suspend,Permit/exemption mechanism needed here.
; SuspendAllToggle below only ever PostMessages to the managed child scripts (Scripts) - it never touches this master script's own native suspend flag.
; So none of these 4 hotkeys can ever actually become suspended in the first place.
;Win+ScrollLock Suspend All Scripts' Hotkeys
#ScrollLock::SuspendAllToggle() ;{ +Fn <- Suspend All Scripts' Hotkeys
#^!ScrollLock::ExitApp() ;{ +Fn <- Terminate All Scripts
#^!R::ReloadAll() ;{ <- Reload All Scripts Cleanly
#^!W::Run('"C:\Program Files\AutoHotkey\WindowSpy.ahk"') ;{ <- Run Window Spy Script
;}

; SUBROUTINES
;{-----------------------------------------------
; v2: every one of these was a Gosub-targeted label in v1. Gosub is removed entirely in v2, so each becomes a real
; function; every variable a label used to reach via v1's implicit shared script-scope now needs an explicit
; `global` declaration. `(*)` on handlers that also serve as hotkey/menu-click targets means "accept and ignore
; whatever positional args the caller supplies" - hotkeys can pass a hotkey name, menu clicks pass (ItemName,
; ItemPos, MenuObj), and this file doesn't need any of that for these specific handlers.
;
ReloadAll(*) {
	global Scripts
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	for scriptName, script in Scripts {
		; v2: WinClose() guarded by WinExist() first - see the identical fix/note in the auto-execute child-launch
		; loop above (Migration-Notes.md section 18.6). ProcessClose(script.Pid) below remains the real termination
		; mechanism regardless; this is just the same "let it exit gracefully first" nicety v1 had.
		if script.Path && WinExist(script.Path " ahk_class AutoHotkey")
			WinClose(script.Path " ahk_class AutoHotkey")
		if script.HasOwnProp("Pid") && script.Pid {
			try ProcessClose(script.Pid)
			try ProcessWaitClose(script.Pid, 1)
		}
	}
	Sleep(100)
	Reload()
}

; Recompiles StartupScript.exe via build_startup_exe.ps1 in background.
; Relaunches fresh binary via Task Scheduler to prevent self-locking.
MenuRecompileStartup(*) {
	buildScript := A_ScriptDir "\..\build_startup_exe.ps1"
	Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "' buildScript '" -Relaunch', , "Hide")
}

; Opens StartupScript.ahk in default registered editor (with notepad fallback)
MenuEditStartupScript(*) {
	startupAhk := A_ScriptDir "\StartupScript.ahk"
	try {
		Run('edit "' startupAhk '"')
	} catch {
		Run('notepad.exe "' startupAhk '"')
	}
}

MenuViewKeyHistoryMaster(*) {
	KeyHistory()
}

; Cascades a real Suspend-Hotkeys toggle to every managed CHILD script (never the master itself - this cascade never targets the master's own window, so its 4 hotkeys stay reachable regardless).
; Targets by path+class, not ahk_pid: a script that has ever shown a SharedHelpers.ahk badge Gui (Hide, not Destroy, after use) can own a second hidden top-level window, and ahk_pid would non-deterministically match either one - only the true main window actually handles the fleet control message.
; Entry point for both the tray item and the hotkey.
SuspendAllToggle(*) {
	global Scripts, GlobalHotkeysSuspended, g_FleetControlMsg
	Critical("On") ; a second cascade must never interleave with this one mid-toggle
	GlobalHotkeysSuspended := !GlobalHotkeysSuspended
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	for scriptName, script in Scripts {
		if (!script.Status || !script.Path)
			continue
		PostMessage(g_FleetControlMsg, 4, 0, , script.Path " ahk_class AutoHotkey")
	}
	SuspendAllCheckSync()
	; Toast feedback for the actual toggle only (not the MenuBuild resync below, which would otherwise
	; fire this on every unrelated per-script Exit/Load while suspend happens to be on).
	ToolTip(GlobalHotkeysSuspended ? "All script hotkeys suspended" : "All script hotkeys resumed")
	SetTimer(RemoveSuspendToggleToolTip, -1500)
	Critical("Off")
}

RemoveSuspendToggleToolTip() {
	ToolTip()
}

; Keeps the tray item's checkmark in sync with GlobalHotkeysSuspended.
; Called both from the toggle above and from MenuBuild() (menu rebuilds wipe the checkmark along with the item).
SuspendAllCheckSync() {
	global GlobalHotkeysSuspended, MenuText_SuspendAll
	if GlobalHotkeysSuspended
		A_TrayMenu.Check(MenuText_SuspendAll)
	else
		A_TrayMenu.Uncheck(MenuText_SuspendAll)
}

; Thin wrapper, deliberately not a direct call to ExitSub - going through ExitApp lets AHK's own OnExit re-entrancy guard ensure the WinClose/ProcessClose cascade in ExitSub runs exactly once.
; Calling ExitSub directly here would let its own trailing ExitApp re-run the whole cascade a second time against now-dead or Windows-recycled PIDs.
ExitAll(*) {
	ExitApp()
}

TrayTipBuild() {
	global Scripts
	tipText := ""
	for scriptName, script in Scripts
		if script.Status
			tipText .= scriptName "`n"
	sortedLines := StrSplit(Trim(tipText, " `n"), "`n")
	sortedLines := Sort_ArrayStrings(sortedLines)
	tipText := ""
	for line in sortedLines
		tipText .= line "`n"
	tipText := TrimAtDelim(Trim(tipText, " `n"))
	TrayTip(tipText) ; Tooltip is limited to first 127 characters
}

; Stop All the Scripts with Status true (Called When this Script Exits)
; v2: OnExit callbacks receive (ExitReason, ExitCode) as real parameters now.
ExitSub(ExitReason, ExitCode) {
	global Scripts
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	for scriptName, script in Scripts {
		; v2: WinClose() guarded by WinExist() first - see the identical fix/note in the auto-execute child-launch
		; loop above (Migration-Notes.md section 18.6). ProcessClose(script.Pid) below remains the real termination
		; mechanism regardless.
		if script.Path && WinExist(script.Path " ahk_class AutoHotkey")
			WinClose(script.Path " ahk_class AutoHotkey")
		if script.HasOwnProp("Pid") && script.Pid {
			try ProcessClose(script.Pid)
			try ProcessWaitClose(script.Pid, 1)
		}
	}
}
;}

; SUBROUTINES - GUI
;{-----------------------------------------------
;
MenuBuild() {
	global Scripts, PinnedScripts, MenuText_SuspendAll, MenuText_ExitAll, MenuText_AdditionalScripts
	global g_ScriptMenus, g_CurrentBasicTasksDrmItem, g_CurrentSunshineMouseSpeedItem

	; v2: fresh Menu() objects every call, replacing v1's DeleteAll-and-reuse-by-name approach - simpler, and avoids
	; ever handing out a stale Menu object for a PID that no longer applies.
	subMenuLoad := Menu()
	subMenuAdditionalScripts := Menu()
	g_ScriptMenus := Map()
	A_TrayMenu.Delete()
	hasLoadSubmenu := false ; Tracks whether any script landed in subMenuLoad below.
	pinned := Map() ; scriptName -> true for everything already placed by the pinned pass below

	; Build every loaded script's own submenu (Edit/Restart/Exit/etc.) - same for pinned and unpinned scripts alike.
	; Top-level placement (pinned first, then the rest) happens after.
	for scriptName, script in Scripts {
		if script.Status {
			pid := script.Pid
			scriptMenu := Menu()
			scriptMenu.Add("View Key History", ScriptCommand.Bind(pid, "ViewKeyHistory"))
			scriptMenu.Add("Edit", ScriptCommand.Bind(pid, "Edit"))
			scriptMenu.Add("Restart", ScriptCommand.Bind(pid, "Restart"))
			scriptMenu.Add("Exit", ScriptCommand.Bind(pid, "Exit"))
			g_ScriptMenus[pid] := scriptMenu

			; Mirror any custom tray items this script has published for itself (generic: no per-script names/IDs hardcoded here; see SharedHelpers.ahk for the publishing side of this).
			; Supports horizontal separator lines when "-" is published.
			; Scripts that don't publish a manifest are unaffected.
			customManifest := A_Temp "\ahk_traymenu_" scriptName ".txt"
			if FileExist(customManifest) {
				scriptMenu.Add()
				Loop Read, customManifest {
					delimPos := InStr(A_LoopReadLine, "|", false, -1) ; v2: StartingPos=0 (v1's implicit "search from end") hangs v2 indefinitely; -1 is the explicit v2 equivalent. See Migration-Notes.md 18.9.
					if (delimPos > 0) {
						customItem1 := SubStr(A_LoopReadLine, 1, delimPos - 1)
						customItem2 := SubStr(A_LoopReadLine, delimPos + 1)
					} else {
						customItem1 := A_LoopReadLine
						customItem2 := ""
					}
					if (customItem1 = "-" || customItem1 = "")
						scriptMenu.Add()
					else if (customItem1 != "") {
						scriptMenu.Add(customItem1, RemoteMenuCommand.Bind(pid, scriptName))
						if (scriptName = "BasicTasks") {
							if (InStr(customItem1, "Graphics Accel") || InStr(customItem1, "DRM Streaming"))
								g_CurrentBasicTasksDrmItem := customItem1
						} else if (scriptName = "SunshineDisplayWatchdog") {
							if InStr(customItem1, "Mouse Speed:")
								g_CurrentSunshineMouseSpeedItem := customItem1
						}
					}
				}
			}
		} else {
			subMenuLoad.Add(scriptName, ScriptCommand_Load)
			hasLoadSubmenu := true
		}
	}

	; Pinned scripts first, in the order listed in PinnedScripts (top of file).
	; Add a name there and it moves to the top automatically - no other change needed.
	hasPinned := false
	for index, scriptName in PinnedScripts {
		if (Scripts.Has(scriptName) && Scripts[scriptName].Status) {
			pid := Scripts[scriptName].Pid
			A_TrayMenu.Add(scriptName, g_ScriptMenus[pid])
			pinned[scriptName] := true
			hasPinned := true
		}
	}

	; Additional (unpinned) scripts, bundled into a single expandable submenu
	hasAdditionalScripts := false
	for scriptName, script in Scripts {
		if (script.Status && !pinned.Has(scriptName)) {
			pid := script.Pid
			subMenuAdditionalScripts.Add(scriptName, g_ScriptMenus[pid])
			hasAdditionalScripts := true
		}
	}

	; Master StartupScript entry tucked inside Additional Scripts for occasional maintenance
	subMenuStartupScript := Menu()
	subMenuStartupScript.Add("Reload All", ReloadAll)
	subMenuStartupScript.Add("Recompile && Relaunch", MenuRecompileStartup)
	subMenuStartupScript.Add()
	subMenuStartupScript.Add("Edit", MenuEditStartupScript)
	subMenuStartupScript.Add("View Key History", MenuViewKeyHistoryMaster)

	if (hasAdditionalScripts) {
		subMenuAdditionalScripts.Add()
		subMenuAdditionalScripts.Add("StartupScript", subMenuStartupScript)
	}

	if (hasPinned && hasAdditionalScripts)
		A_TrayMenu.Add() ; separator between pinned scripts and additional scripts

	if (hasAdditionalScripts)
		A_TrayMenu.Add(MenuText_AdditionalScripts, subMenuAdditionalScripts)

	; Deliberately never calling A_TrayMenu.AddStandard() - it would re-add AHK's own native "Suspend Hotkeys"/"Pause Script"/"Exit" trio, which only ever act on this master script's own 4 hotkeys.
	; Pure clutter alongside the real actions above, which are the ones that actually affect every managed child script. A_TrayMenu.Delete() at the top of this function already excludes them, matching v1's deliberate NoStandard choice.
	if (hasLoadSubmenu) {
		A_TrayMenu.Add()
		A_TrayMenu.Add("Load", subMenuLoad)
	}
	A_TrayMenu.Add()
	A_TrayMenu.Add(MenuText_SuspendAll, SuspendAllToggle)
	A_TrayMenu.Add(MenuText_ExitAll, ExitAll)
	SuspendAllCheckSync() ; must come AFTER the Add above - Check on a not-yet-added item errors
	if (hasLoadSubmenu)
		A_TrayMenu.Default := "Load"

	if FileExist(A_ScriptDir "\..\StartupScript.ico")
		TraySetIcon(A_ScriptDir "\..\StartupScript.ico")
	else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
		TraySetIcon(A_ScriptDir "\..\Startup_Script.ico")

	UpdateSunshineDisplayMenuChecks()
	UpdateBasicTasksMenuChecks()
	UpdateBasicTasksMenuLabels()
}

; Dynamically applies checkmarks to active Skills Vault mode inside BasicTasks's submenu
; v2 port of the same feature added to v1 in commit cbaeb08 ("add dedicated 3-way Skills Vault menu items") -
; mirrors UpdateSunshineDisplayMenuChecks() below exactly, 3 mutually-exclusive states instead of 4.
UpdateBasicTasksMenuChecks() {
	global Scripts, g_ScriptMenus
	if (!Scripts.Has("BasicTasks"))
		return
	pid := Scripts["BasicTasks"].Pid
	if (!pid || !g_ScriptMenus.Has(pid))
		return
	scriptMenu := g_ScriptMenus[pid]

	itemAuto     := "Skills Vault: Auto (Focus-Driven)`tWin+Alt+L"
	itemLocked   := "Skills Vault: Locked (Org Safe Mode)"
	itemUnlocked := "Skills Vault: Unlocked (Personal Mode)"

	try scriptMenu.Uncheck(itemAuto)
	try scriptMenu.Uncheck(itemLocked)
	try scriptMenu.Uncheck(itemUnlocked)

	modeFile := A_Temp "\skills_vault_mode.flag"
	sMode := "auto"
	if FileExist(modeFile) {
		sMode := Trim(FileRead(modeFile))
	}

	if (sMode = "locked") {
		try scriptMenu.Check(itemLocked)
	} else if (sMode = "unlocked") {
		try scriptMenu.Check(itemUnlocked)
	} else {
		try scriptMenu.Check(itemAuto)
	}
}

; Dynamically applies checkmarks to active display mode inside SunshineDisplayWatchdog's submenu
UpdateSunshineDisplayMenuChecks() {
	global Scripts, g_ScriptMenus, g_CurrentSunshineMouseSpeedItem
	if (!Scripts.Has("SunshineDisplayWatchdog"))
		return
	pid := Scripts["SunshineDisplayWatchdog"].Pid
	if (!pid || !g_ScriptMenus.Has(pid))
		return
	scriptMenu := g_ScriptMenus[pid]

	itemLaptop    := "PC Screen Only (1080p @ 144Hz)`tWin+Alt+P"
	itemTablet    := "Tablet Only (2560x1600 @ 120Hz)`tWin+Alt+P"
	itemExtend    := "Extend Displays (Dual Screens)`tWin+Alt+Shift+P"
	itemDuplicate := "Duplicate Displays (Mirror)`tWin+Alt+Shift+P"

	try scriptMenu.Uncheck(itemLaptop)
	try scriptMenu.Uncheck(itemTablet)
	try scriptMenu.Uncheck(itemExtend)
	try scriptMenu.Uncheck(itemDuplicate)

	; v2: a brace-less single-line `try` as the direct body of an `if`/`else if` chain is a hard parse error in v2
	; ("Unexpected Else"), even though the identical structure loads fine in v1. See Migration-Notes.md 18.10.
	topo := GetCurrentDisplayTopology()
	if (topo == 8) {
		try scriptMenu.Check(itemTablet)
	} else if (topo == 2) {
		try scriptMenu.Check(itemDuplicate)
	} else if (topo == 4) {
		try scriptMenu.Check(itemExtend)
	} else if (topo == 1) {
		try scriptMenu.Check(itemLaptop)
	} else {
		if (MonitorGetCount() >= 2) {
			try scriptMenu.Check(itemExtend)
		} else {
			try scriptMenu.Check(itemLaptop)
		}
	}

	; Dynamically synchronize mouse speed menu label with live manifest
	manifest := A_Temp "\ahk_traymenu_SunshineDisplayWatchdog.txt"
	if FileExist(manifest) {
		Loop Read, manifest {
			delimPos := InStr(A_LoopReadLine, "|", false, -1) ; v2: see Migration-Notes.md 18.9 (StartingPos=0 hangs v2)
			item1 := (delimPos > 0) ? SubStr(A_LoopReadLine, 1, delimPos - 1) : A_LoopReadLine
			if InStr(item1, "Mouse Speed:") {
				if (g_CurrentSunshineMouseSpeedItem && g_CurrentSunshineMouseSpeedItem != item1) {
					try scriptMenu.Rename(g_CurrentSunshineMouseSpeedItem, item1)
					g_CurrentSunshineMouseSpeedItem := item1
				}
			}
		}
	}
}

; Dynamically synchronizes BasicTasks tray menu labels with live manifest
; v2: the Skills Vault label-rename branch this function used to carry was removed in the same v1 commit
; (cbaeb08) that replaced the single cycling Skills Vault item with 3 dedicated checkmarked items - see
; UpdateBasicTasksMenuChecks() above, which now owns that state sync instead of a label rename.
UpdateBasicTasksMenuLabels() {
	global Scripts, g_ScriptMenus, g_CurrentBasicTasksDrmItem
	if (!Scripts.Has("BasicTasks"))
		return
	pid := Scripts["BasicTasks"].Pid
	if (!pid || !g_ScriptMenus.Has(pid))
		return
	scriptMenu := g_ScriptMenus[pid]

	manifest := A_Temp "\ahk_traymenu_BasicTasks.txt"
	if !FileExist(manifest)
		return

	Loop Read, manifest {
		delimPos := InStr(A_LoopReadLine, "|", false, -1) ; v2: see Migration-Notes.md 18.9 (StartingPos=0 hangs v2)
		item1 := (delimPos > 0) ? SubStr(A_LoopReadLine, 1, delimPos - 1) : A_LoopReadLine
		if (InStr(item1, "Graphics Accel") || InStr(item1, "DRM Streaming")) {
			if (g_CurrentBasicTasksDrmItem && g_CurrentBasicTasksDrmItem != item1) {
				try scriptMenu.Rename(g_CurrentBasicTasksDrmItem, item1)
				g_CurrentBasicTasksDrmItem := item1
			}
		}
	}
}

; v2: bound at Add-time in MenuBuild() via ScriptCommand.Bind(pid, action) - pid and action arrive as real parameters
; instead of being parsed back out of a dynamic submenu name string (A_ThisMenu) and menu item text (A_ThisMenuItem).
; itemName/itemPos/menuObj are the normal v2 menu-click callback params, unused here since action already says what happened.
ScriptCommand(pid, action, itemName, itemPos, menuObj) {
	global Scripts, g_FleetControlMsg

	; Restart has no fleet-control code of its own (unlike Edit/Exit/ViewKeyHistory, which every child already handles).
	; The master performs the kill and relaunch itself.
	if (action = "Restart") {
		ScriptCommand_Restart(pid)
		return
	}

	codeMap := Map("Edit", 1, "Exit", 2, "ViewKeyHistory", 3)
	if (!codeMap.Has(action))
		return
	code := codeMap[action]

	DetectHiddenWindows(true)
	PostMessage(g_FleetControlMsg, code, 0, , "ahk_pid " pid)

	; If Exit, set Status to false
	if (action = "Exit") {
		targetName := ""
		for scriptName, script in Scripts
			if (script.HasOwnProp("Pid") && script.Pid = pid) {
				targetName := scriptName
				break
			}
		if (targetName != "") {
			Scripts[targetName].Status := false
			MenuBuild()
			TrayTipBuild()
		}
	}
}

; Kills the script (posting the same fleet-control Exit code the Exit menu item itself uses) then relaunches it fresh, reusing ScriptCommand_Load's own launch + suspend-resync pattern below.
; Unlike Exit, Status stays true and the script keeps its own top-level tray entry - it never moves to the Load submenu.
ScriptCommand_Restart(pid) {
	global Scripts, GlobalHotkeysSuspended, g_FleetControlMsg
	targetName := ""
	for scriptName, script in Scripts
		if (script.HasOwnProp("Pid") && script.Pid = pid) {
			targetName := scriptName
			break
		}
	if (targetName = "")
		return

	oldPath := Scripts[targetName].Path
	runPath := Scripts[targetName].RunPath

	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	PostMessage(g_FleetControlMsg, 2, 0, , oldPath " ahk_class AutoHotkey") ; code 2 = Exit, same as the Exit item
	WinWaitClose(oldPath " ahk_class AutoHotkey", , 2)

	Run('"' runPath '" "' oldPath '"', , "Hide", &newPid)
	Scripts[targetName].Pid := newPid

	; Suspend toggle is a toggle, not a set - mirrors ScriptCommand_Load's own resync below: a freshly-launched script always starts unsuspended, so bring it into sync if global suspend is currently active.
	; WinWait first since Run returns before the new window exists.
	if GlobalHotkeysSuspended {
		if WinWait(oldPath " ahk_class AutoHotkey", , 5)
			PostMessage(g_FleetControlMsg, 4, 0, , oldPath " ahk_class AutoHotkey")
	}

	MenuBuild()
	TrayTipBuild()
}

; Handles clicks on custom items mirrored in from a script's published manifest (see MenuBuild() above and SharedHelpers.ahk's publishing side).
; v2: pid and scriptName arrive bound at Add-time instead of being parsed back out of A_ThisMenu; itemName replaces A_ThisMenuItem.
; Generic: does not know or care which script or which items; just re-reads that PID's manifest to find which line matches the clicked text, then posts that line's 1-based number to the script's own registered remote-trigger message so it can dispatch the right handler itself.
RemoteMenuCommand(pid, scriptName, itemName, itemPos, menuObj) {
	customManifest := A_Temp "\ahk_traymenu_" scriptName ".txt"
	if !FileExist(customManifest)
		return
	lineNum := 0
	Loop Read, customManifest {
		lineNum++
		delimPos := InStr(A_LoopReadLine, "|", false, -1) ; v2: see Migration-Notes.md 18.9 (StartingPos=0 hangs v2)
		customItem1 := (delimPos > 0) ? SubStr(A_LoopReadLine, 1, delimPos - 1) : A_LoopReadLine
		if (customItem1 = itemName
			|| (InStr(customItem1, "Graphics Accel") && InStr(itemName, "Graphics Accel"))
			|| (InStr(customItem1, "DRM Streaming") && InStr(itemName, "DRM Streaming"))
			|| (InStr(customItem1, "Mouse Speed:") && InStr(itemName, "Mouse Speed:"))) {
			remoteTrayTriggerMsg := DllCall("RegisterWindowMessage", "Str", "AHK_RemoteTrayMenuTrigger_v1", "UInt")
			PostMessage(remoteTrayTriggerMsg, lineNum, 0, , "ahk_pid " pid)
			break
		}
	}
}

; v2: itemName is the clicked Load-submenu entry, replacing A_ThisMenuItem - it's already the scriptName since that's
; exactly what subMenuLoad.Add(scriptName, ScriptCommand_Load) used as the item's own display text.
ScriptCommand_Load(itemName, itemPos, menuObj) {
	global Scripts, GlobalHotkeysSuspended, g_FleetControlMsg
	scriptName := itemName
	; Run Script and Keep Info
	Run('"' Scripts[scriptName].RunPath '" "' Scripts[scriptName].Path '"', , "Hide", &pid) ; specify Autohotkey version
	Scripts[scriptName].Pid := pid
	Scripts[scriptName].Status := true

	; Suspend toggle is a toggle, not a set - a freshly-launched script always starts unsuspended, so if global suspend is currently active, bring this new process into sync with it.
	; Run returns as soon as the process exists, before its window does, so WinWait is required or the PostMessage below would silently miss.
	if GlobalHotkeysSuspended {
		DetectHiddenWindows(true)
		SetTitleMatchMode(2)
		if WinWait(Scripts[scriptName].Path " ahk_class AutoHotkey", , 5)
			PostMessage(g_FleetControlMsg, 4, 0, , Scripts[scriptName].Path " ahk_class AutoHotkey")
	}

	; Rebuild Menu and TrayTip then Remove Tray Icon
	MenuBuild()
	TrayTipBuild()
	TrayIconRemove(8)
}

;}

; FUNCTIONS
;{-----------------------------------------------
;
TrayIconRemove(Attempts) {
	global Scripts
	Loop Attempts { ; Try To Remove Over Time Because Icons May Lag Especially During Bootup
		for scriptName, script in Scripts
			; BasicTasks and SunshineDisplayWatchdog manage their own dynamic taskbar tray indicators
			if (script.Status && scriptName != "BasicTasks" && scriptName != "SunshineDisplayWatchdog") {
				try {
					hWnds := WinGetList("ahk_pid " script.Pid)
					for hWnd in hWnds
						if (hWnd != A_ScriptHwnd)
							KillTrayIcon(hWnd)
				}
			}
		Sleep(A_Index ** 2 * 200)
	}
}

; Lexikos
KillTrayIcon(scriptHwnd) {
	static NIM_DELETE := 2, AHK_NOTIFYICON := 1028
	nic := Buffer(936 + 4 * A_PtrSize, 0)
	NumPut("UInt", nic.Size, nic, 0)
	NumPut("Ptr", scriptHwnd, nic, A_PtrSize)
	NumPut("UInt", AHK_NOTIFYICON, nic, A_PtrSize * 2)
	return DllCall("Shell32\Shell_NotifyIcon", "UInt", NIM_DELETE, "Ptr", nic)
}

GetCurrentDisplayTopology() {
	numPaths := Buffer(4, 0)
	numModes := Buffer(4, 0)
	if DllCall("GetDisplayConfigBufferSizes", "UInt", 4, "Ptr", numPaths, "Ptr", numModes)
		return 0

	pCount := NumGet(numPaths, 0, "UInt")
	mCount := NumGet(numModes, 0, "UInt")
	if (pCount = 0)
		return 0

	paths := Buffer(pCount * 72, 0)
	modes := Buffer(mCount * 64, 0)
	topologyId := Buffer(4, 0)

	ret := DllCall("QueryDisplayConfig", "UInt", 4, "Ptr", numPaths, "Ptr", paths, "Ptr", numModes, "Ptr", modes, "Ptr", topologyId)
	if (ret != 0)
		return 0

	return NumGet(topologyId, 0, "UInt")
}

TrimAtDelim(String, Length := 124, Delim := "`n", Tail := "...") {
	if (StrLen(String) > Length) {
		if RegExMatch(SubStr(String, 1, Length + 1), "(.*)" Delim, &match)
			Result := match[1] Tail
		else
			Result := SubStr(String, 1, Length) Tail
	} else
		Result := String
	return Result
}

; Simple ascending string sort for an array (replaces v1's Sort command over a delimited string).
; v2: the native `<`/`>` string-relational operators hang indefinitely in this environment - confirmed down to the
; simplest possible case ("a" < "b") in total isolation; `=`/`!=` are unaffected. Traced to this machine's mismatched
; locale configuration (system locale en-US, user locale en-GB) deadlocking v2's locale-aware string collation path;
; v1 does not hit this. Workaround: StrGreaterThan() below compares ordinally by character code, never invoking the
; native operator on two strings. See Migration-Notes.md 18.11.
Sort_ArrayStrings(arr) {
	n := arr.Length
	Loop n - 1 {
		i := A_Index
		Loop n - i {
			j := A_Index
			if StrGreaterThan(arr[j], arr[j + 1]) {
				tmp := arr[j]
				arr[j] := arr[j + 1]
				arr[j + 1] := tmp
			}
		}
	}
	return arr
}

; Ordinal (byte/codepoint) string comparison, deliberately not using the native `>` operator - see the note on
; Sort_ArrayStrings() above. Character-by-character via Ord()/SubStr(), which never touches the string-relational
; code path that hangs in this environment.
StrGreaterThan(a, b) {
	lenA := StrLen(a), lenB := StrLen(b)
	minLen := lenA < lenB ? lenA : lenB ; numeric `<` - unaffected, confirmed safe (only string `<`/`>` hangs)
	Loop minLen {
		ca := Ord(SubStr(a, A_Index, 1))
		cb := Ord(SubStr(b, A_Index, 1))
		if (ca != cb)
			return ca > cb
	}
	return lenA > lenB
}

AHK_NOTIFYICON(wParam, lParam, uMsg, hWnd) { ; OnMessage(0x404, AHK_NOTIFYICON)
	; Cleanup Tray Icons on MouseOver
	if (lParam = 0x200) ; WM_MOUSEMOVE := 0x200
		TrayIconRemove(1)
	; Both left-click and right-click open the master tray context menu.
	else if (lParam = 0x202 || lParam = 0x205) { ; WM_LBUTTONUP or WM_RBUTTONUP
		UpdateSunshineDisplayMenuChecks()
		UpdateBasicTasksMenuChecks()
		UpdateBasicTasksMenuLabels()
		A_TrayMenu.Show()
		return 0
	}
}

AHK_DISPLAYCHANGE(wParam, lParam, msg, hwnd) { ; OnMessage(0x7E, AHK_DISPLAYCHANGE)
	TrayIconRemove(8) ; Resolution Change can take a moment so try over time
	UpdateSunshineDisplayMenuChecks()
}

AHK_TASKBARCREATED(wParam, lParam, msg, hwnd) {
	TrayTipBuild()
	MenuBuild()
	if FileExist(A_ScriptDir "\..\StartupScript.ico")
		TraySetIcon(A_ScriptDir "\..\StartupScript.ico")
	else if FileExist(A_ScriptDir "\..\Startup_Script.ico")
		TraySetIcon(A_ScriptDir "\..\Startup_Script.ico")
	TrayIconRemove(5)
}
;}
