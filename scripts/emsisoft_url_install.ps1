$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Emsisoft Install via URL                                    v1.1.2
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\emsisoft_url_install.ps1
================================================================================
 FILE     : emsisoft_url_install.ps1
 DESCRIPTION : Downloads and installs Emsisoft Anti-Malware from a specified URL
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Downloads and installs Emsisoft Anti-Malware from a specified URL. This script
   is designed for deployments where the Emsisoft installer is hosted on a web
   server or cloud storage and needs to be deployed to endpoints via RMM.

 DATA SOURCES & PRIORITY

   1. Hardcoded download URL - Must point to valid Emsisoft installer
   2. Local temp directory - Default download location ($env:TEMP)

 REQUIRED INPUTS

   $installerUrl   - Full URL to Emsisoft installer executable
                     Must be a valid HTTP/HTTPS URL ending in .exe
                     Example: "https://dl.emsisoft.com/EmsisoftAntiMalwareSetup.exe"

   $downloadPath   - Local directory to download installer to
                     Default: $env:TEMP
                     Must exist and be writable

 SETTINGS

   - Download location: %TEMP% directory by default
   - Installer is executed immediately after download
   - Downloaded installer is NOT deleted after execution
   - No installation flags are passed (interactive install)

 BEHAVIOR

   1. Validates inputs (URL format, download path exists)
   2. Extracts filename from URL
   3. Downloads installer from specified URL
   4. Verifies download completed successfully
   5. Executes the installer
   6. Reports final status

 PREREQUISITES

   - Windows PowerShell 5.1 or PowerShell 7+
   - Internet connectivity to download URL
   - Administrator privileges recommended (for installation)
   - Sufficient disk space for installer download

 SECURITY NOTES

   - No secrets logged or displayed
   - Ensure download URL is from trusted source only
   - Downloaded file is executed immediately - validate URL before use
   - Consider using HTTPS URLs for secure downloads

 ENDPOINTS

   - Download URL (specified in $installerUrl variable)

 EXIT CODES

   0 = Success - Installer downloaded and executed
   1 = Failure - Error during download or execution

 EXAMPLE RUN

   PS> .\emsisoft_url_install.ps1

   [INFO] INPUT VALIDATION
   ==============================================================
   Validating configuration...
   Download URL  : https://example.com/EmsisoftSetup.exe
   Download path : C:\Users\Admin\AppData\Local\Temp
   Input validation passed

   [RUN] DOWNLOAD
   ==============================================================
   Downloading installer...
   Source URL   : https://example.com/EmsisoftSetup.exe
   Target file  : C:\Users\Admin\AppData\Local\Temp\EmsisoftSetup.exe
   Download completed successfully

   [RUN] INSTALLATION
   ==============================================================
   Launching installer...
   Installer started : EmsisoftSetup.exe

   [OK] FINAL STATUS
   ==============================================================
   Download successful : Yes
   Installer launched  : Yes

   [OK] SCRIPT COMPLETED
   ==============================================================
   Script completed successfully
   Exit code : 0

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.2 Updated to two-line ASCII console output style
 2026-01-14 v1.1.1 Fixed file structure - moved $ErrorActionPreference before <#
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-02 v1.0.0 Initial migration from SuperOps
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

# URL to Emsisoft installer
# IMPORTANT: Update this URL with your Emsisoft download link
$installerUrl = "https://dl.emsisoft.com/EmsisoftAntiMalwareSetup.exe"

# Directory to download installer to
$downloadPath = $env:TEMP

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Validating configuration..."

$errorOccurred = $false
$errorText = ""

# Validate URL
if ([string]::IsNullOrWhiteSpace($installerUrl)) {
    $errorOccurred = $true
    $errorText += "- Installer URL is required`n"
}

if (-not [string]::IsNullOrWhiteSpace($installerUrl)) {
    # Check URL format
    $urlValid = $installerUrl -match '^https?://'
    if (-not $urlValid) {
        $errorOccurred = $true
        $errorText += "- Installer URL must be a valid HTTP or HTTPS URL`n"
    }

    # Check URL ends with .exe
    if ($installerUrl -notmatch '\.exe$') {
        $errorOccurred = $true
        $errorText += "- Installer URL must point to an .exe file`n"
    }
}

# Validate download path
if ([string]::IsNullOrWhiteSpace($downloadPath)) {
    $errorOccurred = $true
    $errorText += "- Download path is required`n"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure installerUrl is set to a valid HTTPS URL"
    Write-Host "- Ensure download path exists and is writable"
    Write-Host "- Update hardcoded values in script before running"
    Write-Host ""
    exit 1
}

Write-Host "Download URL  : $installerUrl"
Write-Host "Download path : $downloadPath"
Write-Host "Input validation passed"

# ============================================================================
# DOWNLOAD
# ============================================================================

Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="
Write-Host "Downloading installer..."

try {
    # Extract filename from URL
    $filename = $installerUrl.Split("/")[-1]
    $fullPath = Join-Path -Path $downloadPath -ChildPath $filename

    Write-Host "Source URL   : $installerUrl"
    Write-Host "Target file  : $fullPath"

    # Download the installer
    Invoke-WebRequest -Uri $installerUrl -OutFile $fullPath -ErrorAction Stop

    # Verify download
    if (Test-Path -Path $fullPath) {
        $fileSize = (Get-Item $fullPath).Length
        Write-Host "Download completed successfully"
        Write-Host "File size    : $([math]::Round($fileSize / 1MB, 2)) MB"
    } else {
        throw "Downloaded file not found at expected location"
    }

} catch {
    Write-Host ""
    Write-Host "[ERROR] DOWNLOAD FAILED"
    Write-Host "=============================================================="
    Write-Host "Error details:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify internet connectivity"
    Write-Host "- Verify download URL is accessible"
    Write-Host "- Check firewall/proxy settings"
    Write-Host "- Ensure download path is writable"
    Write-Host ""
    exit 1
}

# ============================================================================
# INSTALLATION
# ============================================================================

Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="
Write-Host "Launching installer..."

try {
    # Execute the installer
    Start-Process -FilePath $fullPath -ErrorAction Stop

    Write-Host "Installer started : $filename"
    Write-Host ""
    Write-Host "Note: Installer may run in the background"
    Write-Host "      Follow on-screen prompts to complete installation"

} catch {
    Write-Host ""
    Write-Host "[ERROR] INSTALLATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Error details:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify downloaded file is a valid executable"
    Write-Host "- Check antivirus is not blocking execution"
    Write-Host "- Try running installer manually from: $fullPath"
    Write-Host ""
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Download successful : Yes"
Write-Host "Installer launched  : Yes"
Write-Host "Installer location  : $fullPath"

# ============================================================================
# SCRIPT COMPLETED
# ============================================================================

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
Write-Host "Script completed successfully"
Write-Host "Exit code : 0"
Write-Host ""

exit 0
