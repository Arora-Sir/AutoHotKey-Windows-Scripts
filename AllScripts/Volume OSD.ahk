; ^ for Ctrl, ! for Alt, # for Win, + for Shift
; ~ prefix to prevent blocking native (original) functionality of that key

#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#SingleInstance force ; Ensures that only the last executed instance of script is running
DetectHiddenWindows, On

Volume_Up::SoundSet, +10
Volume_Down::SoundSet, -10

; Media_Prev::volDown()
; Media_Next::volUp()

; volUp(){
;     Volume_Up += 2
; }
; volDown(){
;     Volume_Down -= 2
; }

; #InstallKeybdHook
; ; or
; #UseHook
; ; or
; $!Right::SendInput {LWin down}{Tab}{LWin up}  
; $!Left::SendInput {Alt down}{Tab}{Alt up}

