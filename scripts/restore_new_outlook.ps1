$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Restore New Outlook                                          v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\restore_new_outlook.ps1
================================================================================
 FILE     : restore_new_outlook.ps1
 DESCRIPTION : Reinstalls the New Outlook app and re-enables the Try the new Outlook toggle
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Reverses the remove_new_outlook.ps1 script by reinstalling the New Outlook
 (Microsoft.OutlookForWindows) app and re-enabling the "Try the new Outlook"
 toggle in Classic Outlook. Used when an organization wants to roll back the
 removal and allow users to access New Outlook again.

 DATA SOURCES & PRIORITY

 1) winget package manager (preferred install method)
 2) Microsoft Store via Add-AppxPackage (fallback)
 3) Registry: HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler
 4) Registry: HKEY_USERS\<SID>\Software\Microsoft\Office\16.0\Outlook\Options\General

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $packageId    : Winget package identifier (default:
                       Microsoft.OutlookForWindows)
     - $storeUri     : Microsoft Store product URI for fallback install
     - $registryPath : UScheduler registry path for OutlookUpdate key

 SETTINGS

 - Package ID: Microsoft.OutlookForWindows
 - Store URI: ms-windows-store://pdp/?productid=9NRX63209R7B
 - Registry Path: HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate
 - Toggle Registry: HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General (HideNewOutlookToggle)

 BEHAVIOR

 1. Resolves winget path (SYSTEM context aware) and reinstalls the
    Microsoft.OutlookForWindows package via winget
 2. If winget is unavailable, falls back to Add-AppxPackage with the
    Microsoft Store URI
 3. Recreates the OutlookUpdate registry key under UScheduler so Windows
    Update can provision the app again
 4. Iterates loaded user hives and removes the HideNewOutlookToggle value
    to re-enable the toggle in Classic Outlook
 5. Reports results and exits with appropriate code

 PREREQUISITES

 - PowerShell 5.1 or later
 - Administrator privileges required
 - winget recommended (falls back to Store URI if unavailable)

 SECURITY NOTES

 - No secrets (API keys, passwords) are used or logged
 - All actions confined to local Appx store and registry

 ENDPOINTS

 - N/A (local machine only; winget and Store handle network internally)

 EXIT CODES

 - 0 : Success - New Outlook restored
 - 1 : Failure - one or more restoration steps failed

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
   Computer Name : WKSTN-MKT-03
   Username      : SYSTEM
   Package ID    : Microsoft.OutlookForWindows

 [RUN] REINSTALLING NEW OUTLOOK
 ==============================================================
   [INFO] Running as SYSTEM - resolving winget path
   [RUN] Installing via winget
   [OK] New Outlook installed via winget

 [RUN] RE-ENABLING OUTLOOK UPDATE
 ==============================================================
   [INFO] Creating OutlookUpdate registry key
   [OK] OutlookUpdate key created

 [RUN] SHOWING NEW OUTLOOK TOGGLE
 ==============================================================
   [INFO] Removing HideNewOutlookToggle for loaded user profiles
   [OK] Toggle restored for 3 user(s)

 [OK] FINAL STATUS
 ==============================================================
   Result : New Outlook restored and toggle re-enabled

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
$packageId    = 'Microsoft.OutlookForWindows'
$storeUri     = 'ms-windows-store://pdp/?productid=9NRX63209R7B'
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
Write-Host "  Package ID    : $packageId"

# ===========================================================================
# REINSTALLING NEW OUTLOOK
# ===========================================================================
Write-Section 'run' 'REINSTALLING NEW OUTLOOK'

try {
    # Detect if running as SYSTEM
    $isSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    $wingetExe = $null

    if ($isSystem) {
        Write-Host "  [INFO] Running as SYSTEM - resolving winget path"
        $wingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object | Select-Object -Last 1
        if ($wingetPath) {
            $wingetExe = $wingetPath.Path
        }
    } else {
        Write-Host "  [INFO] Running as user - checking winget availability"
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetExe = 'winget'
        }
    }

    if ($wingetExe) {
        Write-Host "  [RUN] Installing via winget"
        $wingetOutput = & $wingetExe install $packageId --accept-package-agreements --accept-source-agreements --silent 2>&1
        $wingetExit = $LASTEXITCODE

        if ($wingetExit -eq 0) {
            Write-Host "  [OK] New Outlook installed via winget"
        } elseif ($wingetExit -eq -1978335189) {
            # Already installed
            Write-Host "  [INFO] New Outlook is already installed"
        } else {
            Write-Host "  [WARN] Winget exited with code $wingetExit - output:"
            Write-Host "  $wingetOutput"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Winget install failed with exit code $wingetExit"
        }
    } else {
        Write-Host "  [WARN] Winget not available - falling back to Microsoft Store"
        Write-Host "  [RUN] Installing via Add-AppxPackage (Store URI)"
        Add-AppxPackage -AppInstallerFile $storeUri
        Write-Host "  [OK] New Outlook install initiated via Store URI"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to reinstall New Outlook: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# RE-ENABLING OUTLOOK UPDATE
# ===========================================================================
Write-Section 'run' 'RE-ENABLING OUTLOOK UPDATE'

try {
    if (Test-Path $registryPath) {
        Write-Host "  [INFO] OutlookUpdate key already exists - no action needed"
    } else {
        Write-Host "  [INFO] Creating OutlookUpdate registry key"
        New-Item -Path $registryPath -Force | Out-Null
        Write-Host "  [OK] OutlookUpdate key created"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to create OutlookUpdate registry key: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# SHOWING NEW OUTLOOK TOGGLE
# ===========================================================================
Write-Section 'run' 'SHOWING NEW OUTLOOK TOGGLE'

try {
    $profileList = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' }
    $toggleCount = 0

    foreach ($profile in $profileList) {
        $sid = $profile.PSChildName
        $hivePath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Office\16.0\Outlook\Options\General"

        # Only process hives that are loaded (user logged in)
        if (Test-Path "Registry::HKEY_USERS\$sid") {
            if (Test-Path $hivePath) {
                $existing = Get-ItemProperty -Path $hivePath -Name 'HideNewOutlookToggle' -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    Remove-ItemProperty -Path $hivePath -Name 'HideNewOutlookToggle' -Force
                    $toggleCount++
                }
            }
        }
    }

    if ($toggleCount -gt 0) {
        Write-Host "  [OK] Toggle restored for $toggleCount user(s)"
    } else {
        Write-Host "  [INFO] No HideNewOutlookToggle values found - toggle already visible"
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Failed to restore New Outlook toggle: $($_.Exception.Message)"
    Write-Host "  [ERROR] $($_.Exception.Message)"
}

# ===========================================================================
# FINAL STATUS
# ===========================================================================
if ($errorOccurred) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  $errorText"

    Write-Section 'error' 'FINAL STATUS'
    Write-Host "  Result : One or more restoration steps failed"

    exit 1
}

Write-Section 'ok' 'FINAL STATUS'
Write-Host "  Result : New Outlook restored and toggle re-enabled"

Write-Section 'ok' 'SCRIPT COMPLETED'

exit 0
