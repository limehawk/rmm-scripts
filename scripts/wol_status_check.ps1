$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT  : Wake-on-LAN Status Check v1.0.4
 AUTHOR  : Limehawk.io
 DATE    : April 2026
 FILE    : wol_status_check.ps1
 DESCRIPTION : Checks Wake-on-LAN status at BIOS and OS levels
 USAGE   : .\wol_status_check.ps1
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE:
    Checks the Wake-on-LAN (WOL) status at both BIOS and OS levels.
    Supports Dell, HP, and Lenovo devices by using manufacturer-specific
    PowerShell modules to query BIOS settings.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Detects device manufacturer (Dell, HP, or Lenovo)
    2. Installs required PowerShell modules if needed
    3. Queries BIOS for WOL settings
    4. Checks OS-level NIC WOL configuration
    5. Reports combined status

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - Internet access (for module installation)
    - Supported manufacturer: Dell, HP, or Lenovo

SECURITY NOTES:
    - No secrets in logs
    - Requires elevated privileges
    - May install PowerShell modules from PSGallery

EXIT CODES:
    0 = WOL enabled correctly (or unsupported manufacturer)
    1 = WOL not properly configured

EXAMPLE RUN:
    [INFO] MANUFACTURER DETECTION
    ==============================================================
    Manufacturer         : Dell Inc.

    [INFO] BIOS WOL STATUS
    ==============================================================
    Module               : DellBIOSProvider
    BIOS WOL Setting     : LanOnly

    [INFO] OS WOL STATUS
    ==============================================================
    NIC WOL Enabled      : Yes (All NICs)

    [OK] FINAL STATUS
    ==============================================================
    BIOS WOL             : Healthy
    OS WOL               : Healthy
    SCRIPT SUCCEEDED

    [OK] SCRIPT COMPLETE
    ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-15 v1.0.4 Fix .Count on null when no package providers need installing
 2026-01-19 v1.0.3 Fixed EXAMPLE RUN section formatting
 2026-01-19 v1.0.2 Updated to two-line ASCII console output style
 2025-12-23 v1.0.1 Updated to Limehawk Script Framework
 2024-12-01 v1.0.0 Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title, [string]$prefix = "INFO")
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $prefix, $title)
    Write-Host ("=" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

function Install-RequiredProviders {
    $installed = @()

    $PPNuGet = Get-PackageProvider -ListAvailable | Where-Object { $_.Name -eq "Nuget" }
    if (-not $PPNuGet) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        $installed += "NuGet"
    }

    $PSGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $PSGallery) {
        Set-PSRepository -InstallationPolicy Trusted -Name PSGallery
        $installed += "PSGallery"
    }

    return $installed
}

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Section "ERROR OCCURRED" "ERROR"
    Write-Host " This script requires administrative privileges to run."
    Write-Section "SCRIPT HALTED" "ERROR"
    exit 1
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    $biosWolStatus = "Unknown"
    $osWolStatus = "Unknown"
    $summary = @()

    # Detect Manufacturer
    Write-Section "MANUFACTURER DETECTION"
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    PrintKV "Manufacturer" $Manufacturer

    # Install required package providers
    $installedProviders = @(Install-RequiredProviders)
    if ($installedProviders.Count -gt 0) {
        PrintKV "Installed Providers" ($installedProviders -join ", ")
    }

    # Check BIOS WOL based on manufacturer
    Write-Section "BIOS WOL STATUS"

    if ($Manufacturer -like "*Dell*") {
        $mod = Get-Module -ListAvailable -Name DellBIOSProvider
        if (-not $mod) {
            PrintKV "Installing Module" "DellBIOSProvider"
            Install-Module -Name DellBIOSProvider -Force -ErrorAction Stop
        }
        Import-Module DellBIOSProvider -ErrorAction Stop
        PrintKV "Module" "DellBIOSProvider"

        try {
            $WOLMonitor = Get-Item -Path "DellSmBios:\PowerManagement\WakeOnLan" -ErrorAction Stop
            PrintKV "BIOS WOL Setting" $WOLMonitor.CurrentValue

            if ($WOLMonitor.CurrentValue -eq "LanOnly") {
                $biosWolStatus = "Healthy"
            } else {
                $biosWolStatus = "Unhealthy - Not set to LanOnly"
                $summary += "Dell WOL not set to LanOnly"
            }
        } catch {
            $biosWolStatus = "Error - Could not read setting"
            PrintKV "Error" $_.Exception.Message
        }
    }
    elseif ($Manufacturer -like "*HP*" -or $Manufacturer -like "*Hewlett*") {
        $mod = Get-Module -ListAvailable -Name HPCMSL
        if (-not $mod) {
            PrintKV "Installing Module" "HPCMSL"
            Install-Module -Name HPCMSL -Force -AcceptLicense -ErrorAction Stop
        }
        Import-Module HPCMSL -ErrorAction Stop
        PrintKV "Module" "HPCMSL"

        try {
            $WolTypes = Get-HPBIOSSettingsList | Where-Object { $_.Name -like "*Wake On Lan*" }
            foreach ($WolType in $WolTypes) {
                $value = Get-HPBIOSSettingValue -Name $WolType.Name -ErrorAction Stop
                PrintKV $WolType.Name $value
            }
            $biosWolStatus = "Healthy"
        } catch {
            $biosWolStatus = "Error - Could not read setting"
            PrintKV "Error" $_.Exception.Message
        }
    }
    elseif ($Manufacturer -like "*Lenovo*") {
        PrintKV "Method" "WMI Query"

        try {
            $currentSetting = Get-WmiObject -Class "Lenovo_BiosSetting" -Namespace "root\wmi" -ErrorAction Stop |
                Where-Object { $_.CurrentSetting -ne "" }
            $WOLStatus = $currentSetting.CurrentSetting |
                ConvertFrom-Csv -Delimiter "," -Header "Setting", "Status" |
                Where-Object { $_.Setting -eq "Wake on lan" }

            if ($WOLStatus) {
                $statusParts = $WOLStatus.Status -split ";"
                PrintKV "BIOS WOL Setting" $statusParts[0]

                if ($statusParts[0] -eq "Primary") {
                    $biosWolStatus = "Healthy"
                } else {
                    $biosWolStatus = "Unhealthy - Not set to Primary"
                    $summary += "Lenovo WOL not set to Primary"
                }
            } else {
                $biosWolStatus = "Not Found"
                PrintKV "Setting" "Wake on LAN setting not found"
            }
        } catch {
            $biosWolStatus = "Error - Could not read setting"
            PrintKV "Error" $_.Exception.Message
        }
    }
    else {
        PrintKV "Status" "Manufacturer not supported"
        PrintKV "Supported" "Dell, HP, Lenovo"
        $biosWolStatus = "N/A - Unsupported manufacturer"
    }

    # Check OS-level WOL
    Write-Section "OS WOL STATUS"

    $NicsWithoutWake = Get-CimInstance -ClassName "MSPower_DeviceWakeEnable" -Namespace "root/wmi" -ErrorAction SilentlyContinue |
        Where-Object { $_.Enable -eq $false }

    if (-not $NicsWithoutWake) {
        PrintKV "NIC WOL Enabled" "Yes (All NICs)"
        $osWolStatus = "Healthy"
    } else {
        $count = @($NicsWithoutWake).Count
        PrintKV "NIC WOL Enabled" "No ($count NIC(s) disabled)"
        $osWolStatus = "Unhealthy - $count NIC(s) without WOL"
        $summary += "$count NIC(s) do not have WOL enabled in OS"
    }

    # Final Status
    Write-Section "FINAL STATUS"
    PrintKV "BIOS WOL" $biosWolStatus
    PrintKV "OS WOL" $osWolStatus

    $exitCode = 0
    if ($biosWolStatus -like "Unhealthy*" -or $osWolStatus -like "Unhealthy*") {
        Write-Host "[WARN] SCRIPT COMPLETED WITH WARNINGS"
        if ($summary.Count -gt 0) {
            PrintKV "Issues Found" ($summary -join "; ")
        }
        $exitCode = 1
    } elseif ($biosWolStatus -like "Error*") {
        Write-Host "[ERROR] SCRIPT COMPLETED WITH ERRORS"
        $exitCode = 1
    } else {
        Write-Host "[OK] SCRIPT SUCCEEDED"
    }

    Write-Section "SCRIPT COMPLETE"
    exit $exitCode
}
catch {
    Write-Section "ERROR OCCURRED" "ERROR"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Section "SCRIPT HALTED" "ERROR"
    exit 1
}
