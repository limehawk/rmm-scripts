$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Install Printer v1.0.0
AUTHOR  : Limehawk.io
DATE      : March 2026
USAGE   : .\prinstall_install_printer.ps1
FILE    : prinstall_install_printer.ps1
DESCRIPTION : Installs a network printer using prinstall (port + driver + queue)
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs a network printer on Windows using prinstall. Creates the TCP/IP
   port, installs the matched driver, and adds the printer queue in one step.
   Designed for RMM deployment where technicians specify the printer IP and
   optionally a driver name and display name via SuperOps runtime variables.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variables for printer IP, driver, and display name
   2) Prinstall auto-detection via SNMP for model and driver matching

 REQUIRED INPUTS
   - $printerIp    : IP address of the network printer (SuperOps: $YourPrinterIpHere)
   - $driverName   : Specific driver name, or empty for auto-match (SuperOps: $YourDriverNameHere)
   - $printerName  : Display name for the printer, or empty for model name (SuperOps: $YourPrinterNameHere)
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Auto-selects best driver if $driverName is empty
   - Uses printer model as display name if $printerName is empty
   - Verbose output enabled for RMM console visibility

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. Builds prinstall install command with specified options
   3. Runs full install (port + driver + queue)
   4. Reports installation result

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to printer IP
   - UDP 161 (SNMP) for auto-detection

 SECURITY NOTES
   - No secrets in logs
   - Printer IP and driver name visible in process args

 ENDPOINTS
   - Target printer via TCP/IP and SNMP

 EXIT CODES
   - 0 = Success - printer installed
   - 1 = Failure - installation failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Printer IP      : 192.168.1.100
   Driver          : (auto-detect)
   Printer Name    : (auto-detect)
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Inputs validated successfully

   [RUN] INSTALL PRINTER
   ==============================================================
   Installing printer at 192.168.1.100...

   [RUN] Identifying printer via SNMP...
   Model           : HP LaserJet Pro MFP M428fdw
   [RUN] Best driver match: HP Universal Print Driver PCL6 (exact)
   [RUN] Creating port: IP_192.168.1.100
   [OK] Port created
   [RUN] Installing driver: HP Universal Print Driver PCL6
   [OK] Driver installed
   [RUN] Adding printer: HP LaserJet Pro MFP M428fdw
   [OK] Printer added

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Printer         : HP LaserJet Pro MFP M428fdw
   IP              : 192.168.1.100

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-03-25 v1.0.0 Initial release - prinstall printer installation wrapper
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$printerIp    = "$YourPrinterIpHere"      # Printer IP address
$driverName   = "$YourDriverNameHere"      # Specific driver name, or leave as placeholder for auto-match
$printerName  = "$YourPrinterNameHere"     # Display name, or leave as placeholder for model name
$prinstallDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($printerIp) -or $printerIp -eq '$' + 'YourPrinterIpHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourPrinterIpHere was not replaced."
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

# Treat unreplaced optional placeholders as empty
$useDriver = $driverName
if ($useDriver -eq '$' + 'YourDriverNameHere') { $useDriver = '' }

$useName = $printerName
if ($useName -eq '$' + 'YourPrinterNameHere') { $useName = '' }

$exePath = "$prinstallDir\prinstall.exe"

Write-Host "Printer IP      : $printerIp"
if ([string]::IsNullOrWhiteSpace($useDriver)) {
    Write-Host "Driver          : (auto-detect)"
} else {
    Write-Host "Driver          : $useDriver"
}
if ([string]::IsNullOrWhiteSpace($useName)) {
    Write-Host "Printer Name    : (auto-detect)"
} else {
    Write-Host "Printer Name    : $useName"
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
# INSTALL PRINTER
# ============================================================================
Write-Host ""
Write-Host "[RUN] INSTALL PRINTER"
Write-Host "=============================================================="

Write-Host "Installing printer at $printerIp..."
Write-Host ""

try {
    $installArgs = @('install', $printerIp, '--verbose')

    if (-not [string]::IsNullOrWhiteSpace($useDriver)) {
        $installArgs += '--driver'
        $installArgs += $useDriver
    }

    if (-not [string]::IsNullOrWhiteSpace($useName)) {
        $installArgs += '--name'
        $installArgs += $useName
    }

    & $exePath @installArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $installExitCode = $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall install failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($installExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "IP              : $printerIp"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $installExitCode"
    Write-Host "IP              : $printerIp"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
