$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Splashtop Uninstall                                            v1.0.0
FILE   : splashtop_uninstall.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Uninstalls Splashtop Streamer from a Windows system using the Windows
    Installer service (MSI uninstall).

REQUIRED INPUTS:
    $productName : Display name of the Splashtop product to uninstall

BEHAVIOR:
    1. Validates input parameters
    2. Searches for Splashtop Streamer in installed products
    3. Retrieves the identifying number (GUID)
    4. Executes silent uninstall via CIM method
    5. Reports final status

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Splashtop Streamer installed

SECURITY NOTES:
    - No secrets in logs

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Product Name : Splashtop Streamer
    Inputs validated successfully

    [ PRODUCT LOOKUP ]
    --------------------------------------------------------------
    Searching for installed Splashtop Streamer...
    Found : Splashtop Streamer
    Product ID : {12345678-1234-1234-1234-123456789012}

    [ UNINSTALLATION ]
    --------------------------------------------------------------
    Uninstalling Splashtop Streamer...
    Uninstall completed successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Splashtop Streamer has been uninstalled

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$productName = 'Splashtop Streamer'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($productName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Product name is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Product Name : $productName"
Write-Host "Inputs validated successfully"

# ============================================================================
# PRODUCT LOOKUP
# ============================================================================
Write-Host ""
Write-Host "[ PRODUCT LOOKUP ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Searching for installed $productName..."

    $product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }

    if (-not $product) {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "$productName is not installed on this system"
        exit 1
    }

    $idNumber = $product.IdentifyingNumber
    Write-Host "Found : $($product.Name)"
    Write-Host "Product ID : $idNumber"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to query installed products"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# UNINSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ UNINSTALLATION ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Uninstalling $productName..."

    $cimProduct = Get-CimInstance -Class Win32_Product -Filter "IdentifyingNumber='$idNumber'"
    $result = $cimProduct | Invoke-CimMethod -MethodName Uninstall

    if ($result.ReturnValue -ne 0) {
        throw "Uninstall returned code: $($result.ReturnValue)"
    }

    Write-Host "Uninstall completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to uninstall $productName"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "$productName has been uninstalled"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
