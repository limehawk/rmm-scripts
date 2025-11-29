Import-Module $SuperOpsModule
$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : BitLocker Enable with SuperOps Integration v1.1.0
 VERSION  : v1.1.0
================================================================================
 FILE     : bitlocker_enable_superops.ps1
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Enables BitLocker on the OS drive using TPM and Recovery Password protectors.
 Ensures protectors are not duplicated, prints recovery key to console for RMM
 log capture, and syncs the recovery key to SuperOps custom fields.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (drive letter, force flag, encryption settings)
 2) TPM status via Get-Tpm cmdlet
 3) BitLocker volume status via Get-BitLockerVolume
 4) CIM for volume and recovery password retrieval
 5) SuperOps custom fields for recovery key storage

 REQUIRED INPUTS

 - $SuperOpsModule : Path to SuperOps module (injected by RMM; non-empty string)
 - $Drive          : Target drive for BitLocker (default: 'C:')
 - $Force          : Force recovery key rotation (default: $true)

 SETTINGS

 - Encryption Method : XTS-AES 256
 - Used Space Only   : $true (faster encryption)
 - Skip Hardware Test: $true (no reboot required to start)

 BEHAVIOR

 1. Validates administrative privileges and SuperOps module
 2. Ensures BDESVC (BitLocker Service) is running and set to Automatic
 3. Checks TPM status and adds TPM protector if available
 4. Rotates Recovery Password protector when Force=$true
 5. Initiates BitLocker encryption with configured settings
 6. Retrieves and displays recovery key
 7. Syncs recovery key ID and password to SuperOps custom fields

 PREREQUISITES

 - PowerShell 5.1 or later
 - Windows 10/11 Pro or Enterprise
 - BitLocker feature enabled
 - Administrator privileges required
 - SuperOps module available via $SuperOpsModule

 SECURITY NOTES

 - Recovery Password is printed to console (captured by RMM logs)
 - Recovery Password is synced to SuperOps custom fields
 - No local files or transcripts are created

 ENDPOINTS

 - Local TPM (Trusted Platform Module)
 - Local BitLocker Service (BDESVC)
 - SuperOps API via Send-CustomField cmdlet

 EXIT CODES

 - 0 : Success - BitLocker enabled and key synced
 - 1 : Failure - prerequisites, validation, or cmdlet errors

 EXAMPLE RUN

 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 SuperOpsModule   : C:\Program Files\SuperOps\Modules\SuperOps.psm1
 Drive            : C:
 Force            : True
 Admin Privileges : Confirmed

 [ PRECHECK ]
 --------------------------------------------------------------
 BDESVC Status    : Running
 TPM Present      : True
 TPM Ready        : True
 Current Status   : FullyDecrypted

 [ CONFIGURE PROTECTORS ]
 --------------------------------------------------------------
 Removing 1 existing RecoveryPassword protector(s)
 Removed old protector : {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
 Added new RecoveryPassword protector
 Recovery Key ID  : {YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY}
 TPM protector already present

 [ ENABLE ENCRYPTION ]
 --------------------------------------------------------------
 Encryption already active - skipping enable
 Volume Status    : FullyEncrypted

 [ RECOVERY KEY ]
 --------------------------------------------------------------
 Recovery Key ID  : {YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY}
 Recovery Password:
 ------------------------------------------------------------
 123456-789012-345678-901234-567890-123456-789012-345678
 ------------------------------------------------------------

 [ SUPEROPS SYNC ]
 --------------------------------------------------------------
 Sent BitLocker Recovery Key ID to SuperOps
 Sent BitLocker Recovery Password to SuperOps
 Custom fields synchronized

 [ FINAL STATUS ]
 --------------------------------------------------------------
 Result           : SUCCESS
 BitLocker enablement completed

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2025-11-29 v1.1.0 Refactored to full Style A compliance with SuperOps
                   integration, improved error handling, CIM over WMI,
                   removed status prefixes, and cleaner section organization.
 2025-09-29 v1.0.0 Initial Style A implementation with hardcoded inputs.
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# STATE VARIABLES
# ============================================================================

$errorOccurred  = $false
$errorText      = ""
$recoveryKey    = ""
$recoveryKeyId  = ""

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

$Drive = 'C:'
$Force = $true  # Force recovery key rotation/creation

# Encryption settings
$EncryptionMethod = 'XtsAes256'
$UsedSpaceOnly    = $true
$SkipHardwareTest = $true

# ============================================================================
# HELPER FUNCTION
# ============================================================================

function Get-RecoveryPasswordForId {
    param([string]$MountPoint, [string]$KeyProtectorId)

    # Try CIM/WMI method first
    try {
        $volume = Get-CimInstance -Namespace "root\CIMV2\Security\MicrosoftVolumeEncryption" `
            -ClassName "Win32_EncryptableVolume" -ErrorAction Stop |
            Where-Object { $_.DriveLetter -eq $MountPoint }

        if ($volume) {
            $result = Invoke-CimMethod -InputObject $volume -MethodName "GetKeyProtectorNumericalPassword" `
                -Arguments @{ VolumeKeyProtectorID = $KeyProtectorId } -ErrorAction Stop
            if ($result.NumericalPassword) {
                return $result.NumericalPassword
            }
        }
    } catch {
        # Fall through to manage-bde fallback
    }

    # Fallback to manage-bde parsing
    try {
        $output = & manage-bde -protectors -get $MountPoint 2>$null
        $currentId = $null

        foreach ($line in $output) {
            # Match protector ID (with or without braces)
            if ($line -match 'ID:\s*\{?([0-9A-Fa-f\-]{36})\}?') {
                $currentId = $Matches[1]
            }
            # Match recovery password pattern
            if ($line -match '([0-9]{6}-){7}[0-9]{6}') {
                $cleanKeyId = $KeyProtectorId -replace '[{}]', ''
                if ($currentId -eq $cleanKeyId) {
                    return $Matches[0]
                }
            }
        }
    } catch {
        # Return null if all methods fail
    }

    return $null
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

# Validate SuperOps module
if ([string]::IsNullOrWhiteSpace($SuperOpsModule)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOpsModule path is required (injected by RMM)"
}

# Validate drive
if ([string]::IsNullOrWhiteSpace($Drive)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Drive is required"
}

# Validate Force is boolean
if ($null -eq $Force -or $Force -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Force must be a boolean (\$true or \$false)"
}

# Validate admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Script must be run with Administrator privileges"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure SuperOps module is configured in RMM environment"
    Write-Host "- Run script with Administrator privileges"
    exit 1
}

Write-Host "SuperOpsModule   : $SuperOpsModule"
Write-Host "Drive            : $Drive"
Write-Host "Force            : $Force"
Write-Host "Admin Privileges : Confirmed"

# ============================================================================
# PRECHECK
# ============================================================================

Write-Host ""
Write-Host "[ PRECHECK ]"
Write-Host "--------------------------------------------------------------"

# Check drive exists
try {
    $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$Drive'" -ErrorAction Stop
    if (-not $vol) {
        throw "Drive not found"
    }
} catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Target drive $Drive not found"
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

# Check and start BDESVC
try {
    $svc = Get-Service -Name "BDESVC" -ErrorAction Stop
    if ($svc.Status -ne "Running") {
        Start-Service -Name "BDESVC" -ErrorAction Stop
    }
    Set-Service -Name "BDESVC" -StartupType Automatic -ErrorAction Stop
    $svcStatus = (Get-Service BDESVC).Status
    Write-Host "BDESVC Status    : $svcStatus"
} catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "BDESVC (BitLocker Service) check failed"
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure BitLocker feature is installed"
    Write-Host "- Check Windows edition supports BitLocker (Pro/Enterprise)"
    exit 1
}

# Check TPM status
$tpmPresent = $false
$tpmReady = $false
try {
    $tpm = Get-Tpm -ErrorAction Stop
    $tpmPresent = $tpm.TpmPresent
    $tpmReady = $tpm.TpmReady
} catch {
    # TPM not available
}
Write-Host "TPM Present      : $tpmPresent"
Write-Host "TPM Ready        : $tpmReady"

# Check current BitLocker state
$blv = $null
try {
    $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
    Write-Host "Current Status   : $($blv.VolumeStatus)"
    Write-Host "Protection       : $($blv.ProtectionStatus)"
} catch {
    Write-Host "Current Status   : Not configured"
}

# ============================================================================
# CONFIGURE PROTECTORS
# ============================================================================

Write-Host ""
Write-Host "[ CONFIGURE PROTECTORS ]"
Write-Host "--------------------------------------------------------------"

# Handle Recovery Password protector
$existingRecProtectors = @()
if ($blv -and $blv.KeyProtector) {
    $existingRecProtectors = @($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
}

# Remove existing recovery protectors if Force is set
if ($Force -and $existingRecProtectors.Count -gt 0) {
    Write-Host "Removing $($existingRecProtectors.Count) existing RecoveryPassword protector(s)"

    foreach ($kp in $existingRecProtectors) {
        try {
            Remove-BitLockerKeyProtector -MountPoint $Drive -KeyProtectorId $kp.KeyProtectorId -ErrorAction Stop | Out-Null
            Write-Host "Removed old protector : $($kp.KeyProtectorId)"
        } catch {
            Write-Host "Failed to remove     : $($kp.KeyProtectorId) - $($_.Exception.Message)"
            $errorOccurred = $true
        }
    }

    # Refresh volume state
    $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
}

# Check if recovery protector exists after cleanup
$recProtectorExists = $false
if ($blv -and $blv.KeyProtector) {
    $recProtectorExists = ($blv.KeyProtector.KeyProtectorType -contains 'RecoveryPassword')
}

# Add new recovery protector if needed
if (-not $recProtectorExists) {
    try {
        Add-BitLockerKeyProtector -MountPoint $Drive -RecoveryPasswordProtector -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        Write-Host "Added new RecoveryPassword protector"

        $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
        $newKp = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1

        if ($newKp) {
            $recoveryKeyId = $newKp.KeyProtectorId
            $recoveryKey = Get-RecoveryPasswordForId -MountPoint $Drive -KeyProtectorId $recoveryKeyId
            Write-Host "Recovery Key ID  : $recoveryKeyId"
        } else {
            Write-Host "Failed to retrieve new protector ID"
            $errorOccurred = $true
        }
    } catch {
        Write-Host "Failed to add RecoveryPassword protector: $($_.Exception.Message)"
        $errorOccurred = $true
    }
} else {
    $existingKp = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
    $recoveryKeyId = $existingKp.KeyProtectorId
    $recoveryKey = Get-RecoveryPasswordForId -MountPoint $Drive -KeyProtectorId $recoveryKeyId
    Write-Host "RecoveryPassword protector already exists"
    Write-Host "Recovery Key ID  : $recoveryKeyId"
}

# Handle TPM protector
if ($tpmPresent -and $tpmReady) {
    $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
    $hasTpm = $false

    if ($blv -and $blv.KeyProtector) {
        $hasTpm = ($blv.KeyProtector.KeyProtectorType -contains 'Tpm')
    }

    if (-not $hasTpm) {
        try {
            Add-BitLockerKeyProtector -MountPoint $Drive -TpmProtector -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            Write-Host "TPM protector added"
        } catch {
            Write-Host "Failed to add TPM protector: $($_.Exception.Message)"
            $errorOccurred = $true
        }
    } else {
        Write-Host "TPM protector already present"
    }
} else {
    Write-Host "TPM not available - skipping TPM protector"
}

# ============================================================================
# ENABLE ENCRYPTION
# ============================================================================

Write-Host ""
Write-Host "[ ENABLE ENCRYPTION ]"
Write-Host "--------------------------------------------------------------"

if (-not $errorOccurred) {
    $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
    $needEnable = $true

    if ($blv -and ($blv.VolumeStatus -in @('EncryptionInProgress', 'EncryptionSuspended', 'FullyEncrypted'))) {
        $needEnable = $false
        Write-Host "Encryption already active - skipping enable"
        Write-Host "Volume Status    : $($blv.VolumeStatus)"
    }

    if ($needEnable) {
        # Use manage-bde for cleaner state transition when protectors exist
        if ($blv -and $blv.KeyProtector.Count -gt 0) {
            Write-Host "Starting encryption with manage-bde..."

            $bdeArgs = @('-on', $Drive, '-skiphardwaretest')
            if ($UsedSpaceOnly) { $bdeArgs += '-usedspaceonly' }
            if ($EncryptionMethod) { $bdeArgs += @('-encryptionmethod', $EncryptionMethod) }

            try {
                & manage-bde @bdeArgs 2>&1 | Out-Null
                Write-Host "Encryption initiated successfully"
            } catch {
                Write-Host "manage-bde failed: $($_.Exception.Message)"
                $errorOccurred = $true
            }
        } else {
            # Fallback to Enable-BitLocker
            Write-Host "Starting encryption with Enable-BitLocker..."
            try {
                Enable-BitLocker -MountPoint $Drive -EncryptionMethod $EncryptionMethod `
                    -UsedSpaceOnly:$UsedSpaceOnly -SkipHardwareTest:$SkipHardwareTest -ErrorAction Stop | Out-Null
                Write-Host "Encryption initiated successfully"
            } catch {
                Write-Host "Enable-BitLocker failed: $($_.Exception.Message)"
                $errorOccurred = $true
            }
        }

        # Show current status
        $blv = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
        if ($blv) {
            Write-Host "Volume Status    : $($blv.VolumeStatus)"
            Write-Host "Encryption %     : $($blv.EncryptionPercentage)"
        }
    }
}

# ============================================================================
# RECOVERY KEY
# ============================================================================

Write-Host ""
Write-Host "[ RECOVERY KEY ]"
Write-Host "--------------------------------------------------------------"

if ($errorOccurred) {
    Write-Host "Configuration failed - recovery key may not be available"
} else {
    Write-Host "Recovery Key ID  : $recoveryKeyId"

    if ([string]::IsNullOrWhiteSpace($recoveryKey)) {
        Write-Host ""
        Write-Host "Recovery password not retrieved"
        Write-Host "(May be blocked by policy or provider)"
    } else {
        Write-Host "Recovery Password:"
        Write-Host " ------------------------------------------------------------"
        Write-Host " $recoveryKey"
        Write-Host " ------------------------------------------------------------"
    }
}

# ============================================================================
# SUPEROPS SYNC
# ============================================================================

Write-Host ""
Write-Host "[ SUPEROPS SYNC ]"
Write-Host "--------------------------------------------------------------"

$syncErrorOccurred = $false

# Send Recovery Key ID
if (-not [string]::IsNullOrWhiteSpace($recoveryKeyId)) {
    try {
        Send-CustomField -CustomFieldName "BitLocker Recovery Key ID" -Value $recoveryKeyId -ErrorAction Stop
        Write-Host "Sent BitLocker Recovery Key ID to SuperOps"
    } catch {
        Write-Host "Failed to send Recovery Key ID: $($_.Exception.Message)"
        $syncErrorOccurred = $true
    }
} else {
    Write-Host "No Recovery Key ID to send"
}

# Send Recovery Password
if (-not [string]::IsNullOrWhiteSpace($recoveryKey)) {
    try {
        Send-CustomField -CustomFieldName "BitLocker Recovery Password" -Value $recoveryKey -ErrorAction Stop
        Write-Host "Sent BitLocker Recovery Password to SuperOps"
    } catch {
        Write-Host "Failed to send Recovery Password: $($_.Exception.Message)"
        $syncErrorOccurred = $true
    }
} else {
    Write-Host "No Recovery Password to send"
}

if ($syncErrorOccurred) {
    Write-Host ""
    Write-Host "Warning: Some custom fields failed to sync"
    Write-Host "Verify fields exist in SuperOps tenant"
} else {
    Write-Host "Custom fields synchronized"
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

if ($errorOccurred) {
    Write-Host "Result           : FAILED"
    Write-Host "BitLocker enablement encountered errors"
    exit 1
} else {
    $final = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
    Write-Host "Result           : SUCCESS"
    if ($final) {
        Write-Host "Protection       : $($final.ProtectionStatus)"
        Write-Host "Volume Status    : $($final.VolumeStatus)"
    }
    Write-Host "BitLocker enablement completed"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
