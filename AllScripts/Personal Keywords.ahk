; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; Personal key bindings

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

; Typing key will get value in return
:*:Key::Value
; Send {backspace 11}