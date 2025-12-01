$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Remove All Printers                                            v1.0.0
FILE   : printers_remove_all.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Removes ALL installed printers, their associated ports, and unused printer
    drivers from Windows. Use with caution - this is a destructive operation
    that cannot be undone.

REQUIRED INPUTS:
    $removeDrivers : Whether to also remove unused printer drivers (default: true)
    $removePorts   : Whether to also remove orphaned printer ports (default: true)

BEHAVIOR:
    1. Enumerates all installed printers
    2. Removes each printer
    3. Removes orphaned TCP/IP printer ports (optional)
    4. Removes unused printer drivers (optional)
    5. Reports results

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - Print Spooler service running

SECURITY NOTES:
    - No secrets in logs
    - Destructive operation - removes ALL printers
    - Cannot be undone without reinstalling printers

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Remove Drivers : True
    Remove Ports   : True

    [ REMOVING PRINTERS ]
    --------------------------------------------------------------
    Found 3 printer(s)
    Removing : HP LaserJet Pro MFP M428fdw
    Removing : Microsoft Print to PDF
    Removing : Canon LBP6030
    Removed 3 printer(s)

    [ REMOVING PRINTER PORTS ]
    --------------------------------------------------------------
    Found 2 orphaned port(s)
    Removing : IP_192.168.1.100
    Removing : IP_192.168.1.101
    Removed 2 port(s)

    [ REMOVING UNUSED DRIVERS ]
    --------------------------------------------------------------
    Removed unused printer drivers

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : All printers removed successfully

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - converted from batch script
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$removeDrivers = $true
$removePorts = $true

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Remove Drivers : $removeDrivers"
Write-Host "Remove Ports   : $removePorts"

Write-Host ""
Write-Host "WARNING: This script will remove ALL installed printers!"
Write-Host "This operation cannot be undone."

# ============================================================================
# REMOVE PRINTERS
# ============================================================================
Write-Host ""
Write-Host "[ REMOVING PRINTERS ]"
Write-Host "--------------------------------------------------------------"

try {
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $printerCount = @($printers).Count

    if ($printerCount -eq 0) {
        Write-Host "No printers found"
    }
    else {
        Write-Host "Found $printerCount printer(s)"
        $removedCount = 0
        $failedCount = 0

        foreach ($printer in $printers) {
            try {
                Write-Host "Removing : $($printer.Name)"
                Remove-Printer -Name $printer.Name -ErrorAction Stop
                $removedCount++
            }
            catch {
                Write-Host "  Failed : $($_.Exception.Message)"
                $failedCount++
            }
        }

        Write-Host "Removed $removedCount printer(s)"
        if ($failedCount -gt 0) {
            Write-Host "Failed to remove $failedCount printer(s)"
        }
    }
}
catch {
    Write-Host "Error enumerating printers: $($_.Exception.Message)"
}

# ============================================================================
# REMOVE PRINTER PORTS
# ============================================================================
if ($removePorts) {
    Write-Host ""
    Write-Host "[ REMOVING PRINTER PORTS ]"
    Write-Host "--------------------------------------------------------------"

    try {
        # Get all printer ports
        $allPorts = Get-PrinterPort -ErrorAction SilentlyContinue

        # Get ports currently in use by printers
        $usedPorts = @()
        $remainingPrinters = Get-Printer -ErrorAction SilentlyContinue
        foreach ($p in $remainingPrinters) {
            if ($p.PortName) {
                $usedPorts += $p.PortName
            }
        }

        # Find orphaned ports (TCP/IP ports not in use)
        $orphanedPorts = $allPorts | Where-Object {
            $_.Name -notin $usedPorts -and
            ($_.Name -like "IP_*" -or $_.Name -like "TCPIP*" -or $_.Name -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}')
        }

        $orphanCount = @($orphanedPorts).Count

        if ($orphanCount -eq 0) {
            Write-Host "No orphaned ports found"
        }
        else {
            Write-Host "Found $orphanCount orphaned port(s)"
            $removedPorts = 0

            foreach ($port in $orphanedPorts) {
                try {
                    Write-Host "Removing : $($port.Name)"
                    Remove-PrinterPort -Name $port.Name -ErrorAction Stop
                    $removedPorts++
                }
                catch {
                    Write-Host "  Failed : $($_.Exception.Message)"
                }
            }

            Write-Host "Removed $removedPorts port(s)"
        }
    }
    catch {
        Write-Host "Error removing ports: $($_.Exception.Message)"
    }
}

# ============================================================================
# REMOVE UNUSED DRIVERS
# ============================================================================
if ($removeDrivers) {
    Write-Host ""
    Write-Host "[ REMOVING UNUSED DRIVERS ]"
    Write-Host "--------------------------------------------------------------"

    try {
        # Get all printer drivers
        $allDrivers = Get-PrinterDriver -ErrorAction SilentlyContinue

        # Get drivers currently in use
        $usedDrivers = @()
        $remainingPrinters = Get-Printer -ErrorAction SilentlyContinue
        foreach ($p in $remainingPrinters) {
            if ($p.DriverName) {
                $usedDrivers += $p.DriverName
            }
        }

        # Find unused drivers
        $unusedDrivers = $allDrivers | Where-Object { $_.Name -notin $usedDrivers }
        $unusedCount = @($unusedDrivers).Count

        if ($unusedCount -eq 0) {
            Write-Host "No unused drivers found"
        }
        else {
            Write-Host "Found $unusedCount unused driver(s)"
            $removedDrivers = 0

            foreach ($driver in $unusedDrivers) {
                try {
                    Write-Host "Removing : $($driver.Name)"
                    Remove-PrinterDriver -Name $driver.Name -ErrorAction Stop
                    $removedDrivers++
                }
                catch {
                    # Some drivers may be in use by the system
                    Write-Host "  Skipped: $($_.Exception.Message)"
                }
            }

            Write-Host "Removed $removedDrivers driver(s)"
        }
    }
    catch {
        Write-Host "Error removing drivers: $($_.Exception.Message)"
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

$finalPrinters = Get-Printer -ErrorAction SilentlyContinue
$finalCount = @($finalPrinters).Count

if ($finalCount -eq 0) {
    Write-Host "Result : All printers removed successfully"
}
else {
    Write-Host "Result : $finalCount printer(s) remaining"
    Write-Host "Some printers could not be removed (may be system printers)"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
