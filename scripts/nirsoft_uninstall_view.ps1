$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : NirSoft UninstallView                                          v1.0.0
FILE   : nirsoft_uninstall_view.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads NirSoft UninstallView utility and uses it to uninstall software
    matching a specified pattern using wildcard matching.

REQUIRED INPUTS:
    $appName : Name or pattern of application to uninstall (supports wildcards)

BEHAVIOR:
    1. Validates input parameters
    2. Determines system architecture (32/64-bit)
    3. Downloads appropriate UninstallView version
    4. Extracts to limehawk\nirsoft directory
    5. Runs uninstall command with wildcard matching
    6. Cleans up downloaded zip file

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Downloads from official NirSoft website

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Application Pattern : Adobe*
    System : 64-bit
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Downloading UninstallView (64-bit)...
    Extracting to C:\limehawk\nirsoft...
    Download completed

    [ UNINSTALL ]
    --------------------------------------------------------------
    Attempting to uninstall: Adobe*
    Uninstall command executed

    [ CLEANUP ]
    --------------------------------------------------------------
    Removing downloaded zip file...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Check manually to confirm uninstallation

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
# Set the application name or pattern to uninstall (supports wildcards)
$appName = 'CHANGE_ME'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($appName) -or $appName -eq 'CHANGE_ME') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Application name must be set (edit the script)"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

$systemArch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
Write-Host "Application Pattern : $appName"
Write-Host "System : $systemArch"
Write-Host "Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

$downloadUrl = if ([Environment]::Is64BitOperatingSystem) {
    "https://www.nirsoft.net/utils/uninstallview-x64.zip"
} else {
    "https://www.nirsoft.net/utils/uninstallview.zip"
}

$destinationFolder = "$env:SystemDrive\limehawk\nirsoft"

try {
    if (-not (Test-Path $destinationFolder)) {
        New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
    }

    $zipFilePath = Join-Path $destinationFolder "UninstallView.zip"

    Write-Host "Downloading UninstallView ($systemArch)..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing

    Write-Host "Extracting to $destinationFolder..."
    Expand-Archive -Path $zipFilePath -DestinationPath $destinationFolder -Force

    Write-Host "Download completed"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download UninstallView"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# UNINSTALL
# ============================================================================
Write-Host ""
Write-Host "[ UNINSTALL ]"
Write-Host "--------------------------------------------------------------"

$uninstallViewPath = Join-Path $destinationFolder "UninstallView.exe"

Write-Host "Attempting to uninstall: $appName"
Start-Process -FilePath $uninstallViewPath -ArgumentList "/quninstallwildcard `"$appName`" 5" -Wait -PassThru | Out-Null
Write-Host "Uninstall command executed"

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Removing downloaded zip file..."
Remove-Item $zipFilePath -Force -ErrorAction SilentlyContinue
Write-Host "Cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Check manually to confirm uninstallation"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
