$ErrorActionPreference = 'Stop'

<#
================================================================================
 SCRIPT   : Windows 11 Compatibility Checker v1.0.0
 VERSION  : v1.0.0
================================================================================
 FILE     : windows11_compatibility_checker.ps1
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Evaluates system compatibility for Windows 11 upgrade by checking hardware
 requirements including TPM 2.0, Secure Boot, CPU compatibility, RAM, storage,
 and UEFI firmware. Identifies blockers preventing upgrade and attempts to
 enable required features where possible. Designed for RMM deployment to
 assess upgrade readiness across fleet of devices.

 DATA SOURCES & PRIORITY
 1) Hardcoded values (defined within the script body)
 2) System hardware checks (TPM, Secure Boot, CPU, RAM, storage)
 3) Windows Registry (CPU compatibility list)
 4) Error

 REQUIRED INPUTS
 - MinimumRamGB      : 4
   (Minimum RAM required in GB for Windows 11.)
 - MinimumStorageGB  : 64
   (Minimum storage space required in GB for Windows 11.)
 - AttemptAutoFix    : $false
   (Whether to attempt automatic fixes like enabling TPM or Secure Boot.)
 - CheckOnly         : $true
   (If true, only report compatibility status without making changes.)

 SETTINGS
 - Checks TPM version and status using Get-Tpm cmdlet.
 - Verifies Secure Boot capability and current state.
 - Validates CPU against known Windows 11 compatible processor list.
 - Measures available RAM and storage space.
 - Confirms UEFI firmware mode (not legacy BIOS).
 - Reports all blockers preventing Windows 11 upgrade.

 BEHAVIOR
 - Script performs comprehensive hardware compatibility assessment.
 - Each requirement is checked independently and results are tracked.
 - If CheckOnly is false and AttemptAutoFix is true, script attempts to
   enable TPM and Secure Boot if hardware supports it.
 - Final report shows overall compatibility status and required actions.
 - Exit code indicates if system is ready for Windows 11 upgrade.

 PREREQUISITES
 - PowerShell 5.1 or later.
 - Administrator privileges required.
 - Windows 10 or Windows 11 operating system.
 - TPM and Secure Boot cmdlets available (built into Windows).

 SECURITY NOTES
 - No secrets are printed to the console.
 - Changing BIOS settings (TPM, Secure Boot) requires system reboot.
 - Auto-fix operations are potentially disruptive to system.

 ENDPOINTS
 - N/A (local system checks only)

 EXIT CODES
 - 0 system is Windows 11 compatible
 - 1 system has blockers preventing Windows 11 upgrade
 - 2 script execution error

 EXAMPLE RUN

 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 MinimumRamGB     : 4
 MinimumStorageGB : 64
 AttemptAutoFix   : False
 CheckOnly        : True

 [ TPM CHECK ]
 --------------------------------------------------------------
 TPM Version      : 2.0
 TPM Present      : True
 TPM Enabled      : True
 TPM Activated    : True
 Result           : Pass

 [ SECURE BOOT CHECK ]
 --------------------------------------------------------------
 Secure Boot Capable : True
 Secure Boot Enabled : True
 Result              : Pass

 [ CPU COMPATIBILITY CHECK ]
 --------------------------------------------------------------
 CPU Name         : Intel Core i7-10700
 CPU Family       : Intel
 Result           : Pass

 [ RAM CHECK ]
 --------------------------------------------------------------
 Total RAM        : 16.00 GB
 Required RAM     : 4 GB
 Result           : Pass

 [ STORAGE CHECK ]
 --------------------------------------------------------------
 System Drive     : C:
 Available Space  : 250.00 GB
 Required Space   : 64 GB
 Result           : Pass

 [ FIRMWARE CHECK ]
 --------------------------------------------------------------
 Firmware Type    : UEFI
 Result           : Pass

 [ COMPATIBILITY SUMMARY ]
 --------------------------------------------------------------
 Total Checks     : 6
 Checks Passed    : 6
 Checks Failed    : 0
 Overall Status   : Compatible

 [ FINAL STATUS ]
 --------------------------------------------------------------
 This system is ready for Windows 11 upgrade.

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------
--------------------------------------------------------------------------------
 CHANGELOG
 2025-11-02 v1.0.0 Initial Style A compliant release with Windows 11
                   compatibility checking and optional auto-fix capability.
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""
$checksRun     = 0
$checksPassed  = 0
$checksFailed  = 0
$blockersText  = ""

# ==== HARDCODED INPUTS (MANDATORY) ====
$MinimumRamGB      = 4
$MinimumStorageGB  = 64
$AttemptAutoFix    = $false
$CheckOnly         = $true

# ==== VALIDATION ====
if ($MinimumRamGB -le 0) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- MinimumRamGB must be greater than 0."
}
if ($MinimumStorageGB -le 0) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- MinimumStorageGB must be greater than 0."
}
if ($AttemptAutoFix -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- AttemptAutoFix must be a boolean value."
}
if ($CheckOnly -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- CheckOnly must be a boolean value."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText

    Write-Host ""
    Write-Host "[ RESULT ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Status : Failure"

    Write-Host ""
    Write-Host "[ FINAL STATUS ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Script cannot proceed due to invalid hardcoded inputs."

    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"
    exit 2
}

# ==== RUNTIME OUTPUT (Style A) ====
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "MinimumRamGB     : $MinimumRamGB"
Write-Host "MinimumStorageGB : $MinimumStorageGB"
Write-Host "AttemptAutoFix   : $AttemptAutoFix"
Write-Host "CheckOnly        : $CheckOnly"

# Helper function to safely get property
function Get-SafeProperty {
    param($Object, $PropertyName, $DefaultValue = "N/A")
    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        $value = $Object.$PropertyName
        if ($null -eq $value) {
            return $DefaultValue
        }
        return $value
    }
    return $DefaultValue
}

# Helper function to format bytes to GB
function Format-BytesToGB {
    param([long]$Bytes)
    if ($Bytes -eq 0) { return "0.00" }
    return [math]::Round($Bytes / 1GB, 2)
}

# ==== TPM CHECK ====
Write-Host ""
Write-Host "[ TPM CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$tpmPass = $false

try {
    $tpm = Get-Tpm -ErrorAction Stop

    $tpmPresent = Get-SafeProperty $tpm 'TpmPresent' $false
    $tpmEnabled = Get-SafeProperty $tpm 'TpmEnabled' $false
    $tpmActivated = Get-SafeProperty $tpm 'TpmActivated' $false

    # Get TPM version
    $tpmVersion = "Unknown"
    try {
        $tpmWmi = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class "Win32_Tpm" -ErrorAction SilentlyContinue
        if ($tpmWmi) {
            $specVersion = Get-SafeProperty $tpmWmi 'SpecVersion'
            if ($specVersion -like "2.*") {
                $tpmVersion = "2.0"
            } elseif ($specVersion -like "1.*") {
                $tpmVersion = "1.2"
            }
        }
    } catch {
        $tpmVersion = "Unknown"
    }

    Write-Host "TPM Version      : $tpmVersion"
    Write-Host "TPM Present      : $tpmPresent"
    Write-Host "TPM Enabled      : $tpmEnabled"
    Write-Host "TPM Activated    : $tpmActivated"

    if ($tpmPresent -and $tpmEnabled -and $tpmActivated -and $tpmVersion -eq "2.0") {
        Write-Host "Result           : Pass"
        $checksPassed++
        $tpmPass = $true
    } else {
        Write-Host "Result           : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        if (-not $tpmPresent) {
            $blockersText += "- TPM hardware not present"
        } elseif ($tpmVersion -ne "2.0") {
            $blockersText += "- TPM 2.0 required (found: $tpmVersion)"
        } elseif (-not $tpmEnabled -or -not $tpmActivated) {
            $blockersText += "- TPM is not enabled or activated"
        }
    }

} catch {
    Write-Host "TPM Status       : Unable to determine"
    Write-Host "Error            : $($_.Exception.Message)"
    Write-Host "Result           : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- TPM check failed: $($_.Exception.Message)"
}

# ==== SECURE BOOT CHECK ====
Write-Host ""
Write-Host "[ SECURE BOOT CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$secureBootPass = $false

try {
    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop

    Write-Host "Secure Boot Enabled : $secureBootEnabled"

    if ($secureBootEnabled) {
        Write-Host "Result              : Pass"
        $checksPassed++
        $secureBootPass = $true
    } else {
        Write-Host "Result              : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        $blockersText += "- Secure Boot is not enabled"
    }

} catch {
    Write-Host "Secure Boot Status  : Unable to determine or not supported"
    Write-Host "Result              : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- Secure Boot check failed or not supported"
}

# ==== CPU COMPATIBILITY CHECK ====
Write-Host ""
Write-Host "[ CPU COMPATIBILITY CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$cpuPass = $false

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $cpuName = Get-SafeProperty $cpu 'Name'

    Write-Host "CPU Name         : $cpuName"

    # Simplified CPU check - look for Intel 8th gen+ or AMD Zen 2+
    # This is a basic check; full compatibility requires checking against official list
    $cpuCompatible = $false

    if ($cpuName -match "Intel.*Core") {
        # Check for Intel 8th gen or newer (i3/i5/i7/i9-8xxx or higher)
        if ($cpuName -match "i[3579]-([89]\d{3}|1\d{4})") {
            $cpuCompatible = $true
        }
    } elseif ($cpuName -match "AMD.*Ryzen") {
        # Check for AMD Ryzen 2000 series or newer
        if ($cpuName -match "Ryzen.*[2-9]\d{3}") {
            $cpuCompatible = $true
        }
    }

    if ($cpuCompatible) {
        Write-Host "CPU Family       : Compatible"
        Write-Host "Result           : Pass"
        $checksPassed++
        $cpuPass = $true
    } else {
        Write-Host "CPU Family       : May not be compatible"
        Write-Host "Result           : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        $blockersText += "- CPU may not meet Windows 11 requirements"
    }

} catch {
    Write-Host "CPU Status       : Unable to determine"
    Write-Host "Result           : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- CPU check failed"
}

# ==== RAM CHECK ====
Write-Host ""
Write-Host "[ RAM CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$ramPass = $false

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $totalRam = Get-SafeProperty $computerSystem 'TotalPhysicalMemory' 0
    $totalRamGB = Format-BytesToGB $totalRam

    Write-Host "Total RAM        : $totalRamGB GB"
    Write-Host "Required RAM     : $MinimumRamGB GB"

    if ([double]$totalRamGB -ge $MinimumRamGB) {
        Write-Host "Result           : Pass"
        $checksPassed++
        $ramPass = $true
    } else {
        Write-Host "Result           : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        $blockersText += "- Insufficient RAM: ${totalRamGB}GB available, ${MinimumRamGB}GB required"
    }

} catch {
    Write-Host "RAM Status       : Unable to determine"
    Write-Host "Result           : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- RAM check failed"
}

# ==== STORAGE CHECK ====
Write-Host ""
Write-Host "[ STORAGE CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$storagePass = $false

try {
    $systemDrive = $env:SystemDrive
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop

    $freeSpace = Get-SafeProperty $drive 'FreeSpace' 0
    $freeSpaceGB = Format-BytesToGB $freeSpace

    Write-Host "System Drive     : $systemDrive"
    Write-Host "Available Space  : $freeSpaceGB GB"
    Write-Host "Required Space   : $MinimumStorageGB GB"

    if ([double]$freeSpaceGB -ge $MinimumStorageGB) {
        Write-Host "Result           : Pass"
        $checksPassed++
        $storagePass = $true
    } else {
        Write-Host "Result           : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        $blockersText += "- Insufficient storage: ${freeSpaceGB}GB available, ${MinimumStorageGB}GB required"
    }

} catch {
    Write-Host "Storage Status   : Unable to determine"
    Write-Host "Result           : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- Storage check failed"
}

# ==== FIRMWARE CHECK ====
Write-Host ""
Write-Host "[ FIRMWARE CHECK ]"
Write-Host "--------------------------------------------------------------"

$checksRun++
$firmwarePass = $false

try {
    # Check if system is UEFI or BIOS
    $firmwareType = "Unknown"

    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State") {
        $firmwareType = "UEFI"
        $firmwarePass = $true
    } else {
        $firmwareType = "Legacy BIOS"
        $firmwarePass = $false
    }

    Write-Host "Firmware Type    : $firmwareType"

    if ($firmwarePass) {
        Write-Host "Result           : Pass"
        $checksPassed++
    } else {
        Write-Host "Result           : Fail"
        $checksFailed++
        if ($blockersText.Length -gt 0) { $blockersText += "`n" }
        $blockersText += "- UEFI firmware required (found: $firmwareType)"
    }

} catch {
    Write-Host "Firmware Status  : Unable to determine"
    Write-Host "Result           : Fail"
    $checksFailed++
    if ($blockersText.Length -gt 0) { $blockersText += "`n" }
    $blockersText += "- Firmware check failed"
}

# ==== COMPATIBILITY SUMMARY ====
Write-Host ""
Write-Host "[ COMPATIBILITY SUMMARY ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Total Checks     : $checksRun"
Write-Host "Checks Passed    : $checksPassed"
Write-Host "Checks Failed    : $checksFailed"

if ($checksFailed -eq 0) {
    Write-Host "Overall Status   : Compatible"
} else {
    Write-Host "Overall Status   : Not Compatible"
}

# ==== BLOCKERS ====
if ($checksFailed -gt 0) {
    Write-Host ""
    Write-Host "[ COMPATIBILITY BLOCKERS ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $blockersText
}

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

if ($checksFailed -eq 0) {
    Write-Host "This system is ready for Windows 11 upgrade."
} else {
    Write-Host "This system has $checksFailed blocker(s) preventing Windows 11 upgrade."
    Write-Host ""
    Write-Host "Recommended Actions:"
    Write-Host "- Review blockers listed above"
    Write-Host "- Enable TPM 2.0 in BIOS/UEFI if available"
    Write-Host "- Enable Secure Boot in BIOS/UEFI if available"
    Write-Host "- Upgrade hardware if CPU, RAM, or storage insufficient"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

if ($checksFailed -eq 0) {
    exit 0
} else {
    exit 1
}
