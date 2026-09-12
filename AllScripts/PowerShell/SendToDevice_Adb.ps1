param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("phone", "s24", "s24_ultra", "tablet", "tab", "tab_s10")]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [string]$TailscaleIp = "",

    [Parameter(Mandatory = $false)]
    [string]$LanIp = "",

    [Parameter(Mandatory = $false)]
    [string]$AdbPath = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

# =============================================================================
# SendToDevice_Adb.ps1: Resilient Wireless File Transfer Engine
# =============================================================================
# Features:
# 1. Non-blocking 500ms TCP socket pre-check (eliminates native 21s adb freeze)
# 2. Dual-IP failover: Tailscale WireGuard IP -> Local Wi-Fi LAN IP
# 3. Dynamic IP lookup from Sefirah database if static LAN IP changed
# 4. Non-destructive duplicate auto-numbering (file.ext -> file (1).ext)
# 5. O(1) in-memory collision detection for multi-file batches
# 6. URI-encoded Android MediaScanner broadcast (space and symbol safe)
# 7. Sefirah GUI failover if wireless debugging is completely offline
# =============================================================================

# Resolve ADB executable
$adbExe = $AdbPath
if (-not $adbExe -or -not (Test-Path $adbExe)) {
    $localPathsFile = Join-Path $PSScriptRoot "..\LocalPaths.ahk"
    if (Test-Path $localPathsFile) {
        $adbMatch = Select-String -Path $localPathsFile -Pattern 'PATH_ADB_EXE\s*:=\s*["'']([^"'']+)["'']'
        if ($adbMatch -and (Test-Path $adbMatch.Matches[0].Groups[1].Value)) {
            $adbExe = $adbMatch.Matches[0].Groups[1].Value
        }
    }
}
if (-not $adbExe -or -not (Test-Path $adbExe)) {
    $adbExe = "adb.exe"
}

# Helper to read a variable from LocalPaths.ahk if parameter is empty
function Get-LocalAhkVar {
    param([string]$VarName)
    $localPathsFile = Join-Path $PSScriptRoot "..\LocalPaths.ahk"
    if (Test-Path $localPathsFile) {
        $m = Select-String -Path $localPathsFile -Pattern "$VarName\s*:=\s*[`"']([^`"']+)[`"']"
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return ""
}

# Target Device Profile Setup
if ($Target -in @("phone", "s24", "s24_ultra")) {
    $targetName        = "S24 Ultra"
    $targetTailscaleIp = if ($TailscaleIp) { $TailscaleIp } else { Get-LocalAhkVar "ADB_PHONE_TAILSCALE_IP" }
    $targetLanIp       = if ($LanIp) { $LanIp } else { Get-LocalAhkVar "ADB_PHONE_LAN_IP" }
    $sefirahDeviceKey  = "S24_Ultra"
} else {
    $targetName        = "Tab S10 Ultra"
    $targetTailscaleIp = if ($TailscaleIp) { $TailscaleIp } else { Get-LocalAhkVar "ADB_TABLET_TAILSCALE_IP" }
    $targetLanIp       = if ($LanIp) { $LanIp } else { Get-LocalAhkVar "ADB_TABLET_LAN_IP" }
    $sefirahDeviceKey  = "Tab S10 Ultra"
}

# Fallback to generic Sefirah / Sunshine targets if specific variables are not set
if (-not $targetTailscaleIp -and $Target -notin @("phone", "s24", "s24_ultra")) {
    $targetTailscaleIp = Get-LocalAhkVar "SUNSHINE_TABLET_TAILSCALE_IP"
    if ($targetTailscaleIp -and $targetTailscaleIp -notmatch ":\d+$") {
        $targetTailscaleIp = "$targetTailscaleIp`:5555"
    }
}

$destFolder = "/sdcard/Download/_LaptopTransfers"

function Show-ToastNotification {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
        $escapedMsg   = [System.Security.SecurityElement]::Escape($Message)

        $template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$escapedTitle</text>
            <text>$escapedMsg</text>
        </binding>
    </visual>
</toast>
"@
        $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xml.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Wireless Share ($targetName)").Show($toast)
    } catch {
        # Fallback to Tray Notification if WinRT Toast is unavailable
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $notify = New-Object System.Windows.Forms.NotifyIcon
            $notify.Icon = [System.Drawing.SystemIcons]::Information
            $notify.BalloonTipTitle = $Title
            $notify.BalloonTipText = $Message
            $notify.Visible = $True
            $notify.ShowBalloonTip(3000)
        } catch {}
    }
}

function Test-TcpPortFast {
    param(
        [string]$HostAndPort,
        [int]$TimeoutMs = 500
    )
    try {
        $parts = $HostAndPort.Split(':')
        $hostName = $parts[0]
        $port = if ($parts.Length -gt 1) { [int]$parts[1] } else { 5555 }

        $tcp = [System.Net.Sockets.TcpClient]::new()
        $iar = $tcp.BeginConnect($hostName, $port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            $tcp.Close()
            return $true
        }
        $tcp.Close()
        return $false
    } catch {
        return $false
    }
}

function Get-DynamicIpsFromSefirahDb {
    param([string]$DeviceNameMatch)
    $ipList = @()
    $dbPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Packages\shrimqy.Seki-PhoneLink_9yhjgvpvzzxz2\LocalState\sefirah.db')
    if (-not (Test-Path $dbPath)) { return $ipList }

    try {
        # Quick regex sweep over DB text to avoid SQLite assembly dependencies
        $content = [System.IO.File]::ReadAllText($dbPath)
        if ($content -match "(?s)$DeviceNameMatch.*?(\[\{.*?\}\])") {
            $jsonStr = $matches[1]
            $entries = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                if ($entry.IsEnabled -and $entry.Address -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                    $ipList += ($entry.Address + ":5555")
                }
            }
        }
    } catch {}
    return $ipList
}

function Get-UniqueDestinationFileName {
    param(
        [string]$BaseFileName,
        [System.Collections.Generic.HashSet[string]]$ExistingNamesSet
    )
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseFileName)
    $ext = [System.IO.Path]::GetExtension($BaseFileName)

    $prefix = $nameWithoutExt
    $startCounter = 1
    if ($nameWithoutExt -match '^(.*) \((\d+)\)$') {
        $prefix = $matches[1]
        $startCounter = [int]$matches[2] + 1
    }

    $candidate = $BaseFileName
    $counter = $startCounter
    while ($ExistingNamesSet.Contains($candidate)) {
        $candidate = "$prefix ($counter)$ext"
        $counter++
    }

    # Reserve candidate name in memory for multi-file batch protection
    [void]$ExistingNamesSet.Add($candidate)
    return $candidate
}

# 1. Resolve Files to Transfer
$transferFiles = @()
if ($Files -and $Files.Count -gt 0) {
    foreach ($f in $Files) {
        $cleanPath = $f.Trim('"').Trim("'")
        if (Test-Path $cleanPath) {
            $transferFiles += (Resolve-Path $cleanPath).Path
        }
    }
}

# If no files passed as CLI arguments, check active Windows Explorer selection via COM
if ($transferFiles.Count -eq 0) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $activeWindow = $shell.Windows() | Where-Object { $_.HWND -and ($_.Document -ne $null) } | Select-Object -First 1
        if ($activeWindow -and $activeWindow.Document.SelectedItems()) {
            foreach ($item in $activeWindow.Document.SelectedItems()) {
                if (Test-Path $item.Path) {
                    $transferFiles += $item.Path
                }
            }
        }
    } catch {}
}

# If still empty, check clipboard for file paths
if ($transferFiles.Count -eq 0) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
            foreach ($drop in [System.Windows.Forms.Clipboard]::GetFileDropList()) {
                if (Test-Path $drop) {
                    $transferFiles += $drop
                }
            }
        } elseif ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $text = [System.Windows.Forms.Clipboard]::GetText().Trim()
            if (Test-Path $text) {
                $transferFiles += (Resolve-Path $text).Path
            }
        }
    } catch {}
}

if ($transferFiles.Count -eq 0) {
    Show-ToastNotification "No Files Selected" "Please select a file in Explorer or copy a file to send to $targetName."
    exit 0
}

# 2. Dual-IP Reachability Probe (Fast 500ms Socket Checks)
$activeIp = $null
$routeType = ""

# Step 2A: Probe Tailscale IP
if (Test-TcpPortFast $targetTailscaleIp 500) {
    $activeIp = $targetTailscaleIp
    $routeType = "Tailscale ADB"
}

# Step 2B: Fallback to Local Wi-Fi LAN IP
if (-not $activeIp -and (Test-TcpPortFast $targetLanIp 500)) {
    $activeIp = $targetLanIp
    $routeType = "Local Wi-Fi ADB"
}

# Step 2C: Fallback to Dynamic IP from Sefirah DB if static IP shifted
if (-not $activeIp) {
    $dbIps = Get-DynamicIpsFromSefirahDb $sefirahDeviceKey
    foreach ($candIp in $dbIps) {
        if ($candIp -ne $targetTailscaleIp -and $candIp -ne $targetLanIp) {
            if (Test-TcpPortFast $candIp 500) {
                $activeIp = $candIp
                $routeType = "Local Wi-Fi ADB (Dynamic)"
                break
            }
        }
    }
}

# Step 2D: Fallback if all ADB sockets are offline (Wireless Debugging disabled)
if (-not $activeIp) {
    # Launch Sefirah app so user can share via GUI
    try {
        Start-Process "explorer.exe" -ArgumentList "shell:AppsFolder\shrimqy.Seki-PhoneLink_9yhjgvpvzzxz2!App"
    } catch {}
    Show-ToastNotification "$targetName ADB Offline" "Wireless debugging offline. Opened Sefirah app to share manually."
    exit 1
}

# 3. Connect ADB and Prepare Destination Directory
& $adbExe connect $activeIp 2>&1 | Out-Null
$state = (& $adbExe -s $activeIp get-state 2>&1) -join ""
if ($state -notmatch "device") {
    Show-ToastNotification "$targetName Connection Stalled" "Socket responded but ADB state is '$state'. Check device screen."
    exit 1
}

& $adbExe -s $activeIp shell mkdir -p $destFolder 2>&1 | Out-Null

# 4. Populate In-Memory HashSet for O(1) Non-Destructive Duplicate Detection
$existingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$rawFileList = & $adbExe -s $activeIp shell "ls -1 '$destFolder'" 2>$null
if ($rawFileList) {
    foreach ($line in $rawFileList) {
        $trimmed = $line.Trim()
        if ($trimmed -ne "") {
            [void]$existingSet.Add($trimmed)
        }
    }
}

# 5. Transfer Files and Trigger Android MediaScanner Broadcast
$successCount = 0
$transferredNames = @()

foreach ($file in $transferFiles) {
    $baseName = [System.IO.Path]::GetFileName($file)
    $uniqueTargetName = Get-UniqueDestinationFileName $baseName $existingSet
    $transferredNames += $uniqueTargetName

    # Push to destination with resolved unique filename
    $destFilePath = "$destFolder/$uniqueTargetName"
    $pushOut = & $adbExe -s $activeIp push "$file" "$destFilePath" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $successCount++

        # URI-encode path for spaces and symbols before MediaScanner broadcast
        $escapedUri = [System.Uri]::EscapeUriString("file://$destFilePath")
        & $adbExe -s $activeIp shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "$escapedUri" 2>&1 | Out-Null
    }
}

# 6. User Feedback via Native Windows Toast
if ($successCount -eq 1) {
    Show-ToastNotification "Sent to $targetName ($routeType)" "$($transferredNames[0]) -> Download/_LaptopTransfers"
} elseif ($successCount -gt 1) {
    Show-ToastNotification "Sent to $targetName ($routeType)" "$successCount files transferred -> Download/_LaptopTransfers"
} else {
    Show-ToastNotification "Transfer Failed" "Failed pushing payload to $targetName."
}
