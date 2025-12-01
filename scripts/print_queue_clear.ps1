$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Print Queue Clear                                              v1.1.0
FILE   : print_queue_clear.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Resets and clears the Windows print queue by stopping the Print Spooler
    service, removing all queued print jobs from the spooler directory, and
    restarting the service. Resolves common printing issues caused by stuck
    or corrupted print jobs.

REQUIRED INPUTS:
    $serviceName  : Name of the Print Spooler service (default: "Spooler")
    $stopTimeout  : Maximum seconds to wait for service to stop (default: 30)
    $startTimeout : Maximum seconds to wait for service to start (default: 30)

BEHAVIOR:
    1. Validates hardcoded input values
    2. Checks current status of Print Spooler service
    3. Stops the Print Spooler service and waits for handles to release
    4. Removes print job files with retry logic (3 attempts per file)
    5. Reports successfully removed and locked files separately
    6. Restarts the Print Spooler service
    7. Verifies service is running and reports final status

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - Print Spooler service must exist

SECURITY NOTES:
    - No secrets in logs
    - Requires elevated privileges
    - Only deletes files from Windows spooler directory

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ SERVICE STATUS CHECK ]
    --------------------------------------------------------------
    Service : Spooler
    Status  : Running

    [ STOPPING PRINT SPOOLER ]
    --------------------------------------------------------------
    Stopping service Spooler
    Service stopped successfully

    [ CLEARING PRINT QUEUE ]
    --------------------------------------------------------------
    Spooler Directory : C:\Windows\System32\spool\PRINTERS
    Total Files Found : 5
    Files Removed     : 5
    Queue cleared successfully

    [ STARTING PRINT SPOOLER ]
    --------------------------------------------------------------
    Service started successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : Print queue cleared and service restarted successfully

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.1.0  Migrated from SuperOps - added retry logic for locked files
2025-01-17 v1.0.0  Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$serviceName  = 'Spooler'
$stopTimeout  = 30
$startTimeout = 30

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($serviceName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Service name is required"
}

if ($stopTimeout -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Stop timeout must be at least 1 second"
}

if ($startTimeout -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Start timeout must be at least 1 second"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    exit 1
}

Write-Host "Service Name  : $serviceName"
Write-Host "Stop Timeout  : $stopTimeout seconds"
Write-Host "Start Timeout : $startTimeout seconds"

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    # Check service status
    Write-Host ""
    Write-Host "[ SERVICE STATUS CHECK ]"
    Write-Host "--------------------------------------------------------------"

    $service = Get-Service -Name $serviceName
    Write-Host "Service : $($service.Name)"
    Write-Host "Status  : $($service.Status)"

    # Stop the Print Spooler service
    Write-Host ""
    Write-Host "[ STOPPING PRINT SPOOLER ]"
    Write-Host "--------------------------------------------------------------"

    if ($service.Status -eq 'Running') {
        Write-Host "Stopping service $serviceName..."
        Stop-Service -Name $serviceName -Force

        $waitCount = 0
        while ((Get-Service -Name $serviceName).Status -ne 'Stopped' -and $waitCount -lt $stopTimeout) {
            Start-Sleep -Seconds 1
            $waitCount++
        }

        $service = Get-Service -Name $serviceName
        if ($service.Status -ne 'Stopped') {
            throw "Service failed to stop within $stopTimeout seconds"
        }

        Write-Host "Service stopped successfully"
        Write-Host "Waiting for file handles to release..."
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "Service is already stopped"
        Start-Sleep -Seconds 2
    }

    # Clear the print queue
    Write-Host ""
    Write-Host "[ CLEARING PRINT QUEUE ]"
    Write-Host "--------------------------------------------------------------"

    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
    Write-Host "Spooler Directory : $spoolPath"

    $files = Get-ChildItem -Path $spoolPath -File -ErrorAction SilentlyContinue
    $totalFiles = @($files).Count
    $removedCount = 0
    $failedCount = 0
    $failedFilesList = ""

    if ($totalFiles -gt 0) {
        Write-Host "Total Files Found : $totalFiles"
        Write-Host "Removing files..."

        foreach ($file in $files) {
            $removed = $false
            $retryCount = 0
            $maxRetries = 3

            while (-not $removed -and $retryCount -lt $maxRetries) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $removed = $true
                    $removedCount++
                }
                catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Milliseconds 500
                    }
                }
            }

            if (-not $removed) {
                $failedCount++
                if ($failedFilesList.Length -gt 0) { $failedFilesList += "`n" }
                $failedFilesList += "  - $($file.Name)"
            }
        }

        Write-Host "Files Removed     : $removedCount"
        if ($failedCount -gt 0) {
            Write-Host "Files Failed      : $failedCount"
            Write-Host "Locked files:"
            Write-Host $failedFilesList
            Write-Host "Note: Locked files will be removed when service restarts"
        }

        if ($removedCount -gt 0) {
            Write-Host "Queue cleared successfully"
        }
    }
    else {
        Write-Host "Files Found       : 0"
        Write-Host "No print jobs to clear"
    }

    # Start the Print Spooler service
    Write-Host ""
    Write-Host "[ STARTING PRINT SPOOLER ]"
    Write-Host "--------------------------------------------------------------"

    Write-Host "Starting service $serviceName..."
    Start-Service -Name $serviceName

    $waitCount = 0
    while ((Get-Service -Name $serviceName).Status -ne 'Running' -and $waitCount -lt $startTimeout) {
        Start-Sleep -Seconds 1
        $waitCount++
    }

    $service = Get-Service -Name $serviceName
    if ($service.Status -ne 'Running') {
        throw "Service failed to start within $startTimeout seconds"
    }

    Write-Host "Service started successfully"

    # Final status
    Write-Host ""
    Write-Host "[ FINAL STATUS ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Service : $($service.Name)"
    Write-Host "Status  : $($service.Status)"
    Write-Host "Result  : Print queue cleared and service restarted successfully"

    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"

    exit 0
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to reset print queue"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure script is running with administrator privileges"
    Write-Host "- Verify Print Spooler service exists on this system"
    exit 1
}
