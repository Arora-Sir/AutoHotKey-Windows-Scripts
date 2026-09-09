Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class MouseSpeed { [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetSpeed(uint uiAction, uint uiParam, uint pvParam, uint fWinIni); [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetAccel(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni); }'
# 0x0071 = SPI_SETMOUSESPEED, pvParam = speed (1-20, hard API max), fWinIni 3 = SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
[MouseSpeed]::SetSpeed(0x0071, 0, 20, 3) | Out-Null
# 0x0004 = SPI_SETMOUSE, pvParam = [Threshold1, Threshold2, Acceleration]; 0 = disable "Enhance pointer precision"
[MouseSpeed]::SetAccel(0x0004, 0, @(6, 10, 0), 3) | Out-Null
# Marker for SunshineMouseWatchdog.ahk: its mtime is the "fast since" timestamp, deleted by set_normal.ps1
New-Item -ItemType File -Path "$PSScriptRoot\.fast_since" -Force | Out-Null
# Clean up any leftover quit flag from a previous session before the new one starts
Remove-Item -Path "$PSScriptRoot\.session_quit" -Force -ErrorAction SilentlyContinue



