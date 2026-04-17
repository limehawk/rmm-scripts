$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Driver Remove v0.4.15
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_driver_remove.ps1
FILE    : prinstall_driver_remove.ps1
DESCRIPTION : Removes a driver from the Windows driver store (prinstall 0.4.13+)
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Removes a print driver from the Windows driver store using prinstall
   0.4.13+. Target can be the exact driver name (as shown in Get-PrinterDriver
   or `prinstall driver list`) or a fuzzy/model string that resolves to one
   staged driver. If the driver is currently bound to any printer queue, the
   command refuses with the blocking queue names; pass $force = $true to
   cascade — the dependent queues are removed first via the standard remove
   pipeline, then the driver. Windows system drivers (Microsoft IPP Class
   Driver, etc.) are protected and never removable.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variable for the target (name or fuzzy string)
   2) Get-PrinterDriver for the local driver store
   3) Get-Printer for dependency (queue) checks

 REQUIRED INPUTS
   - $driverTarget  : Exact driver name OR a fuzzy/model string
                        (SuperOps: $YourDriverTargetHere)
   - $force         : $true to cascade — remove dependent queues first
                        before the driver. Default $false = refuse with
                        queue list if the driver is in use.
   - $prinstallDir  : Directory where prinstall.exe is installed

 SETTINGS
   - Verbose output enabled for RMM console visibility
   - Uses -RemoveFromDriverStore first (removes the oem<N>.inf package too),
     falls back to plain Remove-PrinterDriver if that fails

 BEHAVIOR
   1. Validates inputs and checks prinstall.exe exists
   2. Resolves $driverTarget to an exact driver name in the local store
   3. Enumerates printer queues bound to the driver
   4. If bound and $force = $false: refuses with queue names, exits 1
   5. If bound and $force = $true: removes each dependent queue first
   6. Runs Remove-PrinterDriver -RemoveFromDriverStore -Confirm:$false
   7. Reports result

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - prinstall.exe 0.4.13+ installed (run prinstall_setup.ps1 first)

 SECURITY NOTES
   - No secrets in logs
   - Cascading removal via $force destroys dependent queues — use with care

 EXIT CODES
   - 0 = Success - driver removed
   - 1 = Failure - in use (without --force), not found, or removal failed

 EXAMPLE RUN (no dependencies)

   [INFO] INPUT VALIDATION
   ==============================================================
   Target          : HP Universal Printing PCL 6
   Force           : False
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.4.15
   Inputs validated successfully

   [RUN] REMOVE DRIVER
   ==============================================================
   ✓ Removed driver 'HP Universal Printing PCL 6' (including driver store package)

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Target          : HP Universal Printing PCL 6

CHANGELOG
--------------------------------------------------------------------------------
2026-04-15 v0.4.15 Initial release - wraps `prinstall driver remove <target>`
                   with optional cascade via $force. Requires prinstall 0.4.13+.
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$driverTarget = "$YourDriverTargetHere"    # Exact driver name OR fuzzy string
$force        = $false                     # $true to cascade-remove dependent queues first
$prinstallDir = "$env:ProgramData\prinstall"   # Where prinstall.exe is installed

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($driverTarget) -or $driverTarget -eq '$' + 'YourDriverTargetHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourDriverTargetHere was not replaced. Set it to the exact driver name from `prinstall driver list` (e.g. 'HP Universal Printing PCL 6') or a fuzzy/model string (e.g. 'hp 1320')."
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

Write-Host "Target          : $driverTarget"
Write-Host "Force           : $force"
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
# REMOVE DRIVER
# ============================================================================
Write-Host ""
Write-Host "[RUN] REMOVE DRIVER"
Write-Host "=============================================================="
Write-Host "Removing driver '$driverTarget'..."
Write-Host ""

try {
    $removeArgs = @('driver', 'remove', $driverTarget, '--verbose')

    if ($force) {
        $removeArgs += '--force'
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
    Write-Host "Prinstall driver remove failed"
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
    Write-Host "Target          : $driverTarget"
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
    Write-Host "Target          : $driverTarget"
    Write-Host ""
    if (-not $force) {
        Write-Host "Hint: if the driver is in use by a queue, set `$force = `$true to cascade."
    }
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
