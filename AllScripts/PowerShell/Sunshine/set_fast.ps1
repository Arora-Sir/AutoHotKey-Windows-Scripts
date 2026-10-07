<#
.SYNOPSIS
    Sunshine stream start prep-command hook for tablet streaming optimization.

.DESCRIPTION
    Executed by Sunshine when Moonlight begins a streaming session (prep-cmd "do"):
      - Increases Win32 mouse speed to maximum (20) for responsive tablet pen/touch navigation
      - Disables pointer precision acceleration (accel=0) for 1:1 stylus and touch fidelity
      - Creates .fast_since timestamp marker file read by SunshineDisplayWatchdog.ahk
      - Clears any leftover .session_quit marker from prior sessions
      - Switches Windows default audio recording endpoint to Steam Streaming Microphone across all roles
      - Switches display topology to Second Screen Only
#>

Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class MouseSpeed { [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetSpeed(uint uiAction, uint uiParam, uint pvParam, uint fWinIni); [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetAccel(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni); }'

# 0x0071 = SPI_SETMOUSESPEED, pvParam = speed (1-20, hard API max), fWinIni 3 = SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
[MouseSpeed]::SetSpeed(0x0071, 0, 20, 3) | Out-Null

# 0x0004 = SPI_SETMOUSE, pvParam = [Threshold1, Threshold2, Acceleration]; 0 = disable "Enhance pointer precision"
[MouseSpeed]::SetAccel(0x0004, 0, @(6, 10, 0), 3) | Out-Null

# Marker for SunshineDisplayWatchdog.ahk: its mtime is the "fast since" timestamp, deleted by set_normal.ps1
New-Item -ItemType File -Path "$PSScriptRoot\.fast_since" -Force | Out-Null

# Clean up any leftover quit flag from a previous session before the new one starts
Remove-Item -Path "$PSScriptRoot\.session_quit" -Force -ErrorAction SilentlyContinue

# Auto-switch Windows default recording device to Steam Streaming Microphone on stream connect
$nircmd = "C:\Program Files\AutoHotkey\nircmd.exe"
if (-not (Test-Path $nircmd)) {
    $nircmd = "$PSScriptRoot\..\..\..\AutoHotkey Companion Files\nircmd.exe"
}
if (Test-Path $nircmd) {
    & $nircmd setdefaultsounddevice "Microphone" 0 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone" 1 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone" 2 | Out-Null
    & $nircmd setdefaultsounddevice "Microphone" | Out-Null
}

# Auto-switch display topology to Second Screen Only (2560x1600 @ 120Hz native 16:10) on stream connect
Start-Process "$env:SystemRoot\System32\DisplaySwitch.exe" -ArgumentList "/external" -WindowStyle Hidden
