; Window Spy for AHK v2 with dynamic system dark and light theme support
#Requires AutoHotkey v2.0

#NoTrayIcon
#SingleInstance Ignore
SetWorkingDir A_ScriptDir
CoordMode "Pixel", "Screen"

Global oGui
Global g_hDarkBrush := 0

IsSystemDarkMode() {
    try {
        return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) = 0
    } catch {
        return false
    }
}

ApplyWindowThemeMode(guiObj, isDark) {
    val := isDark ? 1 : 0
    if (DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 20, "Int*", val, "UInt", 4) != 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 19, "Int*", val, "UInt", 4)
    hUxtheme := DllCall("GetModuleHandle", "Str", "uxtheme.dll", "Ptr")
    if (hUxtheme) {
        pSetPreferredAppMode := DllCall("GetProcAddress", "Ptr", hUxtheme, "Ptr", 135, "Ptr")
        pFlushMenuThemes     := DllCall("GetProcAddress", "Ptr", hUxtheme, "Ptr", 136, "Ptr")
        if (pSetPreferredAppMode && pFlushMenuThemes) {
            DllCall(pSetPreferredAppMode, "Int", isDark ? 2 : 3)
            DllCall(pFlushMenuThemes)
        }
    }
}

OnMessage(0x0133, WinSpy_WM_CTLCOLOR) ; WM_CTLCOLOREDIT
OnMessage(0x0138, WinSpy_WM_CTLCOLOR) ; WM_CTLCOLORSTATIC

WinSpy_WM_CTLCOLOR(wParam, lParam, msg, hwnd) {
    global g_hDarkBrush
    if IsSystemDarkMode() {
        DllCall("SetTextColor", "Ptr", wParam, "UInt", 0x00ECECEC) ; Crisp light text in BGR format.
        DllCall("SetBkColor", "Ptr", wParam, "UInt", 0x001E1E1E)   ; Dark grey background in BGR format.
        if (!g_hDarkBrush)
            g_hDarkBrush := DllCall("CreateSolidBrush", "UInt", 0x001E1E1E, "Ptr")
        return g_hDarkBrush
    }
}

WinSpyGui()

WinSpyGui() {
    Global oGui
    
    try TraySetIcon "inc\spy.ico"
    try TraySetIcon "UX\inc\spy.ico"
    DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "wstr", "AutoHotkey.WindowSpy")
    
    isDark := IsSystemDarkMode()
    
    oGui := Gui("AlwaysOnTop Resize MinSize +DPIScale", "Window Spy for AHKv2")
    oGui.OnEvent("Close", WinSpyClose)
    oGui.OnEvent("Size", WinSpySize)
    
    oGui.BackColor := isDark ? "1E1E1E" : "F0F0F0"
    oGui.SetFont('s9 c' (isDark ? "ECECEC" : "000000"), "Segoe UI")
    
    oGui.Add("Text", , "Window Title, Class and Process:")
    cbFollow := oGui.Add("Checkbox", "yp xp+200 w120 Right vCtrl_FollowMouse", "Follow Mouse")
    cbFollow.Value := 1
    edtTitle := oGui.Add("Edit", "xm w320 r5 ReadOnly -Wrap -E0x200 vCtrl_Title")
    
    oGui.Add("Text", , "Mouse Position:")
    edtMousePos := oGui.Add("Edit", "w320 r4 ReadOnly -E0x200 vCtrl_MousePos")
    
    oGui.Add("Text", "w320 vCtrl_CtrlLabel", (txtFocusCtrl := "Focused Control") ":")
    edtCtrl := oGui.Add("Edit", "w320 r4 ReadOnly -E0x200 vCtrl_Ctrl")
    
    oGui.Add("Text", , "Active Window Position:")
    edtPos := oGui.Add("Edit", "w320 r2 ReadOnly -E0x200 vCtrl_Pos")
    
    oGui.Add("Text", , "Status Bar Text:")
    edtSBText := oGui.Add("Edit", "w320 r2 ReadOnly -E0x200 vCtrl_SBText")
    
    cbSlow := oGui.Add("Checkbox", "vCtrl_IsSlow", "Slow TitleMatchMode")
    
    oGui.Add("Text", , "Visible Text:")
    edtVisText := oGui.Add("Edit", "w320 r2 ReadOnly -E0x200 vCtrl_VisText")
    
    oGui.Add("Text", , "All Text:")
    edtAllText := oGui.Add("Edit", "w320 r2 ReadOnly -E0x200 vCtrl_AllText")
    
    txtNotFrozen := "(Hold Ctrl or Shift to suspend updates)"
    oGui.Add("Text", "w320 r1 vCtrl_Freeze", txtNotFrozen)
    
    ApplyWindowThemeMode(oGui, isDark)
    
    themeClass := isDark ? "DarkMode_Explorer" : "Explorer"
    DllCall("uxtheme\SetWindowTheme", "Ptr", cbFollow.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", cbSlow.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtTitle.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtMousePos.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtCtrl.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtPos.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtSBText.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtVisText.Hwnd, "Str", themeClass, "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", edtAllText.Hwnd, "Str", themeClass, "Ptr", 0)
    
    oGui.Show("NoActivate")
    
    oGui.txtNotFrozen := txtNotFrozen
    oGui.txtFrozen    := "(Updates suspended)"
    oGui.txtMouseCtrl := "Control Under Mouse Position"
    oGui.txtFocusCtrl := txtFocusCtrl
    
    SetTimer Update, 250
}

WinSpySize(GuiObj, MinMax, Width, Height) {
    Global oGui
    
    If !oGui.HasProp("txtNotFrozen")
        return
    
    SetTimer Update, (MinMax=0) ? 250 : 0
    
    ctrlW := Width - (oGui.MarginX * 2)
    list := "Title,MousePos,Ctrl,Pos,SBText,VisText,AllText,Freeze"
    Loop Parse list, ","
        oGui["Ctrl_" A_LoopField].Move(, , ctrlW)
}

WinSpyClose(GuiObj) {
    global g_hDarkBrush
    if (g_hDarkBrush) {
        DllCall("DeleteObject", "Ptr", g_hDarkBrush)
        g_hDarkBrush := 0
    }
    ExitApp()
}

Update() {
    Try TryUpdate()
}

TryUpdate() {
    Global oGui
    
    If !oGui.HasProp("txtNotFrozen")
        return
    
    try DllCall("SetThreadDpiAwarenessContext", "ptr", -4)
    
    Ctrl_FollowMouse := oGui["Ctrl_FollowMouse"].Value
    CoordMode "Mouse", "Screen"
    MouseGetPos &msX, &msY, &msWin, &msCtrl, 2
    actWin := WinExist("A")
    
    if (Ctrl_FollowMouse) {
        curWin := msWin, curCtrl := msCtrl
        WinExist("ahk_id " curWin)
    } else {
        curWin := actWin
        curCtrl := ControlGetFocus()
    }
    curCtrlClassNN := ""
    Try curCtrlClassNN := ControlGetClassNN(curCtrl)
    
    t1 := WinGetTitle(), t2 := WinGetClass()
    if (curWin = oGui.hwnd || t2 = "MultitaskingViewFrame") {
        UpdateText("Ctrl_Freeze", oGui.txtFrozen)
        return
    }
    
    UpdateText("Ctrl_Freeze", oGui.txtNotFrozen)
    t3 := WinGetProcessName(), t4 := WinGetPID()
    
    WinDataText := t1 "`n"
                 . "ahk_class " t2 "`n"
                 . "ahk_exe " t3 "`n"
                 . "ahk_pid " t4 "`n"
                 . "ahk_id " curWin
    
    UpdateText("Ctrl_Title", WinDataText)
    CoordMode "Mouse", "Window"
    MouseGetPos &mrX, &mrY
    CoordMode "Mouse", "Client"
    MouseGetPos &mcX, &mcY
    mClr := PixelGetColor(msX, msY, "RGB")
    mClr := SubStr(mClr, 3)
    
    mpText := "Screen:`t" msX ", " msY "`n"
            . "Window:`t" mrX ", " mrY "`n"
            . "Client:`t" mcX ", " mcY " (default)`n"
            . "Color:`t" mClr " (Red=" SubStr(mClr, 1, 2) " Green=" SubStr(mClr, 3, 2) " Blue=" SubStr(mClr, 5) ")"
    
    UpdateText("Ctrl_MousePos", mpText)
    
    UpdateText("Ctrl_CtrlLabel", (Ctrl_FollowMouse ? oGui.txtMouseCtrl : oGui.txtFocusCtrl) ":")
    
    if (curCtrl) {
        ctrlTxt := ControlGetText(curCtrl)
        WinGetClientPos(&sX, &sY, &cW, &cH, curCtrl)
        ControlGetPos &cX, &cY, &sW, &sH, curCtrl
        
        cText := "ClassNN:`t" curCtrlClassNN "`n"
               . "Text:`t" textMangle(ctrlTxt) "`n"
               . "Screen:`tx: " sX "`ty: " sY "`tw: " sW "`th: " sH "`n"
               . "Client:`tx: " cX "`ty: " cY "`tw: " cW "`th: " cH
    } else
        cText := ""
    
    UpdateText("Ctrl_Ctrl", cText)
    wX := "", wY := "", wW := "", wH := ""
    WinGetPos &wX, &wY, &wW, &wH, "ahk_id " curWin
    WinGetClientPos(&wcX, &wcY, &wcW, &wcH, "ahk_id " curWin)
    
    wText := "Screen:`tx: " wX "`ty: " wY "`tw: " wW "`th: " wH "`n"
           . "Client:`tx: " wcX "`ty: " wcY "`tw: " wcW "`th: " wcH
    
    UpdateText("Ctrl_Pos", wText)
    sbTxt := ""
    
    Loop {
        ovi := ""
        Try ovi := StatusBarGetText(A_Index)
        if (ovi = "")
            break
        sbTxt .= "(" A_Index "):`t" textMangle(ovi) "`n"
    }
    
    sbTxt := SubStr(sbTxt, 1, -1)
    UpdateText("Ctrl_SBText", sbTxt)
    bSlow := oGui["Ctrl_IsSlow"].Value
    
    if (bSlow) {
        DetectHiddenText False
        ovVisText := WinGetText()
        DetectHiddenText True
        ovAllText := WinGetText()
    } else {
        ovVisText := WinGetTextFast(false)
        ovAllText := WinGetTextFast(true)
    }
    
    UpdateText("Ctrl_VisText", ovVisText)
    UpdateText("Ctrl_AllText", ovAllText)
}

WinGetTextFast(detect_hidden) {    
    controls := WinGetControlsHwnd()
    static WINDOW_TEXT_SIZE := 32767
    buf := Buffer(WINDOW_TEXT_SIZE * 2, 0)
    text := ""
    
    Loop controls.Length {
        hCtl := controls[A_Index]
        if !detect_hidden && !DllCall("IsWindowVisible", "ptr", hCtl)
            continue
        if !DllCall("GetWindowText", "ptr", hCtl, "Ptr", buf.ptr, "int", WINDOW_TEXT_SIZE)
            continue
        text .= StrGet(buf) "`r`n"
    }
    return text
}

UpdateText(vCtl, NewText) {
    Global oGui
    static OldText := {}
    ctl := oGui[vCtl], hCtl := Integer(ctl.hwnd)
    
    if (!oldText.HasProp(hCtl) Or OldText.%hCtl% != NewText) {
        ctl.Value := NewText
        OldText.%hCtl% := NewText
    }
}

textMangle(x) {
    elli := false
    if (pos := InStr(x, "`n"))
        x := SubStr(x, 1, pos-1), elli := true
    else if (StrLen(x) > 40)
        x := SubStr(x, 1, 40), elli := true
    if elli
        x .= " (...)"
    return x
}

suspend_timer() {
    Global oGui
    SetTimer Update, 0
    UpdateText("Ctrl_Freeze", oGui.txtFrozen)
}

~*Shift::
~*Ctrl::suspend_timer()

~*Ctrl up::
~*Shift up::SetTimer Update, 250
