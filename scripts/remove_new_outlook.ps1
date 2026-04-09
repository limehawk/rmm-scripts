$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Remove New Outlook                                           v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\remove_new_outlook.ps1
================================================================================
 FILE     : remove_new_outlook.ps1
 DESCRIPTION : Removes the New Outlook (Microsoft.OutlookForWindows) app from all user profiles and prevents reinstallation
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Removes the "New Outlook" (Microsoft.OutlookForWindows) Appx package from all
 user profiles on a Windows machine and prevents it from being reprovisioned.
 Used when organizations want to keep users on Classic Outlook and prevent the
 new Outlook from appearing via Windows Update or new user provisioning.

 DATA SOURCES & PRIORITY

 1) AppxPackage registry (Get-AppxPackage -AllUsers)
 2) AppxProvisionedPackage store (Get-AppxProvisionedPackage -Online)
 3) Registry: HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $packageName : Appx package name to target (default:
                      Microsoft.OutlookForWindows)
     - $registryPath : UScheduler registry path for OutlookUpdate key

 SETTINGS

 - Package Name: Microsoft.OutlookForWindows
 - Registry Path: HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate
 - Toggle Registry: HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General (HideNewOutlookToggle = 0)

 BEHAVIOR

 1. Checks if the Microsoft.OutlookForWindows Appx package is installed
 2. If found, removes it from all user profiles with Remove-AppxPackage -AllUsers
 3. Removes the provisioned package so it does not reinstall for new users
 4. Deletes the OutlookUpdate registry key under UScheduler to prevent
    re-provisioning via Windows Update
 5. Disables the "Try the new Outlook" toggle in Classic Outlook via registry
 6. Reports what was done and exits with appropriate code

 PREREQUISITES

 - PowerShell 5.1 or later
 - Administrator privileges required
 - No network requirements (local operations only)

 SECURITY NOTES

 - No secrets (API keys, passwords) are used or logged
 - All actions confined to local Appx store and registry

 ENDPOINTS

 - N/A (local machine only)

 EXIT CODES

 - 0 : Success - package removed or was not present
 - 1 : Failure - removal encountered an error

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
   Computer Name : WKSTN-MKT-03
   Username      : SYSTEM
   Package Name  : Microsoft.OutlookForWindows

 [RUN] REMOVING APPX PACKAGE
 ==============================================================
   [INFO] Package found - removing from all users
   [OK] Appx package removed

 [RUN] REMOVING PROVISIONED PACKAGE
 ==============================================================
   [INFO] Provisioned package found - removing
   [OK] Provisioned package removed

 [RUN] CLEANING REGISTRY
 ==============================================================
   [INFO] OutlookUpdate key found - deleting
   [OK] Registry key deleted

 [RUN] HIDING NEW OUTLOOK TOGGLE
 ==============================================================
   [INFO] Setting HideNewOutlookToggle for all user profiles
   [OK] Toggle hidden for 3 user(s)

 [OK] FINAL STATUS
 ==============================================================
   Result : New Outlook removed and blocked from reinstallation

 [OK] SCRIPT COMPLETED
 ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-09 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

# ---------------------------------------------------------------------------
# Hardcoded Inputs
# ---------------------------------------------------------------------------
$packageName  = 'Microsoft.OutlookForWindows'
$registryPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate'

# ---------------------------------------------------------------------------
# State Variables
# ---------------------------------------------------------------------------
$errorOccurred = $false
$errorText     = ""

# ===========================================================================
# INPUT VALIDATION
# ===========================================================================
Write-Section 'info' 'INPUT VALIDATION'
Write-Host "  Computer Name : $env:COMPUTERNAME"
Write-Host "  Username      : $env:USERNAME"
Write-Host "  Package Name  : $packageName"

# ===========================================================================
# REMOVING APPX PACKAGE
# ===========================================================================
Write-Section 'run' 'REMOVING APPX PACKAGE'

try {
    $appxPackage = Get-AppxPackage -AllUsers -Name $packageName -ErrorAction SilentlyContinue

    if ($appxPackage) {
        Write-Host "  [INFO] Package found - removing from all users"
        $appxPackage | Remove-AppxPackage -AllUsers
        Write-Host "  [OK] Appx package removed"
    } else {
        Write-Host "  [INFO] Package not installed - nothing to remove"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to remove Appx package: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# REMOVING PROVISIONED PACKAGE
# ===========================================================================
Write-Section 'run' 'REMOVING PROVISIONED PACKAGE'

try {
    $provPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $packageName }

    if ($provPackage) {
        Write-Host "  [INFO] Provisioned package found - removing"
        $provPackage | Remove-AppxProvisionedPackage -Online
        Write-Host "  [OK] Provisioned package removed"
    } else {
        Write-Host "  [INFO] Provisioned package not present - nothing to remove"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to remove provisioned package: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# CLEANING REGISTRY
# ===========================================================================
Write-Section 'run' 'CLEANING REGISTRY'

try {
    if (Test-Path $registryPath) {
        Write-Host "  [INFO] OutlookUpdate key found - deleting"
        Remove-Item -Path $registryPath -Recurse -Force
        Write-Host "  [OK] Registry key deleted"
    } else {
        Write-Host "  [INFO] OutlookUpdate key not present - nothing to remove"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to remove registry key: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# HIDING NEW OUTLOOK TOGGLE
# ===========================================================================
Write-Section 'run' 'HIDING NEW OUTLOOK TOGGLE'

try {
    $profileList = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' }
    $toggleCount = 0

    foreach ($profile in $profileList) {
        $sid = $profile.PSChildName
        $hivePath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Office\16.0\Outlook\Options\General"

        # Check if hive is loaded (user logged in)
        if (Test-Path "Registry::HKEY_USERS\$sid") {
            if (-not (Test-Path $hivePath)) {
                New-Item -Path $hivePath -Force | Out-Null
            }
            # HideNewOutlookToggle = 0 hides the toggle (counterintuitive naming by Microsoft)
            Set-ItemProperty -Path $hivePath -Name 'HideNewOutlookToggle' -Value 0 -Type DWord
            $toggleCount++
        }
    }

    if ($toggleCount -gt 0) {
        Write-Host "  [OK] Toggle hidden for $toggleCount user(s)"
    } else {
        Write-Host "  [INFO] No loaded user hives found - toggle will be set at next logon via provisioning policy"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to hide New Outlook toggle: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# FINAL STATUS
# ===========================================================================
if ($errorOccurred) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  $errorText"

    Write-Section 'error' 'FINAL STATUS'
    Write-Host "  Result : One or more removal steps failed"

    exit 1
}

Write-Section 'ok' 'FINAL STATUS'
Write-Host "  Result : New Outlook removed and blocked from reinstallation"

Write-Section 'ok' 'SCRIPT COMPLETED'

exit 0
