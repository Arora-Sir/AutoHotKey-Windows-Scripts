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
