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
; BOTTOM-RIGHT BADGE - colored toast, bottom-right corner
; -----------------------------------------------------------------------------
; Singleton badge surface (one "BottomRightBadge" Gui, matching how this behaved before extraction) - a second call while one is showing updates its color/text in place, never stacks a second one.
; If a future feature needs independent simultaneous badges, this would need a name parameter added - not needed by anything today.
;
; The underlying Gui window is created ONCE (on first call) and never destroyed again afterward - later calls just update its color/text and re-Show it if hidden.
; Destroying and recreating the window on every call instead (via Destroy + Sleep + rebuild) produces a visible blank gap between badge transitions; updating a persistent window in place is instant.
; displayMs := 0 (the default) means "leave this on screen until the next ShowBottomRightBadge/HideBottomRightBadge call" - pass an explicit ms value for anything that should auto-dismiss on its own (status toasts, errors, or a generous safety-net ceiling for a badge normally dismissed explicitly but that shouldn't get stuck forever if that call is ever skipped).
ShowBottomRightBadge(msg, bgColorHex, displayMs := 0) {
    static created := false, hTextCtl := 0

    SetTimer, RemoveBottomRightBadge, Off

    if (!created) {
        SysGet, PrimaryMon, MonitorPrimary
        SysGet, wa, MonitorWorkArea, %PrimaryMon%
        xPos := waRight - 314 ; 300px wide + 14px right margin
        yPos := waBottom - 60 ; 46px tall + 14px gap above taskbar

        Gui, BottomRightBadge: +AlwaysOnTop +ToolWindow -Caption +LastFound
        Gui, BottomRightBadge: Color, %bgColorHex%
        Gui, BottomRightBadge: Font, s11 Bold cFFFFFF, Segoe UI
        ; HwndhTextCtl, not vBottomRightBadgeText: a `v`-prefixed Gui output variable on an Add command executed from INSIDE a function (as opposed to top-level auto-execute code) hangs indefinitely on AHK v1.1.37.02, while the exact same control created with an `Hwnd` option instead works instantly.
        ; The static hTextCtl below holds the control's HWND for later GuiControl/Show calls, which accept a bare HWND value as a ControlID just as readily as a v-variable name.
        Gui, BottomRightBadge: Add, Text, x0 y14 w300 h24 Center BackgroundTrans HwndhTextCtl, % msg
        Gui, BottomRightBadge: Show, x%xPos% y%yPos% w300 h46 NA

        ; Under Windows display scaling above 100%, a requested 300x46 box can RENDER larger (e.g. 375x58 at 125% DPI), even though the requested x/y position matches the actual rendered position exactly.
        ; A clamp computed against the nominal 300x46 size would NOT catch this - it would still overflow using the real, larger rect.
        ; Measure the actual post-creation rect and correct against it, position-only (re-specifying w/h here re-triggers the same inflation on the new values, compounding it further - e.g. 375->469). See ARCHITECTURE.md for the full explanation.
        ; This block only ever runs once now (at creation) - every later call reuses this same window without re-specifying w/h, so the inflation can never recompound.
        WinGetPos, actualX, actualY, actualW, actualH
        finalX := actualX, finalY := actualY
        needsMove := false
        if (actualX + actualW > A_ScreenWidth) {
            finalX := A_ScreenWidth - actualW
            needsMove := true
        }
        if (finalX < 0) {
            finalX := 0
            needsMove := true
        }
        if (actualY + actualH > A_ScreenHeight) {
            finalY := A_ScreenHeight - actualH
            needsMove := true
        }
        if (finalY < 0) {
            finalY := 0
            needsMove := true
        }
        if (needsMove)
            Gui, BottomRightBadge: Show, x%finalX% y%finalY% NA

        created := true
    } else {
        ; Update in place - no Destroy, no Sleep, no gap.
        ; The explicit Redraw forces the BackgroundTrans text control's parent-colored backdrop to repaint immediately; without it the old color can linger behind the control until some unrelated repaint event happens to trigger it.
        Gui, BottomRightBadge: Color, %bgColorHex%
        Gui, BottomRightBadge: +LastFound
        WinSet, Redraw
        GuiControl, BottomRightBadge:, %hTextCtl%, % msg
        Gui, BottomRightBadge: Show, NA
    }

    if (displayMs > 0)
        SetTimer, RemoveBottomRightBadge, % -displayMs
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
; Call PublishTrayMenuManifest once from each script's auto-execute section,
; right after that script's own Menu, Tray, Add lines, passing the same
; label/Gosub-target pairs as a nested array:
;   PublishTrayMenuManifest([["Display Label 1", "TrayLabel1"],
;                             ["Display Label 2", "TrayLabel2"]])
; This writes %A_Temp%\ahk_traymenu_<ScriptName>.txt (one file per script, keyed by that script's own filename) and registers this same shared HandleRemoteTrayMenuTrigger as the responder for "AHK_RemoteTrayMenuTrigger_v1".
; StartupScript.ahk reads these manifest files to mirror every script's custom tray items into one master submenu, and PostMessages this registered ID with wParam = the manifest's 1-based line number when a mirrored item is clicked.
; Each process reads only its own manifest file (via its own A_ScriptFullPath), so sharing this one function across multiple processes is safe - there is no cross-process state, only the convention of "one manifest file per script."
PublishTrayMenuManifest(itemsArray) {
    SplitPath, A_ScriptFullPath,,,, scriptNameNoExt
    manifestPath := A_Temp "\ahk_traymenu_" scriptNameNoExt ".txt"
    FileDelete, %manifestPath%
    for idx, item in itemsArray
        FileAppend, % item[1] "|" item[2] "`n", %manifestPath%
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
