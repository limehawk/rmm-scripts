$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : WiFiman Install                                                v1.0.0
FILE   : wifiman_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Installs Ubiquiti WiFiman Desktop application using winget. Automatically
    installs winget if not present on the system.

REQUIRED INPUTS:
    $packageId : Winget package ID for WiFiman

BEHAVIOR:
    1. Validates input parameters
    2. Checks if winget is installed
    3. If winget not found, installs via PowerShell Gallery
    4. Installs WiFiman using winget
    5. Reports final status

PREREQUISITES:
    - Windows 10 1809+ or Windows 11
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Installs from official Microsoft winget repository

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Package ID : UbiquitiInc.WiFimanDesktop
    Inputs validated successfully

    [ WINGET CHECK ]
    --------------------------------------------------------------
    Checking for winget...
    winget is already installed

    [ INSTALLATION ]
    --------------------------------------------------------------
    Installing WiFiman via winget...
    Installation completed successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    WiFiman installed successfully

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
$packageId = 'UbiquitiInc.WiFimanDesktop'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($packageId)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Package ID is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Package ID : $packageId"
Write-Host "Inputs validated successfully"

# ============================================================================
# WINGET CHECK
# ============================================================================
Write-Host ""
Write-Host "[ WINGET CHECK ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Checking for winget..."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget not detected, installing via PowerShell Gallery..."

    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Host "Installing NuGet provider..."
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "Installing winget-install script..."
        Install-Script winget-install -Force -ErrorAction Stop

        Write-Host "Running winget-install..."
        & winget-install -Force 2>&1 | Out-Null

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "winget is still not available after installation"
        }

        Write-Host "winget installed successfully"
    }
    catch {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Failed to install winget"
        Write-Host "Error : $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "winget is already installed"
}

# ============================================================================
# INSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Installing WiFiman via winget..."
    $result = winget install --id=$packageId -e --accept-package-agreements --accept-source-agreements 2>&1
    Write-Host $result
    Write-Host "Installation completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to install WiFiman"
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
Write-Host "WiFiman installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
