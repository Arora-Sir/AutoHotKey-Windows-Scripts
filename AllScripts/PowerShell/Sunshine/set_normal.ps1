Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class MouseSpeed { [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetSpeed(uint uiAction, uint uiParam, uint pvParam, uint fWinIni); [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SetAccel(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni); }'
# Restores the confirmed default on this machine
[MouseSpeed]::SetSpeed(0x0071, 0, 10, 3) | Out-Null
# Restore "Enhance pointer precision" to its confirmed current ON state (same thresholds, accel=1)
[MouseSpeed]::SetAccel(0x0004, 0, @(6, 10, 1), 3) | Out-Null
# Clears the marker SunshineMouseWatchdog.ahk uses to know fast-mode is active
Remove-Item -Path "$PSScriptRoot\.fast_since" -Force -ErrorAction SilentlyContinue
# Signal for SunshineMouseWatchdog: Sunshine executed the undo hook = explicit session Quit (not a pause/back gesture)
New-Item -ItemType File -Path "$PSScriptRoot\.session_quit" -Force | Out-Null



