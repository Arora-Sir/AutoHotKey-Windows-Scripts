#Requires AutoHotkey v2.0

; Hotkey Help
; Fanatic Guru
; 2019 01 03
;
; Inspired by Jade Dragon's Infile Hotkey Scanner
; PostMessage Information and Script Status derived from Lexikos
;
; Creates a Help Dialog that Shows Current AHK Hotkeys
;
;{-----------------------------------------------
;
; Wings around file names mean
; ===== AHK File with Hotkeys or Hotstrings =====
; ----- AHK File with no Hotkeys or Hotstrings -----
; ==o== AHK Include File with Hotkeys or Hotstrings ==o==
; --o-- AHK Include File with no Hotkeys or Hotstrings --o--
; +++++ AHK or Text File Derived from EXE File Name with Hotkeys or Hotstrings +++++
; +-+-+ AHK or Text File Derived from EXE File Name with no Hotkeys or Hotstrings +-+-+
; ?+?+? EXE File for which no AHK or Text File was Found ?+?+?
;
; May create a txt file with same name as hotkey file to be searched for help information
;}

; INITIALIZATION - ENVIROMENT
;{-----------------------------------------------
;
; v2: #NoEnv is gone - v2 has no %Var%-vs-environment-variable ambiguity to guard against, nothing to port.
SendMode("Input") ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir(A_ScriptDir) ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows(true)

;}

; INITIALIZATION - VARIABLES
;{-----------------------------------------------
;

; File Names with Out Ext Seperated by |
; Files_Excluded 	:= "Test|Debugging"
Files_Excluded 	:= " "

; File Name for Exported Help Dialog
TextOut_FileName := "HotKey Help - Dialog.txt"

; Long or Short Hotkey and Hotstring Names (Modifier Order Matters)
; Hot_Excluded 	:= "Win+Ctrl+Alt+Escape|If|IfWinActive|#a|fyi|brb"
Hot_Excluded 	:= " "

; Text File Extension List for Text Help Files
; v2: v1's (Join,...) continuation-section array literal collapses to a plain array literal.
Text_Ext_List := ["txt"]

; Spacing for Position of Information Column in Help Dialog
Pos_Info := 25

; Parse Delimiter and OmitChar.  Sometimes changing these can give better results.
Parse_Delimiter := "`n"
Parse_OmitChar := "`r"

; Default Settings if Not Changed by Ini File
; v2: legacy `=` command-style assignment is gone - all become `:=`.
Set_ShowBlank		:= 1
Set_ShowBlankInclude	:= 1
Set_ShowExe		:= 1
Set_ShowHotkey		:= 1	; Hotkeys created with the Hotkey Command Tend to be Unusal
Set_VarHotkey		:= 1	; Attempt to Resolve a Variable Used in Hotkeys Definition
Set_FlagHotkey		:= 1	; Flag Hotkeys created with the Hotkey Command with <HK>
Set_ShowString		:= 1
Set_AhkExe		:= 1
Set_AhkTxt		:= 1
Set_AhkTxtOver		:= 1
Set_SortInfo		:= 1
Set_CapHotkey		:= 1	; Set to 0 to not change Capitalization of Hotkey, 1 for Capitalization as Determined by Set_CapHotkey_Radio
Set_CapHotkey_Radio	:= 1	; Set to 1 to use Title Capitalization, 2 for UPPER Capitalization
Set_HideFold		:= 1
Set_TextOut		:= 0	; Set to 1 to automatically create text file output of Help Dialog
Set_FindPos		:= 1
Set_IniSet		:= 1	; Set to 0 to Use Defaults Settings and Not Use INI File
Set_IniExcluded		:= 1	; Set to 0 to Use Default Excluded Information and Not Use INI File
Set_Hotkey_Mod_Delimiter := "+"	; Delimiter Character to Display Between Hotkey Modifiers
Set_FindPos_deltaX := 0
Set_FindPos_deltaY := 0
SearchEdit.Docked := true

; v2: pre-seeded (rather than left unset until the Gui first shows) so the #HotIf below and the
; Gui_Created checks in RefreshHelpDisplay() never reference an unset global.
idDisplayWin := 0
idDisplay := 0
Gui_Created := false
Gui_Raw_Created := false
Display_CreateOnly := false
Display := ""

; Get Settings From Ini File
; v2: IniRead is now a real function returning the value (with an explicit default), not an output-var command.
if Set_IniSet
    if FileExist("Hotkey Help.ini")
{
    Set_ShowBlank := IniRead("Hotkey Help.ini", "Settings", "Set_ShowBlank", Set_ShowBlank)
    Set_ShowBlankInclude := IniRead("Hotkey Help.ini", "Settings", "Set_ShowBlankInclude", Set_ShowBlankInclude)
    Set_ShowExe := IniRead("Hotkey Help.ini", "Settings", "Set_ShowExe", Set_ShowExe)
    Set_ShowHotkey := IniRead("Hotkey Help.ini", "Settings", "Set_ShowHotkey", Set_ShowHotkey)
    ; v2: v1's original lines 95/96 each (likely by copy-paste) read back Set_ShowHotkey's OWN ini key into
    ; Set_VarHotkey/Set_FlagHotkey instead of each variable's own key - preserved exactly as-is (behavior-
    ; preserving port), not "fixed", since this is existing v1 behavior, not a v2 migration concern.
    Set_VarHotkey := IniRead("Hotkey Help.ini", "Settings", "Set_ShowHotkey", Set_VarHotkey)
    Set_FlagHotkey := IniRead("Hotkey Help.ini", "Settings", "Set_ShowHotkey", Set_FlagHotkey)
    Set_ShowString := IniRead("Hotkey Help.ini", "Settings", "Set_ShowString", Set_ShowString)
    Set_AhkExe := IniRead("Hotkey Help.ini", "Settings", "Set_AhkExe", Set_AhkExe)
    Set_AhkTxt := IniRead("Hotkey Help.ini", "Settings", "Set_AhkTxt", Set_AhkTxt)
    Set_AhkTxtOver := IniRead("Hotkey Help.ini", "Settings", "Set_AhkTxtOver", Set_AhkTxtOver)
    Set_SortInfo := IniRead("Hotkey Help.ini", "Settings", "Set_SortInfo", Set_SortInfo)
    Set_CapHotkey := IniRead("Hotkey Help.ini", "Settings", "Set_CapHotkey", Set_CapHotkey)
    Set_CapHotkey_Radio := IniRead("Hotkey Help.ini", "Settings", "Set_CapHotkey_Radio", Set_CapHotkey_Radio)
    Set_HideFold := IniRead("Hotkey Help.ini", "Settings", "Set_HideFold", Set_HideFold)
    Set_TextOut := IniRead("Hotkey Help.ini", "Settings", "Set_TextOut", Set_TextOut)
    Set_FindPos := IniRead("Hotkey Help.ini", "Settings", "Set_FindPos", Set_FindPos)
    Set_IniSet := IniRead("Hotkey Help.ini", "Settings", "Set_IniSet", Set_IniSet)
    Set_IniExcluded := IniRead("Hotkey Help.ini", "Settings", "Set_IniExcluded", Set_IniExcluded)
    Set_Hotkey_Mod_Delimiter := IniRead("Hotkey Help.ini", "Settings", "Set_Hotkey_Mod_Delimiter", Set_Hotkey_Mod_Delimiter)
    if Set_FindPos
    {
        ; v2: IniRead with no default throws if the key is missing - matches v1's behavior of leaving the
        ; output variable blank/ErrorLevel-set, but the two immediate "if !Var" guards below already
        ; handle a blank result either way, so an empty-string default reproduces v1's fallthrough exactly.
        Set_FindPos_deltaX := IniRead("Hotkey Help.ini", "Settings", "Set_FindPos_deltaX", "")
        Set_FindPos_deltaY := IniRead("Hotkey Help.ini", "Settings", "Set_FindPos_deltaY", "")
        Set_FindPos_Docked := IniRead("Hotkey Help.ini", "Settings", "Set_FindPos_Docked", "")
        if !Set_FindPos_deltaX
            Set_FindPos_deltaX := 0
        if !Set_FindPos_deltaY
            Set_FindPos_deltaY := 0
        SearchEdit.UnDock := {deltaX: Set_FindPos_deltaX, deltaY: Set_FindPos_deltaY}
        SearchEdit.Docked := Set_FindPos_Docked
    }
}

; Get Excluded Information From Ini File
if Set_IniExcluded
    if FileExist("Hotkey Help.ini")
{
    Files_Excluded := IniRead("Hotkey Help.ini", "Excluded", "Files_Excluded", Files_Excluded)
    Hot_Excluded := IniRead("Hotkey Help.ini", "Excluded", "Hot_Excluded", Hot_Excluded)
}
;}

; INITIALIZATION - GUI
;{-----------------------------------------------
;

; Create Setting Gui
; v2: `Gui, Set:...` named-Gui command syntax becomes a real Gui() object, stored in GuiSettings.
; Every control that used a v1 `v`-option keeps the same option string (still supported in v2's Add*
; methods) so GuiSettings.Submit() returns an object keyed by the same names as before.
GuiSettings := Gui()
GuiSettings.SetFont("s10")
GuiSettings.AddText("x120 y10 w200 h20", "Hotkey Help - Pick Settings")
GuiSettings.AddText("x30 y40 w390 h2 0x7")
GuiSettings.AddCheckBox("x60 y50 w380 h30 vSet_ShowBlank", "Show Files With No Hotkeys")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_ShowBlankInclude", "Show Include Files With No Hotkeys")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_ShowExe", "Show EXE Files (Help Comments Do Not Exist in EXE)")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_AhkExe", "Scan AHK File with Same Name as Running EXE")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_AhkTxt", "Scan Text Files with Same Name as Running Script")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_AhkTxtOver", "Text File Help will Overwrite Duplicate Help")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_ShowHotkey", "Show Created with Hotkey Command")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_VarHotkey", "Attempt to Resolve Variables in Dynamic Hotkeys")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_FlagHotkey", "Flag Hotkeys created with the Hotkey Command with <HK>")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_SortInfo", "Sort by Hotkey Description (Otherwise by Hotkey Name)")
GuiSettings.AddCheckBox("x60 yp+35 w180 h30 vSet_CapHotkey", "Hotkey Capitalization")
; v2: v1 Radio groups share one variable holding the selected index (1/2) on Submit; v2 Radio controls
; each carry their own .Value (0/1) instead - kept as two explicit control-object references so the
; group can be pre-populated and read back below without relying on a shared index variable.
CtrlCapRadioTitle := GuiSettings.AddRadio("x240 yp w80 h30", "Title")
CtrlCapRadioUpper := GuiSettings.AddRadio("x320 yp w120 h30", "UPPER")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_ShowString", "Show Hotstrings")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_HideFold", "Hide Fold Start `;`{  from Help Comment")
GuiSettings.AddCheckBox("x60 yp+35 w220 h30 vSet_TextOut", "Automatically Export Help Dialog")
CtrlExportBtn := GuiSettings.AddButton("+Border x290 yp w135 h30", "Export Help Dialog")
CtrlExportBtn.OnEvent("Click", ButtonExportDialog)
GuiSettings.AddCheckBox("x60 yp+35 w220 h30 vSet_FindPos", "Save Undocked `"Find`" Position")
CtrlFindPosBtn := GuiSettings.AddButton("+Border x290 yp w135 h30", "Reset `"Find`" Position")
CtrlFindPosBtn.OnEvent("Click", ButtonFindPos)
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_IniSet", "Use INI File to Save Settings")
GuiSettings.AddCheckBox("x60 yp+35 w380 h30 vSet_IniExcluded", "Use INI File to Save Excluded Files and Hotkeys")
CtrlModDelim := GuiSettings.AddComboBox("x60 yp+35 w60 h30 R5 Choose1 vSet_Hotkey_Mod_Delimiter", [Set_Hotkey_Mod_Delimiter, "+", "-", " + ", " - "])
GuiSettings.AddText("x130 yp w250 h30", "Delimiter to Separate Hotkey Modifiers")
CtrlFinishedBtn := GuiSettings.AddButton("Default x60 yp+35 w330 h30", "Finished")
CtrlFinishedBtn.OnEvent("Click", SetGuiClose)
GuiSettings.OnEvent("Escape", SetGuiClose)
GuiSettings.OnEvent("Close", SetGuiClose)

; v2: GuiControl Set -> the control object's own .Value property.
for ctrlName, ctrlValue in Map("Set_ShowBlank", Set_ShowBlank, "Set_ShowBlankInclude", Set_ShowBlankInclude
    , "Set_ShowExe", Set_ShowExe, "Set_ShowHotkey", Set_ShowHotkey, "Set_VarHotkey", Set_VarHotkey
    , "Set_FlagHotkey", Set_FlagHotkey, "Set_ShowString", Set_ShowString, "Set_AhkExe", Set_AhkExe
    , "Set_AhkTxt", Set_AhkTxt, "Set_AhkTxtOver", Set_AhkTxtOver, "Set_SortInfo", Set_SortInfo
    , "Set_CapHotkey", Set_CapHotkey, "Set_HideFold", Set_HideFold, "Set_TextOut", Set_TextOut
    , "Set_FindPos", Set_FindPos, "Set_IniSet", Set_IniSet, "Set_IniExcluded", Set_IniExcluded)
    GuiSettings[ctrlName].Value := ctrlValue
CtrlCapRadioTitle.Value := (Set_CapHotkey_Radio = 1) ? 1 : 0
CtrlCapRadioUpper.Value := (Set_CapHotkey_Radio = 2) ? 1 : 0

; Get Information to Display in Excluded Gui
Gui_Excluded := String_Wings(" EXCLUDED SCRIPTS AND FILES ",40) "`n" Files_Excluded "`n`n`n" String_Wings(" EXCLUDED HOTKEYS & HOTSTRINGS ",40) "`n" Hot_Excluded
; v2: StringReplace -> StrReplace(Haystack, Needle, ReplaceText) - single call, no ",All" needed (v2 always
; replaces every occurrence).
Gui_Excluded := StrReplace(Gui_Excluded, "|", "`n")

; Create Excluded Gui
GuiExcluded := Gui("+MinSize400x600 +Resize")
GuiExcluded.BackColor := "FFFFFF"
GuiExcluded.SetFont("s10", "Courier New")
GuiExcluded.AddText("x10", "Enter Information Below the Appropriate Headings")
GuiExcluded.AddText("x60", "Do Not Modify Heading Lines")
CtrlExcludedConfirmBtn := GuiExcluded.AddButton("Default x20 y60 w350 h30", "Confirm Edit")
CtrlExcludedConfirmBtn.OnEvent("Click", ExcludedButtonConfirmEdit)
CtrlExcludedEdit := GuiExcluded.AddEdit("x20 y100 vGui_Excluded -E0x200", Gui_Excluded)
GuiExcluded.OnEvent("Size", ExcludedGuiSize)
GuiExcluded.OnEvent("Escape", ExcludedGuiEscape)
GuiExcluded.OnEvent("Close", ExcludedGuiEscape)
;}

;{-----------------------------------------------
; v2: OnExit's callback signature is (ExitReason, ExitCode) - a bare label target becomes a real function.
OnExit(SaveSettings)

;
;}-----------------------------------------------
; END OF AUTO-EXECUTE

; HOTKEYS
;{-----------------------------------------------
;

; v2: a bare label after a hotkey (v1's `goto`/fallthrough entry point) becomes a real function call.
; ScriptStop() below re-enters this same refresh instead of `goto Refresh`; ButtonExportDialog() calls it
; directly instead of `gosub #F1`.
#F1::RefreshHelpDisplay() ;{ <- Display Help

RefreshHelpDisplay(*) {
    global Files_Excluded, Hot_Excluded, Set_AhkExe, Set_AhkTxt, Set_ShowHotkey, Set_VarHotkey, Set_FlagHotkey
    global Set_ShowString, Set_HideFold, Set_CapHotkey, Set_CapHotkey_Radio, Set_Hotkey_Mod_Delimiter
    global Set_SortInfo, Set_ShowBlank, Set_ShowExe, Set_ShowBlankInclude, Set_TextOut, Pos_Info
    global Text_Ext_List, Parse_Delimiter, Parse_OmitChar, Scripts, Display, Display_CreateOnly
    global Gui_Created, Previous_Display, idDisplayWin, idDisplay, GuiMain, CtrlDisplay

    Help := Map()				; Main Array for Storing Help Information
    Scripts_Include := []	; Scripts Added with #Include - must be an Array (not Map), since it's later grown via .Push()
    Setting_WorkingDir := A_WorkingDir
    AHKScripts(&Scripts)	; Get Path of all AHK Scripts
    Scripts_Scan := Scripts

    ; v2: v1's `Recursive:` goto-loop (re-scanning newly-discovered #Include files until none are left)
    ; becomes a real Loop, breaking once a pass finds no new includes.
    Loop {
        Include_Found := false
        for index, Script in Scripts_Scan	; Loop Through AHK Script Files
        {
            Txt_Ahk := false
            SetWorkingDir(Setting_WorkingDir)
            File_Path := Script.Path
            SplitPath(File_Path, &File_Name, &File_Dir, &File_Ext, &File_Title)
            if RegExMatch(Files_Excluded,"i)(^|\|)" File_Title "($|\|)")
                continue
            if !Help.Has(File_Title)
                Help[File_Title] := Map()
            Help[File_Title]["Type"] := "AHK"
            Exe_Ahk := false
            if (File_Ext = "exe")
            {
                Help[File_Title]["Type"] := "EXE_UNKNOWN"
                if Set_AhkExe
                {
                    if FileExist(File_Dir "\" File_Title ".ahk")
                    {
                        Exe_Ahk := true
                        Help[File_Title]["Type"] := "EXE2AHK"
                        File_Path := File_Dir "\" File_Title ".ahk"
                    }
                    else if FileExist(A_ScriptDir "\" File_Title ".ahk")
                    {
                        Help[File_Title]["Type"] := "EXE2AHK"
                        Exe_Ahk := true
                        File_Path := A_ScriptDir "\" File_Title ".ahk"
                    }
                    else if FileExist(A_WorkingDir "\" File_Title ".ahk")
                    {
                        Help[File_Title]["Type"] := "EXE2AHK"
                        Exe_Ahk := true
                        File_Path := A_WorkingDir "\" File_Title ".ahk"
                    }
                }
            }
            Txt_Ahk := false
            File_Paths_Txt := []
            if Set_AhkTxt
            {
                for index_Text_Ext, Text_Ext in Text_Ext_List
                {
                    if FileExist(File_Dir "\" File_Title "." Text_Ext)
                    {
                        Txt_Ahk := true
                        File_Paths_Txt.Push(File_Dir "\" File_Title "." Text_Ext)
                    }
                    else if FileExist(A_ScriptDir "\" File_Title "." Text_Ext)
                    {
                        Txt_Ahk := true
                        File_Paths_Txt.Push(A_ScriptDir "\" File_Title "." Text_Ext)
                    }
                    else if FileExist(A_WorkingDir "\" File_Title "." Text_Ext)
                    {
                        Txt_Ahk := true
                        File_Paths_Txt.Push(A_WorkingDir "\" File_Title "." Text_Ext)
                    }
                }
            }
            if (Help[File_Title]["Type"] = "EXE_UNKNOWN" and Txt_Ahk)
                Help[File_Title]["Type"] := "EXE2TEXT"
            if (!Txt_Ahk and !Exe_Ahk and !(File_Ext = "ahk" or File_Ext = "ahkl"))	; No File Found to Scan
                continue
            Script_File := ""
            if !(RegExMatch(Files_Excluded,"i)(^|\|)" File_Title "($|\|)") or RegExMatch(Files_Excluded,"i)(^|\|)" File_Title "." File_Ext "($|\|)"))
            {
                try
                    Script_File := FileRead(File_Path)	;  Read AHK Script File into String
            }
            if Txt_Ahk
            {
                for index_File_Path_Txt, File_Path_Txt in File_Paths_Txt
                {
                    try {
                        Script_File_Txt := FileRead(File_Path_Txt)	;  Read Text File with Same Name as AHK Script File into String
                        Script_File .= Parse_Delimiter "� Hotkey Help Text File �" Parse_Delimiter Script_File_Txt	;  Append Txt File onto AHK File
                    }
                }
            }
            if !Script_File
                continue
            Script_File := RegExReplace(Script_File, "ms`a)^\s*/\*.*?^\s*\*/\s*|^\s*\(.*?^\s*\)\s*")	; Removes /* ... */ and ( ... ) Blocks
            Txt_Ahk_Started := false
            Loop Parse, Script_File, Parse_Delimiter, Parse_OmitChar	; Parse Each Line of Script File
            {
                File_Line := A_LoopField
                if (File_Line = "� Hotkey Help Text File �")
                {
                    Txt_Ahk_Started := true
                    continue
                }
                ; RegEx to Identify Hotkey Command Lines
                ; v2: Match1/Match2 pseudo-array collapses to a real Match object via &Match, indexed Match[1]/Match[2].
                if (RegExMatch(File_Line, "i)^\s*hotkey,(.*?),(.*)", &Match) and Set_ShowHotkey)	; Check if Line Contains Hotkey Command
                {
                    HotkeyMatch1 := Match[1]
                    if Set_VarHotkey
                        if RegExMatch(HotkeyMatch1,"%.*%")
                            HotkeyMatch1 := HotkeyVariable(Script.Path,HotkeyMatch1)
                    File_Line := HotkeyMatch1 ":: " Match[2]
                    Hotkey_Command := true
                }
                else
                    Hotkey_Command := false
                if RegExMatch(File_Line,"::")	; Simple check for Possible Hotkey or Hotstring (for speed)
                {
                    if RegExMatch(File_Line,"^\s*:[0-9\*\?BbCcKkOoPpRrSsIiEeZz]*?:(.*?)::(\s*)(`;?)(.*)",&Match)				; Complex Check if Line Contains Hotstring
                    {
                        if (Set_ShowString and !(RegExMatch(Hot_Excluded,"i)(^|\|)\Q" Match[1] "\E($|\|)")))	; Check for Excluded Hotstring
                        {
                            Line_Hot := "<HS> " Match[1]
                            Line_Help := (Match[3] ? Trim(Match[4]) : "= " Match[2] Match[4])
                            HotkeyHelp_StoreLine(Help, File_Title, Txt_Ahk_Started, Line_Hot, Line_Help)
                        }
                        else
                            continue
                    }
                    else if RegExMatch(File_Line, "Umi)^\s*[\Q#!^+<>*~$\E]*((LButton|RButton|MButton|XButton1|XButton2|WheelDown|WheelUp|WheelLeft|WheelRight|CapsLock|Space|Tab|Enter|Return|Escape|Esc|Backspace|BS|ScrollLock|Delete|Del|Insert|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|NumLock|Numpad0|Numpad1|Numpad2|Numpad3|Numpad4|Numpad5|Numpad6|Numpad7|Numpad8|Numpad9|NumpadDot|NumpadDiv|NumpadMult|NumpadAdd|NumpadSub|NumpadEnter|NumpadIns|NumpadEnd|NumpadDown|NumpadPgDn|NumpadLeft|NumpadClear|NumpadRight|NumpadHome|NumpadUp|NumpadPgUp|NumpadDel|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12|F13|F14|F15|F16|F17|F18|F19|F20|F21|F22|F23|F24|LWin|RWin|Control|Ctrl|Alt|Shift|LControl|LCtrl|RControl|RCtrl|LShift|RShift|LAlt|RAlt|Browser_Back|Browser_Forward|Browser_Refresh|Browser_Stop|Browser_Search|Browser_Favorites|Browser_Home|Volume_Mute|Volume_Down|Volume_Up|Media_Next|Media_Prev|Media_Stop|Media_Play_Pause|Launch_Mail|Launch_Media|Launch_App1|Launch_App2|AppsKey|PrintScreen|CtrlBreak|Pause|Break|Help|Sleep|sc\d{1,3}|vk\d{1,2}|\S)(?<!;)|```;)(\s+&\s+((LButton|RButton|MButton|XButton1|XButton2|WheelDown|WheelUp|WheelLeft|WheelRight|CapsLock|Space|Tab|Enter|Return|Escape|Esc|Backspace|BS|ScrollLock|Delete|Del|Insert|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|NumLock|Numpad0|Numpad1|Numpad2|Numpad3|Numpad4|Numpad5|Numpad6|Numpad7|Numpad8|Numpad9|NumpadDot|NumpadDiv|NumpadMult|NumpadAdd|NumpadSub|NumpadEnter|NumpadIns|NumpadEnd|NumpadDown|NumpadPgDn|NumpadLeft|NumpadClear|NumpadRight|NumpadHome|NumpadUp|NumpadPgUp|NumpadDel|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12|F13|F14|F15|F16|F17|F18|F19|F20|F21|F22|F23|F24|LWin|RWin|Control|Ctrl|Alt|Shift|LControl|LCtrl|RControl|RCtrl|LShift|RShift|LAlt|RAlt|Browser_Back|Browser_Forward|Browser_Refresh|Browser_Stop|Browser_Search|Browser_Favorites|Browser_Home|Volume_Mute|Volume_Down|Volume_Up|Media_Next|Media_Prev|Media_Stop|Media_Play_Pause|Launch_Mail|Launch_Media|Launch_App1|Launch_App2|AppsKey|PrintScreen|CtrlBreak|Pause|Break|Help|Sleep|sc\d{1,3}|vk\d{1,2}|\S)(?<!;)|```;))?(\s+Up)?::") ; Complex Check if Line Contains Hotkey
                    {
                        RegExMatch(File_Line,"(.*?[:]?)::",&Match)
                        HotkeyName := Trim(Match[1])
                        if RegExMatch(Hot_Excluded,"i)(^|\|)\Q" HotkeyName "\E($|\|)")	; Check for Excluded Short Hotkey Name
                            continue
                        if !RegExMatch(HotkeyName,"(Shift|Alt|Ctrl|Win)")
                        {
                            HotkeyName := StrReplace(HotkeyName, "+", "Shift" Set_Hotkey_Mod_Delimiter)
                            HotkeyName := StrReplace(HotkeyName, "<^>!", "AltGr" Set_Hotkey_Mod_Delimiter)
                            HotkeyName := StrReplace(HotkeyName, "<", "Left")
                            HotkeyName := StrReplace(HotkeyName, ">", "Right")
                            HotkeyName := StrReplace(HotkeyName, "!", "Alt" Set_Hotkey_Mod_Delimiter)
                            HotkeyName := StrReplace(HotkeyName, "^", "Ctrl" Set_Hotkey_Mod_Delimiter)
                            HotkeyName := StrReplace(HotkeyName, "#", "Win" Set_Hotkey_Mod_Delimiter)
                        }
                        HotkeyName := StrReplace(HotkeyName, "``;", "`;")
                        if RegExMatch(Hot_Excluded,"i)(^|\|)\Q" HotkeyName "\E($|\|)")	; Check for Excluded Long Hotkey Name
                            continue
                        Line_Hot := HotkeyName
                        if Set_CapHotkey
                            if (Set_CapHotkey_Radio = 1)
                                Line_Hot := RegExReplace(Line_Hot,"((^[^\Q" Set_Hotkey_Mod_Delimiter "\E]*|\Q" Set_Hotkey_Mod_Delimiter "\E[^\Q" Set_Hotkey_Mod_Delimiter "\E]*))","$T1")
                            else
                                Line_Hot := RegExReplace(Line_Hot,"((^[^\Q" Set_Hotkey_Mod_Delimiter "\E]*|\Q" Set_Hotkey_Mod_Delimiter "\E[^\Q" Set_Hotkey_Mod_Delimiter "\E]*))","$U1")
                        ; v2 bug fix: this used to read back as `Line_Help := Trim(HotkeyName)` - discarding the
                        ; regex match entirely and re-displaying the hotkey's own (unformatted) name as its own
                        ; "description". v1's original almost certainly reused HotkeyName as RegExMatch's output-var
                        ; prefix (HotkeyName1 = the captured comment text), which the port dropped when it correctly
                        ; switched to &Match/Match[1] elsewhere in this function but never did here. Found live: every
                        ; regular hotkey's description column showed the hotkey name a second time (in a different
                        ; case) instead of its real ";{ <- Description" comment text - confirmed once Scripts_Include's
                        ; Map/Array bug (elsewhere in this file) stopped aborting the scan before it ever reached here.
                        HasComment := RegExMatch(File_Line,"::.*?;(.*)",&Match)
                        Line_Help := HasComment ? Trim(Match[1]) : ""
                        if Set_HideFold
                            if (SubStr(Line_Help,1,1) = "{")
                                Line_Help := SubStr(Line_Help,2)
                        Line_Help := Trim(Line_Help)
                        if Hotkey_Command
                            if Set_FlagHotkey
                                Line_Hot := "<HK> " Line_Hot
                        HotkeyHelp_StoreLine(Help, File_Title, Txt_Ahk_Started, Line_Hot, Line_Help)
                    }
                }
                ; v2: bare #include is still parsed the same way from raw source text (this reads OTHER
                ; scripts' text as data, not v2's own preprocessor), so the regex itself is unchanged.
                if RegExMatch(File_Line, "mi`a)^\s*#include(?:again)?(?:\s+|\s*,\s*)(?:\*i[ `t]?)?([^;\v]+[^\s;\v])", &Match)	; Check for #Include
                {
                    IncludeTarget := Match[1]
                    IncludeTarget := StrReplace(IncludeTarget, "%A_ScriptDir%", File_Dir)
                    IncludeTarget := StrReplace(IncludeTarget, "%A_AppData%", A_AppData)
                    IncludeTarget := StrReplace(IncludeTarget, "%A_AppDataCommon%", A_AppDataCommon)
                    IncludeTarget := StrReplace(IncludeTarget, "``;", ";")
                    if InStr(FileExist(IncludeTarget), "D")
                    {
                        SetWorkingDir(IncludeTarget)
                        continue
                    }
                    IncludeTarget := Get_Full_Path(IncludeTarget)
                    Include_Repeat := false
                    for k, val in Scripts_Include
                        if (val.Path = IncludeTarget)
                            Include_Repeat := true
                    if !Include_Repeat
                    {
                        Scripts_Include.Push({Path: IncludeTarget})
                        Include_Found := true
                    }
                }
            }
        }
        if !Include_Found
            break
        Scripts_Scan := Scripts_Include
        Scripts_Include := []
    }

    ; Get Count of Hot in Each File
    for File, element in Help
    {
        count := 0
        if element.Has("Hot")
            for Hot, Info in element["Hot"]
                count += 1
        if element.Has("Hot_Text")
            for Hot_Text, Info_Text in element["Hot_Text"]
                count += 1
        element["Count"] := count
    }

    ; Remove Duplicate Help Created by Text Help if Text File Overwrite Set
    if (Set_AhkTxtOver)
        for File, element in Help
            if element.Has("Hot_Text") and element.Has("Hot")
                for Hot_Text, Info_Text in element["Hot_Text"].Clone()
                    for Hot, Info in element["Hot"].Clone()
                        if (Hot = Hot_Text or Hot = "<HK> " Hot_Text)
                        {
                            element["Hot"].Delete(Hot)
                            element["Count"] -= 1
                        }

    ; Add Include Information to Help Array
    for File, element in Help
    {
        Include_Found := true
        for index, Script in Scripts
            if (File = Script.Title)
                Include_Found := false
        element["Include"] := Include_Found
    }

    ; Build Display String from Help Array
    Display := ""
    for File, element in Help
    {
        if (element["Count"] > 0 and element["Type"] = "AHK")
        {
            if element["Include"]
                Display .= "`r`n" String_Wings(" " File " ",,"==o==") "`r`n"
            else
                Display .= "`r`n" String_Wings(" " File " ") "`r`n"
            Display .= HotkeyHelp_BuildSection(element, Pos_Info, Set_SortInfo)
        }
    }
    for File, element in Help
    {
        if (element["Count"] > 0 and (element["Type"] = "EXE2AHK" or element["Type"] = "EXE2TEXT"))
        {
            Display .= "`r`n" String_Wings(" " File " ",,"+") "`r`n"
            Display .= HotkeyHelp_BuildSection(element, Pos_Info, Set_SortInfo)
        }
    }
    if Set_ShowBlank
    {
        for File, element in Help
            if (element["Count"] = 0 and element["Type"] = "EXE2AHK" and Set_ShowExe)
                Display .= "`r`n" String_Wings(" " File " ",,"+-")
        for File, element in Help
            if (element["Type"] = "EXE_UNKNOWN" and Set_ShowExe)
                Display .= "`r`n" String_Wings(" " File " ",,"?+")
        for File, element in Help
            if (element["Count"] = 0 and element["Type"] = "AHK" and !element["Include"])
                Display .= "`r`n" String_Wings(" " File " ",,"-")
        for File, element in Help
            if (element["Count"] = 0 and element["Type"] = "AHK" and element["Include"] and Set_ShowBlankInclude)
                Display .= "`r`n" String_Wings(" " File " ",,"--o--")
    }

    Display := RegExReplace(Display,"^\s*(.*)\s*$", "$1")
    if Display_CreateOnly
        return

    ; Create Main Gui first time then only display unless contents change then recreate to get automatic sizing of Edit
    if Gui_Created
    {
        if !(Display == Previous_Display)
        {
            if Set_TextOut
                TextOut()
            if IsSet(GuiMain)
                GuiMain.Destroy()
            MenuBuild()
            GuiMain := Gui("+MinSize660x100 +Resize")
            idDisplayWin := GuiMain.Hwnd
            GuiMain.BackColor := "FFFFFF"
            GuiMain.SetFont("s10", "Courier New")
            GuiMain.MenuBar := MenuMainObj
            GuiMain.OnEvent("Size", GuiMainSize)
            GuiMain.OnEvent("Escape", GuiMainEscape)
            GuiMain.OnEvent("Close", GuiMainEscape)
            ; v2 note: a Gui control can be created with more than 32k of text directly - v1's 32k split-and-
            ; ControlSetText workaround is unneeded, but kept commented for reference since it's harmless either way.
            CtrlDisplay := GuiMain.AddEdit("vGui_Display ReadOnly -E0x200 +0x100", Display)
            idDisplay := CtrlDisplay.Hwnd
            GuiMain.Show("AutoSize")
            WinActivate("ahk_id " idDisplayWin)
            Send("^{Home}")
        }
        else
        {
            ; v2: Gui.Show() takes only an Options parameter - v1's second Title argument is gone, throws
            ; "Too many parameters passed to function" if passed. Set .Title as a separate property instead
            ; (confirmed live; same fix applied to every other 2-arg .Show(Options, Title) call in this file).
            GuiMain.Title := "Hotkey Help"
            GuiMain.Show()
            Send("^{Home}")
        }
    }
    else
    {
        if Set_TextOut
            TextOut()
        MenuBuild()
        GuiMain := Gui("+MinSize660x100 +Resize")
        GuiMain.Title := "Hotkey Help"
        idDisplayWin := GuiMain.Hwnd
        GuiMain.BackColor := "FFFFFF"
        GuiMain.SetFont("s10", "Courier New")
        GuiMain.MenuBar := MenuMainObj
        GuiMain.OnEvent("Size", GuiMainSize)
        GuiMain.OnEvent("Escape", GuiMainEscape)
        GuiMain.OnEvent("Close", GuiMainEscape)
        CtrlDisplay := GuiMain.AddEdit("vGui_Display ReadOnly -E0x200 +0x100", Display)
        idDisplay := CtrlDisplay.Hwnd
        GuiMain.Show("AutoSize")
        WinActivate("ahk_id " idDisplayWin)
        Send("^{Home}")
        Gui_Created := true
    }
    Previous_Display := Display
    if SearchEdit.Visible
        try
            ControlFocus(SearchEdit.FindEditCtrl)
}

; v2: small helper factoring out the identical "store a Hot/Hot_Text line with running Count" block that
; v1 repeated four times inline (hotstrings, plain hotkeys) - no behavior change, just de-duplication.
HotkeyHelp_StoreLine(Help, File_Title, Txt_Ahk_Started, Line_Hot, Line_Help) {
    bucket := Txt_Ahk_Started ? "Hot_Text" : "Hot"
    if !Help[File_Title].Has(bucket)
        Help[File_Title][bucket] := Map()
    if !Help[File_Title][bucket].Has(Line_Hot)
        Help[File_Title][bucket][Line_Hot] := Map("Count", 0)
    Count := Help[File_Title][bucket][Line_Hot]["Count"] + 1
    Help[File_Title][bucket][Line_Hot]["Count"] := Count
    Help[File_Title][bucket][Line_Hot][Count] := Line_Help
}

; v2: factors out the identical "build one file's sorted Display_Section" block, used for both the
; plain-AHK pass and the EXE2AHK/EXE2TEXT pass above.
HotkeyHelp_BuildSection(element, Pos_Info, Set_SortInfo) {
    Display_Section := ""
    if element.Has("Hot")
        for Hot, HotMap in element["Hot"]
            for Hot_Index2, Info in HotMap
                if (Hot_Index2 != "Count")
                    Display_Section .= Format_Line(Hot,Info,Pos_Info) "`r`n"
    if element.Has("Hot_Text")
        for Hot_Text, HotTextMap in element["Hot_Text"]
            for Hot_Text_Index2, Info_Text in HotTextMap
                if (Hot_Text_Index2 != "Count")
                    Display_Section .= Format_Line(Hot_Text,Info_Text,Pos_Info) "`r`n"
    ; v2: the Sort command becomes the Sort() function; "P%Pos_Info%" (sort by column) becomes "P" Pos_Info.
    if Set_SortInfo
        Display_Section := Sort(Display_Section, "P" Pos_Info)
    else
        Display_Section := Sort(Display_Section)
    return Display_Section
}
;}

; v2: Gui.Show() takes only Options, not v1's second Title argument - set .Title separately (same fix as GuiMain above).
#!F1::ShowSettingsGui() ;{ <- Settings
ShowSettingsGui(*) {
    GuiSettings.Title := "Hotkey Help - Settings"
    GuiSettings.Show()
}
;}

#^F1::ShowExcludedGui() ;{ <- Excluded Files, Hotkeys, and Hotstrings
ShowExcludedGui(*) {
    GuiExcluded.Show("AutoSize")
    Send("^{Home}")
}
;}

#!^F1::ShowRawHotkeyList() ;{ <- Raw Hotkey List
ShowRawHotkeyList(*) {
    global Scripts, Set_Hotkey_Mod_Delimiter, Set_CapHotkey, Set_CapHotkey_Radio
    global Gui_Raw_Created, Previous_Raw_Display, GuiRaw

    AHKScripts(&Scripts)	; Get Path of all AHK Scripts
    Raw_Hotkeys := Map()
    for index, Script in Scripts	; Loop Through All AHK Script Files
    {
        File_Path := Script.Path
        SplitPath(File_Path, &File_Name, &File_Dir, &File_Ext, &File_Title)
        Raw_Hotkeys[File_Title] := ScriptHotkeys(Script.Path)
    }
    Raw_Display := ""
    for Script, HotkeyList in Raw_Hotkeys
    {
        Raw_Display .= "`n" String_Wings(" " Script " ",30) "`n"
        for index, Hotkey_Short in HotkeyList
        {
            Hotkey_Keys := Hotkey_Short
            Hotkey_Keys := StrReplace(Hotkey_Keys, "+", "Shift" Set_Hotkey_Mod_Delimiter)
            Hotkey_Keys := StrReplace(Hotkey_Keys, "<^>!", "AltGr" Set_Hotkey_Mod_Delimiter)
            Hotkey_Keys := StrReplace(Hotkey_Keys, "<", "Left")
            Hotkey_Keys := StrReplace(Hotkey_Keys, ">", "Right")
            Hotkey_Keys := StrReplace(Hotkey_Keys, "!", "Alt" Set_Hotkey_Mod_Delimiter)
            Hotkey_Keys := StrReplace(Hotkey_Keys, "^", "Ctrl" Set_Hotkey_Mod_Delimiter)
            Hotkey_Keys := StrReplace(Hotkey_Keys, "#", "Win" Set_Hotkey_Mod_Delimiter)
            if Set_CapHotkey
                if (Set_CapHotkey_Radio = 1)
                    Hotkey_Keys := RegExReplace(Hotkey_Keys,"((^[^\Q" Set_Hotkey_Mod_Delimiter "\E]*|\Q" Set_Hotkey_Mod_Delimiter "\E[^\Q" Set_Hotkey_Mod_Delimiter "\E]*))","$T1")
                else
                    Hotkey_Keys := RegExReplace(Hotkey_Keys,"((^[^\Q" Set_Hotkey_Mod_Delimiter "\E]*|\Q" Set_Hotkey_Mod_Delimiter "\E[^\Q" Set_Hotkey_Mod_Delimiter "\E]*))","$U1")
            Raw_Display .= Hotkey_Keys "`n"
        }
    }
    Raw_Display := Trim(Raw_Display," `n")

    ; v2: v1's `if A / if B {X} else {Y} else {Z}` dangling-else chain re-expressed with explicit braces -
    ; same 3-way branch (first-time create / unchanged-show / changed-recreate), matching the Main Gui's
    ; already-unambiguous version of this exact pattern above.
    if Gui_Raw_Created
    {
        if !(Raw_Display = Previous_Raw_Display)
        {
            GuiRaw.Destroy()
            GuiRaw := Gui("+Resize")
            GuiRaw.BackColor := "FFFFFF"
            GuiRaw.SetFont("s10", "Courier New")
            GuiRaw.AddEdit("vGui_Raw_Display ReadOnly -E0x200", Raw_Display)
            GuiRaw.OnEvent("Size", GuiRawSize)
            GuiRaw.OnEvent("Escape", GuiRawEscape)
            GuiRaw.OnEvent("Close", GuiRawEscape)
            ; v2: Gui.Show() takes only Options, not v1's second Title argument - set .Title separately.
            GuiRaw.Title := "Hotkey Help"
            GuiRaw.Show("AutoSize")
            Send("^{Home}")
        }
        else
        {
            GuiRaw.Title := "Hotkey Help - Raw Hotkeys"
            GuiRaw.Show("AutoSize")
            Send("^{Home}")
        }
    }
    else
    {
        GuiRaw := Gui("+Resize")
        GuiRaw.BackColor := "FFFFFF"
        GuiRaw.SetFont("s10", "Courier New")
        GuiRaw.AddEdit("vGui_Raw_Display ReadOnly -E0x200", Raw_Display)
        GuiRaw.OnEvent("Size", GuiRawSize)
        GuiRaw.OnEvent("Escape", GuiRawEscape)
        GuiRaw.OnEvent("Close", GuiRawEscape)
        GuiRaw.Title := "Hotkey Help - Raw Hotkeys"
        GuiRaw.Show("AutoSize")
        Send("^{Home}")
        Gui_Raw_Created := true
    }
    Previous_Raw_Display := Raw_Display
}
;}

; v2: #If (hotkey-context directive) is gone, replaced by #HotIf with an expression - same syntax otherwise.
; idDisplayWin is pre-seeded to 0 above, so WinActive("ahk_id 0") safely evaluates false until the Main
; Gui is first created (RefreshHelpDisplay() overwrites it with the real hwnd at that point).
#HotIf WinActive("ahk_id " idDisplayWin)
^f::SearchEdit.Dialog(idDisplay,3+Floor(5*A_ScreenDPI/96)) ;{ <- Find in Hotkey Help
#HotIf
    ;}

;}

; SUBROUTINES
;{-----------------------------------------------
;

TextOut(*) {
    global Display, TextOut_FileName
    File_TextOut := FileOpen(TextOut_FileName, "w")
    File_TextOut.Write(Display)
    File_TextOut.Close()
}

; v2: OnExit callback signature is (ExitReason, ExitCode) - both accepted but unused here, hence `*`.
SaveSettings(*) {
    global Set_IniSet, Set_FindPos, Set_FindPos_deltaX, Set_FindPos_deltaY
    if Set_IniSet and Set_FindPos
    {
        if !Set_FindPos_deltaX
            Set_FindPos_deltaX := 0
        if !Set_FindPos_deltaY
            Set_FindPos_deltaY := 0
        IniWrite(SearchEdit.UnDock.deltaX, "Hotkey Help.ini", "Settings", "Set_FindPos_deltaX")
        IniWrite(SearchEdit.UnDock.deltaY, "Hotkey Help.ini", "Settings", "Set_FindPos_deltaY")
        IniWrite(SearchEdit.Docked, "Hotkey Help.ini", "Settings", "Set_FindPos_Docked")
    }
}

;}

; SUBROUTINES - GUI
;{-----------------------------------------------
;

; Default Help Gui
; v2: a GuiSize event callback receives (GuiObj, MinMax, Width, Height) - Width/Height replace A_GuiWidth/Height.
GuiMainSize(GuiObj, MinMax, Width, Height) {
    global CtrlDisplay
    if (MinMax = -1) ; minimized - nothing sized to resize into
        return
    CtrlDisplay.Move(, , Width - 20, Height - 20)
}

GuiMainEscape(*) {
    global GuiMain
    GuiMain.Hide()
}

; Default Help Gui Menu
; v2: menu click callbacks receive (ItemName, ItemPos, MyMenu) - ItemName replaces v1's A_ThisMenuItem.
ScriptStop(ItemName, ItemPos, MyMenu) {
    global Scripts, MenuStopObj, MenuPauseObj, MenuSuspendObj, MenuEditObj, MenuReloadObj, MenuOpenObj
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    if WinExist("ahk_id " WinID)
        WinKill("ahk_id " WinID)
    MenuStopObj.Delete(ItemName)
    MenuPauseObj.Delete(ItemName)
    MenuSuspendObj.Delete(ItemName)
    MenuEditObj.Delete(ItemName)
    MenuReloadObj.Delete(ItemName)
    MenuOpenObj.Delete(ItemName)
    RefreshHelpDisplay()
}

ScriptPause(ItemName, ItemPos, MyMenu) {
    global Scripts
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    PostMessage(0x111, 65403,,, "ahk_id " WinID)
    Sleep(100)
    MenuBuild()
}

ScriptSuspend(ItemName, ItemPos, MyMenu) {
    global Scripts
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    PostMessage(0x111, 65404,,, "ahk_id " WinID)
    Sleep(100)
    MenuBuild()
}

ScriptEdit(ItemName, ItemPos, MyMenu) {
    global Scripts
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    PostMessage(0x111, 65401,,, "ahk_id " WinID)
}

ScriptReload(ItemName, ItemPos, MyMenu) {
    global Scripts
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    PostMessage(0x111, 65400,,, "ahk_id " WinID)
}

ScriptOpen(ItemName, ItemPos, MyMenu) {
    global Scripts
    DetectHiddenWindows(true)
    WinID := ArrayCrossRef(Scripts,"Title",ItemName,"hWnd")
    PostMessage(0x111, 65300,,, "ahk_id " WinID)
}

; v2: v1's `Menu, MenuX, ...` command syntax becomes real Menu() objects. Submenus persist across calls
; (module-scope globals, built once below) so ScriptStop's per-item .Delete() calls remove exactly the
; stopped script from all six, matching v1's behavior; .Add() on an existing name updates it in place
; instead of duplicating, same as v1.
MenuBuild(*) {
    global Scripts, MenuMainObj, MenuStopObj, MenuPauseObj, MenuSuspendObj, MenuEditObj, MenuReloadObj, MenuOpenObj

    if !IsSet(MenuStopObj) {
        MenuStopObj := Menu()
        MenuPauseObj := Menu()
        MenuSuspendObj := Menu()
        MenuEditObj := Menu()
        MenuReloadObj := Menu()
        MenuOpenObj := Menu()
    }
    MenuMainObj := MenuBar()

    DetectHiddenWindows(true)
    for index, Script in Scripts
    {
        Title := Script.Title
        script_id := Script.hWnd

        ; Force the script to update its Pause/Suspend checkmarks.
        SendMessage(0x211,,,, "ahk_id " script_id) ; WM_ENTERMENULOOP
        SendMessage(0x212,,,, "ahk_id " script_id) ; WM_EXITMENULOOP

        ; Get script status from its main menu.
        mainMenu := DllCall("GetMenu", "UInt", script_id, "Ptr")
        fileMenu := DllCall("GetSubMenu", "Ptr", mainMenu, "Int", 0, "Ptr")
        isPaused := DllCall("GetMenuState", "Ptr", fileMenu, "UInt", 4, "UInt", 0x400) >> 3 & 1
        isSuspended := DllCall("GetMenuState", "Ptr", fileMenu, "UInt", 5, "UInt", 0x400) >> 3 & 1

        MenuStopObj.Add(Title, ScriptStop)
        MenuPauseObj.Add(Title, ScriptPause)
        if isPaused
            MenuPauseObj.Check(Title)
        else
            MenuPauseObj.Uncheck(Title)
        MenuSuspendObj.Add(Title, ScriptSuspend)
        if isSuspended
            MenuSuspendObj.Check(Title)
        else
            MenuSuspendObj.Uncheck(Title)
        MenuEditObj.Add(Title, ScriptEdit)
        MenuReloadObj.Add(Title, ScriptReload)
        MenuOpenObj.Add(Title, ScriptOpen)
    }
    MenuMainObj.Add(" Stop Script ", MenuStopObj)
    MenuMainObj.Add(" Pause Script ", MenuPauseObj)
    MenuMainObj.Add(" Suspend Script ", MenuSuspendObj)
    MenuMainObj.Add(" Edit Script ", MenuEditObj)
    MenuMainObj.Add(" Reload Script ", MenuReloadObj)
    MenuMainObj.Add(" Open Script ", MenuOpenObj)
}

; Excluded Gui
ExcludedButtonConfirmEdit(*) {
    global Files_Excluded, Hot_Excluded, Set_IniExcluded, GuiExcluded, Gui_Excluded

    saved := GuiExcluded.Submit(false)
    Gui_Excluded := saved.Gui_Excluded
    Files_Excluded := ""
    Hot_Excluded := ""
    Next_Section := false
    Loop Parse, Gui_Excluded, "`n", "`r"
    {
        if !A_LoopField
            continue
        if (A_LoopField = String_Wings(" EXCLUDED SCRIPTS AND FILES ",40))
        {
            Next_Section := false
            continue
        }
        if (A_LoopField = String_Wings(" EXCLUDED HOTKEYS & HOTSTRINGS ",40))
            Next_Section := true
        else if !Next_Section
            Files_Excluded .= "|" Trim(A_LoopField)
        else
            Hot_Excluded .= "|" Trim(A_LoopField)
    }
    Files_Excluded := SubStr(Files_Excluded, 2)
    Hot_Excluded := SubStr(Hot_Excluded, 2)
    if Set_IniExcluded
    {
        IniWrite(Files_Excluded, "Hotkey Help.ini", "Excluded", "Files_Excluded")
        IniWrite(Hot_Excluded, "Hotkey Help.ini", "Excluded", "Hot_Excluded")
    }
}

ExcludedGuiSize(GuiObj, MinMax, Width, Height) {
    global CtrlExcludedEdit
    if (MinMax = -1)
        return
    CtrlExcludedEdit.Move(, , Width - 20, Height - 20)
}

ExcludedGuiEscape(*) {
    global GuiExcluded
    GuiExcluded.Hide()
}

; Raw Gui
GuiRawSize(GuiObj, MinMax, Width, Height) {
    global GuiRaw
    if (MinMax = -1)
        return
    ; v1 referenced the Raw Gui's Edit control by its v-name directly (only ever one control in this Gui).
    GuiRaw["Gui_Raw_Display"].Move(, , Width - 20, Height - 20)
}

GuiRawEscape(*) {
    global GuiRaw
    GuiRaw.Hide()
}

; Set Gui
SetGuiClose(*) {
    global Set_ShowBlank, Set_ShowBlankInclude, Set_ShowExe, Set_ShowHotkey, Set_VarHotkey, Set_FlagHotkey
    global Set_ShowString, Set_AhkExe, Set_AhkTxt, Set_AhkTxtOver, Set_SortInfo, Set_CapHotkey
    global Set_CapHotkey_Radio, Set_HideFold, Set_TextOut, Set_FindPos, Set_IniSet, Set_IniExcluded
    global Set_Hotkey_Mod_Delimiter, GuiSettings, CtrlCapRadioTitle, CtrlCapRadioUpper

    saved := GuiSettings.Submit(false)
    Set_ShowBlank := saved.Set_ShowBlank
    Set_ShowBlankInclude := saved.Set_ShowBlankInclude
    Set_ShowExe := saved.Set_ShowExe
    Set_ShowHotkey := saved.Set_ShowHotkey
    Set_VarHotkey := saved.Set_VarHotkey
    Set_FlagHotkey := saved.Set_FlagHotkey
    Set_ShowString := saved.Set_ShowString
    Set_AhkExe := saved.Set_AhkExe
    Set_AhkTxt := saved.Set_AhkTxt
    Set_AhkTxtOver := saved.Set_AhkTxtOver
    Set_SortInfo := saved.Set_SortInfo
    Set_CapHotkey := saved.Set_CapHotkey
    Set_CapHotkey_Radio := CtrlCapRadioTitle.Value ? 1 : (CtrlCapRadioUpper.Value ? 2 : Set_CapHotkey_Radio)
    Set_HideFold := saved.Set_HideFold
    Set_TextOut := saved.Set_TextOut
    Set_FindPos := saved.Set_FindPos
    Set_IniSet := saved.Set_IniSet
    Set_IniExcluded := saved.Set_IniExcluded
    Set_Hotkey_Mod_Delimiter := saved.Set_Hotkey_Mod_Delimiter

    if Set_IniSet
    {
        IniWrite(Set_ShowBlank, "Hotkey Help.ini", "Settings", "Set_ShowBlank")
        IniWrite(Set_ShowBlankInclude, "Hotkey Help.ini", "Settings", "Set_ShowBlankInclude")
        IniWrite(Set_ShowExe, "Hotkey Help.ini", "Settings", "Set_ShowExe")
        IniWrite(Set_ShowHotkey, "Hotkey Help.ini", "Settings", "Set_ShowHotkey")
        IniWrite(Set_VarHotkey, "Hotkey Help.ini", "Settings", "Set_VarHotkey")
        IniWrite(Set_FlagHotkey, "Hotkey Help.ini", "Settings", "Set_FlagHotkey")
        IniWrite(Set_ShowString, "Hotkey Help.ini", "Settings", "Set_ShowString")
        IniWrite(Set_AhkExe, "Hotkey Help.ini", "Settings", "Set_AhkExe")
        IniWrite(Set_AhkTxt, "Hotkey Help.ini", "Settings", "Set_AhkTxt")
        IniWrite(Set_AhkTxtOver, "Hotkey Help.ini", "Settings", "Set_AhkTxtOver")
        IniWrite(Set_SortInfo, "Hotkey Help.ini", "Settings", "Set_SortInfo")
        IniWrite(Set_CapHotkey, "Hotkey Help.ini", "Settings", "Set_CapHotkey")
        IniWrite(Set_CapHotkey_Radio, "Hotkey Help.ini", "Settings", "Set_CapHotkey_Radio")
        IniWrite(Set_HideFold, "Hotkey Help.ini", "Settings", "Set_HideFold")
        IniWrite(Set_TextOut, "Hotkey Help.ini", "Settings", "Set_TextOut")
        IniWrite(Set_FindPos, "Hotkey Help.ini", "Settings", "Set_FindPos")
        IniWrite(Set_IniSet, "Hotkey Help.ini", "Settings", "Set_IniSet")
        IniWrite(Set_IniExcluded, "Hotkey Help.ini", "Settings", "Set_IniExcluded")
        IniWrite(Set_Hotkey_Mod_Delimiter, "Hotkey Help.ini", "Settings", "Set_Hotkey_Mod_Delimiter")
    }
    Set_Hotkey_Mod_Delimiter := Trim(Set_Hotkey_Mod_Delimiter,'"')
    GuiSettings.Hide()
}

; Export Help Dialog to Text File
ButtonExportDialog(*) {
    global Display, Display_CreateOnly
    if IsSet(Display) && Display
        TextOut()
    else
    {
        Display_CreateOnly := true
        RefreshHelpDisplay()
        Display_CreateOnly := false
        TextOut()
        Display := ""
    }
}

; Reset "Find" Position
ButtonFindPos(*) {
    SearchEdit.Docked := true
}
;}

; FUNCTIONS
;{-----------------------------------------------
;

; Get Value of Variable From Script Dialog
HotkeyVariable(Script,Variable)
{
    static Script_List := Map()
    Var := Trim(Variable," %")
    if !Script_List.Has(Script)
    {
        DetectHiddenWindows(true)
        SetTitleMatchMode(2)
        WinMove(A_ScreenWidth, A_ScreenHeight,,, Script)
        PostMessage(0x111, 65407, , , Script)
        Text := ""
        try
            Text := ControlGetText("Edit1", Script)
        WinHide(Script)
        Script_List[Script] := Text
    }
    Pos := RegExMatch(Script_List[Script], Var ".*\:(.*)",&Match)
    if (Pos and Match[1])
        return Match[1]
    else
        return Variable
}

; Get Hotkeys From Script Dialog
ScriptHotkeys(Script)
{
    DetectHiddenWindows(true)
    SetTitleMatchMode(2)
    WinMove(A_ScreenWidth, A_ScreenHeight,,, Script)
    if (Script = A_ScriptFullPath)
        ListHotkeys()
    else
        PostMessage(0x111, 65408, , , Script)
    Text := ""
    try
        Text := ControlGetText("Edit1", Script)
    WinHide(Script)
    Result := []
    Loop Parse, Text, "`n", "`r"
    {
        Pos := RegExMatch(A_LoopField,"^[(reg|k|m|2|joy)].*\t(.*)$",&Match)
        if Pos
            Result.Push(Match[1])
    }
    return Result
}

; Expand File Path
; v2: A_LoopFileLongPath (v1 name) was renamed to A_LoopFileFullPath - the old v1 name resolves to an
; ordinary (never-assigned) variable in v2 instead of the loop's special property, confirmed live via
; a real "#Warn VarUnset" dialog the moment this code path actually ran.
Get_Full_Path(path)
{
    Loop Files, path, "F"
        return A_LoopFileFullPath
    return path
}

; Add Character Wings to Each Side of String to Create Graphical Break
; v2: parameter renamed CaseMode (was Case) - `Case` is a reserved word (switch/case), invalid as a variable name.
String_Wings(String,Length:=76,Char:="=",CaseMode:="U")
{
    if (CaseMode = "U")
        String := StrUpper(String)
    else if (CaseMode = "T")
        String := StrTitle(String)
    else if (CaseMode = "L")
        String := StrLower(String)
    WingX1 := Round(((Length-StrLen(String))/2)/StrLen(Char)-.5)
    WingX2 := Round((Length-StrLen(String)-(WingX1*StrLen(Char)))/StrLen(Char)+.5)
    Wing_1 := ""
    Wing_2 := ""
    Loop WingX1
        Wing_1 .= Char
    Loop WingX2
        Wing_2 .= Char
    return SubStr(Wing_1 String Wing_2,1,Length)
}

; Format Spaces Between Hot Keys and Help Info to Create Columns
Format_Line(Hot,Info,Pos_Info)
{
    Spaces := ""
    Length := Pos_Info - StrLen(Hot) - 1
    Loop Length
        Spaces .= " "
    return Hot Spaces Info
}

; Reference One Branch of Array and Return Corrisponding Information on Cross Branch
ArrayCrossRef(Array, Haystack, Needle, Cross)
{
    for index, element in Array
        if (Needle = element[Haystack])
            return element[Cross]
    return
}
;}

; CLASSES
;{-----------------------------------------------
;

; [Class] SearchEdit - Find Text within Edit Control (Edit Control Must have +0x100 Style for Unfocused Highlights)
; v2: v1's bare `static` directive (making every local in Dialog() an implicitly-shared, persistent class
; field) has no v2 equivalent - each piece of state that needs to persist/share across calls is now an
; explicit `static` class property below. The labels that lived inside Dialog() (WrapToTop, FindText_Sub,
; SearchEdit_DialogGuiEscape, StatusBar) were really Gui-event handlers matched by v1's magic naming
; convention - they become real functions bound via .OnEvent() instead. Per Migration-Notes.md 18.21,
; none of these are registered via ObjBindMethod (which would break OnMessage/click dispatch) - the two
; low-level hooks (WM_LBUTTONDOWN, WM_WINDOWPOSCHANGED) are bare top-level functions instead, each with
; a 4-param signature per 18.17.
class SearchEdit
{
    static Docked := true
    static UnDock := ""
    static Offset := 3
    static ParentID := 0
    static GuiControlID := 0
    static Visible := false
    static FindInput := ""
    static StartingPos := 1
    static Found := false
    static DialogGui := ""
    static FindEditCtrl := ""
    static StatusBarCtrl := ""

    static Dialog(pGuiControlID, pOffset:=3, pFindInput := "")
    {
        SearchEdit.GuiControlID := pGuiControlID
        SearchEdit.Offset := pOffset
        SearchEdit.ParentID := DllCall("GetParent", "Ptr", pGuiControlID, "Ptr")
        if !SearchEdit.DialogGui
        {
            SearchEdit.DialogGui := Gui("-Caption +ToolWindow +Owner" pGuiControlID)
            SearchEdit.FindEditCtrl := SearchEdit.DialogGui.AddEdit("x10 y3 w200 r2 -VScroll")
            SearchEdit.FindEditCtrl.OnEvent("Change", SearchEdit_FindTextChanged)
            SearchEdit.FindEditCtrl.Move(,, , 20)
            SearchEdit.StatusBarCtrl := SearchEdit.DialogGui.AddStatusBar()
            SearchEdit.StatusBarCtrl.SetText("`tType Find string and press Enter")
            SearchEdit.DialogGui.OnEvent("Escape", SearchEdit_DialogGuiEscape)
            SearchEdit.DialogGui.OnEvent("Close", SearchEdit_DialogGuiEscape)
            ; v2: moved here (was a stray top-level statement placed after the file's first hotkey, where
            ; auto-execute fall-through already ends - it would never have actually registered). Fires once,
            ; lazily, alongside the other two OnMessage hooks below.
            OnMessage(0x203, SearchEdit_WM_LBUTTONDBLCLK)
            if !IsObject(SearchEdit.UnDock)
                SearchEdit.Docked := true
        }
        if (pFindInput = "")
        {
            SearchEdit.Found := false
            SearchEdit.StartingPos := 1
            WinGetPos(&X, &Y, &W, &H, "ahk_id " SearchEdit.ParentID)
            Calc := SearchEdit.Calc_Position(X, Y, W, H)
            SearchEdit.DialogGui.Show("h" Calc.h " w" Calc.w " x" Calc.x " y" Calc.y)
            SearchEdit.Visible := true
            OnMessage(0x201, SearchEdit_WM_LBUTTONDOWN)
            OnMessage(0x47, SearchEdit_WM_WINDOWPOSCHANGED)
            return
        }
        if (SearchEdit.FindInput != pFindInput)
        {
            SearchEdit.Found := false
            SearchEdit.StartingPos := 1
        }
        SearchEdit.FindInput := pFindInput
        Loop
        {
            SearchEdit.StartingPos := SearchEdit.FindText(SearchEdit.FindInput, SearchEdit.GuiControlID,, SearchEdit.StartingPos)
            SearchEdit.FindEditCtrl.Value := SearchEdit.FindInput
            Send("^{Right}")
            if !SearchEdit.StartingPos
            {
                SendMessage(0xB1, -1,,, "ahk_id " SearchEdit.GuiControlID) ; EM_SETSEL ; Deselect
                if SearchEdit.Found
                {
                    SearchEdit.Found := false
                    SearchEdit.StartingPos := 1
                    continue ; v2: v1's `goto WrapToTop` becomes a real loop restart.
                }
                MsgBox("NOT FOUND:`n`n" SearchEdit.FindInput)
                SearchEdit.FindEditCtrl.Value := ""
                SearchEdit.Found := false
                SearchEdit.StartingPos := 1
            }
            else
                SearchEdit.Found := true
            break
        }
    }

    static FindText(FindTextStr, GuiControlID, CaseSensitive:=false, StartingPos:=1, Occurance:=1)
    {
        Text := ControlGetText(GuiControlID)
        Text := RegExReplace(Text, "\R", "`r`n")
        if !(Pos := InStr(Text, FindTextStr, CaseSensitive, StartingPos, Occurance))
            return
        StartPos := Pos - 1
        EndingPos := StartPos + StrLen(FindTextStr)
        SendMessage(0xB1, StartPos, EndingPos,, "ahk_id " GuiControlID) ; EM_SETSEL
        SendMessage(0xB7, 0, 0,, "ahk_id " GuiControlID) ;- EM_SCROLLCARET
        return EndingPos + 1 ; Start Position for Next Search
    }

    static Calc_Position(X, Y, W, H)
    {
        guiO := SearchEdit.Offset
        guiH := 45, guiW := 220 ; Gui - Base Height, Base Width
        if !SearchEdit.Docked
            return {h:guiH, w:guiW, x:X+SearchEdit.UnDock.deltaX, y:Y+SearchEdit.UnDock.deltaY}
        MonitorGetWorkArea(, &AreaLeft, &AreaTop, &AreaRight, &AreaBottom)
        scaleH := Floor(guiH*A_ScreenDPI/96), scaleW := Floor(guiW*A_ScreenDPI/96) ; Adjust for different DPI screens
        if (Y+H+scaleH-guiO < AreaBottom)
            return {h:guiH, w:guiW, x:X+guiO, y:Y+H-guiO} ; bottom under outside
        else if (X+W+scaleW-guiO < AreaRight)
            return {h:guiH, w:guiW, x:X+W-guiO, y:Y+H-guiO-scaleH} ; bottom right outside
        else if (X-scaleW > AreaLeft)
            return {h:guiH, w:guiW, x:X-scaleW+guiO, y:Y+H-scaleH-guiO} ; bottom left outside
        else
            return {h:guiH, w:guiW, x:X+W-scaleW-guiO, y:Y+H-scaleH-guiO} ; bottom right inside
    }
}

; v2: bare top-level functions, not ObjBindMethod-bound instance methods - see the class comment above
; (Migration-Notes.md 18.21). All operate on SearchEdit's static state directly.
SearchEdit_WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    if (SearchEdit.DialogGui && hwnd = SearchEdit.DialogGui.Hwnd)
    {
        PostMessage(0xA1, 2,,, "A")
        SearchEdit.Docked := false
        Sleep(20)
        WinGetPos(&X, &Y, &W, &H, "ahk_id " SearchEdit.ParentID)
        WinGetPos(&gX, &gY, &gW, &gH, "ahk_id " SearchEdit.DialogGui.Hwnd)
        SearchEdit.UnDock := {deltaX: gX-X, deltaY: gY-Y}
    }
}

SearchEdit_WM_WINDOWPOSCHANGED(wParam, lParam, msg, hwnd) {
    if (hwnd != SearchEdit.ParentID or !SearchEdit.Visible)
        return
    if !WinExist("ahk_id " hwnd)
    {
        SearchEdit.DialogGui.Hide()
        return
    }
    X := NumGet(lParam+0, A_PtrSize + A_PtrSize, "Int")
    Y := NumGet(lParam+0, A_PtrSize + A_PtrSize + 4, "Int")
    W := NumGet(lParam+0, A_PtrSize + A_PtrSize + 8, "Int")
    H := NumGet(lParam+0, A_PtrSize + A_PtrSize + 12, "Int")
    Flags := NumGet(lParam+0, A_PtrSize + A_PtrSize + 16, "UInt")
    if (Flags = 6147 or Flags = 6163 or Flags = 33072 or Flags = 33060) ; Minimize/Restore
        return
    Calc := SearchEdit.Calc_Position(X, Y, W, H)
    SearchEdit.DialogGui.Show("h" Calc.h " w" Calc.w " x" Calc.x " y" Calc.y)
}

; v1's StatusBar double-click g-label has no direct v2 GuiControl event equivalent - reimplemented with
; the same low-level WM_LBUTTONDBLCLK hook pattern already proven above for the drag-detection handler.
SearchEdit_WM_LBUTTONDBLCLK(wParam, lParam, msg, hwnd) {
    if (SearchEdit.StatusBarCtrl && hwnd = SearchEdit.StatusBarCtrl.Hwnd)
    {
        SearchEdit.Docked := true
        WinGetPos(&X, &Y, &W, &H, "ahk_id " SearchEdit.ParentID)
        Calc := SearchEdit.Calc_Position(X, Y, W, H)
        SearchEdit.DialogGui.Show("h" Calc.h " w" Calc.w " x" Calc.x " y" Calc.y)
    }
}

SearchEdit_FindTextChanged(GuiCtrlObj, Info) {
    Value := GuiCtrlObj.Value
    if !(InStr(Value, "`n"))
        return
    SearchEdit.Dialog(SearchEdit.GuiControlID, SearchEdit.Offset, Trim(Value, "`n"))
}

SearchEdit_DialogGuiEscape(*) {
    SearchEdit.DialogGui.Hide()
    SearchEdit.Visible := false
}
;}

; FUNCTIONS - LIBRARY
;{-----------------------------------------------
;

;{ AHKScripts
; Fanatic Guru
; 2014 03 31
;
; FUNCTION that will find the path and file name of all AHK scripts running.
;
;---------------------------------------------------------------------------------
;
; Method:
;   AHKScripts(&Array)
;
; Parameters:
;   1) {Array} variable in which to store AHK script path data array
;
; Returns:
;   String containing the complete path of all AHK scripts running
;   One path per line of string, delimiter = `n
;
; ByRef:
;   Populates {Array} passed as parameter with AHK script path data
;     {Array}[n].Path
;     {Array}[n].Name
;     {Array}[n].Dir
;     {Array}[n].Ext
;     {Array}[n].Title
;     {Array}[n].hWnd
;
; v2: WinGet's List sub-command is now the real WinGetList() function returning an array of HWNDs
; directly - no more manufacturing AHK_Windows%A_Index%-style pseudo-array variable names (that
; construct-a-variable-name-from-a-string trick has no v2 equivalent at all, per SharedHelpers.ahk's
; CloseBrowserGracefully() precedent elsewhere in this fleet).
AHKScripts(&Array)
{
    DetectHiddenWindows(true)
    AHK_Windows := WinGetList("ahk_class AutoHotkey")
    Array := []
    list := ""
    for hWnd in AHK_Windows
    {
        Win_Name := WinGetTitle("ahk_id " hWnd)
        File_Path := RegExReplace(Win_Name, "^(.*) - AutoHotkey v[0-9\.]+$", "$1")
        SplitPath(File_Path, &File_Name, &File_Dir, &File_Ext, &File_Title)
        Array.Push({Path: File_Path, Name: File_Name, Dir: File_Dir, Ext: File_Ext, Title: File_Title, hWnd: hWnd})
        list .= File_Path "`n"
    }
    return Trim(list, " `n")
}
;}
;}
