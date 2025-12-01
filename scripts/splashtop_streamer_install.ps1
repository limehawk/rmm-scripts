$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Splashtop Streamer Install                                     v1.0.0
FILE   : splashtop_streamer_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Silently installs or upgrades the Splashtop Streamer agent for remote
    access. Configured to hide the system tray icon by default.

REQUIRED INPUTS:
    $installerPath : Full path to the Splashtop Streamer deploy installer EXE

BEHAVIOR:
    1. Validates installer path is provided
    2. Checks that installer file exists
    3. Executes silent installation with parameters:
       - prevercheck : Pre-verification check
       - /s : Silent mode
       - /i confirm_d=0 : No confirmation dialogs
       - hidewindow=1 : Hide installation window
       - notray=1 : Hide tray icon
    4. Reports installation status

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Splashtop deploy installer downloaded to specified path

SECURITY NOTES:
    - No secrets in logs
    - Installer must be pre-staged at the specified path

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Installer Path : C:\temp\Splashtop_Streamer_DEPLOY.exe
    Inputs validated successfully

    [ INSTALLATION ]
    --------------------------------------------------------------
    Starting Splashtop Streamer installation...
    Installation parameters:
      Silent Mode : Yes
      Hide Window : Yes
      Hide Tray : Yes
    Installation completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Splashtop Streamer installed successfully

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - converted from batch script
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Update this path to match your deploy installer location
$installerPath = 'C:\temp\Splashtop_Streamer_Windows_DEPLOY_INSTALLER.exe'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($installerPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Installer path is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Installer Path : $installerPath"

if (-not (Test-Path $installerPath)) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Installer file not found at specified path"
    Write-Host "Please download the deploy installer from Splashtop"
    Write-Host "and place it at: $installerPath"
    exit 1
}

Write-Host "Inputs validated successfully"

# ============================================================================
# INSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Starting Splashtop Streamer installation..."
    Write-Host "Installation parameters:"
    Write-Host "  Silent Mode : Yes"
    Write-Host "  Hide Window : Yes"
    Write-Host "  Hide Tray : Yes"

    $arguments = "prevercheck /s /i confirm_d=0,hidewindow=1,notray=1"
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Installation may have failed"
        Write-Host "Exit Code : $($process.ExitCode)"
        exit 1
    }

    Write-Host "Installation completed"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to execute installer"
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
Write-Host "Splashtop Streamer installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
