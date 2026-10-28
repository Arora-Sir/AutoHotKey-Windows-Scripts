#Requires AutoHotkey v2.0
; Persistent tray icon for direct wireless file and folder transfers to S24 Ultra and Tab S10 Ultra.
Persistent()
#SingleInstance force

; Include SharedHelpers for ShowDualOptionPrompt, ShowBottomRightBadge, and fleet messaging
#Include %A_ScriptDir%\SharedHelpers.ahk
#Include *i %A_ScriptDir%\LocalPaths.ahk

; Global active transfer state for in-flight cancellation support
global g_ActiveTransferPid := 0
global g_ActiveTransferDesc := ""
global g_ActiveTransferTarget := ""
global g_TransferCancelled := false
global g_DefaultTrayTip := "Wireless Share (S24 & Tab S10 Ultra)`nClick: Choose target for selected files`nWin+Alt+T: S24 | Win+Alt+T+T: Tab S10"

; =============================================================================
; [SYSTEM TRAY CONFIGURATION]
; Dedicated, always-visible tray icon with single-click interactive popup
; =============================================================================
SetupWirelessShareTrayIcon()

SetupWirelessShareTrayIcon() {
	global g_DefaultTrayTip
	iconFile := A_ScriptDir "\..\AutoHotkey Companion Files\wireless_share.ico"
	if (FileExist(iconFile)) {
		TraySetIcon(iconFile)
	} else {
		; Use standard Windows mobile device or share icon
		try {
			TraySetIcon("imageres.dll", 194)
		} catch {
			try TraySetIcon("shell32.dll", 275)
		}
	}

	A_IconTip := g_DefaultTrayTip

	A_TrayMenu.Delete()
	A_TrayMenu.Add("Send Selected Items... (Choose Device)", (*) => PromptSendSelectedItems())
	A_TrayMenu.Default := "Send Selected Items... (Choose Device)"
	A_TrayMenu.ClickCount := 1
	A_TrayMenu.Add()
	A_TrayMenu.Add("Send to S24 Ultra (Phone)`tWin+Alt+T", (*) => DispatchSelectedItems("phone"))
	A_TrayMenu.Add("Send to Tab S10 Ultra (Tablet)`tWin+Alt+T+T", (*) => DispatchSelectedItems("tab"))
	A_TrayMenu.Add()
	A_TrayMenu.Add("Open Phone Transfers (/sdcard/Download/...)", (*) => OpenDeviceTransfers("phone"))
	A_TrayMenu.Add("Open Tablet Transfers (/sdcard/Download/...)", (*) => OpenDeviceTransfers("tab"))

	A_IconHidden := false
}

; =============================================================================
; [IN-FLIGHT TRANSFER CANCELLATION]
; Aborts active PowerShell and adb.exe transfer processes via taskkill
; =============================================================================
CancelActiveTransfer() {
	global g_ActiveTransferPid, g_ActiveTransferDesc, g_ActiveTransferTarget, g_DefaultTrayTip, g_TransferCancelled

	if (!g_ActiveTransferPid || !ProcessExist(g_ActiveTransferPid)) {
		g_ActiveTransferPid := 0
		return false
	}

	g_TransferCancelled := true
	pidToKill := g_ActiveTransferPid
	itemDesc := g_ActiveTransferDesc
	targetName := g_ActiveTransferTarget

	; Forcefully terminate PowerShell and any child processes (adb.exe)
	Run('taskkill /PID ' . pidToKill . ' /T /F', , "Hide")

	g_ActiveTransferPid := 0
	g_ActiveTransferDesc := ""
	g_ActiveTransferTarget := ""

	; Restore tray tooltip and menu item
	A_IconTip := g_DefaultTrayTip
	try A_TrayMenu.Rename("1&", "Send Selected Items... (Choose Device)")

	ShowBottomRightBadge("Transfer of " . itemDesc . " to " . targetName . " cancelled!", "D97706", 3000)
	return true
}

; =============================================================================
; [INTERACTIVE DUAL OPTION POPUP]
; Shows bottom-right popup card with S24 Ultra and Tab S10 Ultra action buttons
; =============================================================================
PromptSendSelectedItems() {
	global g_ActiveTransferPid
	if (g_ActiveTransferPid && ProcessExist(g_ActiveTransferPid)) {
		CancelActiveTransfer()
		return
	}

	items := GetSelectedFilesOrFolders()
	if (items.Length = 0) {
		ShowBottomRightBadge("No file or folder selected to send!", "B86200", 2500)
		return
	}

	if (items.Length = 1) {
		SplitPath(items[1], &itemName)
		if (StrLen(itemName) > 28)
			itemName := SubStr(itemName, 1, 25) . "..."
		heading := 'Send "' . itemName . '" to:'
	} else {
		heading := "Send " . items.Length . " selected items to:"
	}

	ShowDualOptionPrompt(
		heading,
		"S24 Ultra (Phone)",
		(*) => (DismissDualOptionPrompt(), DispatchFilesToTarget("phone", items)),
		"Tab S10 Ultra (Tablet)",
		(*) => (DismissDualOptionPrompt(), DispatchFilesToTarget("tab", items)),
		10,
		"Press Esc to cancel  •  Auto-closes in {sec}s",
		0, 0,
		"1F3A5A", "E6EDF3",
		"2D1F45", "F0E6FF"
	)
}

; =============================================================================
; [FOCUS-INDEPENDENT SELECTION RESOLUTION]
; Multi-tier resolution: Active Desktop/Explorer -> Hovered window -> Z-order Explorer -> Desktop fallback -> Clipboard
; Handles desktop Shell COM (FindWindowSW), filters zombie/dead Explorer COM objects via IsWindow, and deduplicates
; =============================================================================
GetDesktopSelectedItems(shellApp) {
	desktopItems := []
	try {
		; SWC_DESKTOP = 8, SWFO_NEEDDISPATCH = 1
		desktopWin := shellApp.Windows.FindWindowSW(0, 0, 8, 0, 1)
		if (desktopWin && desktopWin.Document && desktopWin.Document.SelectedItems) {
			for item in desktopWin.Document.SelectedItems {
				path := Trim(item.Path, '"')
				if (path != "" && FileExist(path))
					desktopItems.Push(path)
			}
		}
	}
	return desktopItems
}

GetSelectedFilesOrFolders() {
	selected := []
	seen := Map()
	shellApp := ComObject("Shell.Application")

	; Helper to add paths with deduplication and existence check
	AddCandidate(path) {
		clean := Trim(path, '"')
		if (clean != "" && FileExist(clean) && !seen.Has(clean)) {
			seen[clean] := true
			selected.Push(clean)
		}
	}

	; 1. Active Window Check: Desktop (Progman or WorkerW)
	if (WinActive("ahk_class Progman") || WinActive("ahk_class WorkerW")) {
		for path in GetDesktopSelectedItems(shellApp)
			AddCandidate(path)
		if (selected.Length > 0)
			return selected
	}

	; 2. Active Window Check: Explorer (CabinetWClass)
	if (activeHwnd := WinActive("ahk_class CabinetWClass")) {
		for window in shellApp.Windows {
			try {
				if (window.hwnd = activeHwnd && DllCall("IsWindow", "ptr", window.hwnd) && window.Document && window.Document.SelectedItems) {
					if (window.Document.SelectedItems.Count > 0) {
						for item in window.Document.SelectedItems
							AddCandidate(item.Path)
						if (selected.Length > 0)
							return selected
					}
				}
			}
		}
	}

	; 3. Mouse Hovered Window (handles transient focus shifts to taskbar or badges)
	try {
		MouseGetPos(, , &mouseHwnd)
		if (mouseHwnd && DllCall("IsWindow", "ptr", mouseHwnd)) {
			mouseClass := WinGetClass("ahk_id " . mouseHwnd)
			if (mouseClass = "Progman" || mouseClass = "WorkerW" || mouseClass = "SysListView32") {
				for path in GetDesktopSelectedItems(shellApp)
					AddCandidate(path)
				if (selected.Length > 0)
					return selected
			} else if (mouseClass = "CabinetWClass") {
				for window in shellApp.Windows {
					try {
						if (window.hwnd = mouseHwnd && DllCall("IsWindow", "ptr", window.hwnd) && window.Document && window.Document.SelectedItems) {
							if (window.Document.SelectedItems.Count > 0) {
								for item in window.Document.SelectedItems
									AddCandidate(item.Path)
								if (selected.Length > 0)
									return selected
							}
						}
					}
				}
			}
		}
	}

	; 4. Explorer Windows in Z-Order (most recently focused active Explorer)
	explorerHwnds := WinGetList("ahk_class CabinetWClass")
	for expHwnd in explorerHwnds {
		for window in shellApp.Windows {
			try {
				; MUST verify window handle is alive to ignore closed/zombie COM objects
				if (window.hwnd = expHwnd && DllCall("IsWindow", "ptr", window.hwnd) && window.Document && window.Document.SelectedItems) {
					if (window.Document.SelectedItems.Count > 0) {
						for item in window.Document.SelectedItems
							AddCandidate(item.Path)
						if (selected.Length > 0)
							return selected
					}
				}
			}
		}
	}

	; 5. Desktop Selection Fallback (when user triggered from background app)
	for path in GetDesktopSelectedItems(shellApp)
		AddCandidate(path)
	if (selected.Length > 0)
		return selected

	; 6. Outside Explorer: check if clipboard contains valid file or folder paths
	Loop Parse, A_Clipboard, "`n", "`r"
		AddCandidate(A_LoopField)

	return selected
}

; =============================================================================
; [DISPATCH TO TARGET DEVICE]
; Executes SendToDevice_Adb.ps1 asynchronously with green HUD completion badge
; =============================================================================
DispatchSelectedItems(target) {
	global g_ActiveTransferPid
	if (g_ActiveTransferPid && ProcessExist(g_ActiveTransferPid)) {
		CancelActiveTransfer()
		return
	}

	items := GetSelectedFilesOrFolders()
	targetName := (target = "tab" || target = "tablet") ? "Tab S10 Ultra" : "S24 Ultra"

	if (items.Length = 0) {
		ShowBottomRightBadge("No file or folder selected in Explorer to send to " . targetName . "!", "B86200", 2500)
		return
	}

	DispatchFilesToTarget(target, items)
}

DispatchFilesToTarget(target, files) {
	global g_ActiveTransferPid, g_ActiveTransferDesc, g_ActiveTransferTarget, g_DefaultTrayTip, g_TransferCancelled
	global PATH_ADB_EXE, ADB_PHONE_TAILSCALE_IP, ADB_PHONE_LAN_IP, ADB_TABLET_TAILSCALE_IP, ADB_TABLET_LAN_IP

	if (g_ActiveTransferPid && ProcessExist(g_ActiveTransferPid)) {
		CancelActiveTransfer()
	}

	if (target = "tab" || target = "tablet") {
		targetName := "Tab S10 Ultra"
		tsIp  := IsSet(ADB_TABLET_TAILSCALE_IP) ? ADB_TABLET_TAILSCALE_IP : ""
		lanIp := IsSet(ADB_TABLET_LAN_IP) ? ADB_TABLET_LAN_IP : ""
	} else {
		targetName := "S24 Ultra"
		tsIp  := IsSet(ADB_PHONE_TAILSCALE_IP) ? ADB_PHONE_TAILSCALE_IP : ""
		lanIp := IsSet(ADB_PHONE_LAN_IP) ? ADB_PHONE_LAN_IP : ""
	}

	itemDesc := (files.Length = 1) ? "1 item" : (files.Length . " items")
	if (files.Length = 1) {
		SplitPath(files[1], &singleName)
		if (StrLen(singleName) > 28)
			singleName := SubStr(singleName, 1, 25) . "..."
		itemDesc := '"' . singleName . '"'
	}
	ShowBottomRightBadge("Dispatching " . itemDesc . " to " . targetName . "...`n(Press Win+Alt+T or click tray icon to cancel)", "2D5A88", 2500)

	fileArgs := ""
	for idx, path in files {
		fileArgs .= ' "' . path . '"'
	}

	psScript := A_ScriptDir "\PowerShell\SendToDevice_Adb.ps1"
	adbArg := (IsSet(PATH_ADB_EXE) && PATH_ADB_EXE) ? ' -AdbPath "' . PATH_ADB_EXE . '"' : ""
	tsArg  := tsIp ? ' -TailscaleIp "' . tsIp . '"' : ""
	lanArg := lanIp ? ' -LanIp "' . lanIp . '"' : ""
	statusFile := A_Temp "\ahk_share_status_" . A_TickCount . ".tmp"
	statusArg := "`; Set-Content -Path `"" . statusFile . "`" -Value `$LASTEXITCODE"

	fullCmd := 'powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& { & `"' . psScript . '`" -Target ' . target . tsArg . lanArg . adbArg . fileArgs . statusArg . ' }"'
	Run(fullCmd, , "Hide", &psPid)

	g_ActiveTransferPid := psPid
	g_ActiveTransferDesc := itemDesc
	g_ActiveTransferTarget := targetName
	g_TransferCancelled := false

	; Dynamically update tray tooltip and menu to reflect transfer in progress
	transferTip := "Sending " . itemDesc . " to " . targetName . "...`nClick or Win+Alt+T to CANCEL"
	if (StrLen(transferTip) > 120)
		transferTip := SubStr(transferTip, 1, 117) . "..."
	A_IconTip := transferTip
	try A_TrayMenu.Rename("1&", "Cancel Active Transfer (" . itemDesc . ")")

	; Asynchronously monitor background PowerShell process completion
	CheckTransferDone() {
		global g_ActiveTransferPid, g_ActiveTransferDesc, g_ActiveTransferTarget, g_DefaultTrayTip, g_TransferCancelled
		if (!ProcessExist(psPid)) {
			SetTimer(CheckTransferDone, 0)
			if (g_TransferCancelled || g_ActiveTransferPid = 0) {
				try FileDelete(statusFile)
				return
			}

			g_ActiveTransferPid := 0
			g_ActiveTransferDesc := ""
			g_ActiveTransferTarget := ""
			A_IconTip := g_DefaultTrayTip
			try A_TrayMenu.Rename("1&", "Send Selected Items... (Choose Device)")

			exitCode := 0
			if (FileExist(statusFile)) {
				try exitCode := Integer(Trim(FileRead(statusFile)))
				try FileDelete(statusFile)
			}
			if (exitCode = 0) {
				ShowBottomRightBadge("Transferred " . itemDesc . " to " . targetName . " successfully!", "1A6E3C", 3500)
			} else {
				ShowBottomRightBadge("Transfer of " . itemDesc . " to " . targetName . " failed!", "8B1A1A", 3500)
			}
		}
	}
	SetTimer(CheckTransferDone, 400)
}

OpenDeviceTransfers(target) {
	global PATH_ADB_EXE, ADB_PHONE_TAILSCALE_IP, ADB_PHONE_LAN_IP, ADB_TABLET_TAILSCALE_IP, ADB_TABLET_LAN_IP
	targetName := (target = "tab" || target = "tablet") ? "Tab S10 Ultra" : "S24 Ultra"
	tsIp := (target = "tab" || target = "tablet") ? (IsSet(ADB_TABLET_TAILSCALE_IP) ? ADB_TABLET_TAILSCALE_IP : "") : (IsSet(ADB_PHONE_TAILSCALE_IP) ? ADB_PHONE_TAILSCALE_IP : "")
	lanIp := (target = "tab" || target = "tablet") ? (IsSet(ADB_TABLET_LAN_IP) ? ADB_TABLET_LAN_IP : "") : (IsSet(ADB_PHONE_LAN_IP) ? ADB_PHONE_LAN_IP : "")
	ShowBottomRightBadge("Opening transfers on " . targetName . "...", "2D5A88", 2000)

	psScript := A_ScriptDir "\PowerShell\SendToDevice_Adb.ps1"
	adbArg := (IsSet(PATH_ADB_EXE) && PATH_ADB_EXE) ? ' -AdbPath "' . PATH_ADB_EXE . '"' : ""
	tsArg  := tsIp ? ' -TailscaleIp "' . tsIp . '"' : ""
	lanArg := lanIp ? ' -LanIp "' . lanIp . '"' : ""
	Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "' psScript '" -Target ' target ' -OpenOnly' tsArg lanArg adbArg, , "Hide")
}

; =============================================================================
; [KEYBOARD SHORTCUT]
; Single tap Win+Alt+T: Direct push to S24 Ultra (Phone)
; Double tap Win+Alt+T+T: Direct push to Tab S10 Ultra (Tablet)
; If transfer is active: Cancels in-flight transfer immediately
; =============================================================================
#!t::SendToPhoneOrTablet() ;{ <- Wireless Share to S24 (Tap) / Tab S10 (Double-tap)

SendToPhoneOrTablet() {
	global g_ActiveTransferPid
	if (g_ActiveTransferPid && ProcessExist(g_ActiveTransferPid)) {
		CancelActiveTransfer()
		return
	}

	KeyWait("t")
	isDoubleTap := KeyWait("t", "D T0.50")
	if (isDoubleTap) {
		; Double tap Win+Alt+T+T: Send to Tablet (Tab S10 Ultra)
		DispatchSelectedItems("tab")
	} else {
		; Single tap Win+Alt+T: Send to Phone (S24 Ultra)
		DispatchSelectedItems("phone")
	}
}
