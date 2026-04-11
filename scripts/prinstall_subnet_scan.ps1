$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Scan Subnet v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_subnet_scan.ps1
FILE    : prinstall_subnet_scan.ps1
DESCRIPTION : Scans a subnet for network printers using prinstall
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Scans a subnet for network printers using prinstall's SNMP and port
   discovery. Returns printer IPs, models, and status. Designed for RMM
   deployment to discover printers on a client network.

 DATA SOURCES & PRIORITY
   1) Prinstall SNMP/port scan results
   2) SuperOps runtime variable for subnet

 REQUIRED INPUTS
   - $subnet       : Subnet in CIDR notation (SuperOps: $YourSubnetHere)
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Discovery method: all (SNMP + port check)
   - SNMP community string: public (default)
   - Output format: verbose text for RMM console

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. Runs prinstall scan with specified subnet
   3. Outputs discovered printers to console

 PREREQUISITES
   - Windows OS
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to target subnet
   - UDP 161 (SNMP) and/or TCP 9100 (raw print) not blocked

 SECURITY NOTES
   - No secrets in logs
   - SNMP community string visible in process args if non-default

 ENDPOINTS
   - Target subnet printers via UDP 161 and TCP 9100

 EXIT CODES
   - 0 = Success - scan completed
   - 1 = Failure - prinstall not found or scan failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Subnet          : 192.168.1.0/24
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Inputs validated successfully

   [RUN] SCAN SUBNET
   ==============================================================
   Scanning 192.168.1.0/24 for printers...

   IP              Model                          Status
   --------------- ------------------------------ ----------
   192.168.1.10    HP LaserJet Pro MFP M428fdw    Ready
   192.168.1.25    Canon imageCLASS MF455dw       Ready

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Printers found  : 2

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 Realign version scheme with prinstall app version (was v1.1.0).
                  No functional changes — prinstall 0.3.0's multi-method scan
                  pipeline (port probe + IPP + SNMP + local enum) works with
                  the same `scan` subcommand and flags.
2026-03-25 v1.1.0 Make subnet optional, auto-detect local subnet when blank
2026-03-25 v1.0.0 Initial release - prinstall subnet scan wrapper
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$subnet       = "$YourSubnetHere"    # CIDR notation, e.g. 192.168.1.0/24
$prinstallDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

# Treat unreplaced placeholder as empty (auto-detect local subnet)
if ($subnet -eq '$' + 'YourSubnetHere') { $subnet = '' }

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

if ([string]::IsNullOrWhiteSpace($subnet)) {
    Write-Host "Subnet          : (auto-detect local)"
} else {
    Write-Host "Subnet          : $subnet"
}
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
# SCAN SUBNET
# ============================================================================
Write-Host ""
Write-Host "[RUN] SCAN SUBNET"
Write-Host "=============================================================="

if ([string]::IsNullOrWhiteSpace($subnet)) {
    Write-Host "Scanning local subnet for printers..."
} else {
    Write-Host "Scanning $subnet for printers..."
}
Write-Host ""

try {
    $scanArgs = @('scan', '--verbose')
    if (-not [string]::IsNullOrWhiteSpace($subnet)) {
        $scanArgs = @('scan', $subnet, '--verbose')
    }
    & $exePath @scanArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $scanExitCode = $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall scan failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($scanExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Subnet          : $subnet"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $scanExitCode"
    Write-Host "Subnet          : $subnet"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
