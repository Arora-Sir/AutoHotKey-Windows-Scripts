<#
.SYNOPSIS
    Sunshine stream end prep-command hook for workstation display restoration.

.DESCRIPTION
    Executed by Sunshine when Moonlight ends a streaming session (prep-cmd "undo"):
      - Restores default Win32 mouse speed (10) for workstation desktop use
      - Restores pointer precision acceleration (accel=1)
      - Clears .fast_since marker file
      - Creates .session_quit signal file for immediate display topology restoration by SunshineDisplayWatchdog.ahk
      - Restores Windows default audio recording endpoint to Microphone Array across all roles
      - Restores display topology to PC Screen Only
#>

Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class MouseSpeed { [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetSpeed(uint uiAction, uint uiParam, uint pvParam, uint fWinIni); [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetAccel(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni); }'

# Restores the confirmed default on this machine
[MouseSpeed]::SetSpeed(0x0071, 0, 10, 3) | Out-Null

# Restore "Enhance pointer precision" to its confirmed current ON state (same thresholds, accel=1)
[MouseSpeed]::SetAccel(0x0004, 0, @(6, 10, 1), 3) | Out-Null

# Clears the marker SunshineDisplayWatchdog.ahk uses to know fast-mode is active
Remove-Item -Path "$PSScriptRoot\.fast_since" -Force -ErrorAction SilentlyContinue

# Signal for SunshineDisplayWatchdog: Sunshine executed the undo hook = explicit session Quit (not a pause/back gesture)
New-Item -ItemType File -Path "$PSScriptRoot\.session_quit" -Force | Out-Null

# Auto-restore Windows default recording device to internal Microphone Array on stream disconnect
$nircmd = "C:\Program Files\AutoHotkey\nircmd.exe"
if (-not (Test-Path $nircmd)) {
    $nircmd = "$PSScriptRoot\..\..\..\AutoHotkey Companion Files\nircmd.exe"
}
if (Test-Path $nircmd) {
    & $nircmd setdefaultsounddevice "Microphone Array" 0 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone Array" 1 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone Array" 2 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone Array" | Out-Null
}

# Auto-restore display topology to PC Screen Only (1080p @ 144Hz laptop panel) on stream disconnect
Start-Process "$env:SystemRoot\System32\DisplaySwitch.exe" -ArgumentList "/internal" -WindowStyle Hidden
