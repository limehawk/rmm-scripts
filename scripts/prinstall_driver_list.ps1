$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Driver List v0.4.15
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_driver_list.ps1
FILE    : prinstall_driver_list.ps1
DESCRIPTION : Lists drivers currently in the Windows driver store (prinstall 0.4.13+)
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Enumerates every driver in the Windows driver store via prinstall 0.4.13+.
   Pulls from Get-PrinterDriver with an INF-DriverVer fallback so the Date
   column populates even for drivers Windows doesn't return DriverDate for
   directly. Useful for RMM audits ("what's on every endpoint's driver
   store?") and for discovery before `prinstall driver remove` — passes the
   JSON shape through so downstream scripts can parse without scraping.

 DATA SOURCES & PRIORITY
   1) Get-PrinterDriver — name + DriverDate field when populated
   2) INF [Version] DriverVer line — fallback when DriverDate is null/1/1/1

 REQUIRED INPUTS
   - $prinstallDir : Directory where prinstall.exe is installed
   - $asJson       : Emit the raw JSON payload (RMM-friendly). Default
                     $false = pretty table.

 BEHAVIOR
   1. Validates prinstall.exe exists
   2. Runs `prinstall driver list` (with --json if $asJson = $true)
   3. Streams the output back through the RMM console

   No admin required — read-only.

 PREREQUISITES
   - Windows OS
   - prinstall.exe 0.4.13+ installed (run prinstall_setup.ps1 first)
   - NO admin privileges required

 SECURITY NOTES
   - No secrets in logs
   - Read-only against the driver store

 EXIT CODES
   - 0 = Success - drivers listed
   - 1 = Failure - prinstall missing or Get-PrinterDriver failed

 EXAMPLE RUN (table output)

   [INFO] INPUT VALIDATION
   ==============================================================
   Output          : Table
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.4.15
   Inputs validated successfully

   [RUN] LIST DRIVERS
   ==============================================================
   Name                                         Date
   ----                                         ----
   Microsoft IPP Class Driver                   2006-06-21
   HP Universal Printing PCL 6                  2025-08-20
   Brother Laser Type1 Class Driver             2009-04-22
   ...

   6 driver(s) in the store.

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success

CHANGELOG
--------------------------------------------------------------------------------
2026-04-15 v0.4.15 Initial release - wraps `prinstall driver list`. Requires
                   prinstall 0.4.13+.
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$asJson       = $false                     # $true = emit JSON payload instead of a table
$prinstallDir = "$env:ProgramData\prinstall"   # Where prinstall.exe is installed

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

Write-Host "Output          : $(if ($asJson) { 'JSON' } else { 'Table' })"
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
# LIST DRIVERS
# ============================================================================
Write-Host ""
Write-Host "[RUN] LIST DRIVERS"
Write-Host "=============================================================="

try {
    $listArgs = @('driver', 'list')
    if ($asJson) {
        $listArgs += '--json'
    }

    # See prinstall_scan.ps1 for why we swap EAP for the subprocess call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exePath @listArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $listExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall driver list failed"
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
