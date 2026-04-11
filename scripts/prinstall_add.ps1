$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Install Printer v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_add.ps1
FILE    : prinstall_add.ps1
DESCRIPTION : Installs a network or USB printer using prinstall 0.3.0+
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs a printer on Windows using prinstall 0.3.0+. For network printers,
   walks the full four-tier driver resolution pipeline (local store →
   manufacturer download → Microsoft Update Catalog HWID match → IPP Class
   Driver fallback) and falls through to the right tier automatically.
   For USB printers, swaps the driver on an existing PnP-created queue via
   Set-Printer. Designed for RMM deployment via SuperOps runtime variables.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variables for printer IP/queue, driver, and display name
   2) Prinstall auto-detection via SNMP + IPP for model + device ID
   3) Microsoft Update Catalog HWID lookup via the printer's IPP CID field

 REQUIRED INPUTS
   - $usbMode       : Set to $true for USB printers (swaps driver on existing queue)
   - $printerIp     : IP address of network printer (SuperOps: $YourPrinterIpHere)
                       Not required in USB mode
   - $usbQueueName  : Existing USB printer queue name (SuperOps: $YourUsbQueueNameHere)
                       Only used in USB mode — the queue Windows PnP auto-created
                       when the printer was plugged in (e.g. "Brother MFC-L2750DW")
   - $driverName    : Specific driver name, or empty for auto-match (SuperOps: $YourDriverNameHere)
   - $printerName   : Display name for the printer, or empty for model name (SuperOps: $YourPrinterNameHere)
   - $prinstallDir  : Directory where prinstall.exe is installed

 SETTINGS
   - Auto-selects best driver if $driverName is empty
   - Uses printer model as display name if $printerName is empty
   - Catalog resolver runs automatically when primary install fails and the
     printer advertises an IPP device ID with a CID field
   - Verbose output enabled for RMM console visibility

 BEHAVIOR
   Network mode:
   1. Validates inputs and checks prinstall.exe exists
   2. Builds `prinstall add <ip> --verbose` command with specified options
   3. Runs through driver resolution tiers 1-4 as needed
   4. Reports installation result

   USB mode:
   1. Validates inputs (queue name required, IP not needed)
   2. Runs `prinstall add <queue-name> --usb --verbose`
   3. Prinstall verifies the queue exists, matches a driver, stages if needed,
      and swaps the driver via Set-Printer
   4. Reports installation result

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

 EXAMPLE RUN (catalog resolver path)

   [INFO] INPUT VALIDATION
   ==============================================================
   Mode            : Network
   Printer IP      : 192.168.1.50
   Driver          : (auto-detect)
   Printer Name    : (auto-detect)
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.3.0
   Inputs validated successfully

   [RUN] INSTALL PRINTER
   ==============================================================
   Installing printer at 192.168.1.50...

   [scan] 192.168.1.50: SNMP -> model "Brother MFC-L2750DW series"
   [add] IPP device ID: MFG:Brother;MDL:MFC-L2750DW series;CID:Brother Laser Type1;...
   [add] Auto-selected driver: Brother Universal Printer
   [add] Primary install failed. Trying catalog resolver with device ID...
   [resolver] Searching catalog by CID: 'Brother Laser Type1'
   [resolver] Catalog returned 5 result(s), scanning top 5
   [resolver] * MATCH: prnbrcl1.inf -> Brother Laser Type1 Class Driver
   [add] Catalog resolver matched -- staging INF and retrying install.

   Printer installed successfully!
     Name:   Brother MFC-L2750DW series
     Driver: Brother Laser Type1 Class Driver
     Port:   IP_192.168.1.50

     WARNING: Installed via Microsoft Update Catalog.
              Matched HWID: 1284_CID_BROTHER_LASER_TYPE1.

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Printer         : Brother MFC-L2750DW series
   IP              : 192.168.1.50

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 BREAKING: realign version scheme with prinstall app version
                  (was v1.1.0). Rename 'install' subcommand to 'add' to match
                  prinstall 0.3.0 CLI. USB mode now requires a real queue name
                  via $YourUsbQueueNameHere (previously used '0.0.0.0'
                  placeholder which was never functional). Example output
                  refreshed to show the catalog resolver flow.
2026-03-25 v1.1.0 Add USB mode (--usb flag) for driver-only installs
2026-03-25 v1.0.0 Initial release - prinstall printer installation wrapper
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$usbMode      = $false                     # Set to $true for USB printers (swaps driver on existing queue)
$printerIp    = "$YourPrinterIpHere"       # Printer IP address (network mode only)
$usbQueueName = "$YourUsbQueueNameHere"    # Existing USB queue name (USB mode only, e.g. "Brother MFC-L2750DW")
$driverName   = "$YourDriverNameHere"      # Specific driver name, or leave as placeholder for auto-match
$printerName  = "$YourPrinterNameHere"     # Display name, or leave as placeholder for model name
$prinstallDir = "$env:ProgramData\prinstall"   # Where prinstall.exe is installed (not the data dir)

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ($usbMode) {
    if ([string]::IsNullOrWhiteSpace($usbQueueName) -or $usbQueueName -eq '$' + 'YourUsbQueueNameHere') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- SuperOps runtime variable `$YourUsbQueueNameHere was not replaced. USB mode needs the name of the existing printer queue Windows created when the printer was plugged in (e.g. 'Brother MFC-L2750DW'). Check Settings -> Bluetooth & devices -> Printers & scanners for the exact queue name."
    }
} else {
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

Write-Host "Mode            : $(if ($usbMode) { 'USB (driver swap)' } else { 'Network' })"
if ($usbMode) {
    Write-Host "USB Queue       : $usbQueueName"
} else {
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
    Write-Host "Swapping driver on USB queue '$usbQueueName'..."
} else {
    Write-Host "Installing printer at $printerIp..."
}
Write-Host ""

try {
    if ($usbMode) {
        # USB mode: target is the existing queue name Windows auto-created
        # on plug-in. prinstall verifies the queue exists, matches a driver,
        # stages it, and swaps via Set-Printer. No port/IP needed.
        $installArgs = @('add', $usbQueueName, '--usb', '--verbose')
    } else {
        # Network mode: target is the IP. The four-tier driver resolver
        # (local store -> manufacturer download -> Microsoft Update Catalog
        # HWID match -> IPP Class Driver fallback) runs automatically.
        $installArgs = @('add', $printerIp, '--verbose')
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
    Write-Host "Prinstall add failed"
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
        Write-Host "USB Queue       : $usbQueueName"
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
    if ($usbMode) {
        Write-Host "USB Queue       : $usbQueueName"
    } else {
        Write-Host "IP              : $printerIp"
    }
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
