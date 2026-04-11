$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Scan Subnet v0.3.1
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_scan.ps1
FILE    : prinstall_scan.ps1
DESCRIPTION : Scans a subnet for network printers using prinstall
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Scans a subnet for network printers using prinstall's full multi-method
   discovery pipeline: TCP port probe (9100/631/515), IPP Get-Printer-
   Attributes, SNMPv2c, and mDNS/Bonjour multicast browse. Returns
   printer IPs, models, discovery methods used, and status. Designed for
   RMM deployment to discover every printer on a client network — even
   silent AirPrint-only printers that ignore SNMP.

 DATA SOURCES & PRIORITY
   1) TCP port probe (9100 raw, 631 IPP, 515 LPR) to find live hosts
   2) IPP Get-Printer-Attributes for make/model and IEEE 1284 device ID
   3) SNMPv2c for vendor/model/serial/status enrichment
   4) mDNS multicast browse (_ipp/_ipps/_pdl-datastream/_printer._tcp.local.)
      catches AirPrint printers that don't respond to unicast probes
   5) SuperOps runtime variable for subnet (optional — blank = auto-detect)

 REQUIRED INPUTS
   - $subnet       : Subnet in CIDR notation (SuperOps: $YourSubnetHere).
                     Leave blank to auto-detect the local subnet via
                     Get-NetIPAddress on the primary NIC.
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Discovery method: all (port + IPP + SNMP + mDNS)
   - SNMP community string: public (default)
   - Output format: verbose text for RMM console

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. If subnet is blank, prinstall auto-detects it from the local NIC
   3. Runs `prinstall scan [subnet] --verbose` which executes the full
      discovery pipeline in parallel and merges results
   4. Outputs discovered printers to console with the method(s) that
      found each one

 PREREQUISITES
   - Windows OS
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to target subnet
   - UDP 161 (SNMP), TCP 9100 (raw print), TCP 631 (IPP) not blocked
   - UDP 5353 (mDNS) open on the NIC — the prinstall_setup.ps1 installer
     pre-creates a "Prinstall (mDNS discovery)" firewall rule so the
     mDNS pass works under SYSTEM-context RMM execution without friction

 SECURITY NOTES
   - No secrets in logs
   - SNMP community string visible in process args if non-default
   - mDNS/IPP/SNMP traffic is normal service-discovery traffic and does
     not authenticate against target printers

 ENDPOINTS
   - Target subnet printers via TCP 9100/631/515 and UDP 161
   - Link-local multicast UDP 5353 (mDNS) — not routed off-segment

 EXIT CODES
   - 0 = Success - scan completed
   - 1 = Failure - prinstall not found or scan failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Subnet          : 192.168.1.0/24
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.3.1
   Inputs validated successfully

   [RUN] SCAN SUBNET
   ==============================================================
   Scanning 192.168.1.0/24 for printers...

   [scan] Port scan found 3 candidates
   [scan] 192.168.1.10: SNMP -> model "HP LaserJet Pro MFP M428fdw"
   [scan] 192.168.1.25: IPP -> model "Canon imageCLASS MF455dw"
   [mdns] resolved 1 unique printer(s)

   IP              Model                          Source   Status
   --------------- ------------------------------ -------- --------
   192.168.1.10    HP LaserJet Pro MFP M428fdw    Network  Ready
   192.168.1.25    Canon imageCLASS MF455dw       Network  Ready
   192.168.1.50    Brother MFC-L2750DW series     Network  Unknown

     3 printer(s)  ·  Port+IPP+SNMP 2  ·  mDNS 1

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Subnet          : 192.168.1.0/24

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.1 Refresh for prinstall 0.3.1: document the new mDNS browse
                  pass (bundled into the default `all` method), the
                  working subnet auto-detect path, and the firewall rule
                  pre-created by prinstall_setup.ps1 for UDP 5353. No
                  wrapper logic changes — leaving $YourSubnetHere blank
                  has always worked, prinstall 0.3.1 just finally honors
                  it instead of erroring out.
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
