$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Drivers Preview v0.4.8
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_drivers.ps1
FILE    : prinstall_drivers.ps1
DESCRIPTION : Previews matched and universal drivers for a network printer
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Wraps `prinstall drivers <ip>` to identify a printer by IP and show the
   matched + universal driver candidates the installer would pick from.
   Lets a technician preview driver selection before committing to a
   `prinstall add` install. Supports SNMP-based model discovery and an
   optional manual model override for printers that don't respond to SNMP.

 DATA SOURCES & PRIORITY
   1) SNMP model discovery against the target printer IP (default path)
   2) Manual --model override via $YourModelHere when SNMP is blocked or
      the printer reports a generic model string
   3) prinstall's bundled driver catalog matched against vendor/model

 REQUIRED INPUTS
   - $printerIp    : IPv4 address of the target printer
                     (SuperOps: $YourIpHere)
   - $printerModel : Optional model override string
                     (SuperOps: $YourModelHere — leave blank for SNMP)
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Discovery method: SNMPv2c (via prinstall) unless --model is supplied
   - Output format: verbose text listing matched + universal drivers
   - Read-only: this command does NOT install any driver, it only previews

 BEHAVIOR
   1. Validates inputs and ensures $printerIp was replaced by SuperOps
   2. Checks prinstall.exe exists at the expected path
   3. Builds the argument array: @('drivers', $printerIp) plus
      @('--model', $printerModel) when $printerModel is non-empty
   4. Invokes prinstall and streams its output to the console
   5. Reports final status based on $LASTEXITCODE

 PREREQUISITES
   - Windows OS
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to the printer's IP
   - UDP 161 (SNMP) reachable, OR a known model string to pass via --model

 SECURITY NOTES
   - No secrets in logs
   - Printer IP and model are surfaced in the RMM console output
   - SNMP community string (default: public) visible in process args if
     prinstall is configured to use a non-default community

 ENDPOINTS
   - Target printer via UDP 161 (SNMP) when no --model override is given
   - No external/internet endpoints — driver catalog is bundled with
     prinstall.exe

 EXIT CODES
   - 0 = Success - driver preview generated
   - 1 = Failure - prinstall not found, IP unreplaced, or drivers command
         failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Printer IP      : 192.168.1.10
   Model override  : (auto-detect via SNMP)
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.4.8
   Inputs validated successfully

   [RUN] DRIVER PREVIEW
   ==============================================================
   Previewing drivers for 192.168.1.10...

   [snmp] 192.168.1.10 -> "HP LaserJet Pro MFP M428fdw"

   Matched drivers (2):
     - HP Universal Printing PCL 6 (v7.0.1.24923)
     - HP LaserJet Pro MFP M428-M429 PCL-6

   Universal fallbacks (1):
     - Microsoft IPP Class Driver

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Printer IP      : 192.168.1.10

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-14 v0.4.8 Initial release — wrapper for `prinstall drivers <ip>`
                  subcommand. Aligns version scheme with prinstall app
                  version 0.4.8. Supports SNMP discovery and --model
                  override for SNMP-silent printers.
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$printerIp    = "$YourIpHere"
$printerModel = "$YourModelHere"
$prinstallDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

# Treat unreplaced model placeholder as empty (SNMP auto-detect path)
if ($printerModel -eq '$' + 'YourModelHere') { $printerModel = '' }

# Printer IP is required — flag unreplaced placeholder explicitly
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
if ([string]::IsNullOrWhiteSpace($printerModel)) {
    Write-Host "Model override  : (auto-detect via SNMP)"
} else {
    Write-Host "Model override  : $printerModel"
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
# DRIVER PREVIEW
# ============================================================================
Write-Host ""
Write-Host "[RUN] DRIVER PREVIEW"
Write-Host "=============================================================="

Write-Host "Previewing drivers for $printerIp..."
Write-Host ""

try {
    $driverArgs = @('drivers', $printerIp)
    if (-not [string]::IsNullOrWhiteSpace($printerModel)) {
        $driverArgs += @('--model', $printerModel)
    }
    & $exePath @driverArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $driversExitCode = $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall drivers preview failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($driversExitCode -eq 0) {
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
    Write-Host "Exit code       : $driversExitCode"
    Write-Host "Printer IP      : $printerIp"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
