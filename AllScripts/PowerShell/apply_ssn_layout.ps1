# =============================================================================
# Simple Sticky Notes (ssn.exe) Dual Deterministic Layout Engine
# =============================================================================
# Solves the multi-resolution desktop layout scrambling issue between:
# - Host Laptop (DISPLAY1): 1920x1080 @ 125% DPI scale = 1536 x 864 logical DIP workspace
# - Tablet (DISPLAY4):     2560x1600 @ 175% DPI scale = 1463 x 914 logical DIP workspace
#
# Mathematical Root Cause:
# Notes arranged across 4 columns on the laptop extend to X=1536 (flush against the right edge).
# When switching to Tablet mode, the tablet's logical screen is 73 pixels narrower (1463px vs 1536px).
# Any note with X + Width > 1463 extends off-screen. Simple Sticky Notes detects Column 3 is off-screen
# and forces it to slide left, colliding with Column 2, which in turn collides with Column 1.
#
# Dual Deterministic Layouts (Pixel-by-Pixel):
#
# 1. LAPTOP LAYOUT (Logical workspace: 1536 x 864):
#    - Column 0 (Far Left):
#      * 1 note: W=240, H=240 -> X=0, Y=576 (bottom edge = 816px)
#    - Column 1:
#      * Top note:    W=240, H=120 -> X=728, Y=0
#      * Bottom note: W=240, H=240 -> X=728, Y=120 (bottom edge = 360px)
#      * Right edge: 728 + 240 = 968px (flush against Column 2)
#    - Column 2:
#      * Top note:    W=300, H=240 -> X=968, Y=0
#      * Middle note: W=300, H=183 -> X=968, Y=240
#      * Bottom note: W=300, H=236 -> X=968, Y=423 (bottom edge = 659px)
#      * Right edge: 968 + 300 = 1268px (flush against Column 3)
#    - Column 3:
#      * 'Today' note (expanded): W=268, H=548 -> X=1268, Y=0
#      * Minimized notes: W=268, H=32 -> X=1268, stacked below Today at Y=548, 580, 612, 644, 676
#      * Right edge: 1268 + 268 = 1536px (flush against laptop right screen boundary)
#
# 2. TABLET LAYOUT (Logical workspace: 1463 x 914):
#    - Column 0 (Far Left):
#      * 1 note: W=240, H=240 -> X=0, Y=576
#    - Column 1:
#      * Top note:    W=240, H=120 -> X=640, Y=0
#      * Bottom note: W=240, H=240 -> X=640, Y=120
#      * Right edge: 640 + 240 = 880px (5px gap before Column 2)
#    - Column 2:
#      * Top note:    W=300, H=240 -> X=885, Y=0
#      * Middle note: W=300, H=183 -> X=885, Y=240
#      * Bottom note: W=300, H=236 -> X=885, Y=423
#      * Right edge: 885 + 300 = 1185px (5px gap before Column 3)
#    - Column 3:
#      * 'Today' note (expanded): W=268, H=548 -> X=1190, Y=0
#      * Minimized notes: W=268, H=32 -> X=1190, stacked below Today at Y=548, 580, 612, 644, 676
#      * Right edge: 1190 + 268 = 1458px (safe 5px margin before 1463px tablet edge, zero cut-off)

param(
    [string]$Mode = "Auto", # "Auto", "Tablet", "Laptop"
    [int]$DelayMs = 0
)

$ErrorActionPreference = "SilentlyContinue"

if ($DelayMs -gt 0) {
    Start-Sleep -Milliseconds $DelayMs
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class SSNLayoutEngine {
    public delegate bool EnumThreadDelegate(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll")]
    public static extern bool EnumThreadWindows(int dwThreadId, EnumThreadDelegate lpfn, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public class WinInfo {
        public IntPtr Hwnd;
        public int W, H, X, Y;
    }

    public static int GetRank(int h) {
        if (Math.Abs(h - 240) <= 10) return 1;
        if (Math.Abs(h - 183) <= 10) return 2;
        if (Math.Abs(h - 236) <= 10) return 3;
        return 4;
    }

    public static bool ApplyLayout(bool isTablet) {
        IntPtr hDesk = OpenDesktop("Default", 0, false, 0x01FF);
        if (hDesk != IntPtr.Zero) {
            SetThreadDesktop(hDesk);
        }

        var proc = System.Diagnostics.Process.GetProcessesByName("ssn");
        if (proc.Length == 0) {
            return false;
        }

        var col0 = new List<WinInfo>();
        var col1 = new List<WinInfo>();
        var col2 = new List<WinInfo>();
        var col3 = new List<WinInfo>();
        var notes240 = new List<WinInfo>();

        foreach (System.Diagnostics.ProcessThread t in proc[0].Threads) {
            EnumThreadWindows(t.Id, (hWnd, lParam) => {
                var sbClass = new StringBuilder(256);
                GetClassName(hWnd, sbClass, 256);
                if (sbClass.ToString() == "UINoteWindow" && IsWindowVisible(hWnd)) {
                    RECT r;
                    GetWindowRect(hWnd, out r);
                    int w = r.Right - r.Left;
                    int h = r.Bottom - r.Top;
                    var info = new WinInfo { Hwnd = hWnd, W = w, H = h, X = r.Left, Y = r.Top };

                    if (w >= 260 && w <= 290) {
                        col3.Add(info);
                    } else if (w >= 295 && w <= 315) {
                        col2.Add(info);
                    } else if (w >= 230 && w <= 250) {
                        if (h <= 130) {
                            col1.Add(info);
                        } else {
                            notes240.Add(info);
                        }
                    }
                }
                return true;
            }, IntPtr.Zero);
        }

        if (col3.Count == 0 && col2.Count == 0) {
            return false;
        }

        // Distinguish col 0 vs col 1 bottom note
        if (notes240.Count == 1) {
            if (notes240[0].X < 400) col0.Add(notes240[0]);
            else col1.Add(notes240[0]);
        } else if (notes240.Count >= 2) {
            notes240.Sort((a, b) => a.X.CompareTo(b.X));
            col0.Add(notes240[0]);
            for (int i = 1; i < notes240.Count; i++) {
                col1.Add(notes240[i]);
            }
        }

        int targetX0 = 0;
        int targetX1 = isTablet ? 640 : 728;
        int targetX2 = isTablet ? 885 : 968;
        int targetX3 = isTablet ? 1190 : 1268;

        uint flags = 0x0014; // SWP_NOZORDER (0x0004) | SWP_NOACTIVATE (0x0010)

        // 1. Column 0: X=0, Y=576
        foreach (var w in col0) {
            SetWindowPos(w.Hwnd, IntPtr.Zero, targetX0, 576, w.W, w.H, flags);
        }

        // 2. Column 1: Top note H=120, Bot note H=240
        col1.Sort((a, b) => a.H.CompareTo(b.H));
        int curY1 = 0;
        foreach (var w in col1) {
            SetWindowPos(w.Hwnd, IntPtr.Zero, targetX1, curY1, w.W, w.H, flags);
            curY1 += w.H;
        }

        // 3. Column 2: 240 -> 183 -> 236
        col2.Sort((a, b) => GetRank(a.H).CompareTo(GetRank(b.H)));
        int curY2 = 0;
        foreach (var w in col2) {
            SetWindowPos(w.Hwnd, IntPtr.Zero, targetX2, curY2, w.W, w.H, flags);
            curY2 += w.H;
        }

        // 4. Column 3: Today (548) -> minimized notes
        col3.Sort((a, b) => b.H.CompareTo(a.H));
        int curY3 = 0;
        foreach (var w in col3) {
            SetWindowPos(w.Hwnd, IntPtr.Zero, targetX3, curY3, w.W, w.H, flags);
            curY3 += w.H;
        }

        return true;
    }
}
'@

# Determine isTablet
$isTablet = $false
if ($Mode -eq "Tablet") {
    $isTablet = $true
} elseif ($Mode -eq "Laptop") {
    $isTablet = $false
} else {
    # Auto detect based on active primary monitor
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $w = $screen.Bounds.Width
    $dev = $screen.DeviceName
    if ($dev -like "*DISPLAY4*" -or ($w -gt 1400 -and $w -lt 1500)) {
        $isTablet = $true
    } else {
        $isTablet = $false
    }
}

# Retry loop: poll every 300ms for up to 6 seconds until windows are ready
$success = $false
for ($attempt = 1; $attempt -le 20; $attempt++) {
    $success = [SSNLayoutEngine]::ApplyLayout($isTablet)
    if ($success) {
        break
    }
    Start-Sleep -Milliseconds 300
}

# Safety re-application 1.2s later to defeat DWM race conditions
if ($success) {
    Start-Sleep -Milliseconds 1200
    [SSNLayoutEngine]::ApplyLayout($isTablet) | Out-Null
}
