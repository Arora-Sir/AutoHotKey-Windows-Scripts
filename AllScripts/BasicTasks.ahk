#Requires AutoHotkey v2.0
#NoTrayIcon

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; NumLock AlwaysOn && ScrollLock Always Off
; Double tap Caps lock to activate/deactivate Caps lock
; Taskbar Mouse Scroll to Increase/Decrease volume
; Volume_Up / Volume_Down -> Adjust system volume

; Win+F -> Run FireFox
; Win+C -> Run Calculator
; Win+M -> Minimize Active window
; Win+F8 -> Bluetooth On/Off
; Win+Del -> Empty Recycle Bin
; Win+Shift+A -> Open Notification center
; Win+Shift+E -> (Folder) Open Downloads (My Screenshots) folder
; Win+Shift+J -> (Folder) Open Java Course
; Win+Alt+C -> Run Alarm Clock
; Win+Alt+Ctr+C -> Open PowerShell
; Win+Alt+Ctr+K -> Click Center of Screen (Disabled)
; Win+Alt+X -> (Script) Reconnect Cloudflare Network
; Win+Alt+N -> Clear Notification center
; Win+Alt+L -> (Script) Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)
; Win+Alt+T -> (Script) Wireless Share to S24 Ultra / Tab S10 Ultra (managed by WirelessShare.ahk)
; Alt+X -> Open Today Calendar
; Alt+D -> Open ChatGPT
; Alt+Shift+T -> Active window Always on Top (Disabled -> Using PowerToys)

; Alt+G -> Copy the content, Open Monica & Grammar Correction
; Alt+Shift+S -> Copy the content, Open Monica & Summarize Content

; Alt+Ctr+D -> Sort Folder content by date
; Alt+Ctr+E -> Enable/Disable file extension
; Alt+Ctr+H -> Enable/Disable hidden files
; Alt+Ctr+MouseLButton -> Move Background Apps
; Ctr+G -> Search the selected/clipboard text
; Ctr+C -> OneNote copy text instead of SS of some text
; Ctr+T+T -> Open new Tab from anywhere (In browser)
; Ctr+J+J -> (Chrome) Close downloads bar at bottom
; Ctr+Y+T -> Open Youtube (In browser: maximum 0.15s second gap between Y & T)
; Win+X+X -> Sleep Laptop
; Ctr+Shift+V -> Browser to go to previous tab when taking a screenshot
; MouseLButton -> Double Click Functions (Taskbar Show/Hide; ) ->> Doing this with WindHawk Now
; Ctr+Shift+WheelUp -> (VS Code) Increase Whole UI Zoom (+0.05)
; Ctr+Shift+WheelDown -> (VS Code) Decrease Whole UI Zoom (-0.05)
; F9 -> Screen Capture via PrintScreen (ShareX)

; v2: #NoEnv is gone: v2 has no %Var%-vs-environment-variable ambiguity to guard against, nothing to port.
SendMode("Input") ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir(A_ScriptDir) ; Ensures a consistent starting directory.
; v2: #MaxHotkeysPerInterval is an assignable built-in: prevents runaway dialog during rapid mouse wheel volume/zoom scrolling.
A_MaxHotkeysPerInterval := 200
#Include *i %A_ScriptDir%\LocalPaths.ahk ; Include local custom paths if present (ignored by Git)
UserProfile := EnvGet("USERPROFILE") ; Get Windows UserProfile directory
#Include %A_ScriptDir%\SharedHelpers.ahk ; Functions shared across scripts - see ARCHITECTURE.md
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows(true)

SetNumLockState("AlwaysOn") ; Set Lock keys permanently
; SetScrollLockState("AlwaysOff") ; Commented this as scrollLock key is now being used to suspend & terminate AHK Scripts
; SetCapsLockState("AlwaysOff")

; System Tray menu integration for Skills Vault (owned by BasicTasks)
g_SkillsTrayStatusLabel := "Skills Vault: [AUTO] (focus-driven)"

; --- Manual toggle debounce state (Win+Alt+L) --------------------------------
; Single source of truth for the settle window: referenced everywhere instead
; of a repeated literal.
g_SkillsDebounceMs := 2000
; In-memory "next mode if committed right now": the ONLY thing the fast path
; (TogglePersonalSkillsLock) cycles. Distinct from the on-disk modeFile, which
; remains the cross-process state of record and is touched only by the commit
; phase. "" is a one-time sentinel meaning "not yet seeded this process" -
; seeded from modeFile on first use, and reset back to "" once a commit
; settles with nothing newer pending (see CommitPersonalSkillsLock's tail).
g_SkillsPendingMode := ""
; Defense-in-depth reentrancy guard for the COMMIT phase only. AHK's own timer
; engine already guarantees at most one concurrently-running instance of a
; given timer target, so this should never actually read true in practice.
g_SkillsCommitBusy := false
g_DRMTrayStatusLabel := "Graphics Accel: Brave (ON) / Chrome (OFF)"
g_LastActiveBrowser := ""
g_LastActiveBrowserTime := 0

; -----------------------------------------------------------------------------
; TRAY MENU INTEGRATION
; Standalone tray items are commented out below because StartupScript.ahk manages the master tray icon for the fleet and hides individual script icons.
; Published via PublishTrayMenuManifest below for master submenu mirroring.
; -----------------------------------------------------------------------------
; Menu, Tray, Add
; Menu, Tray, Add, %g_SkillsTrayStatusLabel%, TraySkillsVaultStatus
; Menu, Tray, Disable, %g_SkillsTrayStatusLabel%
; Menu, Tray, Add, Cycle Skills Vault Mode (Win+Alt+L), TraySkillsVaultCycle
; Menu, Tray, Add, Project: Toggle Display Mode (Win+Alt+P), TrayToggleDisplayMode
; Menu, Tray, Add, Project: Duplicate Display Only, TrayDuplicateDisplayMode
; Menu, Tray, Add, %g_DRMTrayStatusLabel%, TrayDRMStreamingModeToggle

; Publish for StartupScript.ahk's master submenu mirroring (see SharedHelpers.ahk).
; Logical feature groups are divided by horizontal separators (["-"]):
;   Group 1: Dedicated Skills Vault Modes (Auto, Locked, Unlocked)
;   Group 2: Browser Graphics Acceleration Mode (Single-line live status)
PublishBasicTasksManifest()

; v2: RegisterTrayMenuHandler maps each manifest HandlerKey to a real function reference: see
; SharedHelpers.ahk's TRAY MENU MANIFEST section. Each handler below is already a zero-arg function
; (the label-turned-function that dispatches the actual action), so no extra wrapper is needed.
RegisterTrayMenuHandler("TraySkillsVaultAuto", TraySkillsVaultAuto)
RegisterTrayMenuHandler("TraySkillsVaultLocked", TraySkillsVaultLocked)
RegisterTrayMenuHandler("TraySkillsVaultUnlocked", TraySkillsVaultUnlocked)
RegisterTrayMenuHandler("TrayDRMStreamingModeToggle", ToggleDRMStreamingMode)
RegisterTrayMenuHandler("TrayShareXImageEffectsToggle", ToggleShareXImageEffects)

; Microphone Mute Tray Icon & Background Sync
; v2: Menu,Tray,NoStandard has no separate directive: A_TrayMenu.Delete() alone (never calling
; .AddStandard() after) is the v2 equivalent, same pattern as StartupScript.ahk/SharedHelpers.ahk.
A_TrayMenu.Delete()
A_TrayMenu.Add("Unmute Microphone", TrayUnmuteMicAction)
A_TrayMenu.Default := "Unmute Microphone"
A_TrayMenu.ClickCount := 1

OnMessage(0x0011, BasicTasks_WM_QUERYENDSESSION)
OnMessage(0x0016, BasicTasks_WM_ENDSESSION)
OnExit(BasicTasks_OnExit)

BasicTasks_WM_QUERYENDSESSION(wParam, lParam, *) {
	BasicTasks_HaltTimers()
	return true
}

BasicTasks_WM_ENDSESSION(wParam, lParam, *) {
	if (wParam)
		BasicTasks_HaltTimers()
}

BasicTasks_OnExit(ExitReason, ExitCode) {
	BasicTasks_HaltTimers()
}

BasicTasks_HaltTimers() {
	SetTimer(UpdateSkillsTrayStatus, 0)
	SetTimer(UpdateDRMTrayStatus, 0)
	SetTimer(TrackActiveBrowser, 0)
	SetTimer(WatchMicrophoneMuteState, 0)
}

SetTimer(UpdateSkillsTrayStatus, 2000)
SetTimer(UpdateSkillsTrayStatus, -100) ; Fast initial update
SetTimer(UpdateDRMTrayStatus, 3000)
SetTimer(UpdateDRMTrayStatus, -100) ; Fast initial update
SetTimer(TrackActiveBrowser, 250)
SetTimer(WatchMicrophoneMuteState, 1500)
SetTimer(WatchMicrophoneMuteState, -100) ; Fast initial check

#HotIf MouseIsOver("ahk_class Shell_TrayWnd")
	;   WheelUp::SoundSetVolume("+1")   ;Hide OSD
	;   WheelDown::SoundSetVolume("-1") ;Hide OSD
	WheelUp::Send("{Volume_Up}") ;{ <- (Taskbar) Volume Up
	WheelDown::Send("{Volume_Down}") ;{ <- (Taskbar) Volume Down
#HotIf

Volume_Up::SoundSetVolume("+10") ;{ <- Volume Up
Volume_Down::SoundSetVolume("-10") ;{ <- Volume Down

; v2: text()/SplashTextOn dropped entirely: confirmed zero live callers anywhere in this file, and
; SplashTextOn/SplashImage/Progress have no v2 equivalent at all (v2 replaces them fleet-wide with a
; real Gui, e.g. the badge pattern in SharedHelpers.ahk). Not worth building a new mini-Gui for a
; function nothing calls. Restore from git history (backup/pre-v2-migration tag) if ever needed.

MouseIsOver(WinTitle) {
	MouseGetPos(, , &Win)
	return WinExist(WinTitle . " ahk_id " . Win)
}

HideFiles() {
	valorHidden := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "Hidden", "")
	if (valorHidden = 2) {
		RegWrite(1, "REG_DWORD", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "Hidden")
		RefreshExplorer()
		ShowBottomRightBadge("Hidden Files: [SHOWN]", "1A6E3C", 1500)
	} else {
		RegWrite(2, "REG_DWORD", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "Hidden")
		RefreshExplorer()
		ShowBottomRightBadge("Hidden Files: [HIDDEN]", "555555", 1500)
	}
}

ToggleFileExt() {
	regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
	hideFileExt := RegRead(regKey, "HideFileExt", "")
	if (hideFileExt = 1) {
		RegWrite(0, "REG_DWORD", regKey, "HideFileExt")
		RefreshExplorer()
		ShowBottomRightBadge("File Extensions: [SHOWN]", "1A6E3C", 1500)
	} else {
		RegWrite(1, "REG_DWORD", regKey, "HideFileExt")
		RefreshExplorer()
		ShowBottomRightBadge("File Extensions: [HIDDEN]", "555555", 1500)
	}
}

; v2: v1's Loop,%id% + id%A_Index% dynamic-variable "pseudo-array" pattern has no equivalent at all -
; v2 dropped construct-a-variable-name-from-a-string entirely. Rewritten around WinGetList()'s real
; Array return, same pattern already established in SharedHelpers.ahk's CloseBrowserGracefully().
; SendMessage (not PostMessage) preserved to match v1's blocking-send semantics exactly.
RefreshExplorer() {
	id := WinGetID("ahk_class Progman")
	SendMessage(0x111, 0x1A220, , , "ahk_id " id)

	for winId in WinGetList("ahk_class CabinetWClass")
		SendMessage(0x111, 0x1A220, , , "ahk_id " winId)

	for winId in WinGetList("ahk_class ExploreWClass")
		SendMessage(0x111, 0x1A220, , , "ahk_id " winId)

	for winId in WinGetList("ahk_class #32770") {
		; v2: ControlGetHwnd throws if the control isn't found (unlike v1's ControlGet, which just left
		; the output var empty): not every #32770 dialog has this control, so this must stay a soft miss.
		ctrId := 0
		try ctrId := ControlGetHwnd("SHELLDLL_DefView1", "ahk_id " winId)
		if ctrId
			SendMessage(0x111, 0x1A220, , , "ahk_id " ctrId)
	}
}

OpenActionCenter() {
	Send("{LWin down}{n down}")
	Send("{LWin up}{n up}")
}

; BluetoothToggle() {
; Method 1
; Run("ms-settings:bluetooth")
; ; Wait for the Bluetooth settings window to open
; WinWait("Settings")
; WinActivate()
; Sleep(2000)
; Send("{Tab}{Tab}{Tab}{Space}")
; ; Close the Bluetooth settings window
; Send("!{F4}")
; Send("{LWinDown}{a down}")
; Sleep(800)
; Send("{Down}{Right}{Enter}{Esc}")

; Method 2
; MaxTime := 5 ; Max Seconds to wait
; StartTime := A_TickCount
; WinID := "ahk_exe ShellExperienceHost.exe ahk_class Windows.UI.Core.CoreWindow"
; WinActivate(WinID)
; if !WinWaitActive(WinID, , MaxTime - ((A_TickCount - StartTime) / 1000)) {
; 	MsgBox("WinWait timed out.")
; } else {
; 	Sleep(600)
; 	Send("{Down}")
; 	Send("{Down}")
; 	Sleep(1000)
; 	Send("{Right}")
; 	Sleep(100)
; 	Send("{Enter}{Esc}")
; }
; Send("{Click 1650 690}")
; }

; DoubleClick(action) {
; 	if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 500) {
; 		Class := WinGetClass("A")

; 		; Show/Hide Taskbar on Double click on taskbar
; 		if (Class = "Shell_TrayWnd") { ; or (Class = "Progman")
; 			static ABM_SETSTATE := 0xA, ABS_AUTOHIDE := 0x1, ABS_ALWAYSONTOP := 0x2
; 			APPBARDATA := Buffer(size := 2 * A_PtrSize + 2 * 4 + 16 + A_PtrSize, 0)
; 			NumPut("UInt", size, APPBARDATA), NumPut("Ptr", WinExist("ahk_class Shell_TrayWnd"), APPBARDATA, A_PtrSize)
; 			NumPut("UInt", action ? ABS_AUTOHIDE : ABS_ALWAYSONTOP, APPBARDATA, size - A_PtrSize)
; 			DllCall("Shell32\SHAppBarMessage", "UInt", ABM_SETSTATE, "Ptr", APPBARDATA)
; 			return
; 		}
; 	}
; }

; DoubleCapsHit := false
DoubleTapCapsLock() {
	; if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 200 && DoubleCapsHit = false) {
	if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250) {
		SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")
		; SetCapsLockState("On")
		; DoubleCapsHit := true
	}
	; else if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 200 && DoubleCapsHit = true) {
	; 	SetCapsLockState("Off")
	; 	DoubleCapsHit := false
	; }
}

; Close legacy bottom downloads shelf in Chrome (Brave uses a modern top toolbar popup, so this issue only applies to Chrome)
CloseBrowserBottomDownloadsBar() {
	if (IsChromiumBrowserActive()) {
		Send("^j") ; Open downloads tab (Normal Functionality)
		if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250) {
			Sleep(100)
			Send("^w") ; close the tab
		}
	} else {
		Send("^j") ; Normal Functionality
	}
}

ClearNotificaitons() {
	Send("#n")
	Sleep(1000)
	if WinActive("ahk_exe Shellexperiencehost.exe") {
		Send("{Tab} {Space} {Esc}")
	}
}

SleepLaptop() {
	KeyWait("x")
	isDoubleTap := KeyWait("x", "D T0.30")
	if (isDoubleTap) {
		; Double tap Win+X+X: Open menu and invoke Sleep (Win+X -> u -> s)
		SendInput("{LWin down}x{LWin up}")
		Sleep(150)
		SendInput("{LWin up}{RWin up}")
		SendInput("u")
		Sleep(100)
		SendInput("s")
	} else {
		; Single tap Win+X: Open standard Windows Quick Link menu
		SendInput("{LWin down}x{LWin up}")
	}
}



ClipboardSearch() {
	; If (WinExist("ahk_exe brave.exe")) {
	Sleep(100)
	GoogleSearchEngine := "https://www.google.com/search?q="
	Send("^c")
	Sleep(100)

	; WinActivate("ahk_exe brave.exe")
	; Sleep(200)

	LatestCopiedClipboard := A_Clipboard
	securedAddress := "https://"
	UnsecuredAddress := "www."
	if (SubStr(LatestCopiedClipboard, 1, 8) = securedAddress || SubStr(LatestCopiedClipboard, 1, 4) = UnsecuredAddress) {
		Send("^t") ; Open new tab
		Sleep(100)
		Send("^v") ; Paste the URL
		Send("{Enter}") ; Hit Enter
	} else {
		completeURL := GoogleSearchEngine . LatestCopiedClipboard
		; MsgBox("Testing, " completeURL, "Options", "4 T3") ; For Debugging
		Run(completeURL)
	}
	; }
}

MoveBGApp() {
	MouseGetPos(&oldmx, &oldmy, &mwin, &mctrl)
	Loop {
		lbutton := GetKeyState("LButton", "P")
		alt := GetKeyState("Alt", "P")
		if (lbutton = "U" || alt = "U")
			break
		MouseGetPos(&mx, &my)
		WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " mwin)
		wx := wx + mx - oldmx
		wy := wy + my - oldmy
		WinMove(wx, wy, , , "ahk_id " mwin)
		oldmx := mx
		oldmy := my
	}
}

OpenYoutube() {
	; For more tweak read this : https://www.autohotkey.com/boards/viewtopic.php?t=86160
	if IsChromiumBrowserActive() {
		if (openYT()) {
			Sleep(600)
			Send("{LCtrl down}{LShift down}{Tab down}")
			Send("{LCtrl up}{LShift up}{Tab up}")
			Send("{LCtrl down}{w down}")
			Send("{LCtrl up}{w up}")
		}
	} else {
		openYT()
	}
}

openYT() {
	isTPressed := KeyWait("t", "D T0.20") ; wait 0.20 seconds to see if t is pressed
	; Input(&UserInput, "T0.7 L4", "{enter}.{esc}{tab}", "t")
	; if (UserInput = "Timeout") ; y not pressed in time
	if (!isTPressed) { ; t not pressed in time
		return false
		;ignore as of now as it was intrupting normal functionality
		;Send("^y") ; send ^y by itself so it's still usable
	} else {
		YoutubeURL := "https://www.youtube.com/"
		Run(YoutubeURL)
	}
	return true
	; if (UserInput = "t") {
	; 	YoutubeURL := "https://www.youtube.com/"
	; 	Run(YoutubeURL)
	; }
}

OpenNewTab() {
	; If youtube is going to active then disable opening new tab and open YT instead
	if (A_PriorHotkey != "~^Y") {
		if (IsChromiumBrowserActive()) {
			; MsgBox("[ Options, " A_PriorHotkey ", Timeout]")
			Send("^t")
		} else if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250) {
			; Activate whichever Chromium browser exists (Brave preferred); if neither is running, launch
			; Brave fresh: only reached on the double-tap, matching the original gated behavior exactly.
			if !ActivateChromiumBrowserOrRun((*) => Send("^t"), 250) {
				Run("brave.exe")
				Sleep(250)
				Send("^t")
			}
		}
	}
}

OpenCalculator() {
	if WinExist("Calculator") {
		WinActivate()

		;To open another instance if need
		if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 500) {
			Run("calc.exe")
		}
	} else {
		Run("calc.exe")
	}
}

RunPowerShellAsAdministrator() {
	; *RunAs on pwsh.exe or wt.exe directly, Shell.Application ShellExecute on
	; shell:AppsFolder package identity, and a Highest-run-level Task Scheduler
	; task were all tried and rejected: wt.exe is a packaged/MSIX app and none
	; of those reliably elevate it: each either spawns and exits within a
	; second or two, or silently no-ops. This is a genuine Windows limitation
	; (packaged apps generally can't be launched pre-elevated by external
	; automation), not fixable by trying yet another external-elevation
	; variant. *RunAs "...pwsh.exe" DOES elevate reliably on its own, but
	; opens a plain console host window, not Windows Terminal's tabbed UI.

	; Launch a Windows Terminal PROFILE that is itself configured to elevate ("PowerShell
	; (Admin)" in this Terminal install's profile list, normally reached via the dropdown
	; next to the + tab button, or Ctrl+Shift+6 on this machine's current profile order,
	; as that keybinding is NOT stable across installs/reorders, which is why this targets the
	; profile by name instead). Terminal handles the elevation internally for a
	; profile marked this way, the same mechanism the dropdown and Win+X use: the
	; resulting window's title reads "Administrator: PowerShell (Admin)".
	;
	; SETUP REQUIRED: none, on a reasonably current Windows Terminal: "<Profile> (Admin)"
	; entries in that + dropdown are auto-generated by Terminal itself for every detected
	; shell profile, not something manually added to settings.json. No scheduled task, no
	; registry change, nothing to run in an elevated terminal first. If "PowerShell (Admin)"
	; is ever missing from that dropdown on some future machine, that means Terminal itself
	; doesn't see a "PowerShell" profile to generate the admin variant from (e.g. pwsh not
	; installed, or Terminal is on an old version predating this feature), fix that, not
	; this line.
	Run('wt.exe -p "PowerShell (Admin)"')
}

ClickCenterOfScreen() {
	CoordMode("Mouse", "Screen")
	MouseMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
	Click()
}

SortFolderByDate() {
	; if WinActive("ahk_class ExploreWClass") {
	if WinActive("ahk_exe explorer.exe") {
		hWnd := WinGetID("A")
		for oWin in ComObject("Shell.Application").Windows {
			if (oWin.HWND = hWnd) {
				; MsgBox(oWin.Document.SortColumns) ;show current sort columns
				if (oWin.Document.SortColumns == "prop:-System.DateModified;") {
					oWin.Document.SortColumns := "prop:+System.DateModified;" ;sort by date modified descending (newest first)
				} else {
					oWin.Document.SortColumns := "prop:-System.DateModified;" ;sort by date modified ascending (oldest first)
				}
				;oWin.Document.SortColumns := "prop:+System.ItemNameDisplay;" ;sort by name ascending (A-Z)
				;oWin.Document.SortColumns := "prop:-System.ItemNameDisplay;" ;sort by name descending (A-Z)
				; break
			}
		}
		oWin := ""
	}
}

; F8::clickEnter() ;{ <- Delete Recycle Bin Data

; clickEnter() {
; 	Loop {
; 		Sleep(100)
; 		Send("{Click}")
; 		Sleep(100)
; 		Send("{Enter}")
; 	}
; }

; MuteMic: backward-compatible wrapper delegating to ToggleMicrophoneMute() in SharedHelpers.ahk
MuteMic() {
	return ToggleMicrophoneMute()
}

; v2: registered as a Menu.Add() callback below: a zero-parameter function used this way hangs at the
; .Add() call itself (registration time, not click time), confirmed empirically down to the minimal
; case. `(*)` (accept-and-ignore any positional args) is the fix, same convention already used
; throughout StartupScript.ahk for every other menu-click/hotkey target.
TrayUnmuteMicAction(*) {
	SetMicrophoneMute(false, true)
}

WatchMicrophoneMuteState() {
	WatchMicrophoneMute()
}

WatchMicrophoneMute() {
	static s_lastObservedState := -1
	currState := GetMicrophoneMute()
	if (currState == -1)
		return
	if (currState != s_lastObservedState) {
		s_lastObservedState := currState
		UpdateMicrophoneTrayIcon(currState)
	}
}

; YugenAnime() {
; 	Send("{Click 1020 451}")
; 	Sleep(300)
; 	Send("^l")
; 	; Sleep(100)
; 	Send("^c")
; 	Sleep(600)
; 	YugenAnimeEngine := "https://yugenanime.tv/"
; 	LatestCopiedClipboard := A_Clipboard
; 	yugenSubstring := SubStr(LatestCopiedClipboard, 1, 22)
; 	if (yugenSubstring != YugenAnimeEngine) {
; 		Send("^w")
; 		Sleep(200)
; 		Send("f")
; 		Sleep(100)
; 		Send("{Space}")
; 	} else {
; 		Send("{Esc down}")
; 		Sleep(200)
; 		Send("{Esc down}")
; 		Sleep(200)
; 		Send("f")
; 		; Sleep(200)
; 		; Send("{Space}")
; 	}
; }

OpenCalendar() {
	; Sleep, 250 (brave) / Sleep, 100 (chrome): neither ever actually ran live, so no sleep is passed here.
	ActivateChromiumBrowserOrRun(() => Send("!x"))
}

OpenChatGPT() {
	; if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < 250) {
	; WinActivate, ahk_exe brave.exe / WinActivate, ahk_exe chrome.exe
	; Every branch here ran the identical Run() regardless of which browser was found, so the three-way
	; active/exists-brave/exists-chrome check collapses to one predicate.
	if (IsChromiumBrowserActive() || GetRunningBrowsers().Length)
		Run("https://chatgpt.com")
	; }
}

CopyToClipboard() {
	; v1 bailed out here via `if ErrorLevel return` (ClipWait's old error-signaling convention): v2's
	; ClipWait() returns a boolean directly instead, found live to have been dropped entirely during the
	; port (the failure path silently fell through instead of returning), restored below.
	Send("^c")
	if !ClipWait(1) {
		; MsgBox("Copying to clipboard failed.")
		return
	}

	; Sleep, 500
	; Send, ^c

	current_application := WinGetProcessName("A")
	current_window_title := WinGetTitle("A")

	if (current_application = "ApplicationFrameHost.exe" && InStr(current_window_title, "OneNote")) {
		if DllCall("IsClipboardFormatAvailable", "UInt", 1) {
			A_Clipboard := A_Clipboard  ; Convert to text-only, removing formatting.
			if !ClipWait(1) {
				; MsgBox("Failed to process clipboard data.")
			}
		}
	}
}

RevertVideoIntruption() {
	; Hotkey("^+v", "Off")
	; Send("^+v")
	; Hotkey("^+v", "On")
	if (IsChromiumBrowserActive()) {
		; static prevURL := ""
		; Get the URL of the active tab
		; ControlGetText(&url, "Edit1", "ahk_class Chrome_WidgetWin_1")
		; if InStr(url, "file:///") {
		; 	; Close the local file tab
		; 	Send("^w")
		; 	Sleep(500) ; Give some time for the tab to close
		; }

		Sleep(1000)
		Send("{LCtrl down}{LShift down}{tab down}")
		Send("{LCtrl up}{LShift up}{tab up}")
		Sleep(600)
		Send("f")

		; ControlGetText(&url, "Edit1", "ahk_class Chrome_WidgetWin_1")
		; MsgBox(url)

		; if InStr(url, "youtube.com") {
		; }
	}
	return
	; Sleep(500)
	; Send("^l")
	; ; Sleep(10)
	; Send("^c")
	; ClipWait(1)

	; ChromeExtension := "chrome-extension://"
	; LatestCopiedClipboard := A_Clipboard
	; ; MsgBox(LatestCopiedClipboard)

	; chromeExtensionSubstring := SubStr(LatestCopiedClipboard, 1, 19)
	; if (ChromeExtension == chromeExtensionSubstring) {
	; 	Send("{LCtrl down}{LShift down}{tab down}")
	; 	Send("{LCtrl up}{LShift up}{tab up}")
	; 	Sleep(400)
	; 	Send("f")
	; }
}

; MonicaQuickAccess() { ;Grammar Correction
; 	Send("^c")
; 	Sleep(100)
; 	Send("!^f") ;Shortcut to Open Monica
; 	Sleep(500)
; 	Send("{Tab}") ;Going to Grammar section
; 	Send("{Enter}")
; }

MonicaGrammarCorrection() { ;Grammar Correction
	Send("^c")
	Sleep(100)
	Send("!f") ;Shortcut to Open Monica
	Sleep(500)
	; Send, {Tab} ;Going to Grammar section
	Send("{Enter}")
}

MonicaSummary() { ;Summary
	Send("^c")
	Sleep(100)
	Send("!f") ;Shortcut to Open Monica
	Sleep(500)
	Send("{Tab}") ;Going to Summry section
	; Send, {Tab} ;Going to Summry section
	Send("{Enter}")
}

; Alt+Ctr+Z ShareX Image Editor
~!^Z::ImageEditor() ;{ <- ShareX Image Editor

ImageEditor() {
	; Send, ^c
	; MouseClick, left, 902, 471

	Send("^c")
	; ClipWait(1)
	global PATH_SHAREX_EXE
	if (IsSet(PATH_SHAREX_EXE) && PATH_SHAREX_EXE && FileExist(PATH_SHAREX_EXE))
		Run('"' PATH_SHAREX_EXE '" -ImageEditor')
	else
		Run("ShareX.exe -ImageEditor")
	MouseClick("left", 902, 471)
}

; Ctr+Shift+V in browser to go to previous tab when taking a screenshot
~^+v::RevertVideoIntruption() ;{ <- Brave AwesomeSreenshot Intruption Stop

; #HotIf WinActive("ahk_exe EXCEL.EXE") ; This directive targets Microsoft Excel
; !f:: { ; This is the hotkey Alt+F
; 	Send("{LAlt down}{LAlt up}")
; 	Send("{h down}{h up}")
; 	Send("{f down}{f up}")
; 	Send("{p down}{p up}")
; }
; #HotIf ; This closes the Excel-specific directive

; Ctr+C OneNote copy text instead of SS of some text
$^c::CopyToClipboard() ;{ <- OneNote Copy Mechanism Handeling (instead of SS)

; Alt+F11 Hide Window top bar
!F11::WinSetStyle("^0xC00000", "A") ;{ <- Hide Window top bar

; Win+M Minimize window
#M::WinMinimize("A") ;{ <- Minimize Active Window

; Win+F8 -> Bluetooth On/Off
; #F8::BluetoothToggle() ;{ <- Bluetooth Toggle [Discard]

; MouseLButton DoubleClick Show/Hide Taskbar;
; ~LButton::DoubleClick(hide := !hide) ;{ <- Double Click Functions (WindHawk Now)

; Alt+MouseLButton Move background apps
^!LButton::MoveBGApp() ;{ <- Move BG Apps

; Win+F Run FireFox
#f::Run("Firefox") ;{ <- Open FireFox

; Ctr+G Select text to search in browser
^G::ClipboardSearch() ;{ <- Search the selected/clipboard text

; Win+C Run Calculator
#c::OpenCalculator() ;{ <- Open calculaor

; Win+Ctrl+Alt+M Mute/Unmute Microphone
#^!M::ToggleMicrophoneMute() ;{ <- Mute/Unmute Microphone

; Win+Alt+C Run Alarm Clock
#!c::Run("shell:Appsfolder\Microsoft.WindowsAlarms_8wekyb3d8bbwe!App") ;{ <- Open clock

; Win+Alt+Ctrl+C Open Powershell
#!^c::RunPowerShellAsAdministrator() ;{ <- Open Powershell
;Run('"C:\Program Files\PowerShell\7\pwsh.exe" -WorkingDirectory ~')

; Win+Alt+Ctrl+K -> Click Center of Screen
;#!^k::ClickCenterOfScreen() ;{ <- Click Center of Screen

; Win+Shift+E -> (Folder) Open Downloads (My Screenshots) folder
#+e::OpenScreenshotsFolder() ;{ <- Open Screenshots Folder

OpenScreenshotsFolder() {
	global UserProfile
	Run(UserProfile . "\Pictures\Screenshots")
}

; Win+Shift+J -> (Folder) Open Java Course
#+j::OpenJavaCourseFolder() ;{ <- Open Java Course

OpenJavaCourseFolder() {
	global PATH_JAVA_COURSE
	if (IsSet(PATH_JAVA_COURSE) && PATH_JAVA_COURSE)
		Run(PATH_JAVA_COURSE)
}

; Win+Del Empty Recycle Bin
#Del::FileRecycleEmpty() ;{ <- Delete Recycle Bin Data

; Win+Shift+A Open Notification center
#+A::OpenActionCenter() ;{ <- Open Notification center

; Win+Alt+N Clear Notification center
#!N::ClearNotificaitons() ;{ <- Clear Notifications (Win 11)

; Alt+Shift+T Active window Always on Top
; !+T::WinSetAlwaysOnTop(, "A") ;{ <- This Window Always on Top

; Alt+Ctr+J Testing Automation
; $!^J::TestingAutomation() ;{ <- Testing Automation

; Alt+G Copy the content, Open Monica & Grammar Correction
!G::MonicaGrammarCorrection() ;{ <- Monica Grammar Correction

; Alt+Shift+S Copy the content, Open Monica & Summarize Content
!+S::MonicaSummary() ;{ <- Monica Summarize Content

; Alt+Ctr+E Enable/Disable file extension
$!^E::ToggleFileExt() ;{ <- Show/Hide Extenstions

; Alt+Ctr+D Sort Folder content by date
$!^D::SortFolderByDate() ;{ <- Sort Folder content by date

; Alt+Ctr+H Enable/Disable hidden files
$!^H::HideFiles() ;{ <- Show/Hide Hidden Files

; Alt+X -> Open Today Calendar
$!X::OpenCalendar() ;{ <- Open Calender after Browser opening

; Alt+D -> Open ChatGPT
$!D::OpenChatGPT() ;{ <- Open ChatGPT

; Double Tap caps lock to on and off
*CapsLock::DoubleTapCapsLock() ;{ <- Double Tap To Activate/Deactivate

; #HotIf WinActive("ahk_class Shell_TrayWnd")
; Ctr+J+J (Chrome) Close downloads bar at bottom
$^J::CloseBrowserBottomDownloadsBar() ;{ <- (Chrome) Close browser downloads bar at bottom
; #HotIf

; Ctr+Y+T in browser to open Youtube
~^Y::OpenYoutube() ;{ <- Open Youtube

; Ctr+T+T in browser to open new Tab from anywhere
~^T::OpenNewTab() ;{ <- open browser tab from anywhere

; Win+Alt+X -> (Script) Reconnect Cloudfare Network
#!x::ReconnectCloudflare() ;{ <- Reconnect Cloudfare Network

ReconnectCloudflare() {
	global PATH_IP_ROTATOR
	if (IsSet(PATH_IP_ROTATOR) && PATH_IP_ROTATOR)
		Run(PATH_IP_ROTATOR)
}

; Win+Alt+L -> (Script) Cycle Skills Vault Mode (Auto -> Force Locked -> Force Unlocked)
; Scoped MaxThreads override: the handler makes a BLOCKING shell.Run() across 14
; folders (tens-hundreds of ms, more under disk/AV contention). Without this,
; AHK's default (MaxThreadsPerHotkey=1, Buffer=Off) means a second press while
; the first is still running is SILENTLY DISCARDED: not queued, no error.
; Buffer On + PerHotkey 1 coalesces rapid re-presses into exactly one extra
; run, queued (never concurrent: two icacls sweeps racing the same ACLs is
; unacceptable). Reset back to defaults right after, or every hotkey below
; would inherit this (positional, forward-applying).
; v2: #MaxThreadsBuffer takes a boolean (true/false), not v1's On/Off strings: "Parameter #1 invalid"
; otherwise, confirmed empirically.
#MaxThreadsBuffer true
#MaxThreadsPerHotkey 1
#!l::TogglePersonalSkillsLock() ;{ <- Cycle Skills Vault Mode
#MaxThreadsBuffer false
#MaxThreadsPerHotkey 1

; Win+X+X -> Sleep Laptop
$#x::SleepLaptop() ;{ <- Sleep Laptop (Win+X+X)

;Turn Caps Lock into a Shift key
; Capslock::Shift

;F1:: Send("{Left}")
; +NumpadAdd::Send("{Volume_Up}")
; +NumpadSub::Send("{Volume_Down}")
; break::Send("{Volume_Mute}")
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
#HotIf WinActive("ahk_exe Code.exe")
; Ctr+Shift+WheelUp (VS Code) Increase Whole UI Zoom
^+WheelUp::AdjustVsCodeZoom(0.05) ;{ <- (VS Code) Increase Whole UI Zoom (+0.05)
; Ctr+Shift+WheelDown (VS Code) Decrease Whole UI Zoom
^+WheelDown::AdjustVsCodeZoom(-0.05) ;{ <- (VS Code) Decrease Whole UI Zoom (-0.05)
#HotIf

AdjustVsCodeZoom(delta) {
	settingsFile := A_AppData "\Code\User\settings.json"
	if !FileExist(settingsFile)
		return

	sContent := FileRead(settingsFile)
	q := Chr(34)
	pattern := q . "window\.zoomLevel" . q . "\s*:\s*(-?\d+(\.\d+)?)"
	if RegExMatch(sContent, pattern, &match) {
		currentZoom := Round(match[1] + delta, 2)
		; Clamp zoom level between -2.0 (minimum) and 5.0 (maximum) for UI safety
		if (currentZoom < -2.0)
			currentZoom := -2.0
		if (currentZoom > 5.0)
			currentZoom := 5.0

		rep := q . "window.zoomLevel" . q . ": " . currentZoom
		newContent := RegExReplace(sContent, pattern, rep)

		; v2: "File" is a reserved built-in class name (the FileOpen() return type): cannot be used as
		; a plain variable, so v1's "File" is renamed to "fileObj" here (same fix class as 18.4).
		fileObj := FileOpen(settingsFile, "w", "UTF-8")
		if IsObject(fileObj) {
			fileObj.Write(newContent)
			fileObj.Close()
		}

		; Non-intrusive HUD tooltip showing current exact scale factor
		ToolTip("VS Code Whole UI Zoom: " . currentZoom)
		SetTimer(RemoveVsCodeZoomToolTip, -800)
	}
}

RemoveVsCodeZoomToolTip() {
	ToolTip()
}
; [END: VS Code Fine-Grained Whole UI Zoom Hook]

; Win+Alt+M/U (mount/unmount the ext4 backup SSD) now live in
; AllScripts/Ext4SsdManager.ahk, along with the rest of that feature.

; [START: Personal Skills Lock/Unlock 3-Way Toggle]
; Fast phase: the hotkey/tray target. Cycles the in-memory pending mode, shows instant feedback, and arms the settle timer.
; Nothing here blocks: no mutex, no shell.Run, no filesystem check for the lock/unlock scripts: all of that belongs exclusively to CommitPersonalSkillsLock below.
; A blocking icacls sweep across 14 folders (3-4 icacls calls each) takes ~2.3-3.5s, so this split keeps the toast instant on every press; only the LAST press in a rapid run (g_SkillsDebounceMs of quiet, 2000ms by default) actually triggers the real work.
TogglePersonalSkillsLock() {
	global g_SkillsPendingMode, g_SkillsDebounceMs, g_SkillsCommitBusy
	global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT

	; While a commit is actively applying (the amber badge is on screen), the hotkey is a silent no-op.
	; A fresh press here would otherwise clobber the in-flight commit's own badge and then get its OWN commit rejected by DebounceTryBeginCommit anyway, producing a scrambled badge sequence.
	; Cancelling the in-flight commit instead was considered and rejected: it's a blocking shell.Run of icacls across all 14 real vault folders, and killing it mid-sweep could leave the vault partially locked/unlocked: an inconsistent security state this project cannot risk.
	; See ARCHITECTURE.md.
	if (g_SkillsCommitBusy)
		return

	if (!IsSet(PATH_SKILLS_LOCK_SCRIPT) || !PATH_SKILLS_LOCK_SCRIPT || !IsSet(PATH_SKILLS_UNLOCK_SCRIPT) || !PATH_SKILLS_UNLOCK_SCRIPT) {
		ShowSkillsStatusBadge("[ERROR] Skills paths not configured")
		return
	}

	; Seed from the real on-disk mode file only on the first press since this process started (or the first press after a settled commit reset this back to "").
	; Every press after that cycles purely off the in-memory value, so a rapid burst always advances from what the user just SAW, never from stale disk state a pending/in-flight commit hasn't written yet.
	if (g_SkillsPendingMode = "") {
		modeFile := A_Temp "\skills_vault_mode.flag"
		seedMode := "auto"
		if FileExist(modeFile) {
			seedMode := Trim(FileRead(modeFile))
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

	; Arm/re-arm the settle timer (shared helper: see SharedHelpers.ahk for the Reset-timer mechanics).
	; Only the LAST press in any rapid run ever reaches CommitPersonalSkillsLock, and only once g_SkillsDebounceMs elapses with zero further presses.
	; v2: bare function reference, never a string or .Bind() result: a fresh closure each call would
	; break the "only the last press commits" semantics this whole feature depends on.
	DebounceArmTimer(CommitPersonalSkillsLock, g_SkillsDebounceMs)
}

; Slow "commit" phase: the ONLY place that touches the mutex, the lock/unlock scripts, or the on-disk mode file.
; Reached exclusively via the settle timer armed above; nothing else calls this directly.
; v2: was a Gosub-only label, now a real function: every variable it touches needs an explicit global.
CommitPersonalSkillsLock() {
	global g_SkillsPendingMode, g_SkillsCommitBusy, g_SkillsDebounceMs
	global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT, PATH_PWSH_EXE

	; Defense-in-depth only (see g_SkillsCommitBusy's declaration and DebounceTryBeginCommit in SharedHelpers.ahk).
	; AHK's timer engine already guarantees at most one concurrently-running instance of a given timer's target, so this should never actually read true.
	if !DebounceTryBeginCommit(&g_SkillsCommitBusy, CommitPersonalSkillsLock, g_SkillsDebounceMs)
		return

	; Snapshot now, before the mutex wait and the blocking work below.
	; The tail compares the LIVE g_SkillsPendingMode against this snapshot to detect whether a press landed during this invocation, so that press is guaranteed a turn instead of silently lost: see the tail comment.
	targetMode := g_SkillsPendingMode

	; Cross-process mutex: guards against WatchSkillsLock (a separate OS process in BackgroundAutomations.ahk) reading/acting on the same mode file and running the same lock/unlock scripts concurrently with this commit.
	; Same patient 10s timeout the hotkey path always used.
	hMutex := AcquireNamedMutex("SkillsVaultLock_AHK_v1", 10000)
	if (!hMutex) {
		ShowSkillsStatusBadge("[ERROR] Vault busy, try again")
	} else {
		pwsh := (IsSet(PATH_PWSH_EXE) && PATH_PWSH_EXE && FileExist(PATH_PWSH_EXE)) ? PATH_PWSH_EXE : "pwsh.exe"
		shell := ComObject("WScript.Shell")
		scriptOk := true ; false only if a required script vanished since press time

		if (targetMode = "locked") {
			if (FileExist(PATH_SKILLS_LOCK_SCRIPT)) {
				if (IsSkillsVaultUnlocked()) {
					cmd := '"' . pwsh . '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . PATH_SKILLS_LOCK_SCRIPT . '" -Silent'
					ShowBottomRightBadge("[APPLYING...] Locking Skills Vault", "6E5A00", 15000)
					shell.Run(cmd, 0, true)
					HideBottomRightBadge()
				}
			} else {
				ShowSkillsStatusBadge("[ERROR] Lock script not found")
				scriptOk := false
			}
		} else if (targetMode = "unlocked") {
			if (FileExist(PATH_SKILLS_UNLOCK_SCRIPT)) {
				if (!IsSkillsVaultUnlocked()) {
					cmd := '"' . pwsh . '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . PATH_SKILLS_UNLOCK_SCRIPT . '" -Silent'
					ShowBottomRightBadge("[APPLYING...] Unlocking Skills Vault", "6E5A00", 15000)
					shell.Run(cmd, 0, true)
					HideBottomRightBadge()
				}
			} else {
				ShowSkillsStatusBadge("[ERROR] Unlock script not found")
				scriptOk := false
			}
		} else { ; targetMode = "auto"
			; Focus check happens HERE, at commit time, not at press time: "auto" has always meant "whatever's focused NOW" elsewhere in this codebase (WatchSkillsLock's own logic), and the toast shown at press time never promised which script would run, just [AUTO].
			; modeFile is written to "auto" regardless of which (if any) branch below actually runs: unconditional, matching the pre-debounce behavior.
			isUnlocked := IsSkillsVaultUnlocked()
			curExe := WinGetProcessName("A")
			if (curExe = "claude.exe") {
				if (isUnlocked && FileExist(PATH_SKILLS_LOCK_SCRIPT)) {
					cmd := '"' . pwsh . '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . PATH_SKILLS_LOCK_SCRIPT . '" -Silent'
					ShowBottomRightBadge("[APPLYING...] Locking Skills Vault (Auto)", "6E5A00", 15000)
					shell.Run(cmd, 0, true) ; blocking - keep inside the mutex's critical section
					HideBottomRightBadge()
				}
			} else if (curExe = "Antigravity.exe" || curExe = "agy.exe" || curExe = "Antigravity IDE.exe") {
				if (!isUnlocked && FileExist(PATH_SKILLS_UNLOCK_SCRIPT)) {
					cmd := '"' . pwsh . '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . PATH_SKILLS_UNLOCK_SCRIPT . '" -Silent'
					ShowBottomRightBadge("[APPLYING...] Unlocking Skills Vault (Auto)", "6E5A00", 15000)
					shell.Run(cmd, 0, true) ; blocking - keep inside the mutex's critical section
					HideBottomRightBadge()
				}
			}
			; Neither app focused (or its script is missing, or already in requested state): fall through silently: no error, no script, but the mode-file write below still happens.
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

	; Reconciliation (shared helper: see SharedHelpers.ahk): if the live pending value still equals what we just pursued, nothing newer happened: drop back to the "" sentinel so the next press re-seeds from disk instead of trusting this value forever.
	; If it no longer matches, at least one more press landed while this invocation ran (most commonly: while the blocking shell.Run above was still mid-flight, seconds in).
	; That intent can't safely cancel an already-dispatched icacls sweep, so it waits and gets its own turn immediately after instead of being dropped: re-armed once more so it still gets applied. Also clears g_SkillsCommitBusy.
	DebounceEndCommit(&g_SkillsPendingMode, targetMode, &g_SkillsCommitBusy, CommitPersonalSkillsLock, g_SkillsDebounceMs)
}

; AcquireSkillsVaultLock/ReleaseSkillsVaultLock now live in SharedHelpers.ahk as the generalized AcquireNamedMutex/ReleaseNamedMutex.

; Direct mode setter for tray menu selection (Auto, Locked, Unlocked)
SetPersonalSkillsMode(targetMode) {
	global g_SkillsPendingMode, g_SkillsCommitBusy
	global PATH_SKILLS_LOCK_SCRIPT, PATH_SKILLS_UNLOCK_SCRIPT

	if (g_SkillsCommitBusy)
		return

	if (!IsSet(PATH_SKILLS_LOCK_SCRIPT) || !PATH_SKILLS_LOCK_SCRIPT || !IsSet(PATH_SKILLS_UNLOCK_SCRIPT) || !PATH_SKILLS_UNLOCK_SCRIPT) {
		ShowSkillsStatusBadge("[ERROR] Skills paths not configured")
		return
	}

	if (targetMode != "locked" && targetMode != "unlocked")
		targetMode := "auto"

	g_SkillsPendingMode := targetMode

	if (g_SkillsPendingMode = "locked")
		ShowSkillsStatusBadge("[LOCKED] Skills Vault (manual)")
	else if (g_SkillsPendingMode = "unlocked")
		ShowSkillsStatusBadge("[UNLOCKED] Skills Vault (manual)")
	else
		ShowSkillsStatusBadge("[AUTO] Skills Vault (focus-driven)")

	; Fast 300ms debounce for direct user tray clicks
	DebounceArmTimer(CommitPersonalSkillsLock, 300)
}

; Dynamically publishes BasicTasks tray manifest with dedicated modes and tab-aligned hotkey
PublishBasicTasksManifest() {
	braveAccel := GetBrowserHardwareAcceleration("Brave") ? "ON" : "OFF"
	chromeAccel := GetBrowserHardwareAcceleration("Chrome") ? "ON" : "OFF"
	effectsState := GetShareXAddImageEffectsEnabled() ? "ON" : "OFF"

	itemAuto     := "Skills Vault: Auto (Focus-Driven)`tWin+Alt+L"
	itemLocked   := "Skills Vault: Locked (Org Safe Mode)"
	itemUnlocked := "Skills Vault: Unlocked (Personal Mode)"
	accelLabel   := "Graphics Accel: Brave (" braveAccel ") / Chrome (" chromeAccel ")"
	effectsLabel := "ShareX Image Effects: " effectsState "`tWin+Alt+E"

	PublishTrayMenuManifest([ [itemAuto, "TraySkillsVaultAuto"]
	                        , [itemLocked, "TraySkillsVaultLocked"]
	                        , [itemUnlocked, "TraySkillsVaultUnlocked"]
	                        , ["-"]
	                        , [accelLabel, "TrayDRMStreamingModeToggle"]
	                        , ["-"]
	                        , [effectsLabel, "TrayShareXImageEffectsToggle"] ])
}

TraySkillsVaultAuto() {
	SetPersonalSkillsMode("auto")
}

TraySkillsVaultLocked() {
	SetPersonalSkillsMode("locked")
}

TraySkillsVaultUnlocked() {
	SetPersonalSkillsMode("unlocked")
}

TraySkillsVaultStatus() {
	modeFile := A_Temp "\skills_vault_mode.flag"
	sMode := "auto"
	if FileExist(modeFile) {
		sMode := Trim(FileRead(modeFile))
	}
	if (sMode = "locked")
		ShowSkillsStatusBadge("[LOCKED] Skills Vault (manual)")
	else if (sMode = "unlocked")
		ShowSkillsStatusBadge("[UNLOCKED] Skills Vault (manual)")
	else
		ShowSkillsStatusBadge("[AUTO] Skills Vault (focus-driven)")
}

; v2: no longer referenced by PublishBasicTasksManifest()'s manifest list since the single cycling tray
; item was replaced by the 3 dedicated Auto/Locked/Unlocked items above (commit cbaeb08): kept as a
; real function for parity/Win+Alt+L's own use of TogglePersonalSkillsLock() directly, but this specific
; wrapper is currently unreferenced dead code.
TraySkillsVaultCycle() {
	TogglePersonalSkillsLock()
}

UpdateSkillsTrayStatus() {
	PublishBasicTasksManifest()
}

; HandleRemoteTrayMenuTriggerBT replaced by the shared HandleRemoteTrayMenuTrigger
; in SharedHelpers.ahk (the BT suffix existed only to avoid a name collision
; between two file-local copies: no longer needed with one shared function).

; ShowSkillsStatusBadge itself now lives in SharedHelpers.ahk: both this
; file and BackgroundAutomations.ahk's WatchSkillsLock call it, so the
; [LOCKED]/[UNLOCKED]/[AUTO]/error color mapping is defined exactly once.
; [END: Personal Skills Lock/Unlock 3-Way Toggle]

; [START: DRM Video Streaming & Hardware Acceleration Toggle]
; Toggles Chromium hardware acceleration so DRM video streams without black screen.
; Browser-only modification; does not touch display resolution or monitor layout.

ToggleDRMStreamingMode() {
	flagFile := A_Temp "\ahk_drm_streaming_mode.flag"

	; Target: active top browser window currently viewed (not background instances)
	targets := GetTargetBrowsersForDRM()
	if (targets.Length = 0) {
		ShowDRMStatusBadge("[OFF] Graphics Accel: No active Chrome or Brave window")
		return
	}

	; Toggle rule: if any target has HW acceleration ON -> turn OFF (DRM mode). Otherwise restore ON.
	anyHwEnabled := false
	for idx, bName in targets {
		if (GetBrowserHardwareAcceleration(bName)) {
			anyHwEnabled := true
			break
		}
	}

	targetListStr := ""
	for idx, bName in targets
		targetListStr .= (idx > 1 ? " & " : "") bName

	if (anyHwEnabled) {
		; --- ACTIVATE DRM STREAMING MODE (Disable Hardware Acceleration) ---
		FileDelete(flagFile)
		FileAppend("active", flagFile)

		for idx, bName in targets {
			CloseBrowserGracefully(bName)
			SetBrowserHardwareAcceleration(bName, false)
			LaunchBrowserInstance(bName, "--disable-gpu --restore-last-session --disable-session-crashed-bubble")
		}

		ShowDRMStatusBadge("[OFF] Graphics Accel: " targetListStr " (DRM Mode Active)")
		SetTimer(UpdateDRMTrayStatus, -100)
	} else {
		; --- DEACTIVATE DRM STREAMING MODE (Restore Hardware Acceleration) ---
		for idx, bName in targets {
			CloseBrowserGracefully(bName)
			SetBrowserHardwareAcceleration(bName, true)
			LaunchBrowserInstance(bName, "--restore-last-session --disable-session-crashed-bubble")
		}

		; Clean flag file only if no remaining browser has HW accel disabled
		if (GetBrowserHardwareAcceleration("Brave") && GetBrowserHardwareAcceleration("Chrome"))
			FileDelete(flagFile)

		ShowDRMStatusBadge("[ON] Graphics Accel: " targetListStr " (Normal GPU Mode)")
		SetTimer(UpdateDRMTrayStatus, -100)
	}
}

UpdateDRMTrayStatus() {
	PublishBasicTasksManifest()
}

; Deliberately does NOT call the shared GetActiveBrowser() despite the surface-level duplication below -
; this runs on a 250ms hot-loop timer, and GetActiveBrowser()'s Z-order-scanning fallback would then run
; an unconditional DllCall walk 4x/second the entire time neither browser has focus (e.g. while working in
; any other app), which is both wasteful and would start writing g_LastActiveBrowser from a merely-topmost-
; but-unfocused window instead of only a genuinely active one. Keep this narrow and cheap on purpose.
TrackActiveBrowser() {
	global g_LastActiveBrowser, g_LastActiveBrowserTime
	if WinActive("ahk_exe brave.exe") {
		g_LastActiveBrowser := "Brave"
		g_LastActiveBrowserTime := A_TickCount
	} else if WinActive("ahk_exe chrome.exe") {
		g_LastActiveBrowser := "Chrome"
		g_LastActiveBrowserTime := A_TickCount
	}
}
; [END: DRM Video Streaming & Hardware Acceleration Toggle]

; [START: ShareX After-Capture Image Effects Toggle]
; ShareX has no built-in hotkey/CLI job to toggle a single After Capture Task (checked directly
; against ShareX's own HotkeyType enum on GitHub: no such action exists, and the closest thing,
; -ImageEffects, only opens the effects editor window). The only way to flip "Add image effects"
; outside ShareX's own tray/main-window checkbox is to edit DefaultTaskSettings.AfterCaptureJob
; (a comma-separated flags string) directly in ApplicationConfig.json: ShareX only reads that file
; at process start, so this needs the same graceful-close -> edit -> relaunch shape as
; ToggleDRMStreamingMode above, just against ShareX's own settings file instead of a browser's.

; Win+Alt+E -> Toggle ShareX "Add image effects" after-capture task (the watermark preset on/off)
#!e::ToggleShareXImageEffects() ;{ <- Toggle ShareX Image Effects (Watermark)

GetShareXConfigPath() {
	global PATH_SHAREX_CONFIG
	if (IsSet(PATH_SHAREX_CONFIG) && PATH_SHAREX_CONFIG)
		return PATH_SHAREX_CONFIG
	return A_MyDocuments "\ShareX\ApplicationConfig.json"
}

; Reads live off disk (never a cached AHK-side flag) so this stays correct even when the user
; last toggled it by hand through ShareX's own tray menu instead of this hotkey/tray item.
GetShareXAddImageEffectsEnabled() {
	configPath := GetShareXConfigPath()
	if (!FileExist(configPath))
		return false
	try content := FileRead(configPath, "UTF-8")
	catch
		return false
	if (!content)
		return false
	; Split-and-compare rather than a raw substring search: ShareX writes "X, Y" (space after
	; each comma), so a naive InStr(",AddImageEffects,") would miss the space and never match.
	if !RegExMatch(content, '"AfterCaptureJob"\s*:\s*"([^"]*)"', &m)
		return false
	for , f in StrSplit(m[1], ",") {
		if (Trim(f) = "AddImageEffects")
			return true
	}
	return false
}

SetShareXAddImageEffectsEnabled(enable) {
	configPath := GetShareXConfigPath()
	if (!FileExist(configPath))
		return false
	try content := FileRead(configPath, "UTF-8")
	catch
		return false
	if (!content || !RegExMatch(content, '"AfterCaptureJob"\s*:\s*"([^"]*)"', &m))
		return false

	; Rebuild the flag list rather than a blind string-replace, so every OTHER after-capture task
	; (Copy image to clipboard, Save image to file, etc.) survives untouched either way.
	flags := []
	for , f in StrSplit(m[1], ",") {
		f := Trim(f)
		if (f != "" && f != "AddImageEffects")
			flags.Push(f)
	}
	if (enable)
		flags.Push("AddImageEffects")

	newValue := ""
	for idx, f in flags
		newValue .= (idx > 1 ? ", " : "") f

	content := RegExReplace(content, '"AfterCaptureJob"\s*:\s*"[^"]*"', '"AfterCaptureJob": "' newValue '"')

	; Atomic write, same shape as SetBrowserHardwareAcceleration's Local State edit above.
	tempPath := configPath ".tmp"
	try FileDelete(tempPath)
	FileAppend(content, tempPath, "UTF-8")
	if FileExist(tempPath) {
		FileMove(tempPath, configPath, 1)
		return true
	}
	return false
}

; Escalating graceful-close, same shape as CloseBrowserGracefully in SharedHelpers.ahk: a polite
; request first, then taskkill (no /F), then taskkill /F as a guaranteed last resort. -ExitShareX
; has to cold-spawn a fresh helper process just to forward the command via ShareX's single-instance
; IPC to the already-running one, so the first wait is deliberately generous rather than assumed-instant;
; a single short wait with no escalation (the earlier bug) can silently bail out before ShareX
; actually finishes exiting, leaving the JSON edit and relaunch never reached at all.
CloseShareXGracefully(sharexExe, timeoutMs := 4000) {
	if (!ProcessExist("ShareX.exe"))
		return true ; Already not running

	Run('"' sharexExe '" -ExitShareX')
	timeoutSec := Ceil(timeoutMs / 1000)
	ProcessWaitClose("ShareX.exe", timeoutSec)

	if (ProcessExist("ShareX.exe")) {
		try RunWait("taskkill /IM ShareX.exe", , "Hide")
		Loop 15 {
			if (!ProcessExist("ShareX.exe"))
				break
			Sleep(100)
		}
		if (ProcessExist("ShareX.exe")) {
			try RunWait("taskkill /F /IM ShareX.exe", , "Hide")
			Sleep(300)
		}
	}
	Sleep(200) ; Settle delay so the OS releases the file handle on ApplicationConfig.json
	return !ProcessExist("ShareX.exe")
}

ToggleShareXImageEffects() {
	global PATH_SHAREX_EXE

	configPath := GetShareXConfigPath()
	if (!FileExist(configPath)) {
		ShowBottomRightBadge("ShareX config not found - run ShareX once first", "7A3B00", 3000)
		return
	}

	sharexExe := (IsSet(PATH_SHAREX_EXE) && PATH_SHAREX_EXE && FileExist(PATH_SHAREX_EXE)) ? PATH_SHAREX_EXE : "ShareX.exe"
	newState := !GetShareXAddImageEffectsEnabled()

	; Editing the JSON while ShareX is still alive would just get overwritten by ShareX's own next
	; in-memory settings save, so this must fully finish (guaranteed force-kill fallback, not just
	; a single hopeful wait) before the file is touched.
	if !CloseShareXGracefully(sharexExe) {
		ShowBottomRightBadge("ShareX would not close - try again", "7A3B00", 3000)
		return
	}

	SetShareXAddImageEffectsEnabled(newState)

	Run('"' sharexExe '" -silent')

	if (newState)
		ShowBottomRightBadge("ShareX Image Effects: ON", "1A6E3C", 2500)
	else
		ShowBottomRightBadge("ShareX Image Effects: OFF", "6E1A1A", 2500)

	PublishBasicTasksManifest()
}
; [END: ShareX After-Capture Image Effects Toggle]

$F9::Send("{PrintScreen}") ;{ <- Screen Capture via PrintScreen (ShareX)
