$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT  : NirSoft UninstallView v1.1.0
AUTHOR  : Limehawk.io
DATE      : May 2026
USAGE   : .\nirsoft_uninstall_view.ps1
FILE    : nirsoft_uninstall_view.ps1
DESCRIPTION : Uses NirSoft UninstallView to uninstall software matching patterns
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads NirSoft UninstallView utility and uses it to uninstall software
    matching a specified pattern using wildcard matching.

REQUIRED INPUTS:
    $YourAppPatternHere : Name or pattern of application to uninstall
                          (supports wildcards), via SuperOps runtime variable

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
    [INFO] INPUT VALIDATION
    ==============================================================
    Application Pattern : Adobe*
    System : 64-bit
    Inputs validated successfully

    [RUN] DOWNLOAD
    ==============================================================
    Downloading UninstallView (64-bit)...
    Extracting to C:\limehawk\nirsoft...
    Download completed

    [RUN] UNINSTALL
    ==============================================================
    Attempting to uninstall: Adobe*
    Uninstall command executed

    [RUN] CLEANUP
    ==============================================================
    Removing downloaded zip file...
    Cleanup completed

    [OK] FINAL STATUS
    ==============================================================
    Result : SUCCESS
    Check manually to confirm uninstallation

    [OK] SCRIPT COMPLETED
    ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-05-21 v1.1.0 Use SuperOps runtime variable $YourAppPatternHere (was hardcoded CHANGE_ME)
2026-01-19 v1.0.3 Fixed EXAMPLE RUN section formatting
2026-01-19 v1.0.2 Updated to two-line ASCII console output style
2025-12-23 v1.0.1 Updated to Limehawk Script Framework
2024-12-01 v1.0.0 Initial release - migrated from SuperOps
================================================================================
#>

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Application name or pattern to uninstall (supports wildcards).
# Set via SuperOps runtime variable $YourAppPatternHere.
$appName = "$YourAppPatternHere"

Set-StrictMode -Version Latest

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($appName) -or $appName -eq '$' + 'YourAppPatternHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourAppPatternHere was not replaced."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

$systemArch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
Write-Host "Application Pattern : $appName"
Write-Host "System : $systemArch"
Write-Host "[OK] Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[INFO] DOWNLOAD"
Write-Host "=============================================================="

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

    Write-Host "[RUN] Downloading UninstallView ($systemArch)..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing

    Write-Host "[RUN] Extracting to $destinationFolder..."
    Expand-Archive -Path $zipFilePath -DestinationPath $destinationFolder -Force

    Write-Host "[OK] Download completed"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] DOWNLOAD FAILED"
    Write-Host "=============================================================="
    Write-Host "Failed to download UninstallView"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# UNINSTALL
# ============================================================================
Write-Host ""
Write-Host "[INFO] UNINSTALL"
Write-Host "=============================================================="

$uninstallViewPath = Join-Path $destinationFolder "UninstallView.exe"

Write-Host "[RUN] Attempting to uninstall: $appName"
Start-Process -FilePath $uninstallViewPath -ArgumentList "/quninstallwildcard `"$appName`" 5" -Wait -PassThru | Out-Null
Write-Host "[OK] Uninstall command executed"

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[INFO] CLEANUP"
Write-Host "=============================================================="

Write-Host "[RUN] Removing downloaded zip file..."
Remove-Item $zipFilePath -Force -ErrorAction SilentlyContinue
Write-Host "[OK] Cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[INFO] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Result : SUCCESS"
Write-Host "Check manually to confirm uninstallation"

Write-Host ""
Write-Host "[INFO] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
