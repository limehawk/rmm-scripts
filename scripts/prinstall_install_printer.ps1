$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Install Printer v1.1.0
AUTHOR  : Limehawk.io
DATE      : March 2026
USAGE   : .\prinstall_install_printer.ps1
FILE    : prinstall_install_printer.ps1
DESCRIPTION : Installs a network or USB printer using prinstall
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs a printer on Windows using prinstall. For network printers,
   creates the TCP/IP port, installs the driver, and adds the queue. For
   USB printers, stages the driver only (Windows handles the rest on plug-in).
   Designed for RMM deployment via SuperOps runtime variables.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variables for printer IP, driver, and display name
   2) Prinstall auto-detection via SNMP for model and driver matching

 REQUIRED INPUTS
   - $usbMode      : Set to $true for USB printers (driver-only, no port/queue)
   - $printerIp    : IP address of network printer (SuperOps: $YourPrinterIpHere)
                      Not required in USB mode
   - $driverName   : Specific driver name, or empty for auto-match (SuperOps: $YourDriverNameHere)
   - $printerName  : Display name for the printer, or empty for model name (SuperOps: $YourPrinterNameHere)
   - $prinstallDir : Directory where prinstall.exe is installed

 SETTINGS
   - Auto-selects best driver if $driverName is empty
   - Uses printer model as display name if $printerName is empty
   - USB mode skips port and queue creation, stages driver only
   - Verbose output enabled for RMM console visibility

 BEHAVIOR
   Network mode:
   1. Validates inputs and checks prinstall.exe exists
   2. Builds prinstall install command with specified options
   3. Runs full install (port + driver + queue)
   4. Reports installation result

   USB mode:
   1. Validates inputs (IP not required)
   2. Runs prinstall install with --usb flag (driver staging only)
   3. Reports installation result

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - prinstall.exe installed (run prinstall_setup.ps1 first)
   - Network access to printer IP (network mode only)
   - UDP 161 (SNMP) for auto-detection (network mode only)

 SECURITY NOTES
   - No secrets in logs
   - Printer IP and driver name visible in process args

 ENDPOINTS
   - Target printer via TCP/IP and SNMP (network mode only)
   - Not applicable (USB mode)

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
2026-03-25 v1.1.0 Add USB mode (--usb flag) for driver-only installs
2026-03-25 v1.0.0 Initial release - prinstall printer installation wrapper
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$usbMode      = $false                     # Set to $true for USB printers (driver-only, no port/queue)
$printerIp    = "$YourPrinterIpHere"       # Printer IP address (not required in USB mode)
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

if (-not $usbMode) {
    if ([string]::IsNullOrWhiteSpace($printerIp) -or $printerIp -eq '$' + 'YourPrinterIpHere') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- SuperOps runtime variable `$YourPrinterIpHere was not replaced."
    }
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

Write-Host "Mode            : $(if ($usbMode) { 'USB (driver-only)' } else { 'Network' })"
if (-not $usbMode) {
    Write-Host "Printer IP      : $printerIp"
}
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

if ($usbMode) {
    Write-Host "Staging driver for USB printer..."
} else {
    Write-Host "Installing printer at $printerIp..."
}
Write-Host ""

try {
    if ($usbMode) {
        # USB mode requires --driver and --model since there's no IP to probe
        $installArgs = @('install', '0.0.0.0', '--usb', '--verbose')
    } else {
        $installArgs = @('install', $printerIp, '--verbose')
    }

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
    if ($usbMode) {
        Write-Host "Mode            : USB (driver staged)"
    } else {
        Write-Host "IP              : $printerIp"
    }
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
    if (-not $usbMode) {
        Write-Host "IP              : $printerIp"
    }
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
