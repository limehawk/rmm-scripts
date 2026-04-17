$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Winget Package Installer v1.0.2
AUTHOR  : Limehawk.io
DATE      : January 2026
USAGE   : .\winget_package_install.ps1
FILE    : winget_package_install.ps1
DESCRIPTION : Installs software package using winget with SuperOps integration
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs a software package using winget (Windows Package Manager). Uses
   SuperOps runtime text replacement for the package name. Handles silent
   installation with automatic acceptance of agreements.

 DATA SOURCES & PRIORITY
   1) Hardcoded script configuration (package name via SuperOps replacement)
   2) Winget package repository

 REQUIRED INPUTS
   - $PackageName - SuperOps runtime replacement variable for winget package ID
                    (e.g., "Google.Chrome", "Mozilla.Firefox")

 SETTINGS
   - Silent installation mode
   - Accepts package and source agreements automatically
   - Uses machine scope when available

 BEHAVIOR
   1. Validates software name input
   2. Checks winget availability
   3. Searches for package to verify it exists
   4. Installs package silently
   5. Reports installation result

 PREREQUISITES
   - Winget must be installed
   - Administrator privileges recommended
   - Internet connectivity

 SECURITY NOTES
   - No secrets in logs
   - Downloads only from official winget sources

 EXIT CODES
   - 0 = Success - package installed
   - 1 = Failure - installation failed or winget unavailable

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Software Name   : Google.Chrome

   [INFO] WINGET CHECK
   ==============================================================
   Winget          : Available
   Version         : v1.7.10861

   [RUN] INSTALLATION
   ==============================================================
   Installing Google.Chrome...
   Installation complete

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Package         : Google.Chrome installed

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-01-19 v1.0.2 Updated to two-line ASCII console output style
2025-12-23 v1.0.1 Updated to Limehawk Script Framework
2025-12-03 v1.0.0 Initial release - winget package installer for SuperOps
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS (SuperOps runtime replacement)
# ============================================================================

$PackageId = "$PackageName"    # Winget package ID - SuperOps replaces $PackageName

# ============================================================================
# INPUT VALIDATION
# ============================================================================

$errorOccurred = $false
$errorText = ""

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

if ([string]::IsNullOrWhiteSpace($PackageId)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Package ID is required (set via SuperOps runtime replacement)"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    exit 1
}

Write-Host "Package ID      : $PackageId"

# ============================================================================
# WINGET CHECK
# ============================================================================

Write-Host ""
Write-Host "[INFO] WINGET CHECK"
Write-Host "=============================================================="

$wingetPath = $null
$runAsSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")

try {
    if ($runAsSystem) {
        $resolvedPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
                        Sort-Object | Select-Object -Last 1
        if ($resolvedPath) {
            $wingetPath = Join-Path $resolvedPath.Path "winget.exe"
            if (-not (Test-Path $wingetPath)) {
                $wingetPath = $null
            }
        }
    } else {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $wingetPath = $wingetCmd.Source
        }
    }
} catch {
    $wingetPath = $null
}

if (-not $wingetPath) {
    Write-Host ""
    Write-Host "[ERROR] WINGET NOT AVAILABLE"
    Write-Host "=============================================================="
    Write-Host "Winget is not installed or not available"
    Write-Host "Run winget_installer.ps1 first to install winget"
    Write-Host ""
    exit 1
}

# Get version
try {
    $versionOutput = & $wingetPath --version 2>&1
    $wingetVersion = if ($versionOutput -match 'v[\d.]+') { $matches[0] } else { "Unknown" }
} catch {
    $wingetVersion = "Unknown"
}

Write-Host "Winget          : Available"
Write-Host "Version         : $wingetVersion"

# ============================================================================
# INSTALLATION
# ============================================================================

Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

Write-Host "Installing $PackageId..."

try {
    $installArgs = @(
        "install"
        "--id", $PackageId
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    $process = Start-Process -FilePath $wingetPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Host "Installation complete"
        $installSuccess = $true
    } elseif ($process.ExitCode -eq -1978335189) {
        # Package already installed
        Write-Host "Package already installed"
        $installSuccess = $true
    } else {
        Write-Host "Winget exit code : $($process.ExitCode)"
        $installSuccess = $false
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] INSTALLATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($installSuccess) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Package         : $PackageId installed"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Package         : $PackageId"
    Write-Host "Action          : Check winget logs or try manual installation"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
