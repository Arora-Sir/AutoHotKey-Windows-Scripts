<#
.SYNOPSIS
    Shared configuration loader and disk discovery helper for WSL ext4 automation.

.DESCRIPTION
    Provides reusable utility functions across the WSL2 ext4 SSD automation suite:
      - Get-SSDConfig: Loads and parses ssd_config.json (falling back to ssd_config.json.example)
      - Find-TargetSSD: Discovers the target external physical disk based on model, bus, and size filters
#>

function Get-SSDConfig {
    <#
    .SYNOPSIS
        Resolves and parses the active JSON configuration for WSL SSD mounting.
    #>
    $dir = $PSScriptRoot
    if (-not $dir -and $MyInvocation.MyCommand.Path) {
        $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if (-not $dir -or -not (Test-Path $dir)) {
        $candidate = Join-Path (Get-Location) "AllScripts\PowerShell"
        if (Test-Path $candidate) { $dir = $candidate }
        else { $dir = (Get-Location).Path }
    }

    $userConfig = Join-Path $dir "ssd_config.json"
    $exampleConfig = Join-Path $dir "ssd_config.json.example"

    if (Test-Path $userConfig) {
        return (Get-Content -Path $userConfig -Raw -Encoding UTF8 | ConvertFrom-Json)
    } elseif (Test-Path $exampleConfig) {
        return (Get-Content -Path $exampleConfig -Raw -Encoding UTF8 | ConvertFrom-Json)
    } else {
        throw "Neither ssd_config.json nor ssd_config.json.example found in $dir"
    }
}

function Find-TargetSSD {
    <#
    .SYNOPSIS
        Discovers the target physical external disk matching configured model, bus, and size criteria.
    .PARAMETER Config
        Optional configuration object. If omitted, loaded dynamically via Get-SSDConfig.
    #>
    param($Config)
    if (-not $Config) { $Config = Get-SSDConfig }

    Get-Disk | Where-Object {
        $diskObj = $_
        $matchesModel = $false
        if ($Config.disk.modelFilter -and $Config.disk.modelFilter.Count -gt 0) {
            foreach ($m in $Config.disk.modelFilter) {
                if ($diskObj.FriendlyName -like "*$m*") { $matchesModel = $true; break }
            }
        } else {
            $matchesModel = $true
        }

        $matchesBus = (-not $Config.disk.busType) -or ($diskObj.BusType -eq $Config.disk.busType)
        $matchesSize = $true
        if ($Config.disk.minSizeGB -gt 0) { $matchesSize = $matchesSize -and ($diskObj.Size -ge ($Config.disk.minSizeGB * 1GB)) }
        if ($Config.disk.maxSizeGB -gt 0) { $matchesSize = $matchesSize -and ($diskObj.Size -le ($Config.disk.maxSizeGB * 1GB)) }

        $matchesModel -and $matchesBus -and $matchesSize
    } | Select-Object -First 1
}
