$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Set Always-On Power Profile                                    v2.0.0
FILE   : power_profile_always_on.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Creates a custom "Always On - Limehawk" power plan optimized for workstations
    that should never sleep while on AC power. If the plan already exists, it will
    be reused and reconfigured. The plan is based on High Performance settings.

REQUIRED INPUTS:
    $customPlanName     : Name of the custom power plan
    $displayTimeoutAC   : Display timeout on AC power (minutes)
    $displayTimeoutDC   : Display timeout on battery (minutes)
    $diskTimeoutAC      : Hard disk timeout on AC power (minutes)
    $diskTimeoutDC      : Hard disk timeout on battery (minutes)
    $standbyTimeoutAC   : Sleep timeout on AC power (0 = never)
    $standbyTimeoutDC   : Sleep timeout on battery (minutes)
    $hibernateTimeoutAC : Hibernate timeout on AC power (0 = never)
    $hibernateTimeoutDC : Hibernate timeout on battery (minutes)

BEHAVIOR:
    1. Validates all hardcoded timeout values and plan name
    2. Verifies script is running with Administrator privileges
    3. Checks if custom power plan already exists
    4. Creates or reuses the custom power plan
    5. Sets the custom plan as active
    6. Configures all power timeouts
    7. Disables hibernation on desktops (no battery)

PREREQUISITES:
    - Windows 10/11 or Windows Server 2016+
    - Administrator privileges
    - High Performance power plan must exist

SECURITY NOTES:
    - No secrets in logs
    - All operations are local

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    All required inputs are valid

    [ POWER PLAN SETUP ]
    --------------------------------------------------------------
    Custom Plan Name         : Always On - Limehawk
    Plan Status              : Creating new plan
    Active Plan              : Always On - Limehawk

    [ APPLYING POWER SETTINGS ]
    --------------------------------------------------------------
    Display Timeout (AC)     : 30 minutes
    Standby Timeout (AC)     : 0 (Never)

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Power plan configured successfully

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v2.0.0  Migrated from SuperOps - removed module dependency
2025-09-12 v1.0.0  Initial version
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$customPlanName     = "Always On - Limehawk"
$displayTimeoutAC   = 30   # Minutes until display turns off on AC power
$displayTimeoutDC   = 10   # Minutes until display turns off on battery
$diskTimeoutAC      = 60   # Minutes until hard disk spins down on AC power
$diskTimeoutDC      = 30   # Minutes until hard disk spins down on battery
$standbyTimeoutAC   = 0    # Minutes until system sleeps on AC power (0 = never)
$standbyTimeoutDC   = 20   # Minutes until system sleeps on battery
$hibernateTimeoutAC = 0    # Minutes until system hibernates on AC (0 = never)
$hibernateTimeoutDC = 45   # Minutes until system hibernates on battery

# High Performance plan GUID (standard across Windows installations)
$highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($customPlanName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Custom plan name cannot be empty"
}

$timeouts = @{
    'Display timeout (AC)'   = $displayTimeoutAC
    'Display timeout (DC)'   = $displayTimeoutDC
    'Disk timeout (AC)'      = $diskTimeoutAC
    'Disk timeout (DC)'      = $diskTimeoutDC
    'Standby timeout (AC)'   = $standbyTimeoutAC
    'Standby timeout (DC)'   = $standbyTimeoutDC
    'Hibernate timeout (AC)' = $hibernateTimeoutAC
    'Hibernate timeout (DC)' = $hibernateTimeoutDC
}

foreach ($name in $timeouts.Keys) {
    $value = $timeouts[$name]
    if ($value -lt 0 -or $value -gt 999) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- $name must be between 0-999 minutes"
    }
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"
    exit 1
}

Write-Host "All required inputs are valid"

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
Write-Host ""
Write-Host "[ INITIALIZING SCRIPT ]"
Write-Host "--------------------------------------------------------------"

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "This script must be run with Administrator privileges"
    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"
    exit 1
}

Write-Host ("Privilege Check".PadRight(24) + " : Administrator")
Write-Host ("Host Name".PadRight(24) + " : $env:COMPUTERNAME")

$activePlanRaw = powercfg /getactivescheme
$previousPlanName = if ($activePlanRaw -match '\(([^)]+)\)') { $matches[1] } else { "Unknown" }
Write-Host ("Previous Active Plan".PadRight(24) + " : $previousPlanName")

# ============================================================================
# CREATE OR REUSE CUSTOM POWER PLAN
# ============================================================================
Write-Host ""
Write-Host "[ POWER PLAN SETUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host ("Custom Plan Name".PadRight(24) + " : $customPlanName")

$allPlansRaw = powercfg /list
$customPlanGuid = $null

foreach ($line in $allPlansRaw) {
    if ($line -match '([a-f0-9-]{36}).*\((.+)\)') {
        $guid = $matches[1]
        $name = $matches[2]
        if ($name -eq $customPlanName) {
            $customPlanGuid = $guid
            break
        }
    }
}

if ($customPlanGuid) {
    Write-Host ("Plan Status".PadRight(24) + " : Already exists (reusing)")
    Write-Host ("Plan GUID".PadRight(24) + " : $customPlanGuid")
}
else {
    Write-Host ("Plan Status".PadRight(24) + " : Creating new plan")
    $duplicateOutput = powercfg /duplicatescheme $highPerfGuid

    if ($duplicateOutput -match '([a-f0-9-]{36})') {
        $customPlanGuid = $matches[1]
        Write-Host ("Plan GUID".PadRight(24) + " : $customPlanGuid")
        powercfg /changename $customPlanGuid $customPlanName "Limehawk managed always-on power plan" | Out-Null
        Write-Host ("Plan Created".PadRight(24) + " : Based on High Performance")
    }
    else {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Failed to create custom power plan"
        Write-Host ""
        Write-Host "[ SCRIPT COMPLETED ]"
        Write-Host "--------------------------------------------------------------"
        exit 1
    }
}

powercfg /setactive $customPlanGuid
Write-Host ("Active Plan".PadRight(24) + " : $customPlanName")

# ============================================================================
# APPLY POWER SETTINGS
# ============================================================================
Write-Host ""
Write-Host "[ APPLYING POWER SETTINGS ]"
Write-Host "--------------------------------------------------------------"

$formatLabel = { param($val) if ($val -eq 0) { "0 (Never)" } else { "$val minutes" } }

powercfg.exe -change -monitor-timeout-ac $displayTimeoutAC
Write-Host ("Display Timeout (AC)".PadRight(24) + " : " + (& $formatLabel $displayTimeoutAC))

powercfg.exe -change -monitor-timeout-dc $displayTimeoutDC
Write-Host ("Display Timeout (DC)".PadRight(24) + " : " + (& $formatLabel $displayTimeoutDC))

powercfg.exe -change -disk-timeout-ac $diskTimeoutAC
Write-Host ("Disk Timeout (AC)".PadRight(24) + " : " + (& $formatLabel $diskTimeoutAC))

powercfg.exe -change -disk-timeout-dc $diskTimeoutDC
Write-Host ("Disk Timeout (DC)".PadRight(24) + " : " + (& $formatLabel $diskTimeoutDC))

powercfg.exe -change -standby-timeout-ac $standbyTimeoutAC
Write-Host ("Standby Timeout (AC)".PadRight(24) + " : " + (& $formatLabel $standbyTimeoutAC))

powercfg.exe -change -standby-timeout-dc $standbyTimeoutDC
Write-Host ("Standby Timeout (DC)".PadRight(24) + " : " + (& $formatLabel $standbyTimeoutDC))

# ============================================================================
# CONFIGURE HIBERNATION
# ============================================================================
Write-Host ""
Write-Host "[ CONFIGURING HIBERNATION ]"
Write-Host "--------------------------------------------------------------"

$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

if ($null -eq $battery) {
    Write-Host ("Battery Status".PadRight(24) + " : NOT DETECTED")
    powercfg.exe -h off
    Write-Host ("Hibernation".PadRight(24) + " : DISABLED")
}
else {
    Write-Host ("Battery Status".PadRight(24) + " : DETECTED")
    powercfg.exe -change -hibernate-timeout-ac $hibernateTimeoutAC
    Write-Host ("Hibernate Timeout (AC)".PadRight(24) + " : " + (& $formatLabel $hibernateTimeoutAC))
    powercfg.exe -change -hibernate-timeout-dc $hibernateTimeoutDC
    Write-Host ("Hibernate Timeout (DC)".PadRight(24) + " : " + (& $formatLabel $hibernateTimeoutDC))
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Power plan configured: $customPlanName"
Write-Host "Settings are effective immediately"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
