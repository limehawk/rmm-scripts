$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : 1Password Install                                              v1.0.0
FILE   : 1password_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads and silently installs the latest version of 1Password for Windows
    using the official MSI installer with configurable deployment options.

REQUIRED INPUTS:
    $downloadUrl        : URL to download 1Password MSI installer
    $preventRestart     : Prevent automatic restart after install (true/false)
    $manageUpdates      : Disable user-initiated updates (true/false)
    $removeOtherInstalls: Remove other 1Password installations (true/false)

BEHAVIOR:
    1. Validates input parameters
    2. Downloads 1Password MSI installer to temp directory
    3. Builds MSI arguments based on deployment options
    4. Installs silently using msiexec
    5. Cleans up installer file

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Downloads from official 1Password URL

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Download URL : https://downloads.1password.com/win/1PasswordSetup-latest.msi
    Prevent Restart : True
    Manage Updates : False
    Remove Other Installs : True
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Downloading 1Password installer...
    Download completed successfully

    [ INSTALLATION ]
    --------------------------------------------------------------
    Installing 1Password silently...
    Option: Prevent restart enabled
    Option: Remove other installations enabled
    Installation completed successfully

    [ CLEANUP ]
    --------------------------------------------------------------
    Removing installer file...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    1Password installed successfully

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
$downloadUrl         = 'https://downloads.1password.com/win/1PasswordSetup-latest.msi'
$preventRestart      = $true
$manageUpdates       = $false
$removeOtherInstalls = $true

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
Write-Host "Prevent Restart : $preventRestart"
Write-Host "Manage Updates : $manageUpdates"
Write-Host "Remove Other Installs : $removeOtherInstalls"
Write-Host "Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

$installerPath = Join-Path $env:TEMP "1PasswordSetup-latest.msi"

try {
    Write-Host "Downloading 1Password installer..."
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
    Write-Host "Failed to download 1Password installer"
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
    Write-Host "Installing 1Password silently..."

    $msiArgs = @("/i", "`"$installerPath`"", "/qn")

    if ($preventRestart) {
        $msiArgs += "/norestart"
        Write-Host "Option: Prevent restart enabled"
    }

    if ($manageUpdates) {
        $msiArgs += "MANAGED_UPDATE=1"
        Write-Host "Option: User updates disabled"
    }

    if ($removeOtherInstalls) {
        $msiArgs += "MANAGED_INSTALL=1"
        Write-Host "Option: Remove other installations enabled"
    }

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "MSI installation failed with exit code: $($process.ExitCode)"
    }

    Write-Host "Installation completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to install 1Password"
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
Write-Host "1Password installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
