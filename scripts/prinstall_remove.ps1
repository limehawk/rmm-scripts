$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Remove Printer v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_remove.ps1
FILE    : prinstall_remove.ps1
DESCRIPTION : Removes a printer and its orphaned driver/port using prinstall 0.3.0+
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Removes a printer on Windows using prinstall 0.3.0+. Three-step cleanup
   with orphan detection:
   1. Removes the printer queue (Remove-Printer)
   2. Waits for the spooler to release references (settle sleep + retry loop)
   3. Removes the driver if no other printer uses it, INCLUDING the underlying
      oem<N>.inf package in the Windows driver store (via -RemoveFromDriverStore)
   4. Removes the TCP/IP port if no other printer uses it

   System drivers (Microsoft IPP Class Driver, Print to PDF, etc.) and non-IP
   ports (USB001, LPT1, COM1, WSD-*) are automatically skipped — prinstall
   only touches resources it would have created itself.

   Designed for RMM deployment via SuperOps runtime variables.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variable for printer target (IP or queue name)
   2) Prinstall resolves IP targets to queue names via the IP_<ip> port

 REQUIRED INPUTS
   - $printerTarget : IP address or printer queue name (SuperOps: $YourPrinterTargetHere)
                       Examples: "192.168.1.50" or "Brother MFC-L2750DW series"
   - $keepDriver    : Set to $true to skip driver cleanup (leave driver staged)
   - $keepPort      : Set to $true to skip port cleanup (leave port registered)
   - $prinstallDir  : Directory where prinstall.exe is installed

 SETTINGS
   - Idempotent — removing a non-existent printer returns success
   - Driver and port cleanup are non-fatal on their own — only queue removal
     failure is a fatal error
   - --keep-driver and --keep-port give surgical control when another printer
     on the same machine shares the driver or port

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. Runs `prinstall remove <target> --verbose` with any keep flags
   3. Reports removal result + which cleanup steps ran

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - prinstall.exe 0.3.0 or newer installed (run prinstall_setup.ps1 first)

 SECURITY NOTES
   - No secrets in logs
   - Printer target visible in process args

 ENDPOINTS
   - None (local operation only)

 EXIT CODES
   - 0 = Success - printer removed (or was already absent)
   - 1 = Failure - removal failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Target          : 192.168.1.50
   Keep Driver     : false
   Keep Port       : false
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.3.0
   Inputs validated successfully

   [RUN] REMOVE PRINTER
   ==============================================================
   Removing printer at 192.168.1.50...

   [remove] Looking up printer by port 'IP_192.168.1.50'
   [remove] Resolved target '192.168.1.50' -> 'Brother MFC-L2750DW series'
   [remove] Printer uses driver 'Brother Laser Type1 Class Driver' on port 'IP_192.168.1.50'
   [remove] Remove-Printer -Name 'Brother MFC-L2750DW series' -Confirm:$false
   [remove] Waiting 500ms for spooler to release references...
   [remove] Remove-PrinterDriver -Name 'Brother Laser Type1 Class Driver' -RemoveFromDriverStore -Confirm:$false
   [remove] Removed driver 'Brother Laser Type1 Class Driver' (including driver store package)
   [remove] Remove-PrinterPort -Name 'IP_192.168.1.50' -Confirm:$false
   [remove] Removed port 'IP_192.168.1.50'

   Removed printer: Brother MFC-L2750DW series
     - Port also removed (no other printers were using it)
     - Driver also removed from driver store

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Target          : 192.168.1.50

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 Initial release - prinstall remove wrapper for 0.3.0+
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$printerTarget = "$YourPrinterTargetHere"    # IP address or printer queue name
$keepDriver    = $false                      # Set to $true to skip driver cleanup
$keepPort      = $false                      # Set to $true to skip port cleanup
$prinstallDir  = "$env:ProgramData\prinstall"  # Where prinstall.exe is installed

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($printerTarget) -or $printerTarget -eq '$' + 'YourPrinterTargetHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourPrinterTargetHere was not replaced. Set it to the printer IP (e.g. '192.168.1.50') or the exact queue name (e.g. 'Brother MFC-L2750DW series')."
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

Write-Host "Target          : $printerTarget"
Write-Host "Keep Driver     : $keepDriver"
Write-Host "Keep Port       : $keepPort"
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
# REMOVE PRINTER
# ============================================================================
Write-Host ""
Write-Host "[RUN] REMOVE PRINTER"
Write-Host "=============================================================="
Write-Host "Removing printer at $printerTarget..."
Write-Host ""

try {
    $removeArgs = @('remove', $printerTarget, '--verbose')

    if ($keepDriver) {
        $removeArgs += '--keep-driver'
    }

    if ($keepPort) {
        $removeArgs += '--keep-port'
    }

    # See prinstall_scan.ps1 for why we swap EAP for the subprocess call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exePath @removeArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $removeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall remove failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($removeExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Target          : $printerTarget"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $removeExitCode"
    Write-Host "Target          : $printerTarget"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
