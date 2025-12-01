$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Splashtop Business Install                                    v1.0.0
FILE   : splashtop_business_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads and silently installs the Splashtop Business client application.
    This is the end-user remote access client, not the streamer agent.

REQUIRED INPUTS:
    $downloadUrl   : URL to download the Splashtop Business MSI installer
    $tempDirectory : Directory to store the installer temporarily

BEHAVIOR:
    1. Validates input parameters
    2. Creates temporary directory if needed
    3. Downloads Splashtop Business MSI installer
    4. Installs silently with logging
    5. Cleans up installer file

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Installer downloaded over HTTPS

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Download URL : https://redirect.splashtop.com/my/src/msi
    Temp Directory : C:\Temp
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Downloading Splashtop Business installer...
    Download completed successfully
    File Size : 45.2 MB

    [ INSTALLATION ]
    --------------------------------------------------------------
    Installing Splashtop Business silently...
    Installation completed successfully

    [ CLEANUP ]
    --------------------------------------------------------------
    Removing installer file...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Splashtop Business installed successfully

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
$downloadUrl   = 'https://redirect.splashtop.com/my/src/msi'
$tempDirectory = "$env:SystemDrive\Temp"

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

if ([string]::IsNullOrWhiteSpace($tempDirectory)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Temp directory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Download URL : $downloadUrl"
Write-Host "Temp Directory : $tempDirectory"
Write-Host "Inputs validated successfully"

# ============================================================================
# SETUP
# ============================================================================
$installerPath = "$tempDirectory\Splashtop_Business_Win_INSTALLER.msi"
$logPath = "$tempDirectory\splashtop_install_log.txt"

if (-not (Test-Path $tempDirectory)) {
    New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null
    Write-Host "Created temp directory"
}

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Downloading Splashtop Business installer..."

    $curlPath = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curlPath) {
        & $curlPath -L -o $installerPath $downloadUrl 2>&1 | Out-Null
    } else {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
    }

    if (-not (Test-Path $installerPath)) {
        throw "Installer file was not downloaded"
    }

    $fileSize = [math]::Round((Get-Item $installerPath).Length / 1MB, 2)
    Write-Host "Download completed successfully"
    Write-Host "File Size : $fileSize MB"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download Splashtop installer"
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
    Write-Host "Installing Splashtop Business silently..."

    $msiArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$logPath`""
    $process = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru

    if ($process.ExitCode -ne 0) {
        throw "MSI installation failed with exit code: $($process.ExitCode)"
    }

    Write-Host "Installation completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to install Splashtop Business"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host "Check install log : $logPath"
    exit 1
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Removing installer file..."
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "Cleanup completed"
}
catch {
    Write-Host "Warning: Could not remove installer file"
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Splashtop Business installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
