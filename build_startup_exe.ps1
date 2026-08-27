# Recompiles StartupScript.exe from AllScripts\StartupScript.ahk, with the correct icon
# and base AutoHotkey binary. Rerun any time StartupScript.ahk's source changes -- Task
# Scheduler's "AHK Startup Script" task launches the compiled .exe, not the .ahk source,
# so a source edit alone does not take effect until this is rerun.

$ErrorActionPreference = "Stop"

$root     = $PSScriptRoot
$compiler = Join-Path $env:ProgramFiles "AutoHotkey\Compiler\Ahk2Exe.exe"
$src      = Join-Path $root "AllScripts\StartupScript.ahk"
$out      = Join-Path $root "AllScripts\StartupScript.exe"
$icon     = Join-Path $root "StartupScript.ico"
$base     = Join-Path $env:ProgramFiles "AutoHotkey\AutoHotkeyU64.exe"

if (-not (Test-Path $compiler)) { throw "Ahk2Exe.exe not found at $compiler -- is AutoHotkey installed?" }
if (-not (Test-Path $src))      { throw "Source script not found: $src" }
if (-not (Test-Path $icon))     { throw "Icon not found: $icon" }
if (-not (Test-Path $base))     { throw "Base AutoHotkey binary not found: $base" }

# StartupScript.exe holds a file lock on itself while running, which makes the compiler
# fail with 'is still running, and needs to be unloaded'. Stop it first -- this is exactly
# what its own #SingleInstance force would do to itself on the next real launch anyway.
Get-Process -Name "StartupScript" -ErrorAction SilentlyContinue | Stop-Process -Force

$compileArgs = @(
    "/in", "`"$src`"",
    "/out", "`"$out`"",
    "/icon", "`"$icon`"",
    "/base", "`"$base`"",
    "/silent", "verbose"   # required: without /silent, Ahk2Exe opens its GUI compiler
                            # window instead of compiling directly, and does nothing when
                            # run non-interactively (e.g. from a script or CI).
)

$stdoutFile = Join-Path $env:TEMP "ahk2exe_build_out.txt"
$stderrFile = Join-Path $env:TEMP "ahk2exe_build_err.txt"
$proc = Start-Process -FilePath $compiler -ArgumentList $compileArgs -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

if ($proc.ExitCode -ne 0) {
    Write-Host "Compile FAILED (exit $($proc.ExitCode)):" -ForegroundColor Red
    Get-Content $stdoutFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Get-Content $stderrFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

$size = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "OK -> $out ($size KB)" -ForegroundColor Green
Write-Host "Not relaunched automatically. When ready:  Start-Process `"$out`""
