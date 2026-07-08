$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows DISM SFC Chkdsk Maintenance                          v2.0.2
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windows_dism_sfc_chkdsk_run.ps1
================================================================================
 FILE     : windows_dism_sfc_chkdsk_run.ps1
DESCRIPTION : Runs DISM, SFC, and chkdsk for Windows system file repair
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Runs standard Windows health checks and repair commands including DISM image
 health scans, disk checks, system file verification, and component cleanup.
 Designed for unattended execution in RMM environments to perform routine
 system maintenance and repair operations.

 DATA SOURCES & PRIORITY
 1) Hardcoded values (defined within the script body)
 2) System commands (DISM, chkdsk, sfc)
 3) Error

 REQUIRED INPUTS
 - RunDismScan       : $true
   (Whether to run DISM ScanHealth to check for image corruption.)
 - RunDismRestore    : $true
   (Whether to run DISM RestoreHealth - only runs if ScanHealth finds corruption.)
 - RunChkdsk         : $false
   (Whether to run chkdsk on local drives. Requires reboot to complete.)
 - RunSfc            : $true
   (Whether to run System File Checker to verify and repair system files.)
 - ChkdskParameters  : '/scan'
   (Parameters for chkdsk. Use '/scan' for quick scan or '/f /r' for full check.)
 - RebootAfterMaintenance : $false
   (Whether to reboot the system after maintenance with a 5-minute warning.)

 SETTINGS
 - All maintenance operations are optional via hardcoded input flags.
 - DISM operations use online mode against the running Windows installation.
 - chkdsk runs against all fixed local drives (DriveType = 3).
 - Commands run synchronously with full output captured for logging.

 BEHAVIOR
 - Script runs each enabled maintenance operation in sequence.
 - DISM RestoreHealth only runs if ScanHealth detects corruption (saves time on healthy systems).
 - Each operation's success or failure is tracked individually.
 - chkdsk requires admin rights and may schedule operations on next reboot.
 - Failed operations are reported but script continues to next operation.

 PREREQUISITES
 - PowerShell 5.1 or later.
 - Administrator privileges required.
 - Windows 8.1/Server 2012 R2 or later for DISM commands.
 - Sufficient disk space for repair operations.

 SECURITY NOTES
 - No secrets are printed to the console.
 - Requires elevated permissions to modify system components.
 - Operations may cause system modifications and require reboots.

 ENDPOINTS
 - N/A (local system commands only)

 EXIT CODES
 - 0 success (all enabled operations completed)
 - 1 failure (one or more operations failed)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 RunDismScan      : True
 RunDismRestore   : True
 RunChkdsk        : False
 RunSfc           : True
 ChkdskParameters : /scan

 [RUN] DISM SCAN HEALTH
 ==============================================================
 Starting DISM image scan...
 No component store corruption detected.
 Result : Success (no corruption)

 [INFO] DISM RESTORE HEALTH
 ==============================================================
 Skipped - no corruption detected by ScanHealth

 [RUN] SYSTEM FILE CHECK
 ==============================================================
 Starting system file verification...
 Windows Resource Protection did not find any integrity violations.
 Result : Success (no integrity violations)

 [OK] FINAL STATUS
 ==============================================================
 Operations Run    : 2
 Operations Passed : 2
 Operations Failed : 0
 Overall Result    : Success

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-08 v2.0.2 Raised sidecar execution timeout to 120 min for long DISM/SFC/chkdsk runs
 2026-01-19 v2.0.1 Updated to two-line ASCII console output style
 2025-12-28 v2.0.0 Smart logic: RestoreHealth only runs if ScanHealth finds corruption; removed ComponentCleanup
 2025-12-28 v1.2.0 Use exit codes instead of string parsing for DISM/SFC result detection
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-10-31 v1.0.3 Added full command output display for all operations (DISM and SFC)
 2025-10-31 v1.0.2 Fixed DISM component cleanup access denied errors
 2025-10-31 v1.0.1 Added optional reboot functionality with 5-minute warning
 2025-10-31 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""
$operationsRun = 0
$operationsPassed = 0
$operationsFailed = 0
$corruptionDetected = $false

# ==== HARDCODED INPUTS (MANDATORY) ====
# --- Operation Run Flags ---
$RunDismScan      = $true  # Whether to run DISM ScanHealth to check for image corruption.
$RunDismRestore   = $true  # Whether to run DISM RestoreHealth to repair image corruption (only if ScanHealth finds issues).
$RunChkdsk        = $false # Whether to run chkdsk on local drives. Requires reboot to complete.
$RunSfc           = $true  # Whether to run System File Checker to verify and repair system files.

# --- Operation Parameters ---
$ChkdskParameters = '/scan'  # Parameters for chkdsk. Use '/scan' for quick scan or '/f /r' for full check.

# --- Post-Operation Actions ---
$RebootAfterMaintenance = $false # Set to $true to reboot the system after maintenance with a 5-minute warning.

# ==== VALIDATION ====
if ($RunDismScan -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RunDismScan must be a boolean value."
}
if ($RunDismRestore -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RunDismRestore must be a boolean value."
}
if ($RunChkdsk -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RunChkdsk must be a boolean value."
}
if ($RunSfc -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RunSfc must be a boolean value."
}
if ([string]::IsNullOrWhiteSpace($ChkdskParameters)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- ChkdskParameters cannot be empty."
}
if ($RebootAfterMaintenance -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- RebootAfterMaintenance must be a boolean value."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText

    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script cannot proceed due to invalid hardcoded inputs."

    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== RUNTIME OUTPUT (Style A) ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "RunDismScan      : $RunDismScan"
Write-Host "RunDismRestore   : $RunDismRestore"
Write-Host "RunChkdsk        : $RunChkdsk"
Write-Host "RunSfc           : $RunSfc"
Write-Host "ChkdskParameters : $ChkdskParameters"

# ==== DISM SCAN HEALTH ====
if ($RunDismScan) {
    Write-Host ""
    Write-Host "[RUN] DISM SCAN HEALTH"
    Write-Host "=============================================================="

    $operationsRun++
    $opSuccess = $false

    try {
        Write-Host "Starting DISM image scan..."
        Write-Host ""
        $dismScanResult = & DISM.exe /Online /Cleanup-Image /ScanHealth 2>&1
        $dismScanExitCode = $LASTEXITCODE
        $dismScanOutput = $dismScanResult -join "`n"

        # Display the actual output
        Write-Host $dismScanOutput
        Write-Host ""

        # Check exit code as primary indicator (DISM: 0 = success)
        if ($dismScanExitCode -eq 0) {
            # Check if corruption was detected (scan succeeded but found issues)
            if ($dismScanOutput -match "component store is repairable|corruption.*detected") {
                Write-Host "Result : Corruption detected - repair needed"
                $corruptionDetected = $true
            } else {
                Write-Host "Result : Success (no corruption)"
            }
            $operationsPassed++
            $opSuccess = $true
        }
        elseif ($dismScanOutput -match "Error: 5|Access is denied") {
            Write-Host "Result : Failed - Access Denied"
            $operationsFailed++
        }
        else {
            Write-Host "Result : Failed (exit code: $dismScanExitCode)"
            $operationsFailed++
        }

    } catch {
        Write-Host "Exception occurred during DISM scan"
        Write-Host "Error : $($_.Exception.Message)"
        Write-Host "Result : Failed"
        $operationsFailed++
    }
}

# ==== DISM RESTORE HEALTH ====
# Only runs if ScanHealth detected corruption (or if ScanHealth was skipped)
$shouldRunRestore = $RunDismRestore -and ($corruptionDetected -or -not $RunDismScan)

if ($shouldRunRestore) {
    Write-Host ""
    Write-Host "[RUN] DISM RESTORE HEALTH"
    Write-Host "=============================================================="

    $operationsRun++
    $opSuccess = $false

    try {
        Write-Host "Starting DISM image repair..."
        Write-Host ""
        $dismRestoreResult = & DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1
        $dismRestoreExitCode = $LASTEXITCODE
        $dismRestoreOutput = $dismRestoreResult -join "`n"

        # Display the actual output
        Write-Host $dismRestoreOutput
        Write-Host ""

        # Check exit code as primary indicator (DISM: 0 = success)
        if ($dismRestoreExitCode -eq 0) {
            Write-Host "Result : Success"
            $operationsPassed++
            $opSuccess = $true
        }
        elseif ($dismRestoreOutput -match "Error: 5|Access is denied") {
            Write-Host "Result : Failed - Access Denied"
            $operationsFailed++
        }
        else {
            Write-Host "Result : Failed (exit code: $dismRestoreExitCode)"
            $operationsFailed++
        }

    } catch {
        Write-Host "Exception occurred during DISM restore"
        Write-Host "Error : $($_.Exception.Message)"
        Write-Host "Result : Failed"
        $operationsFailed++
    }
}
elseif ($RunDismRestore -and -not $corruptionDetected) {
    Write-Host ""
    Write-Host "[INFO] DISM RESTORE HEALTH"
    Write-Host "=============================================================="
    Write-Host "Skipped - no corruption detected by ScanHealth"
}

# ==== DISK CHECK ====
if ($RunChkdsk) {
    Write-Host ""
    Write-Host "[RUN] DISK CHECK"
    Write-Host "=============================================================="

    try {
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop

        if ($drives) {
            foreach ($drive in $drives) {
                $driveLetter = $drive.DeviceID
                $operationsRun++

                try {
                    Write-Host "Checking drive $driveLetter with parameters: $ChkdskParameters"

                    # Note: chkdsk may schedule operation for next reboot on system drive
                    $chkdskCmd = "chkdsk.exe $driveLetter $ChkdskParameters"
                    $chkdskResult = & cmd.exe /c "echo y | chkdsk $driveLetter $ChkdskParameters" 2>&1

                    if ($LASTEXITCODE -eq 0 -or $chkdskResult -match "scheduled|will check") {
                        Write-Host "Drive $driveLetter check completed or scheduled"
                        Write-Host "Result : Success"
                        $operationsPassed++
                    } else {
                        Write-Host "Drive $driveLetter check encountered issues"
                        Write-Host "Result : Check output above"
                        $operationsFailed++
                    }

                } catch {
                    Write-Host "Error checking drive $driveLetter"
                    Write-Host "Error : $($_.Exception.Message)"
                    Write-Host "Result : Failed"
                    $operationsFailed++
                }
            }
        } else {
            Write-Host "No fixed drives found to check"
        }

    } catch {
        Write-Host "Failed to enumerate drives"
        Write-Host "Error : $($_.Exception.Message)"
    }
}

# ==== SYSTEM FILE CHECK ====
if ($RunSfc) {
    Write-Host ""
    Write-Host "[RUN] SYSTEM FILE CHECK"
    Write-Host "=============================================================="

    $operationsRun++
    $opSuccess = $false

    try {
        Write-Host "Starting system file verification..."
        Write-Host ""
        $sfcResult = & sfc.exe /scannow 2>&1
        $sfcExitCode = $LASTEXITCODE
        $sfcOutput = $sfcResult -join "`n"

        # Display the actual output
        Write-Host $sfcOutput
        Write-Host ""

        # Check exit code as primary indicator (more reliable than string parsing)
        # SFC exit codes: 0 = no issues, 1 = repaired, 2 = couldn't repair some
        if ($sfcExitCode -eq 0) {
            Write-Host "Result : Success (no integrity violations)"
            $operationsPassed++
            $opSuccess = $true
        }
        elseif ($sfcExitCode -eq 1) {
            Write-Host "Result : Success (corrupt files were repaired)"
            $operationsPassed++
            $opSuccess = $true
        }
        elseif ($sfcExitCode -eq 2) {
            Write-Host "Result : Manual intervention required (some files could not be repaired)"
            $operationsFailed++
        }
        else {
            Write-Host "Result : Failed (exit code: $sfcExitCode)"
            $operationsFailed++
        }

    } catch {
        Write-Host "Exception occurred during system file check"
        Write-Host "Error : $($_.Exception.Message)"
        Write-Host "Result : Failed"
        $operationsFailed++
    }
}

# ==== FINAL STATUS ====
if ($operationsFailed -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Operations Run    : $operationsRun"
    Write-Host "Operations Passed : $operationsPassed"
    Write-Host "Operations Failed : $operationsFailed"
    Write-Host "Overall Result    : Success"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
} else {
    Write-Host ""
    Write-Host "[WARN] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Operations Run    : $operationsRun"
    Write-Host "Operations Passed : $operationsPassed"
    Write-Host "Operations Failed : $operationsFailed"
    Write-Host "Overall Result    : Some operations failed"
    Write-Host ""
    Write-Host "[WARN] SCRIPT COMPLETED"
    Write-Host "=============================================================="
}

if ($operationsFailed -gt 0) {
    exit 1
} else {
    # Schedule reboot if enabled
    if ($RebootAfterMaintenance) {
        Write-Host ""
        Write-Host "[RUN] REBOOT SCHEDULE"
        Write-Host "=============================================================="
        Write-Host "Scheduling system reboot in 5 minutes..."
        Write-Host "Please save any open work."
        & shutdown.exe /r /t 300 /c "Windows system maintenance is complete. Your computer will reboot in 5 minutes. Please save your work."
        Write-Host "Reboot command issued."
        exit 0 # Exit immediately after scheduling reboot
    } else {
        exit 0
    }
}
