; =============================================================================
; SHARED HELPERS - functions used by more than one script in this repo.
;
; #Include this file (with an explicit %A_ScriptDir%\ prefix, never a bare filename - see ARCHITECTURE.md for why) from any script that needs one of these.
; Every function below is self-contained and takes its inputs as parameters rather than reaching for a specific script's own globals, so it behaves identically no matter which script includes it.
; Full design rationale (why these moved here, why ByRef + dynamic-label dispatch instead of Func()/.Bind(), the debounce pattern as a reusable template) lives in ARCHITECTURE.md at the repo root - read that before adding a new feature that needs any of this.
;
; This file must contain ONLY function/label definitions, plus the single #Persistent below - no other top-level executable statements, no #Requires/#SingleInstance.
; AHK pastes an #Include'd file in-place, so top-level code here would run as part of whichever script's auto-execute section happens to include it first.
; Every function below avoids that entirely by using explicit `global` declarations for anything it needs from the caller's namespace.
; #Persistent is the one deliberate exception: it's a pure lifecycle flag, not executable code, so its effect doesn't depend on include order.
; It's a no-op for every current #Include'ing script (BasicTasks/BackgroundAutomations/Ext4SsdManager all already stay alive via their own hotkeys/loops).
; It exists solely so this file can also run standalone as its own StartupScript.ahk tray entry, for quick Edit access.
; =============================================================================
#Persistent


; -----------------------------------------------------------------------------
; NAMED MUTEX - cross-process mutual exclusion
; -----------------------------------------------------------------------------
; Kernel-object mutex, not a file-existence convention: a plain lock file can be left permanently stuck if the owning process crashes mid-critical-section, but a named mutex cannot - Windows auto-releases it as "abandoned" and the next waiter picks it up cleanly.
; Pass a distinct mutexName per logical resource being guarded (e.g. "SkillsVaultLock_AHK_v1") - every caller sharing that exact string, across however many separate processes, contends on the same kernel object.
; Plain names (no "Global\" prefix) are correct as long as every consumer runs in the same interactive user session, which is the case for every script in this repo - no elevated privilege needed.
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
; Each feature keeps owning its own state as plain globals (a pending-value variable, a busy flag, an interval) and passes them in by name/ByRef - nothing here stores any feature-specific state itself.
; See ARCHITECTURE.md for the full worked example of wiring these into a new debounced hotkey.
;
; timerLabel is always a literal string naming a commit LABEL (not a function), dispatched dynamically via AHK's documented %var% SetTimer target support ("the name stored in the variable is used as the target").
; This is the same dynamic-dispatch idiom this codebase already uses for tray-menu Gosubs (HandleRemoteTrayMenuTrigger below).

; (Re)arms a one-shot timer at timerLabel, delayMs from now.
; A negative SetTimer period, per AHK's documented "Reset" behavior, cancels any already-pending countdown for that same target and starts a fresh one rather than stacking a second pending firing.
; So calling this repeatedly for the same label keeps pushing the firing back out by delayMs, and only a call that goes delayMs milliseconds without a follow-up actually fires.
DebounceArmTimer(timerLabel, delayMs) {
    if (IsLabel(timerLabel))
        SetTimer, %timerLabel%, % -delayMs
}

; First line of a commit label.
; AHK's own timer engine already guarantees at most one concurrently-running instance of a given timer's target, so busyFlag reading true here should never actually happen in practice - defense in depth only, in case something other than the timer ever Gosubs the label directly.
; Returns true if the caller should proceed with the real work; false if the caller should return immediately (the settle timer has already been re-armed on its behalf).
DebounceTryBeginCommit(ByRef busyFlag, timerLabel, delayMs) {
    if (busyFlag) {
        DebounceArmTimer(timerLabel, delayMs)
        return false
    }
    busyFlag := true
    return true
}

; Last step of a commit label, called once the real work is fully done.
; snapshotValue is whatever the caller read from pendingVar BEFORE doing that work (before any blocking call) - comparing the LIVE pendingVar against that snapshot is how a press that landed WHILE the commit was running gets detected.
; Clears busyFlag first so a re-armed timer firing immediately after this returns never sees a stale true.
DebounceEndCommit(ByRef pendingVar, snapshotValue, ByRef busyFlag, timerLabel, delayMs) {
    busyFlag := false
    if (pendingVar != snapshotValue)
        DebounceArmTimer(timerLabel, delayMs)
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
; 6. HwndhTextCtl, not a v-variable: a `v`-prefixed Gui output variable on an Add command executed from INSIDE a function (as opposed to top-level auto-execute code) hangs indefinitely on AHK v1.1.37.02, while the exact same control created with an `Hwnd` option instead works instantly. The static hTextCtl holds the control's HWND for later GuiControl/Show calls, which accept a bare HWND value as a ControlID just as readily as a v-variable name.
; 7. Explicit WinSet Redraw forces transparent text controls to repaint immediately on color changes - without it, the old color can linger behind the control until some unrelated repaint event happens to trigger it.
ShowBottomRightBadge(msg, bgColorHex, displayMs := 0) {
    static created := false, hGui := 0, hTextCtl := 0

    SetTimer, RemoveBottomRightBadge, Off

    if (!created) {
        Gui, BottomRightBadge: -DPIScale +AlwaysOnTop +ToolWindow -Caption +HwndhGui +LastFound
        Gui, BottomRightBadge: Margin, 0, 0
        Gui, BottomRightBadge: Font, s12 Bold cFFFFFF, Segoe UI
        ; HwndhTextCtl, not a v-variable: a `v`-prefixed Gui output variable on an Add command executed from INSIDE a function (as opposed to top-level auto-execute code) hangs indefinitely on AHK v1.1.37.02, while the exact same control created with an `Hwnd` option instead works instantly - see the function header above for the full explanation.
        ; Start with -Wrap so text stays strictly inline on a single line
        Gui, BottomRightBadge: Add, Text, HwndhTextCtl Center -Wrap BackgroundTrans, % msg
        created := true
    } else {
        Gui, BottomRightBadge: Font, s12 Bold cFFFFFF, Segoe UI
        GuiControl, BottomRightBadge: Font, %hTextCtl%
    }

    ; 1. Resolve current active monitor work area (handles Laptop vs Tablet switches)
    monIndex := GetToastTargetMonitor()
    SysGet, wa, MonitorWorkArea, %monIndex%
    monW := waRight - waLeft
    monH := waBottom - waTop
    if (monW <= 0 || monH <= 0) {
        waLeft := 0, waTop := 0, waRight := A_ScreenWidth, waBottom := A_ScreenHeight
        monW := A_ScreenWidth, monH := A_ScreenHeight
    }

    ; 2. Measure text dimensions via GDI DrawText
    hDC := DllCall("GetDC", "ptr", hGui, "ptr")
    SendMessage, 0x31, 0, 0,, ahk_id %hTextCtl% ; WM_GETFONT
    hFont := ErrorLevel
    hOldFont := DllCall("SelectObject", "ptr", hDC, "ptr", hFont, "ptr")

    ; Measure single-line extent first (DT_CALCRECT | DT_SINGLELINE = 0x420)
    VarSetCapacity(RECT_SINGLE, 16, 0)
    DllCall("DrawTextW", "ptr", hDC, "wstr", msg, "int", -1, "ptr", &RECT_SINGLE, "uint", 0x420)
    measuredW_single := NumGet(RECT_SINGLE, 8, "int") - NumGet(RECT_SINGLE, 0, "int")
    measuredH_single := NumGet(RECT_SINGLE, 12, "int") - NumGet(RECT_SINGLE, 4, "int")

    ; Max inline single-line width: generous 60% of monitor width (e.g. 1150px on 1080p, 1530px on 2560x1600)
    maxInlineBadgeW := Floor(monW * 0.60)
    if (maxInlineBadgeW < 450)
        maxInlineBadgeW := 450

    ; Scale padding, height, and corner radius proportionally with measured single-line text height
    padX := Max(26, Floor(measuredH_single * 1.15))
    padY := Max(13, Floor(measuredH_single * 0.45))
    badgeH := Max(50, measuredH_single + (padY * 2))
    cornerR := Max(11, Floor(badgeH * 0.22))

    if (measuredW_single + (padX * 2) <= maxInlineBadgeW) {
        ; --- PREFERRED: SLEEK SINGLE-LINE INLINE PILL ---
        GuiControl, BottomRightBadge: -Wrap, %hTextCtl%
        badgeW := measuredW_single + (padX * 2)
        minBadgeW := Max(220, Floor(monW * 0.12))
        if (badgeW < minBadgeW)
            badgeW := minBadgeW
        textW := measuredW_single + 10 ; extra breathing room prevents subpixel word wrap
        textH := measuredH_single
        textX := Floor((badgeW - textW) / 2)
        textY := Floor((badgeH - textH) / 2)
    } else {
        ; --- FALLBACK: MULTI-LINE WORD-WRAPPED BOX (only for extreme strings) ---
        GuiControl, BottomRightBadge: +Wrap, %hTextCtl%
        maxWrapTextW := maxInlineBadgeW - (padX * 2)
        VarSetCapacity(RECT_WRAP, 16, 0)
        NumPut(maxWrapTextW, RECT_WRAP, 8, "int")
        DllCall("DrawTextW", "ptr", hDC, "wstr", msg, "int", -1, "ptr", &RECT_WRAP, "uint", 0x410)
        measuredW_wrap := NumGet(RECT_WRAP, 8, "int") - NumGet(RECT_WRAP, 0, "int")
        measuredH_wrap := NumGet(RECT_WRAP, 12, "int") - NumGet(RECT_WRAP, 4, "int")

        badgeW := measuredW_wrap + (padX * 2)
        badgeH := measuredH_wrap + (padY * 2)
        cornerR := Max(10, Floor(badgeH * 0.15))
        textW := measuredW_wrap + 4
        textH := measuredH_wrap
        textX := padX
        textY := padY
    }

    DllCall("SelectObject", "ptr", hDC, "ptr", hOldFont)
    DllCall("ReleaseDC", "ptr", hGui, "ptr", hDC)

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
    Gui, BottomRightBadge: Color, %bgColorHex%
    GuiControl, BottomRightBadge:, %hTextCtl%, % msg
    GuiControl, BottomRightBadge: Move, %hTextCtl%, x%textX% y%textY% w%textW% h%textH%

    ; Show GUI with exact physical coordinates (-DPIScale guarantees 1:1 match)
    Gui, BottomRightBadge: Show, x%finalX% y%finalY% w%badgeW% h%badgeH% NA

    ; Smooth rounded corners for modern Windows toast finish
    hRgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", badgeW, "int", badgeH, "int", cornerR, "int", cornerR, "ptr")
    DllCall("SetWindowRgn", "ptr", hGui, "ptr", hRgn, "int", true)

    ; Force immediate redraw to prevent backdrop color artifacting
    Gui, BottomRightBadge: +LastFound
    WinSet, Redraw

    if (displayMs > 0)
        SetTimer, RemoveBottomRightBadge, % -displayMs
}

GetToastTargetMonitor() {
    ; Determine which monitor the user is actively viewing.
    ; Check cursor position first as it tracks active user focus across monitors.
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    SysGet, monCount, MonitorCount
    Loop, %monCount% {
        SysGet, m, Monitor, %A_Index%
        if (mx >= mLeft && mx <= mRight && my >= mTop && my <= mBottom)
            return A_Index
    }
    ; Fallback to Primary monitor
    SysGet, primaryMon, MonitorPrimary
    return primaryMon ? primaryMon : 1
}

; Hides the badge immediately, without waiting for any auto-dismiss timer - the window itself stays alive (Hide, not Destroy), so the next ShowBottomRightBadge call is an instant in-place update, not a rebuild.
; Use this (rather than showing a replacement badge) once real work following an "applying" badge has finished and there is nothing new worth telling the user - see CommitPersonalSkillsLock in BasicTasks.ahk for the motivating case.
HideBottomRightBadge() {
    SetTimer, RemoveBottomRightBadge, Off
    Gui, BottomRightBadge: Hide
}

; A FUNCTION, not a label - deliberate.
; This file is #Include'd early (before any hotkey definition) in every consumer script; AHK's auto-execute section ends only at the first hotkey/hotstring label, Return, or Exit encountered during a top-to-bottom load-time scan, and that scan SKIPS OVER function bodies entirely but does NOT skip over a plain label.
; If this were written as "RemoveBottomRightBadge:" + code + "return" instead, that Return would be reached by the auto-execute scan (after falling through all the preceding function definitions, which are correctly skipped) and would end auto-execute right there, before the including script's OWN remaining top-level initialization code ever runs - not a theoretical concern, this is exactly what a plain label here would do.
; SetTimer targeting a bare function name (zero mandatory parameters) works exactly like targeting a label - see AHK v1.1's own SetTimer docs.
;
; Hides rather than destroys, same reasoning as HideBottomRightBadge above - this is just the timer-driven path to the same end state.
RemoveBottomRightBadge() {
    Gui, BottomRightBadge: Hide
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
; DRM STREAMING STATUS BADGE - color-coded toast over ShowBottomRightBadge
; -----------------------------------------------------------------------------
ShowDRMStatusBadge(msg) {
    if InStr(msg, "[ACTIVE]")
        bgColor := "1A6E3C" ; Deep green for ACTIVE
    else
        bgColor := "3A3D40" ; Dark slate grey for OFF

    ShowBottomRightBadge(msg, bgColor, 3000)
}


; -----------------------------------------------------------------------------
; TIMED TOOLTIP - native ToolTip, auto-dismissed after N ms
; -----------------------------------------------------------------------------
; Collapses the repeated inline "ToolTip -> SetTimer -Nms -> Label: ToolTip \ return" pattern that previously appeared independently at several call sites across BasicTasks.ahk and BackgroundAutomations.ahk (VS Code zoom HUD, SSD mount/unmount feedback).
; For anything wanting color/positioning control beyond native ToolTip's default near-cursor placement, use ShowBottomRightBadge above instead.
ShowTimedToolTip(msg, displayMs) {
    ToolTip, % msg
    SetTimer, RemoveTimedToolTip, % -displayMs
}

; A function, not a label - same reasoning as RemoveBottomRightBadge() above.
RemoveTimedToolTip() {
    ToolTip
}


; -----------------------------------------------------------------------------
; CONNECTED DISPLAY DETECTION - hardware-level check for external displays
; -----------------------------------------------------------------------------
; Checks if a second display (physical monitor or HDMI dummy plug) is attached to any graphics adapter, even when Windows has turned off its desktop output in PC Screen Only mode (where SM_CMONITORS / SysGet MonitorCount reports 1).
HasSecondDisplayConnected() {
    ; If virtual desktop already has 2 or more active monitors (e.g. extended desktop), a second display is definitely active.
    SysGet, monCount, MonitorCount
    if (monCount >= 2)
        return true

    ; When in single-monitor mode (PC Screen Only or Second Screen Only), query attached hardware devices via EnumDisplayDevices to find unique attached monitors.
    uniqueMonitors := {}
    devNum := 0
    VarSetCapacity(dispDev, 840, 0)
    NumPut(840, dispDev, 0, "UInt")

    while DllCall("EnumDisplayDevices", "Ptr", 0, "UInt", devNum, "Ptr", &dispDev, "UInt", 0) {
        ; Skip virtual mirroring drivers (DISPLAY_DEVICE_MIRRORING_DRIVER = 0x00000008)
        devFlags := NumGet(dispDev, 324, "UInt")
        if (devFlags & 8) {
            devNum++
            VarSetCapacity(dispDev, 840, 0)
            NumPut(840, dispDev, 0, "UInt")
            continue
        }

        devName := StrGet(&dispDev + 4, 32)
        monNum := 0
        VarSetCapacity(monDev, 840, 0)
        NumPut(840, monDev, 0, "UInt")

        while DllCall("EnumDisplayDevices", "Str", devName, "UInt", monNum, "Ptr", &monDev, "UInt", 0) {
            monFlags := NumGet(monDev, 324, "UInt")
            monId := StrGet(&monDev + 328, 128)
            ; 0x2 = DISPLAY_DEVICE_ATTACHED
            if ((monFlags & 2) && monId != "") {
                uniqueMonitors[monId] := true
            }
            monNum++
            VarSetCapacity(monDev, 840, 0)
            NumPut(840, monDev, 0, "UInt")
        }
        devNum++
        VarSetCapacity(dispDev, 840, 0)
        NumPut(840, dispDev, 0, "UInt")
    }

    count := 0
    for id in uniqueMonitors
        count++

    return (count >= 2)
}

; Checks if an external display (e.g. HDMI dummy plug on DISPLAY4) is active on the virtual desktop,
; either alone (Second Screen Only / Tablet Mode) or combined with the internal panel (Duplicate or Extend).
IsExternalDisplayActive() {
    ; Check 1: If internal laptop panel (DISPLAY1) is not active at all, an external display is active alone.
    SysGet, monCount, MonitorCount
    hasInternal := false
    Loop, %monCount% {
        SysGet, mName, MonitorName, %A_Index%
        if InStr(mName, "DISPLAY1") {
            hasInternal := true
            break
        }
    }
    if (!hasInternal)
        return true

    ; Check 2: If internal panel is active, check if any external graphics adapter (DISPLAY4+) is attached to the desktop (0x1).
    devNum := 0
    VarSetCapacity(dispDev, 840, 0)
    NumPut(840, dispDev, 0, "UInt")
    while DllCall("EnumDisplayDevices", "Ptr", 0, "UInt", devNum, "Ptr", &dispDev, "UInt", 0) {
        devName := StrGet(&dispDev + 4, 32)
        devFlags := NumGet(dispDev, 324, "UInt")
        if (!InStr(devName, "DISPLAY1") && (devFlags & 1)) {
            return true
        }
        devNum++
        VarSetCapacity(dispDev, 840, 0)
        NumPut(840, dispDev, 0, "UInt")
    }
    return false
}


; -----------------------------------------------------------------------------
; TRAY MENU MANIFEST - publish/dispatch for StartupScript.ahk's master submenu
; -----------------------------------------------------------------------------
; Call PublishTrayMenuManifest once from each script's auto-execute section right after its native tray setup, passing label/Gosub pairs as a nested array:
;   PublishTrayMenuManifest([ ["Display Label 1", "TrayLabel1"]
;                           , ["-"]
;                           , ["Display Label 2", "TrayLabel2"] ])
;
; Architecture:
; 1. Writes %A_Temp%\ahk_traymenu_<ScriptName>.txt (one file per script, keyed by that script's own filename).
; 2. Supports ["-"] entries (serialized as "-|") to render native Win32 horizontal separator bars in StartupScript's mirrored submenu.
; 3. Registers this shared HandleRemoteTrayMenuTrigger as the handler for the system-wide registered window message "AHK_RemoteTrayMenuTrigger_v1".
; 4. StartupScript.ahk reads these manifest files to mirror every script's custom tray items into one master submenu, and PostMessages this registered ID with wParam = the manifest's 1-based line number when a mirrored item is clicked.
; 5. Each process reads only its own manifest file (via its own A_ScriptFullPath), so sharing this function across multiple processes is safe without collision.
PublishTrayMenuManifest(itemsArray) {
    SplitPath, A_ScriptFullPath,,,, scriptNameNoExt
    manifestPath := A_Temp "\ahk_traymenu_" scriptNameNoExt ".txt"
    FileDelete, %manifestPath%
    for idx, item in itemsArray
    {
        if (!IsObject(item) && (item = "-" || item = ""))
            FileAppend, -|`n, %manifestPath%
        else if (item[1] = "-" || item[1] = "")
            FileAppend, -|`n, %manifestPath%
        else
            FileAppend, % item[1] . "|" . item[2] . "`n", %manifestPath%
    }
    OnMessage(DllCall("RegisterWindowMessage", "str", "AHK_RemoteTrayMenuTrigger_v1"), "HandleRemoteTrayMenuTrigger")
}

HandleRemoteTrayMenuTrigger(wParam, lParam) {
    SplitPath, A_ScriptFullPath,,,, scriptNameNoExt
    manifestPath := A_Temp "\ahk_traymenu_" scriptNameNoExt ".txt"
    FileReadLine, line, %manifestPath%, %wParam%
    if ErrorLevel
        return
    StringSplit, parts, line, |
    ; IsLabel guard: a manifest can outlive the label it names (e.g. mid-migration, before a stale %A_Temp%\ahk_traymenu_<script>.txt is deleted).
    ; Without this, a dynamic Gosub to a nonexistent label raises a modal error dialog in this process instead of a silent no-op.
    if (parts0 >= 2 && parts2 != "" && IsLabel(parts2))
        Gosub, %parts2%
}


; -----------------------------------------------------------------------------
; RUN SILENT POWERSHELL
; -----------------------------------------------------------------------------
; Launches a PowerShell script with zero visible window (no conhost flash, no focus theft).
; Prefers run_silent.exe (true CREATE_NO_WINDOW) when present next to the calling script; falls back to WScript.Shell.Run's hidden-window flag, then to a plain hidden Run as a last resort if COM creation itself fails.
RunSilentPowerShell(scriptPath, args := "") {
    runSilentExe := A_ScriptDir "\PowerShell\run_silent.exe"
    if FileExist(runSilentExe) {
        cmd := """" runSilentExe """ powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ scriptPath """" (args != "" ? " " args : "")
        Run, %cmd%,, Hide
        return true
    }
    cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ scriptPath """" (args != "" ? " " args : "")
    try {
        shell := ComObjCreate("WScript.Shell")
        shell.Run(cmd, 0, false)
        return true
    } catch {
        Run, %cmd%,, Hide
        return false
    }
}

; MountExt4Ssd/UnmountExt4Ssd now live in AllScripts/Ext4SsdManager.ahk - the ext4 SSD feature is single-owner (that one script), not shared across multiple consumers, so it no longer belongs in this shared-helpers file.


; -----------------------------------------------------------------------------
; CHROMIUM BROWSER OPERATIONS (Brave & Chrome)
; -----------------------------------------------------------------------------
; Manages graceful close, atomic Local State JSON edits, and zero-GPU launch.

GetBrowserMeta(browserName) {
    global PATH_BRAVE_EXE, PATH_CHROME_EXE
    EnvGet, localAppData, LOCALAPPDATA
    meta := {}
    meta.name := browserName

    if (browserName = "Brave") {
        meta.exeName := "brave.exe"
        meta.localStatePath := localAppData "\BraveSoftware\Brave-Browser\User Data\Local State"
        if (PATH_BRAVE_EXE && FileExist(PATH_BRAVE_EXE)) {
            meta.exePath := PATH_BRAVE_EXE
        } else {
            ; Query standard Windows App Paths registry before falling back to bare executable name
            RegRead, regExe, HKLM, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe
            if (!regExe)
                RegRead, regExe, HKCU, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe
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
        if (PATH_CHROME_EXE && FileExist(PATH_CHROME_EXE)) {
            meta.exePath := PATH_CHROME_EXE
        } else {
            ; Query standard Windows App Paths registry before falling back to bare executable name
            RegRead, regExe, HKLM, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe
            if (!regExe)
                RegRead, regExe, HKCU, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe
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
    if WinActive("ahk_exe brave.exe")
        return "Brave"
    if WinActive("ahk_exe chrome.exe")
        return "Chrome"
    return ""
}

GetRunningBrowsers() {
    running := []
    Process, Exist, brave.exe
    if (ErrorLevel)
        running.Push("Brave")
    Process, Exist, chrome.exe
    if (ErrorLevel)
        running.Push("Chrome")
    return running
}

GetTargetBrowsersForDRM() {
    active := GetActiveBrowser()
    if (active != "")
        return [active]

    running := GetRunningBrowsers()
    if (running.Length() > 0)
        return running

    return ["Brave"]
}

CloseBrowserGracefully(browserName, timeoutMs := 3000) {
    meta := GetBrowserMeta(browserName)
    exeName := meta.exeName
    if (!exeName)
        return false

    Process, Exist, %exeName%
    if (!ErrorLevel)
        return true ; Already not running

    ; Send WM_CLOSE to all top-level windows of this browser to flush session tabs
    WinGet, idList, List, ahk_exe %exeName%
    Loop, %idList%
    {
        this_id := idList%A_Index%
        WinClose, ahk_id %this_id%
    }
    
    timeoutSec := Ceil(timeoutMs / 1000)
    WinWaitClose, ahk_exe %exeName%,, %timeoutSec%

    ; Terminate lingering background tray watcher processes to release Local State file locks
    Process, Exist, %exeName%
    if (ErrorLevel) {
        RunWait, taskkill /IM %exeName%,, Hide
        Loop, 15 {
            Process, Exist, %exeName%
            if (!ErrorLevel)
                break
            Sleep, 100
        }
        ; Force terminate if still lingering to guarantee file lock release
        Process, Exist, %exeName%
        if (ErrorLevel) {
            RunWait, taskkill /F /IM %exeName%,, Hide
            Sleep, 300
        }
    }
    Sleep, 200 ; Settle delay to ensure OS releases file handles on Local State
    return true
}

GetBrowserHardwareAcceleration(browserName) {
    meta := GetBrowserMeta(browserName)
    localStatePath := meta.localStatePath
    if (!localStatePath || !FileExist(localStatePath))
        return true

    FileEncoding, UTF-8
    FileRead, content, %localStatePath%
    if (ErrorLevel || !content)
        return true

    if RegExMatch(content, """hardware_acceleration_mode""\s*:\s*\{\s*""enabled""\s*:\s*false\s*\}")
        return false

    return true
}

SetBrowserHardwareAcceleration(browserName, enable) {
    meta := GetBrowserMeta(browserName)
    localStatePath := meta.localStatePath
    if (!localStatePath || !FileExist(localStatePath))
        return false

    FileEncoding, UTF-8
    FileRead, content, %localStatePath%
    if (ErrorLevel || !content)
        return false

    targetEnabled := enable ? "true" : "false"

    ; 1. Update or insert hardware_acceleration_mode: {"enabled": bool}
    if RegExMatch(content, """hardware_acceleration_mode""\s*:\s*\{\s*""enabled""\s*:\s*(true|false)\s*\}") {
        content := RegExReplace(content, """hardware_acceleration_mode""\s*:\s*\{\s*""enabled""\s*:\s*(true|false)\s*\}", """hardware_acceleration_mode"":{""enabled"":" targetEnabled "}")
    } else {
        content := RegExReplace(content, "^\{", "{""hardware_acceleration_mode"":{""enabled"":" targetEnabled "},")
    }

    ; 2. Update or insert hardware_acceleration_mode_previous
    if RegExMatch(content, """hardware_acceleration_mode_previous""\s*:\s*(true|false)") {
        content := RegExReplace(content, """hardware_acceleration_mode_previous""\s*:\s*(true|false)", """hardware_acceleration_mode_previous"":" targetEnabled)
    } else {
        content := RegExReplace(content, "^\{", "{""hardware_acceleration_mode_previous"":" targetEnabled ",")
    }

    tempPath := localStatePath ".tmp"
    FileDelete, %tempPath%
    FileAppend, %content%, %tempPath%, UTF-8
    if FileExist(tempPath) {
        FileMove, %tempPath%, %localStatePath%, 1
        return true
    }
    return false
}

LaunchBrowserInstance(browserName, args := "") {
    meta := GetBrowserMeta(browserName)
    exePath := meta.exePath
    if (!exePath || !FileExist(exePath))
        return false

    cmd := """" exePath """" (args != "" ? (" " args) : "")
    Run, %cmd%
    return true
}

; =============================================================================
; Simple Sticky Notes (ssn.exe) Dual Deterministic Layout Engine
; =============================================================================
; Solves the multi-resolution desktop layout scrambling issue between:
; - Host Laptop (DISPLAY1): 1920x1080 @ 125% DPI scale = 1536 x 864 logical DIP workspace
; - Tablet (DISPLAY4):     2560x1600 @ 175% DPI scale = 1463 x 914 logical DIP workspace
;
; Mathematical Root Cause:
; Notes arranged across 4 columns on the laptop extend to X=1536 (flush against the right edge).
; When switching to Tablet mode, the tablet's logical screen is 73 pixels narrower (1463px vs 1536px).
; Any note with X + Width > 1463 extends off-screen. Simple Sticky Notes detects Column 3 is off-screen
; and forces it to slide left, colliding with Column 2, which in turn collides with Column 1.
;
; Dual Deterministic Layouts (Pixel-by-Pixel):
;
; 1. LAPTOP LAYOUT (Logical workspace: 1536 x 864):
;    - Column 0 (Far Left):
;      * 1 note: W=240, H=240 -> X=0, Y=576 (bottom edge = 816px)
;    - Column 1:
;      * Top note:    W=240, H=120 -> X=728, Y=0
;      * Bottom note: W=240, H=240 -> X=728, Y=120 (bottom edge = 360px)
;      * Right edge: 728 + 240 = 968px (flush against Column 2)
;    - Column 2:
;      * Top note:    W=300, H=240 -> X=968, Y=0
;      * Middle note: W=300, H=183 -> X=968, Y=240
;      * Bottom note: W=300, H=236 -> X=968, Y=423 (bottom edge = 659px)
;      * Right edge: 968 + 300 = 1268px (flush against Column 3)
;    - Column 3:
;      * 'Today' note (expanded): W=268, H=548 -> X=1268, Y=0
;      * Minimized notes: W=268, H=32 -> X=1268, stacked below Today at Y=548, 580, 612, 644, 676
;      * Right edge: 1268 + 268 = 1536px (flush against laptop right screen boundary)
;
; 2. TABLET LAYOUT (Logical workspace: 1463 x 914):
;    - Column 0 (Far Left):
;      * 1 note: W=240, H=240 -> X=0, Y=576
;    - Column 1:
;      * Top note:    W=240, H=120 -> X=640, Y=0
;      * Bottom note: W=240, H=240 -> X=640, Y=120
;      * Right edge: 640 + 240 = 880px (5px gap before Column 2)
;    - Column 2:
;      * Top note:    W=300, H=240 -> X=885, Y=0
;      * Middle note: W=300, H=183 -> X=885, Y=240
;      * Bottom note: W=300, H=236 -> X=885, Y=423
;      * Right edge: 885 + 300 = 1185px (5px gap before Column 3)
;    - Column 3:
;      * 'Today' note (expanded): W=268, H=548 -> X=1190, Y=0
;      * Minimized notes: W=268, H=32 -> X=1190, stacked below Today at Y=548, 580, 612, 644, 676
;      * Right edge: 1190 + 268 = 1458px (safe 5px margin before 1463px tablet edge, zero cut-off)
;
; Window Identification Signatures:
; - Column 3: Width in [260, 290] ('Today' H=548, minimized notes H=32)
; - Column 2: Width in [295, 315] (H=240 top, H=183 middle, H=236 bottom)
; - Column 1: Width in [230, 250], H <= 130 is top note (H=120)
; - Column 0 vs Column 1: Width in [230, 250], H > 130 (H=240): note with smaller X is Column 0, larger X is Column 1 bottom

_SSN_Sort(arr, prop, ascending := true) {
    n := arr.Length()
    if (n <= 1)
        return
    Loop, % n - 1 {
        i := A_Index
        Loop, % n - i {
            j := A_Index
            v1 := arr[j][prop]
            v2 := arr[j + 1][prop]
            swap := ascending ? (v1 > v2) : (v1 < v2)
            if (swap) {
                tmp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := tmp
            }
        }
    }
}

ApplyLaptopStickyNotesLayout(delayMs := 0) {
    psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
    cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ psScript """ -Mode Laptop -DelayMs " delayMs
    Run, %cmd%,, Hide
    return true
}

ApplyTabletStickyNotesLayout(delayMs := 0) {
    psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
    cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ psScript """ -Mode Tablet -DelayMs " delayMs
    Run, %cmd%,, Hide
    return true
}

AutoApplyStickyNotesLayout(delayMs := 0) {
    psScript := A_ScriptDir "\PowerShell\apply_ssn_layout.ps1"
    cmd := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ psScript """ -Mode Auto -DelayMs " delayMs
    Run, %cmd%,, Hide
    return true
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


