; =============================================================================
; SHARED HELPERS - functions used by more than one script in this repo.
;
; #Include this file (with an explicit %A_ScriptDir%\ prefix, never a bare filename - see ARCHITECTURE.md for why) from any script that needs one of these.
; Every function below is self-contained and takes its inputs as parameters rather than reaching for a specific script's own globals, so it behaves identically no matter which script includes it.
; Full design rationale (why these moved here, the debounce pattern as a reusable template) lives in ARCHITECTURE.md at the repo root - read that before adding a new feature that needs any of this.
;
; v2 port notes: #Persistent is not usable as a directive in v2 (confirmed empirically: it does not proceed past itself, even after an 8s wait, regardless of what other reference material claims - Persistent() the function is the proven-working replacement, used below).
; ByRef became &, dynamic label-based SetTimer/Gosub dispatch (debounce trio, tray-manifest trigger) became real function references (see each section for the redesign), VarSetCapacity became Buffer(), ComObjCreate became ComObject(),
; SysGet's monitor sub-commands became MonitorGetPrimary()/MonitorGetCount()/MonitorGetWorkArea()/MonitorGetName(), and the v1-only Hwnd-vs-v Gui bug workaround is dropped since v2's .Add() always returns the control object directly.
; Since v2 addresses a Gui by object reference rather than by name string, the badge singleton below now needs an
; explicit shared reference (g_BadgeGui/g_BadgeTextCtl) so Show/Hide/Remove can all reach the same window instance.
; =============================================================================
#Requires AutoHotkey v2.0
Persistent()
; This file is a real managed entry in StartupScript.ahk's own Files[] (Script_12), launched standalone just like
; every other managed script - it deserves the same duplicate-launch protection they all have. Confirmed
; empirically safe to declare here even though every consumer #Includes this file and already has its own
; #SingleInstance force: a duplicate directive with the same value across a merged script is a harmless no-op,
; not a conflict or a load-time hang.
#SingleInstance force

; v2 fleet control protocol: replaces v1's master PostMessage to AutoHotkey's own reserved tray-command IDs (Edit/Exit/
; ViewKeyHistory/Suspend), which is not guaranteed to carry over to v2 processes. Every managed script (this one included,
; since it's Script_12 in StartupScript.ahk's own Files[] array, run standalone for quick Edit access) registers the same
; custom message and handles it locally.
g_FleetControlMsg := DllCall("RegisterWindowMessage", "Str", "AHK_FleetControl_v2", "UInt")
OnMessage(g_FleetControlMsg, HandleFleetControlMessage)
HandleFleetControlMessage(wParam, lParam, msg, hwnd) {
	switch wParam {
		case 1: Edit()
		case 2: ExitApp()
		case 3: KeyHistory()
		case 4: Suspend(!A_IsSuspended)
	}
}


; -----------------------------------------------------------------------------
; NAMED MUTEX - cross-process mutual exclusion
; -----------------------------------------------------------------------------
; Kernel-object mutex, not a file-existence convention: a plain lock file can be left permanently stuck if the owning process crashes mid-critical-section, but a named mutex cannot - Windows auto-releases it as "abandoned" and the next waiter picks it up cleanly.
; Pass a distinct mutexName per logical resource being guarded (e.g. "SkillsVaultLock_AHK_v1") - every caller sharing that exact string, across however many separate processes, contends on the same kernel object.
; Plain names (no "Global\" prefix) are correct as long as every consumer runs in the same interactive user session, which is the case for every script in this repo - no elevated privilege needed.
; v2: DllCall syntax is unchanged here (types were already quoted strings in the original), only the surrounding function-vs-command shell changes elsewhere in this file.
AcquireNamedMutex(mutexName, timeoutMs) {
	hMutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", mutexName, "Ptr")
	if (!hMutex)
		return 0
	waitResult := DllCall("WaitForSingleObject", "Ptr", hMutex, "UInt", timeoutMs, "UInt")
	if (waitResult = 0x102 || waitResult = 0xFFFFFFFF) { ; WAIT_TIMEOUT / WAIT_FAILED
		DllCall("CloseHandle", "Ptr", hMutex)
		return 0
	}
	; 0 = WAIT_OBJECT_0 (clean acquire).
	; 0x80 = WAIT_ABANDONED (prior owner crashed mid-op; we still now own it cleanly - Windows handled the cleanup).
	return hMutex
}

ReleaseNamedMutex(hMutex) {
	if (hMutex) {
		DllCall("ReleaseMutex", "Ptr", hMutex)
		DllCall("CloseHandle", "Ptr", hMutex)
	}
}


; -----------------------------------------------------------------------------
; DEBOUNCE - "settle after N ms of quiet, then act once" pattern
; -----------------------------------------------------------------------------
; Three small functions meant to be used together.
; Each feature keeps owning its own state as plain globals (a pending-value variable, a busy flag, an interval) and passes them in by name/&reference - nothing here stores any feature-specific state itself.
; See ARCHITECTURE.md for the full worked example of wiring these into a new debounced hotkey.
;
; v2 REDESIGN (genuine redesign, not a syntax port): v1 dispatched to a dynamically-named commit LABEL via
; SetTimer's documented "the name stored in the variable is used as the target" behavior.
; v2 removes label-targeted SetTimer entirely (one-shot or recurring) - there is no string-dispatch alternative
; left at all. Every commit phase is now an ordinary FUNCTION, and timerFunc below is a real function reference,
; never a string.
; Callers must pass the bare function name (no parens, no quotes), never a fresh closure/.Bind() result - a
; closure is a different object every call, which would defeat SetTimer's "re-arming resets the countdown instead
; of stacking a second firing" behavior this pattern depends on.

; (Re)arms a one-shot timer at timerFunc, delayMs from now.
; A negative SetTimer period, per AHK's documented "Reset" behavior (unchanged in v2), cancels any already-pending
; countdown for that same target and starts a fresh one rather than stacking a second pending firing - but only
; when timerFunc is the SAME function-object identity across calls, which is exactly why callers must pass a
; stable, named function reference.
DebounceArmTimer(timerFunc, delayMs) {
	SetTimer(timerFunc, -delayMs)
}

; First line of a commit function.
; AHK's own timer engine already guarantees at most one concurrently-running instance of a given timer's target,
; so busyFlag reading true here should never actually happen in practice - defense in depth only.
; Returns true if the caller should proceed with the real work; false if the caller should return immediately (the settle timer has already been re-armed on its behalf).
DebounceTryBeginCommit(&busyFlag, timerFunc, delayMs) {
	if (busyFlag) {
		DebounceArmTimer(timerFunc, delayMs)
		return false
	}
	busyFlag := true
	return true
}

; Last step of a commit function, called once the real work is fully done.
; snapshotValue is whatever the caller read from pendingVar BEFORE doing that work (before any blocking call) - comparing the LIVE pendingVar against that snapshot is how a press that landed WHILE the commit was running gets detected.
; Clears busyFlag first so a re-armed timer firing immediately after this returns never sees a stale true.
DebounceEndCommit(&pendingVar, snapshotValue, &busyFlag, timerFunc, delayMs) {
	busyFlag := false
	if (pendingVar != snapshotValue)
		DebounceArmTimer(timerFunc, delayMs)
	else
		pendingVar := ""
}


; -----------------------------------------------------------------------------
; BOTTOM-RIGHT BADGE - dynamic singleton toast surface
; -----------------------------------------------------------------------------
; Singleton badge surface (one "BottomRightBadge" Gui) - a second call while one is showing updates its color/text in place, never stacks a second one. If a future feature needs independent simultaneous badges, this would need a name parameter added - not needed by anything today.
;
; Auto-sizing dynamic toast surface anchored to the bottom-right corner of active monitor work area.
; 1. Operates with -DPIScale so all coordinates and dimensions map 1:1 to physical screen pixels.
; 2. Recalculates work area on every invocation to eliminate drift during display mode switches.
; 3. Uses GDI DrawText (DT_CALCRECT + DT_WORDBREAK) to dynamically auto-size without clipping.
; 4. Applies modern 10px rounded corners via SetWindowRgn for polished toast aesthetics.
; 5. Reuses the persistent GUI window in-place without flicker, blank gaps, or rebuild delays.
; 6. v2: the v1-only Hwnd-vs-v Gui-control-hang bug (AHK v1.1.37.02, Add from inside a function) does not exist in v2 - .AddText() always returns the control object directly regardless of calling context.
;    Because v2 addresses a Gui by object reference rather than by name string, g_BadgeGui/g_BadgeTextCtl (file-level globals) replace both the old "BottomRightBadge" name string and the Hwnd-workaround statics - every function below that needs the same window instance shares these two globals explicitly.
; 7. Explicit WinRedraw forces transparent text controls to repaint immediately on color changes - without it, the old color can linger behind the control until some unrelated repaint event happens to trigger it.
g_BadgeGui := ""
g_BadgeTextCtl := ""

ShowBottomRightBadge(msg, bgColorHex, displayMs := 0) {
	global g_BadgeGui, g_BadgeTextCtl

	SetTimer(RemoveBottomRightBadge, 0)

	if (!IsObject(g_BadgeGui)) {
		g_BadgeGui := Gui("-DPIScale +AlwaysOnTop +ToolWindow -Caption")
		g_BadgeGui.MarginX := 0
		g_BadgeGui.MarginY := 0
		g_BadgeGui.SetFont("s12 Bold cFFFFFF", "Segoe UI")
		; Start with -Wrap so text stays strictly inline on a single line
		g_BadgeTextCtl := g_BadgeGui.AddText("Center -Wrap BackgroundTrans", msg)
	} else {
		g_BadgeGui.SetFont("s12 Bold cFFFFFF", "Segoe UI")
		g_BadgeTextCtl.SetFont("s12 Bold cFFFFFF", "Segoe UI")
	}

	; 1. Resolve current active monitor work area (handles Laptop vs Tablet switches)
	monIndex := GetToastTargetMonitor()
	MonitorGetWorkArea(monIndex, &waLeft, &waTop, &waRight, &waBottom)
	monW := waRight - waLeft
	monH := waBottom - waTop
	if (monW <= 0 || monH <= 0) {
		waLeft := 0, waTop := 0, waRight := A_ScreenWidth, waBottom := A_ScreenHeight
		monW := A_ScreenWidth, monH := A_ScreenHeight
	}

	; 2. Measure text dimensions via GDI DrawText
	hDC := DllCall("GetDC", "Ptr", g_BadgeGui.Hwnd, "Ptr")
	hFont := SendMessage(0x31, 0, 0, g_BadgeTextCtl.Hwnd) ; WM_GETFONT
	hOldFont := DllCall("SelectObject", "Ptr", hDC, "Ptr", hFont, "Ptr")

	isMultiLine := InStr(msg, "`n") ? true : false
	dtFormat := isMultiLine ? 0x400 : 0x420 ; 0x400 = DT_CALCRECT (multi-line), 0x420 = DT_CALCRECT | DT_SINGLELINE

	rectText := Buffer(16, 0)
	DllCall("DrawTextW", "Ptr", hDC, "WStr", msg, "Int", -1, "Ptr", rectText, "UInt", dtFormat)
	measuredW := NumGet(rectText, 8, "Int") - NumGet(rectText, 0, "Int")
	measuredH := NumGet(rectText, 12, "Int") - NumGet(rectText, 4, "Int")

	; Proportional padding and sizing
	if (isMultiLine) {
		padX := 24
		padY := 12
		badgeW := measuredW + (padX * 2)
		badgeH := Max(52, measuredH + (padY * 2))
		cornerR := Max(10, Floor(badgeH * 0.18))
		g_BadgeTextCtl.Opt("+Center")
	} else {
		padX := Max(24, Floor(measuredH * 1.1))
		padY := Max(12, Floor(measuredH * 0.45))
		badgeH := Max(48, measuredH + (padY * 2))
		badgeW := measuredW + (padX * 2)
		cornerR := Max(10, Floor(badgeH * 0.22))
		g_BadgeTextCtl.Opt("-Wrap +Center")
	}

	minBadgeW := 220
	if (badgeW < minBadgeW)
		badgeW := minBadgeW

	textW := measuredW + 8
	textH := measuredH
	textX := Floor((badgeW - textW) / 2)
	textY := Floor((badgeH - textH) / 2)

	DllCall("SelectObject", "Ptr", hDC, "Ptr", hOldFont)
	DllCall("ReleaseDC", "Ptr", g_BadgeGui.Hwnd, "Ptr", hDC)

	; 3. Anchor to bottom-right corner of active monitor work area (respects taskbar)
	marginX := Max(24, Floor(monW * 0.015))
	marginY := Max(24, Floor(monH * 0.02))
	finalX := waRight - badgeW - marginX
	finalY := waBottom - badgeH - marginY

	; Clamp strictly within active monitor boundaries
	if (finalX < waLeft + marginX)
		finalX := waLeft + marginX
	if (finalY < waTop + marginY)
		finalY := waTop + marginY

	; 4. Update GUI styling, text position, and content
	g_BadgeGui.BackColor := bgColorHex
	g_BadgeTextCtl.Text := msg
	g_BadgeTextCtl.Move(textX, textY, textW, textH)

	; Show GUI with exact physical coordinates (-DPIScale guarantees 1:1 match)
	g_BadgeGui.Show("x" finalX " y" finalY " w" badgeW " h" badgeH " NA")

	; Smooth rounded corners for modern Windows toast finish
	hRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", badgeW, "Int", badgeH, "Int", cornerR, "Int", cornerR, "Ptr")
	DllCall("SetWindowRgn", "Ptr", g_BadgeGui.Hwnd, "Ptr", hRgn, "Int", true)

	; Force immediate redraw to prevent backdrop color artifacting
	WinRedraw(g_BadgeGui)

	if (displayMs > 0)
		SetTimer(RemoveBottomRightBadge, -displayMs)
}

GetToastTargetMonitor() {
	; Determine which monitor the user is actively viewing.
	; Check cursor position first as it tracks active user focus across monitors.
	CoordMode("Mouse", "Screen")
	MouseGetPos(&mx, &my)
	monCount := MonitorGetCount()
	Loop monCount {
		MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (mx >= mLeft && mx <= mRight && my >= mTop && my <= mBottom)
			return A_Index
	}
	; Fallback to Primary monitor
	primaryMon := MonitorGetPrimary()
	return primaryMon ? primaryMon : 1
}

; Hides the badge immediately, without waiting for any auto-dismiss timer - the window itself stays alive (Hide, not Destroy), so the next ShowBottomRightBadge call is an instant in-place update, not a rebuild.
; Use this (rather than showing a replacement badge) once real work following an "applying" badge has finished and there is nothing new worth telling the user - see CommitPersonalSkillsLock in BasicTasks.ahk for the motivating case.
HideBottomRightBadge() {
	global g_BadgeGui
	SetTimer(RemoveBottomRightBadge, 0)
	if IsObject(g_BadgeGui)
		g_BadgeGui.Hide()
}

; A FUNCTION, not a label - deliberate, same reasoning as v1: SetTimer targeting a bare function name works.
; Hides rather than destroys, same reasoning as HideBottomRightBadge above - this is just the timer-driven path to the same end state.
RemoveBottomRightBadge() {
	global g_BadgeGui
	if IsObject(g_BadgeGui)
		g_BadgeGui.Hide()
}


; -----------------------------------------------------------------------------
; SKILLS VAULT STATUS BADGE - color-coded wrapper over ShowBottomRightBadge
; -----------------------------------------------------------------------------
; Shared by BasicTasks.ahk (manual Win+Alt+L toggle) and BackgroundAutomations.ahk (WatchSkillsLock, the focus-driven auto watcher) - both want the exact same [LOCKED]/[UNLOCKED]/[AUTO]/error color mapping, so it's defined once here rather than duplicated per script.
; Explicit 3000ms: ShowBottomRightBadge's own default is 0 (persist until replaced/hidden, for the commit-phase hide-on-completion flow) - every caller through this wrapper wants the original auto-dismiss behavior instead.
ShowSkillsStatusBadge(msg) {
	; Check [UNLOCKED] before [LOCKED] to prevent "LOCKED" substring collision
	if InStr(msg, "[UNLOCKED]")
		bgColor := "1A6E3C" ; Deep green
	else if InStr(msg, "[LOCKED]")
		bgColor := "8B1A1A" ; Deep red
	else if InStr(msg, "[AUTO]")
		bgColor := "0D4F8B" ; Deep blue
	else
		bgColor := "7A3B00" ; Dark orange for errors

	ShowBottomRightBadge(msg, bgColor, 3000)
}


; -----------------------------------------------------------------------------
; SKILLS VAULT PHYSICAL STATE PROBE - read-test via PATH_SKILLS_TEST_FILE
; -----------------------------------------------------------------------------
; Probes whether personal skills are currently readable or blocked by NTFS Deny ACLs.
; Returns true if unlocked (readable), false if locked (Access Denied) or unconfigured.
IsSkillsVaultUnlocked() {
	global PATH_SKILLS_TEST_FILE
	; v2 gotcha (empirically found, real production impact, not just a test artifact): a global declared here but
	; never assigned ANYWHERE in the loaded script causes a load-time hang when read in a boolean context, not a
	; graceful falsy/empty value like v1 gave.
	; PATH_SKILLS_TEST_FILE normally comes from LocalPaths.ahk, included by every real consumer - but this file
	; also runs standalone (Script_12 in StartupScript.ahk's Files[], "quick Edit access"), where LocalPaths.ahk
	; is never included and the global genuinely has no assignment anywhere. IsSet() first avoids it.
	if (!IsSet(PATH_SKILLS_TEST_FILE) || !PATH_SKILLS_TEST_FILE)
		return false
	try {
		f := FileOpen(PATH_SKILLS_TEST_FILE, "r")
		if (f) {
			f.Close()
			return true
		}
	}
	return false
}


; -----------------------------------------------------------------------------
; DRM STREAMING STATUS BADGE - color-coded toast over ShowBottomRightBadge
; -----------------------------------------------------------------------------
ShowDRMStatusBadge(msg) {
	if (InStr(msg, "[ON]") || InStr(msg, "[ACTIVE]"))
		bgColor := "1A6E3C" ; Deep green for ON / ACTIVE
	else
		bgColor := "3A3D40" ; Dark slate grey for OFF

	ShowBottomRightBadge(msg, bgColor, 3000)
}


; -----------------------------------------------------------------------------
; TIMED TOOLTIP - native ToolTip, auto-dismissed after N ms
; -----------------------------------------------------------------------------
; Collapses the repeated inline "ToolTip -> SetTimer -Nms -> commit -> ToolTip" pattern that previously appeared independently at several call sites across BasicTasks.ahk and BackgroundAutomations.ahk (VS Code zoom HUD, SSD mount/unmount feedback).
; For anything wanting color/positioning control beyond native ToolTip's default near-cursor placement, use ShowBottomRightBadge above instead.
ShowTimedToolTip(msg, displayMs) {
	ToolTip(msg)
	SetTimer(RemoveTimedToolTip, -displayMs)
}

; A function, not a label - same reasoning as RemoveBottomRightBadge() above.
RemoveTimedToolTip() {
	ToolTip()
}


; -----------------------------------------------------------------------------
; CONNECTED DISPLAY DETECTION - hardware-level check for external displays
; -----------------------------------------------------------------------------
; Checks if a second display (physical monitor or HDMI dummy plug) is attached to any graphics adapter, even when Windows has turned off its desktop output in PC Screen Only mode (where SM_CMONITORS / MonitorGetCount reports 1).
HasSecondDisplayConnected() {
	; If virtual desktop already has 2 or more active monitors (e.g. extended desktop), a second display is definitely active.
	if (MonitorGetCount() >= 2)
		return true

	; When in single-monitor mode (PC Screen Only or Second Screen Only), query attached hardware devices via EnumDisplayDevices to find unique attached monitors.
	uniqueMonitors := Map()
	devNum := 0
	dispDev := Buffer(840, 0)
	NumPut("UInt", 840, dispDev, 0)

	while DllCall("EnumDisplayDevices", "Ptr", 0, "UInt", devNum, "Ptr", dispDev, "UInt", 0) {
		; Skip virtual mirroring drivers (DISPLAY_DEVICE_MIRRORING_DRIVER = 0x00000008)
		devFlags := NumGet(dispDev, 324, "UInt")
		if (devFlags & 8) {
			devNum++
			dispDev := Buffer(840, 0)
			NumPut("UInt", 840, dispDev, 0)
			continue
		}

		devName := StrGet(dispDev.Ptr + 4, 32)
		monNum := 0
		monDev := Buffer(840, 0)
		NumPut("UInt", 840, monDev, 0)

		while DllCall("EnumDisplayDevices", "Str", devName, "UInt", monNum, "Ptr", monDev, "UInt", 0) {
			monFlags := NumGet(monDev, 324, "UInt")
			monId := StrGet(monDev.Ptr + 328, 128)
			; 0x2 = DISPLAY_DEVICE_ATTACHED
			if ((monFlags & 2) && monId != "") {
				uniqueMonitors[monId] := true
			}
			monNum++
			monDev := Buffer(840, 0)
			NumPut("UInt", 840, monDev, 0)
		}
		devNum++
		dispDev := Buffer(840, 0)
		NumPut("UInt", 840, dispDev, 0)
	}

	return (uniqueMonitors.Count >= 2)
}

; Checks if an external display (e.g. HDMI dummy plug on DISPLAY4) is active on the virtual desktop,
; either alone (Second Screen Only / Tablet Mode) or combined with the internal panel (Duplicate or Extend).
IsExternalDisplayActive() {
	; Check 1: If internal laptop panel (DISPLAY1) is not active at all, an external display is active alone.
	monCount := MonitorGetCount()
	hasInternal := false
	Loop monCount {
		if InStr(MonitorGetName(A_Index), "DISPLAY1") {
			hasInternal := true
			break
		}
	}
	if (!hasInternal)
		return true

	; Check 2: If internal panel is active, check if any external graphics adapter (DISPLAY4+) is attached to the desktop (0x1).
	devNum := 0
	dispDev := Buffer(840, 0)
	NumPut("UInt", 840, dispDev, 0)
	while DllCall("EnumDisplayDevices", "Ptr", 0, "UInt", devNum, "Ptr", dispDev, "UInt", 0) {
		devName := StrGet(dispDev.Ptr + 4, 32)
		devFlags := NumGet(dispDev, 324, "UInt")
		if (!InStr(devName, "DISPLAY1") && (devFlags & 1)) {
			return true
		}
		devNum++
		dispDev := Buffer(840, 0)
		NumPut("UInt", 840, dispDev, 0)
	}
	return false
}

; Queries Windows Display Engine kernel for active desktop topology ID.
; Returns:
;   1 = SDC_TOPOLOGY_INTERNAL (PC Screen Only)
;   2 = SDC_TOPOLOGY_CLONE (Duplicate Displays)
;   4 = SDC_TOPOLOGY_EXTEND (Extend Displays)
;   8 = SDC_TOPOLOGY_EXTERNAL (Second Screen / Tablet Only)
;   0 = Query failed
GetCurrentDisplayTopology() {
	numPaths := Buffer(4, 0)
	numModes := Buffer(4, 0)
	; QDC_DATABASE_CURRENT := 4
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

; Checks if the system is currently in Second Screen Only mode (headless tablet display).
; Authoritative via QueryDisplayConfig (SDC_TOPOLOGY_EXTERNAL = 8).
; Falls back to checking internal panel attachment if QueryDisplayConfig fails.
IsSecondScreenOnly() {
	topo := GetCurrentDisplayTopology()
	if (topo == 8)
		return true
	if (topo == 1 || topo == 2 || topo == 4)
		return false

	monCount := MonitorGetCount()
	Loop monCount {
		if InStr(MonitorGetName(A_Index), "DISPLAY1")
			return false
	}
	return true
}


; -----------------------------------------------------------------------------
; TRAY MENU MANIFEST - publish/dispatch for StartupScript.ahk's master submenu
; -----------------------------------------------------------------------------
; Call PublishTrayMenuManifest once from each script's auto-execute section right after its native tray setup, passing [DisplayLabel, HandlerKey] pairs as a nested array:
;   PublishTrayMenuManifest([ ["Display Label 1", "TrayLabel1"]
;                           , ["-"]
;                           , ["Display Label 2", "TrayLabel2"] ])
; Then call RegisterTrayMenuHandler("TrayLabel1", MyHandlerFunc) once per item, mapping each HandlerKey to a real function reference.
;
; v2 REDESIGN (genuine redesign, not a syntax port): v1 dispatched a manifest-driven click via Gosub to a label
; NAMED by the manifest's second field.
; Gosub is removed entirely in v2, with no replacement of any kind, dynamic or otherwise - so this can no longer
; be "a string that happens to name a label," it has to become a real lookup into a table of function references
; built at startup by each consuming script. g_TrayMenuHandlers below is that table.
;
; Architecture (unchanged from v1 otherwise):
; 1. Writes %A_Temp%\ahk_traymenu_<ScriptName>.txt (one file per script, keyed by that script's own filename).
; 2. Supports ["-"] entries (serialized as "-|") to render native Win32 horizontal separator bars in StartupScript's mirrored submenu.
; 3. Registers this shared HandleRemoteTrayMenuTrigger as the handler for the system-wide registered window message "AHK_RemoteTrayMenuTrigger_v1".
; 4. StartupScript.ahk reads these manifest files to mirror every script's custom tray items into one master submenu, and PostMessages this registered ID with wParam = the manifest's 1-based line number when a mirrored item is clicked.
; 5. Each process reads only its own manifest file (via its own A_ScriptFullPath), so sharing this function across multiple processes is safe without collision.
g_TrayMenuHandlers := Map()

RegisterTrayMenuHandler(key, handlerFunc) {
	global g_TrayMenuHandlers
	g_TrayMenuHandlers[key] := handlerFunc
}

PublishTrayMenuManifest(itemsArray) {
	SplitPath(A_ScriptFullPath, , , , &scriptNameNoExt)
	manifestPath := A_Temp "\ahk_traymenu_" scriptNameNoExt ".txt"
	content := ""
	for idx, item in itemsArray {
		if (!IsObject(item) && (item = "-" || item = ""))
			content .= "-|`n"
		else if (item[1] = "-" || item[1] = "")
			content .= "-|`n"
		else
			content .= item[1] . "|" . item[2] . "`n"
	}
	try {
		f := FileOpen(manifestPath, "w", "UTF-8")
		if (f) {
			f.Write(content)
			f.Close()
		}
	} catch {
		try FileDelete(manifestPath)
		FileAppend(content, manifestPath, "UTF-8")
	}
	; v2: OnMessage's name-string registration mode ("HandleRemoteTrayMenuTrigger" as a string) is gone - only a
	; real function-object reference survives. Passing the bare name below (no quotes) is the fix.
	OnMessage(DllCall("RegisterWindowMessage", "Str", "AHK_RemoteTrayMenuTrigger_v1", "UInt"), HandleRemoteTrayMenuTrigger)
}

HandleRemoteTrayMenuTrigger(wParam, lParam, msg, hwnd) {
	global g_TrayMenuHandlers
	SplitPath(A_ScriptFullPath, , , , &scriptNameNoExt)
	manifestPath := A_Temp "\ahk_traymenu_" scriptNameNoExt ".txt"
	try content := FileRead(manifestPath)
	catch
		return
	lines := StrSplit(content, "`n", "`r")
	if (wParam < 1 || wParam > lines.Length)
		return
	parts := StrSplit(lines[wParam], "|")
	; Map.Has guard: a manifest can outlive the handler it names (e.g. mid-migration, before a stale
	; %A_Temp%\ahk_traymenu_<script>.txt is deleted).
	; Without this, a lookup miss would need its own guard anyway; this keeps a leftover manifest entry a
	; silent no-op instead of an error.
	if (parts.Length >= 2 && parts[2] != "" && g_TrayMenuHandlers.Has(parts[2]))
		g_TrayMenuHandlers[parts[2]]()
}


; -----------------------------------------------------------------------------
; RUN SILENT POWERSHELL & CONSOLE LAUNCHER
; -----------------------------------------------------------------------------
; Launches a PowerShell script or console binary with zero visible window (no conhost flash, no focus theft).
; Prefers run_silent.exe (true CREATE_NO_WINDOW) when present next to the calling script; falls back to WScript.Shell.Run's hidden-window flag, then to a plain hidden Run as a last resort if COM creation itself fails.
GetRunSilentExe() {
	runSilentExe := A_ScriptDir "\PowerShell\run_silent.exe"
	if !FileExist(runSilentExe)
		runSilentExe := A_LineFile "\..\PowerShell\run_silent.exe"
	return FileExist(runSilentExe) ? runSilentExe : ""
}

RunSilentPowerShell(scriptPath, args := "") {
	runSilentExe := GetRunSilentExe()
	if (runSilentExe) {
		cmd := '"' runSilentExe '" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '"' (args != "" ? " " args : "")
		Run(cmd, , "Hide")
		return true
	}
	cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '"' (args != "" ? " " args : "")
	try {
		shell := ComObject("WScript.Shell")
		shell.Run(cmd, 0, false)
		return true
	} catch {
		Run(cmd, , "Hide")
		return false
	}
}

RunSilentProcess(targetExe, args := "") {
	runSilentExe := GetRunSilentExe()
	if (runSilentExe) {
		cmd := '"' runSilentExe '" "' targetExe '"' (args != "" ? " " args : "")
		Run(cmd, , "Hide")
		return true
	}
	cmd := '"' targetExe '"' (args != "" ? " " args : "")
	try {
		shell := ComObject("WScript.Shell")
		shell.Run(cmd, 0, false)
		return true
	} catch {
		Run(cmd, , "Hide")
		return false
	}
}

; MountExt4Ssd/UnmountExt4Ssd now live in AllScripts/Ext4SsdManager.ahk: the ext4 SSD feature is single-owner (that one script), not shared across multiple consumers, so it no longer belongs in this shared-helpers file.


; -----------------------------------------------------------------------------
; CHROMIUM BROWSER OPERATIONS (Brave & Chrome)
; -----------------------------------------------------------------------------
; Manages graceful close, atomic Local State JSON edits, and zero-GPU launch.
;
; v2 gotcha (same class as IsSkillsVaultUnlocked's, same fix shape): g_LastActiveBrowser/g_LastActiveBrowserTime
; are only ever assigned conditionally INSIDE GetActiveBrowser() below, never at script top level - empirically
; that also causes the load-time hang, not just a genuinely-never-assigned-anywhere global.
; A top-level initialization avoids it.
g_LastActiveBrowser := ""
g_LastActiveBrowserTime := 0

GetBrowserMeta(browserName) {
	global PATH_BRAVE_EXE, PATH_CHROME_EXE
	localAppData := EnvGet("LOCALAPPDATA")
	meta := {}
	meta.name := browserName

	if (browserName = "Brave") {
		meta.exeName := "brave.exe"
		meta.localStatePath := localAppData "\BraveSoftware\Brave-Browser\User Data\Local State"
		; v2 gotcha: see IsSkillsVaultUnlocked's comment above - same fix, same reason
		; (PATH_BRAVE_EXE/PATH_CHROME_EXE come from LocalPaths.ahk, not guaranteed present when this file runs standalone).
		if (IsSet(PATH_BRAVE_EXE) && PATH_BRAVE_EXE && FileExist(PATH_BRAVE_EXE)) {
			meta.exePath := PATH_BRAVE_EXE
		} else {
			; Query standard Windows App Paths registry before falling back to bare executable name
			regExe := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe", , "")
			if (!regExe)
				regExe := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe", , "")
			if (regExe && FileExist(regExe)) {
				meta.exePath := regExe
			} else {
				localExe := localAppData "\BraveSoftware\Brave-Browser\Application\brave.exe"
				meta.exePath := FileExist(localExe) ? localExe : "brave.exe"
			}
		}
	} else if (browserName = "Chrome") {
		meta.exeName := "chrome.exe"
		meta.localStatePath := localAppData "\Google\Chrome\User Data\Local State"
		if (IsSet(PATH_CHROME_EXE) && PATH_CHROME_EXE && FileExist(PATH_CHROME_EXE)) {
			meta.exePath := PATH_CHROME_EXE
		} else {
			regExe := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", , "")
			if (!regExe)
				regExe := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", , "")
			if (regExe && FileExist(regExe)) {
				meta.exePath := regExe
			} else {
				localExe := localAppData "\Google\Chrome\Application\chrome.exe"
				meta.exePath := FileExist(localExe) ? localExe : "chrome.exe"
			}
		}
	}
	return meta
}

GetActiveBrowser() {
	global g_LastActiveBrowser, g_LastActiveBrowserTime

	; Direct active window check (immediate response if browser currently has focus)
	if WinActive("ahk_exe brave.exe") {
		g_LastActiveBrowser := "Brave"
		g_LastActiveBrowserTime := A_TickCount
		return "Brave"
	}
	if WinActive("ahk_exe chrome.exe") {
		g_LastActiveBrowser := "Chrome"
		g_LastActiveBrowserTime := A_TickCount
		return "Chrome"
	}

	; If triggered from tray menu or notification area, the tray or taskbar window has focus at this instant.
	; Check if Chrome or Brave was focused recently (within the last 20 seconds) and is still running.
	if (g_LastActiveBrowser != "" && (A_TickCount - g_LastActiveBrowserTime < 20000)) {
		meta := GetBrowserMeta(g_LastActiveBrowser)
		exeName := meta.exeName
		if (exeName && ProcessExist(exeName))
			return g_LastActiveBrowser
	}

	; Fallback: inspect desktop window Z-order (topmost to bottommost)
	; to find the topmost visible, unminimized browser window.
	topBrowser := GetTopBrowserFromZOrder()
	if (topBrowser != "") {
		g_LastActiveBrowser := topBrowser
		g_LastActiveBrowserTime := A_TickCount
		return topBrowser
	}

	return ""
}

GetTopBrowserFromZOrder() {
	hwnd := DllCall("GetTopWindow", "Ptr", 0, "Ptr")
	while (hwnd) {
		if DllCall("IsWindowVisible", "Ptr", hwnd) {
			cls := WinGetClass("ahk_id " hwnd)
			; Ignore shell tray, secondary tray, desktop, task switcher, and context popup menus
			if (cls != "Shell_TrayWnd" && cls != "Shell_SecondaryTrayWnd" && cls != "#32768"
				&& cls != "Progman" && cls != "WorkerW" && cls != "NotifyIconOverflowWindow") {
				minMax := WinGetMinMax("ahk_id " hwnd)
				if (minMax != -1) { ; Ensure window is not minimized
					proc := WinGetProcessName("ahk_id " hwnd)
					if (proc = "brave.exe")
						return "Brave"
					if (proc = "chrome.exe")
						return "Chrome"
					; If an application window with a non-empty title is higher in Z-order,
					; then neither Chrome nor Brave was the frontmost application.
					title := WinGetTitle("ahk_id " hwnd)
					if (title != "" && cls != "Windows.UI.Core.CoreWindow")
						return ""
				}
			}
		}
		hwnd := DllCall("GetWindow", "Ptr", hwnd, "UInt", 2, "Ptr") ; GW_HWNDNEXT = 2
	}
	return ""
}

GetRunningBrowsers() {
	running := []
	if ProcessExist("brave.exe")
		running.Push("Brave")
	if ProcessExist("chrome.exe")
		running.Push("Chrome")
	return running
}

; Narrow "is a Chromium browser active right now" predicate - deliberately does NOT use GetActiveBrowser()'s 20s
; recent-focus cache or Z-order fallback, since several BasicTasks.ahk hotkeys need "literally active this
; instant," not "was recently active" (using GetActiveBrowser() here would broaden when these hotkeys fire
; beyond their original intent).
; Was duplicated inline across half a dozen functions before being pulled out here.
IsChromiumBrowserActive() {
	return WinActive("ahk_exe brave.exe") || WinActive("ahk_exe chrome.exe")
}

; Shared "run action in the active Chromium browser, or activate one and then run it" pattern - was duplicated
; inline (with Brave preferred over Chrome) across several BasicTasks.ahk hotkeys.
; sleepMs matches each call site's own prior behavior exactly (0 by default, since most call sites never
; actually slept between WinActivate and the action - only pass a nonzero value where live code already did).
; Returns true if a browser was found (active or activated) and action ran, false if neither is running.
ActivateChromiumBrowserOrRun(action, sleepMs := 0) {
	if IsChromiumBrowserActive() {
		action.Call()
		return true
	} else if WinExist("ahk_exe brave.exe") {
		WinActivate("ahk_exe brave.exe")
		if (sleepMs)
			Sleep(sleepMs)
		action.Call()
		return true
	} else if WinExist("ahk_exe chrome.exe") {
		WinActivate("ahk_exe chrome.exe")
		if (sleepMs)
			Sleep(sleepMs)
		action.Call()
		return true
	}
	return false
}

GetTargetBrowsersForDRM() {
	active := GetActiveBrowser()
	if (active != "")
		return [active]

	return []
}

CloseBrowserGracefully(browserName, timeoutMs := 3000) {
	meta := GetBrowserMeta(browserName)
	exeName := meta.exeName
	if (!exeName)
		return false

	if (!ProcessExist(exeName))
		return true ; Already not running

	; Send WM_CLOSE to all top-level windows of this browser to flush session tabs
	idList := WinGetList("ahk_exe " exeName)
	for this_id in idList
		WinClose("ahk_id " this_id)

	timeoutSec := Ceil(timeoutMs / 1000)
	WinWaitClose("ahk_exe " exeName, , timeoutSec)

	; Terminate lingering background tray watcher processes to release Local State file locks
	if (ProcessExist(exeName)) {
		try RunWait('taskkill /IM ' exeName, , "Hide")
		Loop 15 {
			if (!ProcessExist(exeName))
				break
			Sleep(100)
		}
		; Force terminate if still lingering to guarantee file lock release
		if (ProcessExist(exeName)) {
			try RunWait('taskkill /F /IM ' exeName, , "Hide")
			Sleep(300)
		}
	}
	Sleep(200) ; Settle delay to ensure OS releases file handles on Local State
	return true
}

GetBrowserHardwareAcceleration(browserName) {
	meta := GetBrowserMeta(browserName)
	localStatePath := meta.localStatePath
	if (!localStatePath || !FileExist(localStatePath))
		return true

	try content := FileRead(localStatePath, "UTF-8")
	catch
		return true
	if (!content)
		return true

	if RegExMatch(content, '"hardware_acceleration_mode"\s*:\s*\{\s*"enabled"\s*:\s*false\s*\}')
		return false

	return true
}

SetBrowserHardwareAcceleration(browserName, enable) {
	meta := GetBrowserMeta(browserName)
	localStatePath := meta.localStatePath
	if (!localStatePath || !FileExist(localStatePath))
		return false

	try content := FileRead(localStatePath, "UTF-8")
	catch
		return false
	if (!content)
		return false

	targetEnabled := enable ? "true" : "false"

	; 1. Update or insert hardware_acceleration_mode: {"enabled": bool}
	if RegExMatch(content, '"hardware_acceleration_mode"\s*:\s*\{\s*"enabled"\s*:\s*(true|false)\s*\}') {
		content := RegExReplace(content, '"hardware_acceleration_mode"\s*:\s*\{\s*"enabled"\s*:\s*(true|false)\s*\}', '"hardware_acceleration_mode":{"enabled":' targetEnabled '}')
	} else {
		content := RegExReplace(content, "^\{", '{"hardware_acceleration_mode":{"enabled":' targetEnabled '},')
	}

	; 2. Update or insert hardware_acceleration_mode_previous
	if RegExMatch(content, '"hardware_acceleration_mode_previous"\s*:\s*(true|false)') {
		content := RegExReplace(content, '"hardware_acceleration_mode_previous"\s*:\s*(true|false)', '"hardware_acceleration_mode_previous":' targetEnabled)
	} else {
		content := RegExReplace(content, "^\{", '{"hardware_acceleration_mode_previous":' targetEnabled ',')
	}

	tempPath := localStatePath ".tmp"
	try FileDelete(tempPath)
	FileAppend(content, tempPath, "UTF-8")
	if FileExist(tempPath) {
		FileMove(tempPath, localStatePath, 1)
		return true
	}
	return false
}

LaunchBrowserInstance(browserName, args := "") {
	meta := GetBrowserMeta(browserName)
	exePath := meta.exePath
	if (!exePath || !FileExist(exePath))
		return false

	cmd := '"' exePath '"' (args != "" ? (" " args) : "")
	Run(cmd)
	return true
}

; =============================================================================
; Simple Sticky Notes (ssn.exe) Dual Deterministic Layout Engine
; =============================================================================
; Solves the multi-resolution desktop layout scrambling issue between:
; - Host Laptop (DISPLAY1): 1920x1080 @ 125% DPI scale = 1536 x 864 logical DIP workspace
; - Tablet (DISPLAY4):     2560x1600 @ 175% DPI scale = 1463 x 914 logical DIP workspace
;
; The actual coordinate math lives in AllScripts/PowerShell/apply_ssn_layout.ps1 (untouched by this migration,
; PowerShell isn't AHK) - these are thin wrappers only.

ApplyLaptopStickyNotesLayout(delayMs := 0) {
	psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
	return RunSilentPowerShell(psScript, "-Mode Laptop -DelayMs " delayMs)
}

ApplyTabletStickyNotesLayout(delayMs := 0) {
	psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
	return RunSilentPowerShell(psScript, "-Mode Tablet -DelayMs " delayMs)
}

AutoApplyStickyNotesLayout(delayMs := 0) {
	psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
	return RunSilentPowerShell(psScript, "-Mode Auto -DelayMs " delayMs)
}

; Backward compatibility shims
SaveSimpleStickyNotesPositions() {
	; No-op: deterministic profiles eliminate fragile dynamic snapshotting
	return true
}

RestoreSimpleStickyNotesPositions(delayMs := 0) {
	; Fallback redirection to deterministic laptop profile
	return ApplyLaptopStickyNotesLayout(delayMs)
}


; -----------------------------------------------------------------------------
; CORE AUDIO MICROPHONE HELPERS: Windows WASAPI endpoint volume controls
; -----------------------------------------------------------------------------
; Uses Windows Core Audio COM interfaces directly via Win32 DllCall:
; 1. IMMDeviceEnumerator (CLSID {BCDE0395-E52F-467C-8E3D-C4579291692E}, IID {A95664D2-9614-4F35-A746-DE8DB63617E6})
; 2. IAudioEndpointVolume (IID {5CDF2C82-841E-4546-9722-0CF74078229A})
;
; v2: only the buffer-creation (VarSetCapacity -> Buffer) and COM-creation (ComObjCreate -> ComObject) calls change.
; The vtable-offset arithmetic itself (N*A_PtrSize) is Win32 interface layout, unrelated to the AHK language version,
; and is deliberately left untouched below - do not "simplify" or re-derive these offsets, they are correct as-is.
;
; Why this approach:
; - Native in-process COM call (<5ms execution time, zero process spawning overhead).
; - Bypasses legacy winmm mixer quirks and eliminates any need for NirCmd or PowerToys.
; - Simultaneously targets both eConsole (0) and eCommunications (2) capture endpoints
;   to ensure meetings in Zoom, Teams, Discord, and browsers are all muted together.
; - Reuses ShowBottomRightBadge() for DPI-scaled on-screen HUD feedback.

GetMicrophoneMute() {
	static CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
	static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
	static IID_IAudioEndpointVolume := "{5CDF2C82-841E-4546-9722-0CF74078229A}"

	enumerator := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
	if (!enumerator)
		return -1

	device := 0
	; Try eConsole (0) first, fallback to eCommunications (2)
	; v2: NumGet's Type parameter is mandatory now (no implicit "Ptr" default like v1 had) - confirmed empirically,
	; omitting it here causes a load-time hang (not a clean error) rather than throwing.
	; Every vtable-offset NumGet below needs an explicit "Ptr" type: it's always reading a pointer-sized vtable
	; slot or function pointer.
	; v2: `enumerator+0` throws "Expected a Number but got a ComValue" - ComObject() returns a real ComValue
	; wrapper, which (unlike v1) does not auto-coerce to a number via arithmetic.
	; Use its .Ptr property instead to get the raw interface pointer for NumGet's vtable walk. (Passing
	; `enumerator` directly as a DllCall "Ptr" argument below is unaffected - v2 DllCall already reads
	; .Ptr automatically for that.)
	hr := DllCall(NumGet(NumGet(enumerator.Ptr, "Ptr") + 4*A_PtrSize, "Ptr"), "Ptr", enumerator, "Int", 1, "Int", 0, "Ptr*", &device)
	if (hr != 0 || !device)
		hr := DllCall(NumGet(NumGet(enumerator.Ptr, "Ptr") + 4*A_PtrSize, "Ptr"), "Ptr", enumerator, "Int", 1, "Int", 2, "Ptr*", &device)
	; v2: `enumerator` is now a real ComValue wrapper (see above), not a raw pointer - ObjRelease requires a raw
	; pointer and throws "Parameter #1 of ObjRelease is invalid" on a ComValue (confirmed live).
	; The wrapper manages its own COM reference count and releases it automatically when garbage-collected, so
	; the explicit release is no longer needed at all - simply drop it (unlike device/deviceConsole/deviceComm/
	; endpointVolume/endpointConsole/endpointComm below, which stay correct: those are genuine raw pointers
	; from "Ptr*" DllCall outputs, not wrapper objects, so their ObjRelease calls are unchanged).

	if (hr != 0 || !device)
		return -1

	iidVolume := Buffer(16, 0)
	DllCall("ole32\CLSIDFromString", "WStr", IID_IAudioEndpointVolume, "Ptr", iidVolume)

	endpointVolume := 0
	hr := DllCall(NumGet(NumGet(device+0, "Ptr") + 3*A_PtrSize, "Ptr"), "Ptr", device, "Ptr", iidVolume, "UInt", 7, "Ptr", 0, "Ptr*", &endpointVolume)
	ObjRelease(device)

	if (hr != 0 || !endpointVolume)
		return -1

	isMuted := 0
	hr := DllCall(NumGet(NumGet(endpointVolume+0, "Ptr") + 15*A_PtrSize, "Ptr"), "Ptr", endpointVolume, "Int*", &isMuted)
	ObjRelease(endpointVolume)

	return (hr == 0) ? isMuted : -1
}

SetMicrophoneMute(bMute, showBadge := true, displayMs := 1200) {
	static CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
	static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
	static IID_IAudioEndpointVolume := "{5CDF2C82-841E-4546-9722-0CF74078229A}"

	enumerator := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
	if (!enumerator) {
		if (showBadge)
			ShowBottomRightBadge("Microphone Enumerator Error", "7A3B00", displayMs)
		return -1
	}

	iidVolume := Buffer(16, 0)
	DllCall("ole32\CLSIDFromString", "WStr", IID_IAudioEndpointVolume, "Ptr", iidVolume)

	deviceConsole := 0
	deviceComm := 0
	endpointConsole := 0
	endpointComm := 0

	; v2: NumGet's Type parameter is mandatory (see GetMicrophoneMute's comment above) - "Ptr" added to every
	; vtable-offset NumGet call below, same fix, same reason.
	; `enumerator.Ptr` (not `enumerator+0`) - see the matching comment in GetMicrophoneMute above for why.
	hrConsole := DllCall(NumGet(NumGet(enumerator.Ptr, "Ptr") + 4*A_PtrSize, "Ptr"), "Ptr", enumerator, "Int", 1, "Int", 0, "Ptr*", &deviceConsole)
	hrComm := DllCall(NumGet(NumGet(enumerator.Ptr, "Ptr") + 4*A_PtrSize, "Ptr"), "Ptr", enumerator, "Int", 1, "Int", 2, "Ptr*", &deviceComm)
	; v2: `enumerator` is a ComValue wrapper now, not a raw pointer - see the matching comment in GetMicrophoneMute above.
	; ObjRelease on it throws; the wrapper releases itself automatically.

	if (hrConsole != 0 && hrComm != 0) {
		if (showBadge)
			ShowBottomRightBadge("Microphone Not Found", "7A3B00", displayMs)
		return -1
	}

	if (hrConsole == 0 && deviceConsole) {
		DllCall(NumGet(NumGet(deviceConsole+0, "Ptr") + 3*A_PtrSize, "Ptr"), "Ptr", deviceConsole, "Ptr", iidVolume, "UInt", 7, "Ptr", 0, "Ptr*", &endpointConsole)
		ObjRelease(deviceConsole)
	}

	if (hrComm == 0 && deviceComm) {
		DllCall(NumGet(NumGet(deviceComm+0, "Ptr") + 3*A_PtrSize, "Ptr"), "Ptr", deviceComm, "Ptr", iidVolume, "UInt", 7, "Ptr", 0, "Ptr*", &endpointComm)
		ObjRelease(deviceComm)
	}

	successCount := 0
	if (endpointConsole) {
		hr := DllCall(NumGet(NumGet(endpointConsole+0, "Ptr") + 14*A_PtrSize, "Ptr"), "Ptr", endpointConsole, "Int", bMute, "Ptr", 0)
		if (hr == 0)
			successCount++
		ObjRelease(endpointConsole)
	}

	if (endpointComm) {
		hr := DllCall(NumGet(NumGet(endpointComm+0, "Ptr") + 14*A_PtrSize, "Ptr"), "Ptr", endpointComm, "Int", bMute, "Ptr", 0)
		if (hr == 0)
			successCount++
		ObjRelease(endpointComm)
	}

	if (successCount == 0) {
		if (showBadge)
			ShowBottomRightBadge("Microphone Mute Failed", "7A3B00", displayMs)
		return -1
	}

	UpdateMicrophoneTrayIcon(bMute)

	if (showBadge) {
		if (bMute)
			ShowBottomRightBadge("Microphone Muted", "8B1A1A", displayMs)
		else
			ShowBottomRightBadge("Microphone Unmuted", "1A6E3C", displayMs)
	}

	return bMute
}

ToggleMicrophoneMute(showBadge := true, displayMs := 1200) {
	currMute := GetMicrophoneMute()
	if (currMute = -1) {
		newMute := 1
	} else {
		newMute := currMute ? 0 : 1
	}
	return SetMicrophoneMute(newMute, showBadge, displayMs)
}

; v2: Menu,Tray,Icon (bare, un-hide) / Menu,Tray,NoIcon (hide) map to the writable A_IconHidden boolean - the port
; dropped this entirely, so the icon bitmap got set but this dedicated tray icon never actually became visible.
; Menu,Tray,Tip maps to A_IconTip (persistent hover text), not TrayTip() (a one-shot balloon notification) -
; found live, confirmed by the working sibling pattern in SunshineDisplayWatchdog.ahk's UpdateTabletHibernateTrayIcon().
; See Migration-Notes.md 18.32.
UpdateMicrophoneTrayIcon(isMuted) {
	if (isMuted = 1) {
		iconPath := A_ScriptDir "\..\AutoHotkey Companion Files\mic_muted.ico"
		if (!FileExist(iconPath))
			iconPath := A_ScriptDir "\AutoHotkey Companion Files\mic_muted.ico"
		if (FileExist(iconPath))
			TraySetIcon(iconPath)
		A_IconTip := "Microphone Muted (Click or Win+Ctrl+Alt+M to unmute)"
		A_IconHidden := false
	} else {
		TraySetIcon()
		A_IconHidden := true
	}
}
