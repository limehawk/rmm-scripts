$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : New Outlook Force Migration                                  v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\new_outlook_force_migration.ps1
================================================================================
 FILE     : new_outlook_force_migration.ps1
 DESCRIPTION : Forces migration to New Outlook and hides toggle to prevent revert
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Forces all user profiles on a machine to migrate to New Outlook and
   prevents them from switching back to Classic Outlook. Applies registry
   keys across all loaded and unloaded user hives since this runs as
   SYSTEM via RMM. Also sets machine-wide (HKLM) policies to enforce
   New Outlook as the default mail client.

 DATA SOURCES & PRIORITY

   - Windows Registry: Per-user Outlook preferences (ntuser.dat hives)
   - Windows Registry: Machine-wide Outlook/Office policies (HKLM)
   - User profile list: HKU enumeration + ProfileList for offline hives

 REQUIRED INPUTS

   All inputs are hardcoded in the script body (booleans, $true/$false):
     - $forceAutoMigration: Enable auto-migration to New Outlook
     - $setNewOutlookDefault: Set New Outlook as default mail client
     - $hideClassicToggle: Hide the "switch to classic" toggle
     - $enableOneWinNative: Enable One Win Native Outlook via policy

 SETTINGS

   All options default to $true (full lockdown to New Outlook).
   Set individual options to $false to keep specific behaviors.

 BEHAVIOR

   The script performs the following actions in order:
   1. Detects all user profile registry hives on the machine
   2. Loads any unloaded ntuser.dat hives into HKU temporarily
   3. Applies per-user registry keys for Outlook migration preferences
   4. Unloads any hives that were loaded temporarily
   5. Applies machine-wide HKLM policies for New Outlook enforcement
   6. Reports per-profile results

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges required (runs as SYSTEM via RMM)
   - Windows 10/11

 SECURITY NOTES

   - No secrets exposed in output
   - Modifies user registry hives - changes persist across logins
   - Users will not be able to revert to Classic Outlook without admin
     intervention to remove these keys

 ENDPOINTS

   - Not applicable (local registry operations only)

 EXIT CODES

   0 = Success (all profiles configured)
   1 = Failure (error occurred)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
   All inputs are valid

 [INFO] PROFILE DISCOVERY
 ==============================================================
   Profiles found : 3
     S-1-5-21-...-1001 (C:\Users\jsmith)
     S-1-5-21-...-1002 (C:\Users\kryan)
     S-1-5-21-...-1003 (C:\Users\admin.local)

 [RUN] PER-USER REGISTRY CONFIGURATION
 ==============================================================
   [OK] jsmith - all keys applied
   [OK] kryan - all keys applied
   [OK] admin.local - all keys applied
   Profiles configured : 3

 [RUN] MACHINE-WIDE POLICY
 ==============================================================
   [OK] HKLM Outlook policies applied

 [OK] FINAL STATUS
 ==============================================================
   Result : New Outlook migration enforced
   Profiles updated : 3

 [OK] SCRIPT COMPLETED
 ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-01 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# State variables
# ---------------------------------------------------------------------------
$errorOccurred = $false
$errorText     = ''
$profilesConfigured = 0
$hivesLoaded   = @()

# ---------------------------------------------------------------------------
# Hardcoded inputs
# ---------------------------------------------------------------------------
$forceAutoMigration  = $true
$setNewOutlookDefault = $true
$hideClassicToggle   = $true
$enableOneWinNative  = $true

# ---------------------------------------------------------------------------
# Helper: Write-Section
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ''
    Write-Host "[$label] $Name"
    Write-Host '=============================================================='
}

# ---------------------------------------------------------------------------
# Helper: Apply per-user Outlook registry keys under a given HKU path
# ---------------------------------------------------------------------------
function Set-OutlookUserKeys {
    param([string]$HkuPath)

    $optionsPath = "$HkuPath\Software\Microsoft\Office\16.0\Outlook\Options\General"
    $prefsPath   = "$HkuPath\Software\Microsoft\Office\16.0\Outlook\Preferences"

    if ($forceAutoMigration) {
        if (-not (Test-Path "Registry::$optionsPath")) {
            New-Item -Path "Registry::$optionsPath" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::$optionsPath" -Name 'DoNewOutlookAutoMigration' -Value 1 -Type DWord
    }

    if ($hideClassicToggle) {
        if (-not (Test-Path "Registry::$optionsPath")) {
            New-Item -Path "Registry::$optionsPath" -Force | Out-Null
        }
        # HideNewOutlookToggle = 0 means the toggle is hidden in classic (counterintuitive name)
        Set-ItemProperty -Path "Registry::$optionsPath" -Name 'HideNewOutlookToggle' -Value 0 -Type DWord
    }

    if ($setNewOutlookDefault) {
        if (-not (Test-Path "Registry::$prefsPath")) {
            New-Item -Path "Registry::$prefsPath" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::$prefsPath" -Name 'UseNewOutlook' -Value 1 -Type DWord
    }
}

# ============================================================================
# MAIN
# ============================================================================

# ---------------------------------------------------------------------------
# INPUT VALIDATION
# ---------------------------------------------------------------------------
Write-Section 'info' 'INPUT VALIDATION'

if (-not $forceAutoMigration -and -not $setNewOutlookDefault -and -not $hideClassicToggle -and -not $enableOneWinNative) {
    $errorOccurred = $true
    $errorText += '- All options are disabled. Enable at least one migration setting.'
}

if ($errorOccurred) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  $errorText"
    exit 1
}

Write-Host '  All inputs are valid'

# ---------------------------------------------------------------------------
# PROFILE DISCOVERY
# ---------------------------------------------------------------------------
Write-Section 'info' 'PROFILE DISCOVERY'

$profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$profileItems = Get-ChildItem -Path $profileListPath | Where-Object {
    $_.PSChildName -match '^S-1-5-21-'
}

$profiles = @()
foreach ($item in $profileItems) {
    $sid = $item.PSChildName
    $profileImagePath = (Get-ItemProperty -Path $item.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
    if ($profileImagePath) {
        $profiles += [PSCustomObject]@{
            SID              = $sid
            ProfilePath      = $profileImagePath
            Username         = Split-Path $profileImagePath -Leaf
            HiveAlreadyLoaded = $false
        }
    }
}

Write-Host "  Profiles found : $($profiles.Count)"
foreach ($p in $profiles) {
    Write-Host "    $($p.SID) ($($p.ProfilePath))"
}

if ($profiles.Count -eq 0) {
    Write-Section 'warn' 'NO PROFILES'
    Write-Host '  No user profiles found to configure'
    Write-Section 'ok' 'SCRIPT COMPLETED'
    exit 0
}

# ---------------------------------------------------------------------------
# PER-USER REGISTRY CONFIGURATION
# ---------------------------------------------------------------------------
Write-Section 'run' 'PER-USER REGISTRY CONFIGURATION'

foreach ($profile in $profiles) {
    $sid      = $profile.SID
    $username = $profile.Username

    try {
        # Check if the hive is already loaded under HKU
        $hiveLoaded = Test-Path "Registry::HKEY_USERS\$sid"

        if (-not $hiveLoaded) {
            # Load the ntuser.dat hive
            $ntUserDat = Join-Path $profile.ProfilePath 'ntuser.dat'
            if (-not (Test-Path $ntUserDat)) {
                Write-Host "  [WARN] $username - ntuser.dat not found, skipping"
                continue
            }
            $regLoadResult = & reg.exe load "HKU\$sid" $ntUserDat 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [WARN] $username - could not load hive (may be in use): $regLoadResult"
                continue
            }
            $hivesLoaded += $sid
        } else {
            $profile.HiveAlreadyLoaded = $true
        }

        # Apply the per-user keys
        Set-OutlookUserKeys -HkuPath "HKEY_USERS\$sid"
        Write-Host "  [OK] $username - all keys applied"
        $profilesConfigured++

    } catch {
        Write-Host "  [WARN] $username - failed: $($_.Exception.Message)"
    }
}

# Unload any hives we loaded
foreach ($sid in $hivesLoaded) {
    try {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg.exe unload "HKU\$sid" 2>&1 | Out-Null
    } catch {
        Write-Host "  [WARN] Could not unload hive for $sid"
    }
}

Write-Host "  Profiles configured : $profilesConfigured"

# ---------------------------------------------------------------------------
# MACHINE-WIDE POLICY
# ---------------------------------------------------------------------------
Write-Section 'run' 'MACHINE-WIDE POLICY'

try {
    if ($enableOneWinNative) {
        # Machine-wide policy to enable New Outlook for all users
        $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Preferences'
        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $policyPath -Name 'NewOutlookMigrationComplete' -Value 1 -Type DWord
        Set-ItemProperty -Path $policyPath -Name 'UseNewOutlook' -Value 1 -Type DWord

        # OneWinNativeOutlookEnabled policy
        $outlookPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook'
        if (-not (Test-Path $outlookPolicyPath)) {
            New-Item -Path $outlookPolicyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $outlookPolicyPath -Name 'OneWinNativeOutlookEnabled' -Value 1 -Type DWord
    }

    Write-Host '  [OK] HKLM Outlook policies applied'

} catch {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  Machine-wide policy failed: $($_.Exception.Message)"
    exit 1
}

# ---------------------------------------------------------------------------
# FINAL STATUS
# ---------------------------------------------------------------------------
Write-Section 'ok' 'FINAL STATUS'
Write-Host "  Result : New Outlook migration enforced"
Write-Host "  Profiles updated : $profilesConfigured"

Write-Section 'ok' 'SCRIPT COMPLETED'

exit 0
