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
 SCRIPT   : Windows Product Key to SuperOps                               v1.1.1
 AUTHOR   : Limehawk.io
 DATE      : January 2026
 USAGE    : .\windows_product_key_export_superops.ps1
================================================================================
 FILE     : windows_product_key_export_superops.ps1
DESCRIPTION : Retrieves Windows product key and syncs to SuperOps custom field
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Retrieves the Windows product key from the local machine's registry by decoding
 the DigitalProductId value and sends it to a SuperOps custom field for asset
 management and license tracking. Designed for unattended execution in RMM
 environments to automatically populate license information.

 DATA SOURCES & PRIORITY
 1) Hardcoded values (defined within the script body)
 2) Windows Registry (HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion)
 3) SuperOps API (via Send-CustomField)
 4) Error

 REQUIRED INPUTS
 - CustomFieldName  : 'Windows Product Key'
   (The name of the SuperOps custom field to populate with the product key.)
 - RegistryKeyPath  : 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
   (Registry path where DigitalProductId is stored.)

 SETTINGS
 - Decodes DigitalProductId using standard Windows key algorithm.
 - Sends decoded product key to SuperOps custom field.
 - Uses SuperOps module's Send-CustomField function.
 - Product key format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX

 BEHAVIOR
 - Script reads DigitalProductId from registry.
 - Converts binary product ID to readable product key format.
 - Sends product key to specified SuperOps custom field.
 - If product key cannot be retrieved, reports error and exits.

 PREREQUISITES
 - PowerShell 5.1 or later.
 - SuperOps RMM agent installed and module available.
 - $SuperOpsModule variable must be defined by SuperOps agent.
 - Registry access to read Windows product information.

 SECURITY NOTES
 - Product key is sent to SuperOps (no secrets in local logs).
 - Registry read is non-destructive.
 - Product key is considered sensitive licensing data.

 ENDPOINTS
 - SuperOps API (via Send-CustomField function)

 EXIT CODES
 - 0 success
 - 1 failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 CustomFieldName : Windows Product Key
 RegistryKeyPath : HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion

 [RUN] RETRIEVE PRODUCT KEY
 ==============================================================
 Reading DigitalProductId from registry...
 Decoding product key...
 Product Key     : XXXXX-XXXXX-XXXXX-XXXXX-XXXXX

 [RUN] SEND TO SUPEROPS
 ==============================================================
 Sending to custom field: Windows Product Key
 SuperOps update successful

 [OK] FINAL STATUS
 ==============================================================
 Product key retrieved and sent to SuperOps successfully.

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-10-31 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""
$productKey    = ""

# ==== HARDCODED INPUTS (MANDATORY) ====
$CustomFieldName = 'Windows Product Key'
$RegistryKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($CustomFieldName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- CustomFieldName is required."
}
if ([string]::IsNullOrWhiteSpace($RegistryKeyPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RegistryKeyPath is required."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText

    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script cannot proceed due to invalid hardcoded inputs."

    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== RUNTIME OUTPUT (Style A) ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "CustomFieldName : $CustomFieldName"
Write-Host "RegistryKeyPath : $RegistryKeyPath"

# ==== FUNCTION: CONVERT DIGITAL PRODUCT ID TO KEY ====
function Convert-DigitalProductIdToKey {
    param (
        [byte[]]$DigitalProductId
    )

    $keyStartIndex = 52
    $keyChars = "BCDFGHJKMPQRTVWXY2346789"
    $decodedKey = ""

    # Create working copy of product ID bytes
    $productIdCopy = $DigitalProductId.Clone()

    # Decode the key
    for ($i = 24; $i -ge 0; $i--) {
        $current = 0
        for ($j = 14; $j -ge 0; $j--) {
            $current = $current * 256 -bxor $productIdCopy[$j + $keyStartIndex]
            $productIdCopy[$j + $keyStartIndex] = [math]::Floor($current / 24)
            $current = $current % 24
        }
        $decodedKey = $keyChars[$current] + $decodedKey
    }

    # Insert dashes every 5 characters
    $formattedKey = ""
    for ($i = 0; $i -lt 25; $i++) {
        if ($i -gt 0 -and $i % 5 -eq 0) {
            $formattedKey += "-"
        }
        $formattedKey += $decodedKey[$i]
    }

    return $formattedKey
}

# ==== RETRIEVE PRODUCT KEY ====
Write-Host ""
Write-Host "[RUN] RETRIEVE PRODUCT KEY"
Write-Host "=============================================================="

try {
    Write-Host "Reading DigitalProductId from registry..."

    # Check if registry path exists
    if (-not (Test-Path $RegistryKeyPath)) {
        throw "Registry path does not exist: $RegistryKeyPath"
    }

    # Get registry value
    $regValue = Get-ItemProperty -Path $RegistryKeyPath -ErrorAction Stop

    # Check if DigitalProductId exists
    if (-not ($regValue.PSObject.Properties.Name -contains 'DigitalProductId')) {
        throw "DigitalProductId not found in registry at: $RegistryKeyPath"
    }

    $digitalProductId = $regValue.DigitalProductId

    if ($null -eq $digitalProductId -or $digitalProductId.Length -eq 0) {
        throw "DigitalProductId is empty or null"
    }

    Write-Host "Decoding product key..."
    $productKey = Convert-DigitalProductIdToKey -DigitalProductId $digitalProductId

    if ([string]::IsNullOrWhiteSpace($productKey)) {
        throw "Product key decode resulted in empty value"
    }

    Write-Host "Product Key     : $productKey"

} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "Failed to retrieve product key: $($_.Exception.Message)"
}

# ==== SEND TO SUPEROPS ====
if (-not $errorOccurred) {
    Write-Host ""
    Write-Host "[RUN] SEND TO SUPEROPS"
    Write-Host "=============================================================="

    try {
        Write-Host "Sending to custom field: $CustomFieldName"

        Send-CustomField -CustomFieldName $CustomFieldName -Value $productKey -ErrorAction Stop

        Write-Host "SuperOps update successful"

    } catch {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "Failed to send to SuperOps: $($_.Exception.Message)"
    }
}

# ==== ERROR REPORTING ====
if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

# ==== FINAL STATUS ====
if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Product key operation failed. See error details above."
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
} else {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Product key retrieved and sent to SuperOps successfully."
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
}

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
