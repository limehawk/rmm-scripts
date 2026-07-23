$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : BitLocker Enable                                              v2.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\bitlocker_enable.ps1
================================================================================
 FILE     : bitlocker_enable.ps1
 DESCRIPTION : Enables BitLocker on the OS drive and guarantees Protection On
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Converges the OS drive to BitLocker "Protection On" from any starting
   state: fully decrypted, encrypted with protection suspended (the OOBE
   pre-provisioned clear-key state), or already protected. Prints the
   recovery password to the console for Level activity-log capture and
   fails loudly (exit 1) whenever protection cannot be activated, instead
   of reporting false success.

 DATA SOURCES & PRIORITY

   1) Hardcoded values (drive letter, encryption settings)
   2) TPM status via Get-Tpm cmdlet
   3) BitLocker volume status via Get-BitLockerVolume
   4) manage-bde for encryption start and protector activation

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $Drive: Target drive for BitLocker (default: 'C:')

 SETTINGS

   Configuration details and default values:
     - Encryption Method : xts_aes256 (manage-bde token for XTS-AES 256)
     - Used Space Only   : enabled (faster initial encryption)
     - Skip Hardware Test: enabled (no reboot required to start)

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates administrator privileges and input values
   2. Ensures BDESVC (BitLocker Drive Encryption Service) is running
   3. Requires a present and ready TPM (fails otherwise)
   4. Ensures exactly one RecoveryPassword protector and a TPM protector
   5. Starts encryption via manage-bde when the volume is FullyDecrypted
   6. Activates protectors (manage-bde -protectors -enable) when the
      volume is encrypted but Protection Status is Off (clear-key state)
   7. Prints the recovery key ID and recovery password
   8. Verifies final state: Protection On, or encryption in progress with
      protectors activated - anything else exits 1

 PREREQUISITES

   - PowerShell 5.1 or later
   - Windows 10/11 Pro or Enterprise with BitLocker feature
   - Administrator privileges (Level runs as SYSTEM)
   - TPM present and ready

 SECURITY NOTES

   - Recovery password is printed to console by design (captured by the
     Level activity log as the key escrow record)
   - No other secrets in logs

 ENDPOINTS

   - Not applicable (local TPM and BitLocker service only)

 EXIT CODES

   0 = Success - protection on, or encryption in progress with protectors active
   1 = Failure - validation, TPM, protector, encryption, or activation error

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Drive            : C:
     Admin Privileges : Confirmed

   [INFO] PRECHECK
   ==============================================================
     BDESVC Status    : Running
     TPM Present      : True
     TPM Ready        : True
     Volume Status    : FullyEncrypted
     Protection       : Off
     Encryption %     : 100

   [RUN] CONFIGURE PROTECTORS
   ==============================================================
     RecoveryPassword protector already exists
     Recovery Key ID  : {YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY}
     TPM protector already present

   [RUN] ENABLE ENCRYPTION
   ==============================================================
     Volume already encrypted - skipping encryption start

   [RUN] ACTIVATE PROTECTION
   ==============================================================
     Protection is Off - enabling key protectors
     [OK] Key protectors enabled
     Protection       : On

   [INFO] RECOVERY KEY
   ==============================================================
     Recovery Key ID  : {YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY}
     Recovery Password:
     123456-789012-345678-901234-567890-123456-789012-345678

   [OK] FINAL STATUS
   ==============================================================
     Volume Status    : FullyEncrypted
     Protection       : On
     Result           : SUCCESS

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-22 v2.0.0 Rewrite: converge every state to Protection On; activate
                   suspended protectors (OOBE clear-key state); check
                   manage-bde exit codes; fail instead of false success
================================================================================
#>

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================

$Drive = 'C:'

Set-StrictMode -Version Latest

# ==============================================================================
# STATE VARIABLES
# ==============================================================================

$errorOccurred      = $false
$errorText          = ""
$recoveryKeyId      = ""
$recoveryPassword   = ""
$encryptionStartedNow = $false
$activationAttempted = $false
$activationSucceeded = $false

# ==============================================================================
# HELPER FUNCTION
# ==============================================================================

function Invoke-ManageBde {
    # Runs manage-bde with native stderr handling, prints output indented,
    # and returns the exit code.
    param([string[]]$BdeArgs)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & manage-bde @BdeArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    foreach ($line in @($output)) {
        $text = "$line".TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Host "    $text"
        }
    }
    return $code
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

if ([string]::IsNullOrWhiteSpace($Drive) -or $Drive -notmatch '^[A-Za-z]:$') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Drive must be a drive letter like 'C:'"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Script must be run with Administrator privileges"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Input validation failed:"
    Write-Host "  $errorText"
    exit 1
}

Write-Host "  Drive            : $Drive"
Write-Host "  Admin Privileges : Confirmed"

# ==============================================================================
# PRECHECK
# ==============================================================================

Write-Host ""
Write-Host "[INFO] PRECHECK"
Write-Host "=============================================================="

try {
    $svc = Get-Service -Name 'BDESVC'
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'BDESVC'
    }
    Set-Service -Name 'BDESVC' -StartupType Automatic
    Write-Host "  BDESVC Status    : $((Get-Service BDESVC).Status)"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  BDESVC (BitLocker Drive Encryption Service) check failed"
    Write-Host "  Error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "  Troubleshooting:"
    Write-Host "  - Check Windows edition supports BitLocker (Pro/Enterprise)"
    exit 1
}

$tpmPresent = $false
$tpmReady = $false
try {
    $tpm = Get-Tpm
    $tpmPresent = $tpm.TpmPresent
    $tpmReady = $tpm.TpmReady
} catch {
    # Get-Tpm throws when no TPM stack is available; treated as absent below
}
Write-Host "  TPM Present      : $tpmPresent"
Write-Host "  TPM Ready        : $tpmReady"

if (-not ($tpmPresent -and $tpmReady)) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  TPM is not present or not ready - cannot enable BitLocker"
    Write-Host ""
    Write-Host "  Troubleshooting:"
    Write-Host "  - Enable/activate the TPM in UEFI firmware settings"
    Write-Host "  - Initialize the TPM (Initialize-Tpm) and rerun"
    exit 1
}

try {
    $blv = Get-BitLockerVolume -MountPoint $Drive
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Could not read BitLocker state for $Drive"
    Write-Host "  Error: $($_.Exception.Message)"
    exit 1
}

Write-Host "  Volume Status    : $($blv.VolumeStatus)"
Write-Host "  Protection       : $($blv.ProtectionStatus)"
Write-Host "  Encryption %     : $($blv.EncryptionPercentage)"

if ("$($blv.VolumeStatus)" -eq 'DecryptionInProgress') {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Volume is currently DECRYPTING - cannot enable until done"
    Write-Host "  Rerun this script after decryption completes"
    exit 1
}

# ==============================================================================
# CONFIGURE PROTECTORS
# ==============================================================================

Write-Host ""
Write-Host "[RUN] CONFIGURE PROTECTORS"
Write-Host "=============================================================="

# Ensure exactly one RecoveryPassword protector (keep first, drop extras)
$recProtectors = @($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })

if ($recProtectors.Count -eq 0) {
    try {
        Add-BitLockerKeyProtector -MountPoint $Drive -RecoveryPasswordProtector -WarningAction SilentlyContinue | Out-Null
        Write-Host "  Added new RecoveryPassword protector"
    } catch {
        Write-Host "  [ERROR] Failed to add RecoveryPassword protector: $($_.Exception.Message)"
        $errorOccurred = $true
    }
} else {
    Write-Host "  RecoveryPassword protector already exists"
    foreach ($extra in ($recProtectors | Select-Object -Skip 1)) {
        try {
            Remove-BitLockerKeyProtector -MountPoint $Drive -KeyProtectorId $extra.KeyProtectorId | Out-Null
            Write-Host "  Removed extra recovery protector $($extra.KeyProtectorId)"
        } catch {
            Write-Host "  [WARN] Could not remove extra protector $($extra.KeyProtectorId): $($_.Exception.Message)"
        }
    }
}

# Ensure TPM protector
$blv = Get-BitLockerVolume -MountPoint $Drive
$hasTpmProtector = @($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'Tpm' }).Count -gt 0

if (-not $hasTpmProtector) {
    try {
        Add-BitLockerKeyProtector -MountPoint $Drive -TpmProtector -WarningAction SilentlyContinue | Out-Null
        Write-Host "  TPM protector added"
    } catch {
        Write-Host "  [ERROR] Failed to add TPM protector: $($_.Exception.Message)"
        $errorOccurred = $true
    }
} else {
    Write-Host "  TPM protector already present"
}

# Capture recovery key details for output
$blv = Get-BitLockerVolume -MountPoint $Drive
$recKp = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
if ($recKp) {
    $recoveryKeyId = $recKp.KeyProtectorId
    $recoveryPassword = $recKp.RecoveryPassword
    Write-Host "  Recovery Key ID  : $recoveryKeyId"
} else {
    Write-Host "  [ERROR] No RecoveryPassword protector present after configuration"
    $errorOccurred = $true
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Protector configuration failed - aborting before encryption"
    exit 1
}

# ==============================================================================
# ENABLE ENCRYPTION
# ==============================================================================

Write-Host ""
Write-Host "[RUN] ENABLE ENCRYPTION"
Write-Host "=============================================================="

$blv = Get-BitLockerVolume -MountPoint $Drive

if ("$($blv.VolumeStatus)" -eq 'FullyDecrypted') {
    Write-Host "  Starting encryption (xts_aes256, used space only)"
    $exitCode = Invoke-ManageBde -BdeArgs @('-on', $Drive, '-skiphardwaretest', '-usedspaceonly', '-encryptionmethod', 'xts_aes256')

    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "  manage-bde -on failed with exit code $exitCode"
        Write-Host "  See manage-bde output above for the cause"
        exit 1
    }
    Write-Host "  [OK] Encryption started"
    $encryptionStartedNow = $true
} else {
    Write-Host "  Volume already encrypted or in progress - skipping start"
}

# ==============================================================================
# ACTIVATE PROTECTION
# ==============================================================================

Write-Host ""
Write-Host "[RUN] ACTIVATE PROTECTION"
Write-Host "=============================================================="

$blv = Get-BitLockerVolume -MountPoint $Drive

if ($encryptionStartedNow) {
    # Fresh start: protectors were active from the beginning (no clear key),
    # protection flips On automatically when conversion completes
    Write-Host "  Encryption just started - protection activates on completion"
} elseif ("$($blv.ProtectionStatus)" -eq 'Off' -and "$($blv.VolumeStatus)" -ne 'FullyDecrypted') {
    Write-Host "  Protection is Off - enabling key protectors"
    $activationAttempted = $true
    $exitCode = Invoke-ManageBde -BdeArgs @('-protectors', '-enable', $Drive)

    if ($exitCode -eq 0) {
        $activationSucceeded = $true
        Write-Host "  [OK] Key protectors enabled"
    } else {
        Write-Host "  [ERROR] manage-bde -protectors -enable failed with exit code $exitCode"
        $errorOccurred = $true
    }
} else {
    Write-Host "  Protection already active - nothing to enable"
}

$blv = Get-BitLockerVolume -MountPoint $Drive
Write-Host "  Protection       : $($blv.ProtectionStatus)"

# ==============================================================================
# RECOVERY KEY
# ==============================================================================

Write-Host ""
Write-Host "[INFO] RECOVERY KEY"
Write-Host "=============================================================="
Write-Host "  Recovery Key ID  : $recoveryKeyId"

if ([string]::IsNullOrWhiteSpace("$recoveryPassword")) {
    Write-Host "  [WARN] Recovery password not readable via Get-BitLockerVolume"
} else {
    Write-Host "  Recovery Password:"
    Write-Host "  $recoveryPassword"
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

$final = Get-BitLockerVolume -MountPoint $Drive
$finalProtection = "$($final.ProtectionStatus)"
$finalVolume = "$($final.VolumeStatus)"

# Success = protection is On, or encryption is still converting and the
# protectors were activated (protection flips On when conversion completes)
$success = $false
if (-not $errorOccurred) {
    if ($finalProtection -eq 'On') {
        $success = $true
    } elseif ($finalVolume -eq 'EncryptionInProgress' -and (-not $activationAttempted -or $activationSucceeded)) {
        $success = $true
    }
}

if ($success) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Volume Status    : $finalVolume"
    Write-Host "  Protection       : $finalProtection"
    Write-Host "  Encryption %     : $($final.EncryptionPercentage)"
    if ($finalProtection -ne 'On') {
        Write-Host "  [INFO] Encryption in progress - protection activates on completion"
    }
    Write-Host "  Result           : SUCCESS"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Volume Status    : $finalVolume"
    Write-Host "  Protection       : $finalProtection"
    Write-Host "  Result           : FAILED - protection is not active"
    Write-Host ""
    Write-Host "  Troubleshooting:"
    Write-Host "  - Review manage-bde output above for the failing step"
    Write-Host "  - Run 'manage-bde -status $Drive' on the device"
    exit 1
}
