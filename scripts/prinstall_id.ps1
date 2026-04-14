$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Identify Printer v0.4.8
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_id.ps1
FILE    : prinstall_id.ps1
DESCRIPTION : Identifies a single printer by IP via SNMP using prinstall
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Wraps the `prinstall id <ip>` subcommand to query a single printer via
   SNMP and return model, serial number, and device status. Used by techs
   to verify a printer's identity and reachability before running an add,
   or to confirm SNMP is answering on an expected IP.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variable for the target printer IP (required)
   2) prinstall.exe installed under $env:ProgramData\prinstall

 REQUIRED INPUTS
   - $printerIp    : Target printer IP address (SuperOps: $YourIpHere).
                     Required — unreplaced placeholder is an error.
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Subcommand: id
   - Transport: SNMPv2c
   - Output format: default prinstall text output for RMM console

 BEHAVIOR
   1. Validates inputs and ensures $YourIpHere was replaced
   2. Checks prinstall.exe exists
   3. Runs `prinstall id <printerIp>` and streams output to console
   4. Reports success/failure based on $LASTEXITCODE

 PREREQUISITES
   - Windows OS
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to the target printer
   - UDP 161 (SNMP) open to the printer

 SECURITY NOTES
   - No secrets in logs
   - SNMP community string visible in process args if non-default
   - SNMP query is read-only, does not authenticate against the printer

 ENDPOINTS
   - Target printer via UDP 161 (SNMP)

 EXIT CODES
   - 0 = Success - printer identified
   - 1 = Failure - input invalid, prinstall not found, or query failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Printer IP      : 192.168.1.10
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Inputs validated successfully

   [INFO] PRINSTALL CHECK
   ==============================================================
   Version         : prinstall 0.4.8

   [RUN] IDENTIFY PRINTER
   ==============================================================
   Identifying printer at 192.168.1.10...

   IP      : 192.168.1.10
   Model   : HP LaserJet Pro MFP M428fdw
   Serial  : CNB8J1234X
   Status  : Ready

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Printer IP      : 192.168.1.10

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-14 v0.4.8 Initial release - prinstall id wrapper. Aligns version
                  scheme with prinstall app v0.4.8. Requires an explicit
                  target IP via $YourIpHere (no auto-detect fallback).
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$printerIp    = "$YourIpHere"
$prinstallDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

# Unreplaced placeholder is a hard error — unlike scan, this script needs a target IP
if ([string]::IsNullOrWhiteSpace($printerIp) -or $printerIp -eq '$' + 'YourIpHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourIpHere was not replaced."
}

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

Write-Host "Printer IP      : $printerIp"
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
# IDENTIFY PRINTER
# ============================================================================
Write-Host ""
Write-Host "[RUN] IDENTIFY PRINTER"
Write-Host "=============================================================="

Write-Host "Identifying printer at $printerIp..."
Write-Host ""

try {
    & $exePath id $printerIp 2>&1 | ForEach-Object { Write-Host $_ }
    $idExitCode = $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall id failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($idExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Printer IP      : $printerIp"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $idExitCode"
    Write-Host "Printer IP      : $printerIp"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
