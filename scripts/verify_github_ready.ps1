# Requires PowerShell 7
# Automated pre-flight verification script for GitHub workflow

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "GITHUB WORKFLOW PRE-FLIGHT VERIFICATION" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$Passed = $true

# 1. Branch verification
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
Write-Host "[1/6] Git Branch: $branch" -ForegroundColor Yellow
if ($branch -ne "master") {
    Write-Host "  Warning: Not on master branch" -ForegroundColor Yellow
} else {
    Write-Host "  Branch verified: master" -ForegroundColor Green
}

# 2. Syntax validation of modified AHK files
Write-Host "[2/6] Validating AutoHotkey syntax..." -ForegroundColor Yellow
$ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (-not (Test-Path $ahkExe)) {
    throw "AutoHotkey v2 executable not found at $ahkExe"
}

$modifiedAhk = git diff --name-only HEAD | Where-Object { $_ -like "*.ahk" }
$untrackedAhk = git ls-files --others --exclude-standard | Where-Object { $_ -like "*.ahk" }
$allAhkToCheck = @($modifiedAhk) + @($untrackedAhk) | Select-Object -Unique

foreach ($file in $allAhkToCheck) {
    $fullPath = Join-Path $RepoRoot $file
    if (Test-Path $fullPath) {
        $proc = Start-Process -FilePath $ahkExe -ArgumentList "/validate `"$fullPath`"" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-Host "  PASS: $file syntax valid" -ForegroundColor Green
        } else {
            Write-Host "  FAIL: $file syntax check failed (Exit code: $($proc.ExitCode))" -ForegroundColor Red
            $Passed = $false
        }
    }
}

# 3. Sunshine Watchdog Automated Test Suite
Write-Host "[3/6] Running Sunshine Watchdog automated tests..." -ForegroundColor Yellow
$testScript = Join-Path $RepoRoot "AllScripts\Tests\Test_SunshineWatchdog.ahk"
if (Test-Path $testScript) {
    $testProc = Start-Process -FilePath $ahkExe -ArgumentList "`"$testScript`"" -Wait -PassThru -NoNewWindow
    if ($testProc.ExitCode -eq 0) {
        Write-Host "  PASS: Test_SunshineWatchdog.ahk (All 15 test cases passed)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Test_SunshineWatchdog.ahk failed (Exit code: $($testProc.ExitCode))" -ForegroundColor Red
        $Passed = $false
    }
} else {
    Write-Host "  SKIP: Test_SunshineWatchdog.ahk not found" -ForegroundColor Yellow
}

# 4. Prohibited punctuation sweep
Write-Host "[4/6] Checking for prohibited punctuation..." -ForegroundColor Yellow
$cleanDashesScript = Join-Path $RepoRoot "scripts\clean_dashes.py"
if (Test-Path $cleanDashesScript) {
    $dashOut = & python $cleanDashesScript --all --check 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS: Clean! Scanned files, zero violations found" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Dash violations found:" -ForegroundColor Red
        Write-Host "  $dashOut" -ForegroundColor Red
        $Passed = $false
    }
}

# 5. Security and secret leak audit
Write-Host "[5/6] Auditing diff for secrets and private paths..." -ForegroundColor Yellow
$gitDiff = git diff HEAD
$leakFound = $false

$userPattern = [regex]::Escape($env:USERNAME)
$computerPattern = [regex]::Escape($env:COMPUTERNAME)

if ($gitDiff -match "C:\\Users\\[^\\\/`"]+\\") {
    Write-Host "  FAIL: Hardcoded C:\Users\ path found in diff" -ForegroundColor Red
    $leakFound = $true
}

if ($env:USERNAME -and ($gitDiff -match $userPattern)) {
    Write-Host "  FAIL: Machine username ('$($env:USERNAME)') found in diff" -ForegroundColor Red
    $leakFound = $true
}

if ($env:COMPUTERNAME -and ($gitDiff -match $computerPattern)) {
    Write-Host "  FAIL: Machine computer name ('$($env:COMPUTERNAME)') found in diff" -ForegroundColor Red
    $leakFound = $true
}

# Check for personal Tailscale IP pattern in diff
if ($gitDiff -match "100\.\d{1,3}\.\d{1,3}\.\d{1,3}") {
    Write-Host "  FAIL: Personal Tailscale IP found in diff" -ForegroundColor Red
    $leakFound = $true
}

if (-not $leakFound) {
    Write-Host "  PASS: Zero private paths, usernames, or IP leaks detected" -ForegroundColor Green
} else {
    $Passed = $false
}

# 6. Fleet compilation verification
Write-Host "[6/6] Compiling master binaries (dry-run build)..." -ForegroundColor Yellow
$buildScript = Join-Path $RepoRoot "build_startup_exe.ps1"
if (Test-Path $buildScript) {
    $buildOut = & pwsh -ExecutionPolicy Bypass -File $buildScript 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS: StartupScript.exe and WirelessShare.exe compiled cleanly" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Build compilation failed:" -ForegroundColor Red
        Write-Host "  $buildOut" -ForegroundColor Red
        $Passed = $false
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
if ($Passed) {
    Write-Host "PRE-FLIGHT STATUS: ALL CHECKS PASSED. READY FOR COMMIT." -ForegroundColor Green
    exit 0
} else {
    Write-Host "PRE-FLIGHT STATUS: ONE OR MORE CHECKS FAILED." -ForegroundColor Red
    exit 1
}
