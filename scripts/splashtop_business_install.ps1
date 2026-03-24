$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT  : Splashtop Business Install v2.0.0
AUTHOR  : Limehawk.io
DATE      : March 2026
USAGE   : .\splashtop_business_install.ps1
FILE    : splashtop_business_install.ps1
DESCRIPTION : Installs Splashtop Business client via winget
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs the Splashtop Business client application using winget (Windows
   Package Manager). This is the end-user remote access client, not the
   streamer agent.

 DATA SOURCES & PRIORITY
   1) Winget package repository (default source)

 REQUIRED INPUTS
   - $packageId : Winget package ID (default: Splashtop.SplashtopBusiness)

 SETTINGS
   - Silent installation mode
   - Accepts package and source agreements automatically

 BEHAVIOR
   1. Validates input parameters
   2. Detects execution context (SYSTEM vs user)
   3. Resolves winget path accordingly
   4. Installs Splashtop Business silently via winget
   5. Reports installation result

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - Winget installed (run winget_setup.ps1 if needed)
   - Internet connectivity

 SECURITY NOTES
   - No secrets in logs
   - Downloads only from official winget sources

 ENDPOINTS
   - Not applicable (winget manages download sources)

 EXIT CODES
   - 0 = Success - package installed
   - 1 = Failure - installation failed or winget unavailable

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Package ID : Splashtop.SplashtopBusiness
   Inputs validated successfully

   [INFO] WINGET CHECK
   ==============================================================
   Context         : SYSTEM
   Winget          : Available
   Version         : v1.7.10861

   [RUN] INSTALLATION
   ==============================================================
   Installing Splashtop.SplashtopBusiness...
   Installation complete

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Package         : Splashtop.SplashtopBusiness installed

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-03-24 v2.0.0 Rewrite to use winget instead of direct MSI download
2026-01-19 v1.0.2 Updated to two-line ASCII console output style
2025-12-23 v1.0.1 Updated to Limehawk Script Framework
2024-12-01 v1.0.0 Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$packageId = 'Splashtop.SplashtopBusiness'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($packageId)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Package ID is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

Write-Host "Package ID : $packageId"
Write-Host "Inputs validated successfully"

# ============================================================================
# WINGET CHECK
# ============================================================================
Write-Host ""
Write-Host "[INFO] WINGET CHECK"
Write-Host "=============================================================="

$wingetPath = $null
$runAsSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")

if ($runAsSystem) {
    Write-Host "Context         : SYSTEM"
    $resolvedPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
                    Sort-Object | Select-Object -Last 1
    if ($resolvedPath) {
        $wingetPath = Join-Path $resolvedPath.Path "winget.exe"
        if (-not (Test-Path $wingetPath)) {
            $wingetPath = $null
        }
    }
} else {
    Write-Host "Context         : User"
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $wingetPath = $wingetCmd.Source
    }
}

if (-not $wingetPath) {
    Write-Host ""
    Write-Host "[ERROR] WINGET NOT AVAILABLE"
    Write-Host "=============================================================="
    Write-Host "Winget is not installed or not available"
    Write-Host "Run winget_setup.ps1 first to install winget"
    exit 1
}

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

Write-Host "Installing $packageId..."

try {
    $installArgs = @(
        "install"
        "--id", $packageId
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    $process = Start-Process -FilePath $wingetPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Host "Installation complete"
        $installSuccess = $true
    } elseif ($process.ExitCode -eq -1978335189) {
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
    Write-Host "Error : $($_.Exception.Message)"
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
    Write-Host "Package         : $packageId installed"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Package         : $packageId"
    Write-Host "Action          : Check winget logs or try manual installation"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
