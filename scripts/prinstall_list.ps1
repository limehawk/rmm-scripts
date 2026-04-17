$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall List Printers v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_list.ps1
FILE    : prinstall_list.ps1
DESCRIPTION : Lists installed printers on the system using prinstall
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Lists all locally installed printers (USB, network, virtual) using
   prinstall's list command. Useful for auditing printer installations
   via RMM or verifying a printer was added successfully.

 DATA SOURCES & PRIORITY
   1) Windows Get-Printer data via prinstall

 REQUIRED INPUTS
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Output format: verbose text for RMM console

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. Runs prinstall list to enumerate installed printers
   3. Outputs printer list to console

 PREREQUISITES
   - Windows OS
   - prinstall.exe installed (run prinstall_setup.ps1 first)

 SECURITY NOTES
   - No secrets in logs

 ENDPOINTS
   - Not applicable (local query only)

 EXIT CODES
   - 0 = Success - list completed
   - 1 = Failure - prinstall not found or list failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Inputs validated successfully

   [RUN] LIST PRINTERS
   ==============================================================
   Name                           Driver                         Port
   ------------------------------ ------------------------------ ---------------
   HP LaserJet Pro MFP M428fdw    HP Universal Print Driver      IP_192.168.1.10
   Canon MF455dw                  Canon UFR II LT                IP_192.168.1.25
   Microsoft Print to PDF         Microsoft Print To PDF         PORTPROMPT:

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 Realign version scheme with prinstall app version (was v1.0.0).
                  No functional changes — `list` subcommand unchanged in 0.3.0.
2026-03-25 v1.0.0 Initial release - prinstall list printers wrapper
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$prinstallDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($prinstallDir)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Prinstall directory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

$exePath = "$prinstallDir\prinstall.exe"

Write-Host "Prinstall       : $exePath"
Write-Host "Inputs validated successfully"

# ============================================================================
# PRINSTALL CHECK
# ============================================================================
Write-Host ""
Write-Host "[INFO] PRINSTALL CHECK"
Write-Host "=============================================================="

if (-not (Test-Path $exePath)) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "prinstall.exe not found at $exePath"
    Write-Host "Run prinstall_setup.ps1 first to install prinstall"
    exit 1
}

try {
    $versionOutput = & $exePath --version 2>&1
    Write-Host "Version         : $versionOutput"
} catch {
    Write-Host "Version         : Unknown"
}

# ============================================================================
# LIST PRINTERS
# ============================================================================
Write-Host ""
Write-Host "[RUN] LIST PRINTERS"
Write-Host "=============================================================="

try {
    # See prinstall_scan.ps1 for why we swap EAP for the subprocess call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exePath list 2>&1 | ForEach-Object { Write-Host $_ }
        $listExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall list failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($listExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $listExitCode"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
