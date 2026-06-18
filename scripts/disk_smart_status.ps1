$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT  : Disk S.M.A.R.T. Status v1.0.0
 AUTHOR  : Limehawk.io
 DATE    : June 2026
 FILE    : disk_smart_status.ps1
 DESCRIPTION : Reports S.M.A.R.T. predictive-failure health of all physical disks
 USAGE   : .\disk_smart_status.ps1
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE:
    Reports the S.M.A.R.T. / predictive-failure health of every physical disk
    on the machine so the RMM dashboard can flag failing drives. Combines
    PowerShell storage health, WMI predictive-failure status, and SMART
    reliability counters into a single per-machine verdict.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Enumerates physical disks via Get-PhysicalDisk and reports per-disk
       FriendlyName, MediaType, Size (GB), HealthStatus, OperationalStatus
    2. Queries WMI predictive-failure status via
       MSStorageDriver_FailurePredictStatus (PredictFailure boolean), handling
       the common case where the class is unavailable (VMs, some controllers)
       gracefully by reporting "Not available" rather than failing
    3. Pulls SMART reliability counters via Get-StorageReliabilityCounter
       (Wear, Temperature, ReadErrorsTotal, etc.) on a best-effort basis
    4. Aggregates to a final per-machine verdict: Healthy / Warning / Failing

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - PowerShell 5.1 or later
    - Administrator privileges
    - Storage subsystem that exposes SMART data (physical hardware)

SECURITY NOTES:
    - No secrets in logs
    - Read-only; makes no changes to disks or configuration
    - Requires elevated privileges to query storage subsystem

EXIT CODES:
    0 = All disks healthy, or SMART status could not be determined on a
        platform that does not expose it (e.g. a VM)
    1 = One or more disks report a predicted failure or unhealthy HealthStatus

EXAMPLE RUN:
    [INFO] PHYSICAL DISK INVENTORY
    ==============================================================
    Disk #0              : Samsung SSD 980 1TB
    Media Type           : SSD
    Size (GB)            : 931
    Health Status        : Healthy
    Operational Status   : OK

    [INFO] PREDICTIVE FAILURE STATUS
    ==============================================================
    PhysicalDrive0       : OK (no predicted failure)

    [INFO] RELIABILITY COUNTERS
    ==============================================================
    Disk #0 Wear         : 2
    Disk #0 Temperature  : 34
    Disk #0 ReadErrors   : 0

    [OK] FINAL STATUS
    ==============================================================
    Verdict              : Healthy
    SCRIPT SUCCEEDED

    [OK] SCRIPT COMPLETE
    ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-06-18 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title, [string]$prefix = "INFO")
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $prefix, $title)
    Write-Host ("=" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Section "ERROR OCCURRED" "ERROR"
    Write-Host " This script requires administrative privileges to run."
    Write-Section "SCRIPT HALTED" "ERROR"
    exit 1
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    $verdict = "Healthy"
    $issues = @()
    $smartDeterminable = $false

    # ------------------------------------------------------------------------
    # Physical disk inventory
    # ------------------------------------------------------------------------
    Write-Section "PHYSICAL DISK INVENTORY"

    $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)

    if ($physicalDisks.Count -eq 0) {
        PrintKV "Status" "No physical disks reported by Get-PhysicalDisk"
    }

    foreach ($disk in $physicalDisks) {
        $deviceId = if ($disk.PSObject.Properties.Name -contains 'DeviceId') { $disk.DeviceId } else { 'Unknown' }
        $friendly = if ($disk.PSObject.Properties.Name -contains 'FriendlyName') { $disk.FriendlyName } else { 'Unknown' }
        $mediaType = if ($disk.PSObject.Properties.Name -contains 'MediaType') { [string]$disk.MediaType } else { 'Unknown' }
        $sizeGb = if ($disk.PSObject.Properties.Name -contains 'Size' -and $disk.Size) { [math]::Round($disk.Size / 1GB) } else { 0 }
        $health = if ($disk.PSObject.Properties.Name -contains 'HealthStatus') { [string]$disk.HealthStatus } else { 'Unknown' }
        $opStatus = if ($disk.PSObject.Properties.Name -contains 'OperationalStatus') { ($disk.OperationalStatus -join ', ') } else { 'Unknown' }

        Write-Host ""
        PrintKV ("Disk #" + $deviceId) $friendly
        PrintKV "Media Type" $mediaType
        PrintKV "Size (GB)" $sizeGb
        PrintKV "Health Status" $health
        PrintKV "Operational Status" $opStatus

        if ($health -eq 'Healthy') {
            $smartDeterminable = $true
        } elseif ($health -eq 'Warning') {
            $smartDeterminable = $true
            if ($verdict -eq 'Healthy') { $verdict = 'Warning' }
            $issues += ("Disk #$deviceId ($friendly) HealthStatus = Warning")
        } elseif ($health -eq 'Unhealthy') {
            $smartDeterminable = $true
            $verdict = 'Failing'
            $issues += ("Disk #$deviceId ($friendly) HealthStatus = Unhealthy")
        }
    }

    # ------------------------------------------------------------------------
    # WMI predictive-failure status (best-effort; often missing on VMs)
    # ------------------------------------------------------------------------
    Write-Section "PREDICTIVE FAILURE STATUS"

    $failPredict = $null
    try {
        $failPredict = @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSStorageDriver_FailurePredictStatus' -ErrorAction Stop)
    } catch {
        $failPredict = $null
    }

    if (-not $failPredict -or $failPredict.Count -eq 0) {
        PrintKV "Status" "Not available (no SMART predictive data exposed)"
    } else {
        $smartDeterminable = $true
        foreach ($fp in $failPredict) {
            $instance = if ($fp.PSObject.Properties.Name -contains 'InstanceName') { $fp.InstanceName } else { 'Unknown' }
            $predict = if ($fp.PSObject.Properties.Name -contains 'PredictFailure') { [bool]$fp.PredictFailure } else { $false }

            if ($predict) {
                PrintKV $instance "PREDICTED FAILURE"
                $verdict = 'Failing'
                $issues += ("Predicted failure on $instance")
            } else {
                PrintKV $instance "OK (no predicted failure)"
            }
        }
    }

    # ------------------------------------------------------------------------
    # SMART reliability counters (best-effort)
    # ------------------------------------------------------------------------
    Write-Section "RELIABILITY COUNTERS"

    $anyCounters = $false
    foreach ($disk in $physicalDisks) {
        $deviceId = if ($disk.PSObject.Properties.Name -contains 'DeviceId') { $disk.DeviceId } else { 'Unknown' }
        $rc = $null
        try {
            $rc = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
        } catch {
            $rc = $null
        }

        if ($rc) {
            $anyCounters = $true
            $wear = if ($rc.PSObject.Properties.Name -contains 'Wear' -and $null -ne $rc.Wear) { $rc.Wear } else { 'N/A' }
            $temp = if ($rc.PSObject.Properties.Name -contains 'Temperature' -and $null -ne $rc.Temperature) { $rc.Temperature } else { 'N/A' }
            $readErr = if ($rc.PSObject.Properties.Name -contains 'ReadErrorsTotal' -and $null -ne $rc.ReadErrorsTotal) { $rc.ReadErrorsTotal } else { 'N/A' }

            PrintKV ("Disk #$deviceId Wear") $wear
            PrintKV ("Disk #$deviceId Temperature") $temp
            PrintKV ("Disk #$deviceId ReadErrors") $readErr
        }
    }

    if (-not $anyCounters) {
        PrintKV "Status" "Not available (reliability counters not exposed)"
    }

    # ------------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------------
    Write-Section "FINAL STATUS"

    if (-not $smartDeterminable) {
        PrintKV "Verdict" "Undeterminable (no SMART data on this platform)"
        PrintKV "Note" "Treated as non-failing (likely a VM or unsupported controller)"
        Write-Host "[OK] SCRIPT SUCCEEDED"
        Write-Section "SCRIPT COMPLETE"
        exit 0
    }

    PrintKV "Verdict" $verdict

    if ($verdict -eq 'Failing') {
        PrintKV "Issues Found" ($issues -join "; ")
        Write-Host "[ERROR] SCRIPT COMPLETED WITH ERRORS"
        Write-Section "SCRIPT COMPLETE"
        exit 1
    } elseif ($verdict -eq 'Warning') {
        PrintKV "Issues Found" ($issues -join "; ")
        Write-Host "[WARN] SCRIPT COMPLETED WITH WARNINGS"
        Write-Section "SCRIPT COMPLETE"
        exit 0
    } else {
        Write-Host "[OK] SCRIPT SUCCEEDED"
        Write-Section "SCRIPT COMPLETE"
        exit 0
    }
}
catch {
    Write-Section "ERROR OCCURRED" "ERROR"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Section "SCRIPT HALTED" "ERROR"
    exit 1
}
