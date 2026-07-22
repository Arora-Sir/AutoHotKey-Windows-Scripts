#Requires AutoHotkey v1.1

; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key
; Personal key bindings example template.
; For local private hotkeys and shortcuts, use "Personal_Keywords.ahk" (ignored by Git).

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

; Typing key will get value in return
:*:Key::Value
