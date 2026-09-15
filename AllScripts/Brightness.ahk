#Requires AutoHotkey v2.0

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

; F1 & Shift+F1 -> Controls brightness
; Ctr+PgUp & Ctr+PgDn -> Extreme levels of brightness (beyond brightness level)

; v2: #NoEnv deleted entirely (meaningless in v2 - no legacy/ANSI environment mode exists anymore).
; #Persistent is not usable as a directive in v2 (confirmed empirically: it hangs the process at load time with no
; error shown) - Persistent() the function is the proven-working replacement, used below.
Persistent()
SendMode("Input")
SetWorkingDir(A_ScriptDir)
#SingleInstance force
DetectHiddenWindows(true)
; v2: SetBatchLines was removed entirely, no replacement - v2's execution engine has no cooperative line-batching
; concept left to throttle, so this line is simply dropped rather than translated to anything.
; v2: #MaxThreadsBuffer takes a boolean (true/false), not v1's On/Off strings - "Parameter #1 invalid"
; otherwise, confirmed empirically.
#MaxThreadsBuffer true
#MaxThreadsPerHotkey 3
; v2: #MaxHotkeysPerInterval is gone as a directive - it is now the assignable built-in A_MaxHotkeysPerInterval.
A_MaxHotkeysPerInterval := 200

; v2 fleet control protocol: replaces v1's master PostMessage to AutoHotkey's own reserved tray-command IDs (Edit/Exit/
; ViewKeyHistory/Suspend), which is not guaranteed to carry over to v2 processes. Every managed script registers the
; same custom message and handles it locally - see SharedHelpers.ahk for the full explanation.
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

class BrightnessSetter {
    ; qwerty12 - 27/05/17
    ; https://github.com/qwerty12/AutoHotkeyScripts/tree/master/LaptopBrightnessSetter
    static _WM_POWERBROADCAST := 0x218, _osdHwnd := 0, hPowrprofMod := DllCall("LoadLibrary", "Str", "powrprof.dll", "Ptr")

    ; v2: per-instance properties must have a declared default, or reading one before its first assignment
    ; throws "has no property named ..." - v1's looser dynamic objects allowed a blind read to return blank.
    ; _AC is normally set in __New() below, but _lastTime/_cachedBrightness are only ever written inside
    ; SetBrightness() itself, so the very first call on a fresh instance reads them before that write ever runs.
    _AC := "", _lastTime := 0, _cachedBrightness := ""

    ; v2: every method below that is called as BrightnessSetter.MethodName(...) (class-qualified, not
    ; this.MethodName(...)) must be declared `static` - confirmed empirically this session that calling
    ; a non-static instance method via the bare class name hangs the interpreter at the CALL SITE (a
    ; distinct bug from the OnMessage <4-param hang; see Migration-Notes.md's new subsection). None of
    ; these reference `this`, so `static` is also the semantically correct fix, not just a workaround.
    __New() {
        if (BrightnessSetter.IsOnAc(&AC))
            this._AC := AC
        ; v2: this._WM_POWERBROADCAST (a STATIC prop) accessed via `this` hangs the interpreter at
        ; runtime - confirmed empirically this session, a distinct bug from the two above. Static props
        ; must be read via the class name (BrightnessSetter._WM_POWERBROADCAST), never via `this`, even
        ; from inside an instance method.
        ; v2: ObjBindMethod's resulting BoundFunc also hangs OnMessage's registration regardless of the
        ; underlying method's declared param count (confirmed empirically - unlike a plain Func.Bind(),
        ; which works fine). Fix: register the bare top-level Brightness_WM_POWERBROADCAST function
        ; below (which operates on the BS singleton directly, since exactly one instance ever exists)
        ; instead of binding this instance's own method.
        if ((this.pwrAcNotifyHandle := DllCall("RegisterPowerSettingNotification", "Ptr", A_ScriptHwnd, "Ptr", BrightnessSetter._GUID_ACDC_POWER_SOURCE(), "UInt", DEVICE_NOTIFY_WINDOW_HANDLE := 0x00000000, "Ptr"))) ; Sadly the callback passed to *PowerSettingRegister*Notification runs on a new threadl
            OnMessage(BrightnessSetter._WM_POWERBROADCAST, (this.pwrBroadcastFunc := Brightness_WM_POWERBROADCAST))
    }

    __Delete() {
        if (this.pwrAcNotifyHandle) {
            OnMessage(BrightnessSetter._WM_POWERBROADCAST, this.pwrBroadcastFunc, 0)
            ,DllCall("UnregisterPowerSettingNotification", "Ptr", this.pwrAcNotifyHandle)
            ,this.pwrAcNotifyHandle := 0
            ,this.pwrBroadcastFunc := ""
        }
    }

    ;showOSD is enabled for Windows native OSD flyout display
    SetBrightness(increment, jump := false, showOSD := true, autoDcOrAc := -1, ptrAnotherScheme := 0)
    {
        static PowerGetActiveScheme := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerGetActiveScheme", "Ptr")
        ,PowerSetActiveScheme := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerSetActiveScheme", "Ptr")
        ,PowerWriteACValueIndex := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerWriteACValueIndex", "Ptr")
        ,PowerWriteDCValueIndex := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerWriteDCValueIndex", "Ptr")
        ,PowerApplySettingChanges := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerApplySettingChanges", "Ptr")

        if (increment == 0 && !jump) {
            if (showOSD)
                BrightnessSetter._ShowBrightnessOSD()
            return
        }

        ; v2: DllCall's "Ptr*" output parameter now needs an explicit &currSchemeGuid (v1 took the bare variable name
        ; and auto-took its address). currSchemeGuid also needs to be pre-assigned before the call: it's used only
        ; inside one branch of the ternary below, and a variable that has NEVER been assigned anywhere in the function
        ; throws "This local variable has not been assigned a value" right at the DllCall itself when referenced via
        ; &currSchemeGuid from inside a ternary branch - confirmed empirically (Migration-Notes.md 18.x).
        currSchemeGuid := 0
        if (!ptrAnotherScheme ? DllCall(PowerGetActiveScheme, "Ptr", 0, "Ptr*", &currSchemeGuid, "UInt") == 0 : DllCall("powrprof\PowerDuplicateScheme", "Ptr", 0, "Ptr", ptrAnotherScheme, "Ptr*", &currSchemeGuid, "UInt") == 0) {
            if (autoDcOrAc == -1) {
                if (this != BrightnessSetter) {
                    AC := this._AC
                } else {
                    if (!BrightnessSetter.IsOnAc(&AC)) {
                        DllCall("LocalFree", "Ptr", currSchemeGuid, "Ptr")
                        return
                    }
                }
            } else {
                AC := !!autoDcOrAc
            }

            now := A_TickCount
            if (this._lastTime && (now - this._lastTime < 500) && this._cachedBrightness != "") {
                currBrightness := this._cachedBrightness
            } else {
                currBrightness := 0
                if (!BrightnessSetter._GetCurrentBrightness(currSchemeGuid, AC, &currBrightness))
                    currBrightness := 50
            }

            if (jump || currBrightness != "") {
                maxBrightness := BrightnessSetter.GetMaxBrightness()
                ,minBrightness := BrightnessSetter.GetMinBrightness()

                if (jump || !((currBrightness == maxBrightness && increment > 0) || (currBrightness == minBrightness && increment < minBrightness))) {
                    if (currBrightness + increment > maxBrightness)
                        increment := maxBrightness
                    else if (currBrightness + increment < minBrightness)
                        increment := minBrightness
                    else
                        increment += currBrightness

                    this._cachedBrightness := increment
                    this._lastTime := now

                    resAC := DllCall(PowerWriteACValueIndex, "Ptr", 0, "Ptr", currSchemeGuid, "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt", increment, "UInt")
                    resDC := DllCall(PowerWriteDCValueIndex, "Ptr", 0, "Ptr", currSchemeGuid, "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt", increment, "UInt")

                    if (resAC == 0 || resDC == 0) {
                        ; PowerApplySettingChanges is undocumented and exists only in Windows 8+. Since both the Power control panel and the brightness slider use this, we'll do the same, but fallback to PowerSetActiveScheme if on Windows 7 or something
                        if (!PowerApplySettingChanges || DllCall(PowerApplySettingChanges, "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt") != 0)
                            DllCall(PowerSetActiveScheme, "Ptr", 0, "Ptr", currSchemeGuid, "UInt")
                    }
                }

                if (showOSD)
                    BrightnessSetter._ShowBrightnessOSD()
            }
            DllCall("LocalFree", "Ptr", currSchemeGuid, "Ptr")
        }
    }

    static IsOnAc(&acStatus)
    {
        ; v2: VarSetCapacity's lazy "allocate once" idiom collapses to a plain static Buffer initializer - v2 only
        ; ever runs a static initializer once regardless, so the old capacity-check guard is no longer needed at all.
        static SystemPowerStatus := Buffer(12, 0)

        ; v2: pass the Buffer object directly to a "Ptr"-typed DllCall argument, not &SystemPowerStatus.
        if (DllCall("GetSystemPowerStatus", "Ptr", SystemPowerStatus)) {
            acStatus := NumGet(SystemPowerStatus, 0, "UChar") == 1
            return true
        }

        return false
    }

    static GetDefaultBrightnessIncrement()
    {
        static ret := 10
        DllCall("powrprof\PowerReadValueIncrement", "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", &ret, "UInt")
        return ret
    }

    static GetMinBrightness()
    {
        static ret := -1
        if (ret == -1)
            if (DllCall("powrprof\PowerReadValueMin", "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", &ret, "UInt"))
                ret := 0
        return ret
    }

    static GetMaxBrightness()
    {
        static ret := -1
        if (ret == -1)
            if (DllCall("powrprof\PowerReadValueMax", "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", &ret, "UInt"))
                ret := 100
        return ret
    }

    static _GetCurrentBrightness(schemeGuid, AC, &currBrightness)
    {
        static PowerReadACValueIndex := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerReadACValueIndex", "Ptr")
        ,PowerReadDCValueIndex := DllCall("GetProcAddress", "Ptr", BrightnessSetter.hPowrprofMod, "AStr", "PowerReadDCValueIndex", "Ptr")
        return DllCall(AC ? PowerReadACValueIndex : PowerReadDCValueIndex, "Ptr", 0, "Ptr", schemeGuid, "Ptr", BrightnessSetter._GUID_VIDEO_SUBGROUP(), "Ptr", BrightnessSetter._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", &currBrightness, "UInt") == 0
    }

    static _ShowBrightnessOSD()
    {
        ; v2: A_IsUnicode was removed (v2 is always Unicode) - hardcoded to the W-suffixed API, which is what this
        ; ternary always resolved to in practice anyway on any real, modern AHK install.
        static PostMessagePtr := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "user32.dll", "Ptr"), "AStr", "PostMessageW", "Ptr")
        ,WM_SHELLHOOK := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt")
        ; v2: legacy "if Var in MatchList" command syntax is gone - rewritten as an OR'd equality expression, same two
        ; literal values checked as before.
        if (A_OSVersion = "WIN_VISTA" || A_OSVersion = "WIN_7")
            return
        BrightnessSetter._RealiseOSDWindowIfNeeded()
        ; 0x38 = Native Brightness OSD Flyout (0x37 was Volume OSD Flyout)
        if (BrightnessSetter._osdHwnd)
            DllCall(PostMessagePtr, "Ptr", BrightnessSetter._osdHwnd, "UInt", WM_SHELLHOOK, "Ptr", 0x38, "Ptr", 0)
    }

    static _RealiseOSDWindowIfNeeded()
    {
        static IsWindow := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "user32.dll", "Ptr"), "AStr", "IsWindow", "Ptr")
        if (!DllCall(IsWindow, "Ptr", BrightnessSetter._osdHwnd) && !BrightnessSetter._FindAndSetOSDWindow()) {
            BrightnessSetter._osdHwnd := 0
            ; v2: ComObjCreate -> ComObject. ComObjQuery is unchanged (verified against v2 docs, not renamed).
            try if ((shellProvider := ComObject("{C2F03A33-21F5-47FA-B4BB-156362A2F239}", "{00000000-0000-0000-C000-000000000046}"))) {
                try if ((flyoutDisp := ComObjQuery(shellProvider, "{41f9d2fb-7834-4ab6-8b1b-73e74064b465}", "{41f9d2fb-7834-4ab6-8b1b-73e74064b465}"))) {
                    ; IFlyoutDisplay::ShowFlyout enum mapping on Windows 11:
                    ; 0 = Volume Flyout, 1 = Airplane Mode, 3 = Display Brightness Flyout
                    ; v2 gotcha: NumGet's Type argument is mandatory here - omitting it hangs the whole file at load
                    ; time (not a clean error), so "Ptr" is added to BOTH the inner and outer NumGet below.
                    ; v2: `flyoutDisp+0` throws "Expected a Number but got a ComValue" - ComObjQuery() returns a
                    ; real ComValue wrapper, which (unlike v1) does not auto-coerce to a number via arithmetic.
                    ; Use its .Ptr property instead for NumGet's vtable walk (confirmed empirically, same class
                    ; of bug as SharedHelpers.ahk's GetMicrophoneMute/SetMicrophoneMute).
                    DllCall(NumGet(NumGet(flyoutDisp.Ptr, "Ptr") + 3*A_PtrSize, "Ptr"), "Ptr", flyoutDisp, "Int", 3, "UInt", 0)
                    ; v2: flyoutDisp/shellProvider are ComValue wrappers, not raw pointers - ObjRelease on
                    ; a wrapper throws "Parameter #1 of ObjRelease is invalid" (confirmed live, same class
                    ; of bug as SharedHelpers.ahk's GetMicrophoneMute/SetMicrophoneMute). Both release their
                    ; own COM reference automatically when garbage-collected, so both calls are simply dropped.
                }
                if (BrightnessSetter._FindAndSetOSDWindow())
                    return
            }
        }
    }

    static _FindAndSetOSDWindow()
    {
        ; v2: A_IsUnicode removed - see _ShowBrightnessOSD's comment above, identical fix.
        static FindWindow := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "user32.dll", "Ptr"), "AStr", "FindWindowW", "Ptr")
        return !!((BrightnessSetter._osdHwnd := DllCall(FindWindow, "Str", "NativeHWNDHost", "Str", "", "Ptr")))
    }

    static _GUID_VIDEO_SUBGROUP()
    {
        ; v2: VarSetCapacity's "already allocated?" self-check becomes an IsSet() check on the still-bare static - the
        ; Buffer is only ever created and filled once, exactly mirroring the original's lazy-build-once intent.
        static GUID_VIDEO_SUBGROUP__
        if (!IsSet(GUID_VIDEO_SUBGROUP__)) {
            GUID_VIDEO_SUBGROUP__ := Buffer(16, 0)
            ; v2: NumPut's argument order changed from v1's (Value, Target, Offset, Type) to (Type, Value, Target, Offset).
            NumPut("UInt", 0x7516B95F, GUID_VIDEO_SUBGROUP__, 0), NumPut("UInt", 0x4464F776, GUID_VIDEO_SUBGROUP__, 4)
            NumPut("UInt", 0x1606538C, GUID_VIDEO_SUBGROUP__, 8), NumPut("UInt", 0x99CC407F, GUID_VIDEO_SUBGROUP__, 12)
        }
        return GUID_VIDEO_SUBGROUP__.Ptr
    }

    static _GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS()
    {
        static GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__
        if (!IsSet(GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__)) {
            GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__ := Buffer(16, 0)
            NumPut("UInt", 0xADED5E82, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 0), NumPut("UInt", 0x4619B909, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 4)
            NumPut("UInt", 0xD7F54999, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 8), NumPut("UInt", 0xCB0BAC1D, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 12)
        }
        return GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__.Ptr
    }

    static _GUID_ACDC_POWER_SOURCE()
    {
        static GUID_ACDC_POWER_SOURCE_
        if (!IsSet(GUID_ACDC_POWER_SOURCE_)) {
            GUID_ACDC_POWER_SOURCE_ := Buffer(16, 0)
            NumPut("UInt", 0x5D3E9A59, GUID_ACDC_POWER_SOURCE_, 0), NumPut("UInt", 0x4B00E9D5, GUID_ACDC_POWER_SOURCE_, 4)
            NumPut("UInt", 0x34FFBDA6, GUID_ACDC_POWER_SOURCE_, 8), NumPut("UInt", 0x486551FF, GUID_ACDC_POWER_SOURCE_, 12)
        }
        return GUID_ACDC_POWER_SOURCE_.Ptr
    }

}

; v2: moved out of the class (was an instance method bound via ObjBindMethod - see __New()'s comment
; for why that hangs OnMessage's registration). Operates on the BS singleton directly; safe since
; exactly one BrightnessSetter instance is ever constructed in this script.
; v2: OnMessage(msg, handler) hangs at the OnMessage() call itself if the handler has fewer than 4
; declared parameters and no `*` catch-all - confirmed empirically this session (Migration-Notes.md
; 18.16/18.17). `*` is the fix.
Brightness_WM_POWERBROADCAST(wParam, lParam, *)
{
    global BS
    ;OutputDebug(BS)
    if (wParam == 0x8013 && lParam && NumGet(lParam+0, 0, "UInt") == NumGet(BrightnessSetter._GUID_ACDC_POWER_SOURCE()+0, 0, "UInt")) { ; PBT_POWERSETTINGCHANGE and a lazy comparison
        BS._AC := NumGet(lParam+0, 20, "UChar") == 0
        return true
    }
}

BrightnessSetter_new() {
    ; v2: new ClassName() -> ClassName() (the `new` keyword is gone - classes are directly callable).
    return BrightnessSetter()
}

adj_Brightness(d)
{
    ; useful values are: -16 .. +16
    Gamma := get_Brightness() + d
    set_Brightness(Gamma > 255 ? 255 : Gamma < 0 ? 0 : Gamma)
}
get_Brightness()
{
    ; return current brightness (0 .. 255)
    GB := Buffer(1536, 0)
    hDC := DllCall("GetDC", "Ptr", 0)
    DllCall("GetDeviceGammaRamp", "Ptr", hDC, "Ptr", GB)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
    return NumGet(GB, 2, "UShort") - 128
}
set_Brightness(Gamma)
{
    ; set brightness (0 .. 255)
    ; v2: VarSetCapacity's dual role here (allocate the buffer AND return its byte size, used directly as the loop
    ; count) doesn't map 1:1 - re-derived as Buffer(1536) then Loop GB.Size / 6, which yields the same 256 iterations.
    GB := Buffer(1536)
    Loop GB.Size / 6 {
        N := (Gamma + 128) * (A_Index - 1)
        ; v2: NumPut's argument order changed from v1's (Value, Target, Offset, Type) to (Type, Value, Target, Offset).
        NumPut("UShort", N > 65535 ? 65535 : N, GB, 2 * (A_Index - 1))
    }
    DllCall("RtlMoveMemory", "Ptr", GB.Ptr + 512, "Ptr", GB.Ptr, "Ptr", 512)
    DllCall("RtlMoveMemory", "Ptr", GB.Ptr + 1024, "Ptr", GB.Ptr, "Ptr", 512)
    hDC := DllCall("GetDC", "Ptr", 0)
    DllCall("SetDeviceGammaRamp", "Ptr", hDC, "Ptr", GB)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
}

ChangeBrightness(&brightness, timeout := 1)
{
    if (brightness >= 0 && brightness <= 100)
    {
        for property in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
            property.WmiSetBrightness(timeout, brightness)
    }
    else if (brightness > 100)
    {
        brightness := 100
    }
    else if (brightness < 0)
    {
        brightness := 0
    }
}
GetCurrentBrightNess()
{
    for property in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightness")
        CurrentBrightness := property.CurrentBrightness

    return CurrentBrightness
}

BS := BrightnessSetter()
Increments := 10
+F1::BS.SetBrightness(-Increments) ;{ <- Brightness decreased by 5
F1::BS.SetBrightness(+Increments) ;{ <- Brightness increased by 5

ExtremeIncrements := 10
^PgUp:: adj_Brightness(+10) ;{ <- Push Brightness Extremes Up +10
^PgDn:: adj_Brightness(-10) ;{ <- Push Brightness Extremes Down -10

; Increments := 10
; CurrentBrightness := GetCurrentBrightNess()
; +F1::ChangeBrightness( CurrentBrightness -= Increments) ; decrease brightness
; F1::ChangeBrightness( CurrentBrightness += Increments) ; increase brightness
