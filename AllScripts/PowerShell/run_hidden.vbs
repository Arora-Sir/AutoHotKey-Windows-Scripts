' =============================================================================
' run_hidden.vbs - 100% Invisible Background Process Launcher
' =============================================================================
' Why this file exists:
' When launching PowerShell from Task Scheduler or command line with -WindowStyle Hidden,
' Windows still initializes a conhost.exe console window for ~50ms before hiding it.
' In Windows 11, any new top-level window creation can briefly steal active keyboard/mouse focus.
'
' WScript.exe is a native Windows GUI subsystem process (IMAGE_SUBSYSTEM_WINDOWS_GUI),
' NOT a console process. Running PowerShell via WScript.Shell.Run(cmd, 0, False) invokes
' CreateProcess with CREATE_NO_WINDOW:
'   - Zero console window
'   - Zero taskbar button or flicker
'   - Zero foreground focus disruption
'
' Usage:
'   wscript.exe run_hidden.vbs "powershell.exe -NoProfile -File C:\path\script.ps1"
' =============================================================================

Dim objShell, cmd, i, arg
Set objShell = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    If InStr(arg, " ") > 0 And Left(arg, 1) <> """" Then
        arg = """" & arg & """"
    End If
    If i > 0 Then cmd = cmd & " "
    cmd = cmd & arg
Next
If cmd <> "" Then
    objShell.Run cmd, 0, False
End If
