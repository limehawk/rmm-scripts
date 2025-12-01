$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : OnlyOffice Install                                             v1.0.0
FILE   : onlyoffice_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads and silently installs OnlyOffice Desktop Editors, a free office
    suite compatible with Microsoft Office formats.

REQUIRED INPUTS:
    $downloadUrl : URL to download OnlyOffice MSI installer

BEHAVIOR:
    1. Validates input parameters
    2. Downloads OnlyOffice MSI installer to temp directory
    3. Installs silently using msiexec
    4. Cleans up installer file

PREREQUISITES:
    - Windows OS (64-bit)
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Downloads from official OnlyOffice website

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Download URL : https://download.onlyoffice.com/install/desktop/...
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Downloading OnlyOffice Desktop Editors...
    Download completed successfully

    [ INSTALLATION ]
    --------------------------------------------------------------
    Installing OnlyOffice silently...
    Installation completed successfully

    [ CLEANUP ]
    --------------------------------------------------------------
    Removing installer file...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    OnlyOffice Desktop Editors installed successfully

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
$downloadUrl = 'https://download.onlyoffice.com/install/desktop/editors/windows/distrib/onlyoffice/DesktopEditors_x64.msi'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Download URL is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Download URL : $downloadUrl"
Write-Host "Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

$installerPath = Join-Path $env:TEMP "DesktopEditors_x64.msi"

try {
    Write-Host "Downloading OnlyOffice Desktop Editors..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    if (-not (Test-Path $installerPath)) {
        throw "Installer file was not downloaded"
    }

    Write-Host "Download completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download OnlyOffice"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# INSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Installing OnlyOffice silently..."
    $process = Start-Process "msiexec.exe" -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "MSI installation failed with exit code: $($process.ExitCode)"
    }

    Write-Host "Installation completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to install OnlyOffice"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Removing installer file..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "Cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "OnlyOffice Desktop Editors installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
