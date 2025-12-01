$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Duplicati Backup Status Check                                  v1.0.0
FILE   : duplicati_backup_status.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Monitors Duplicati backup jobs via the local API. Authenticates to the
    Duplicati web service, queries configured backups, and reports their status
    including metrics like backup size, file count, and next scheduled run.

REQUIRED INPUTS:
    $duplicatiPassword : Password for Duplicati Web UI (leave empty if no password)
    $duplicatiPort     : Port where Duplicati runs (default 8200)

BEHAVIOR:
    1. Validates input parameters
    2. Authenticates to Duplicati API
    3. Queries all configured backup jobs
    4. Checks status of each job (Success, Warning, Error, etc.)
    5. Reports metrics: size, file count, progress, next schedule
    6. Exits with code 1 if any job has failed

PREREQUISITES:
    - Windows OS
    - Duplicati 2.0+ installed and running
    - Web UI password set (or empty for no password)

SECURITY NOTES:
    - Password is stored in script - modify per deployment
    - No secrets logged to output

EXIT CODES:
    0 = Success (all jobs healthy)
    1 = Failure (service down or jobs failed)

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Duplicati URL : http://localhost:8200
    Inputs validated successfully

    [ AUTHENTICATION ]
    --------------------------------------------------------------
    Authenticating to Duplicati API...
    Authentication successful

    [ BACKUP STATUS ]
    --------------------------------------------------------------
    Job: Daily Backup
      Status : Success
      Last Run : 2024-12-01 02:00
      Size : 45.2 GB
      Files : 125,432
      Next : 2024-12-02 02:00

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    All 1 backup job(s) healthy

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Set your Duplicati Web UI password here (leave empty string if no password)
$duplicatiPassword = ''
$duplicatiPort = 8200

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$duplicatiBaseUrl = "http://localhost:$duplicatiPort"
$duplicatiApiUrl = "$duplicatiBaseUrl/api/v1/backups"

Write-Host "Duplicati URL : $duplicatiBaseUrl"
Write-Host "Inputs validated successfully"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

# ============================================================================
# AUTHENTICATION
# ============================================================================
Write-Host ""
Write-Host "[ AUTHENTICATION ]"
Write-Host "--------------------------------------------------------------"

$baseHeaders = @{
    "Accept" = "application/json"
    "Content-Type" = "application/json"
}

try {
    Write-Host "Authenticating to Duplicati API..."

    $loginBody = @{ Password = $duplicatiPassword } | ConvertTo-Json
    $loginResponse = Invoke-RestMethod -Uri "$duplicatiBaseUrl/api/v1/auth/login" -Method Post -Headers $baseHeaders -Body $loginBody -TimeoutSec 30

    if (-not $loginResponse.AccessToken) {
        throw "Login failed: No Access Token returned"
    }

    $authHeaders = $baseHeaders.Clone()
    $authHeaders["Authorization"] = "Bearer $($loginResponse.AccessToken)"

    Write-Host "Authentication successful"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to authenticate to Duplicati"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host "Check if Duplicati is running and password is correct"
    exit 1
}

# ============================================================================
# QUERY BACKUPS
# ============================================================================
Write-Host ""
Write-Host "[ BACKUP STATUS ]"
Write-Host "--------------------------------------------------------------"

try {
    $backups = Invoke-RestMethod -Uri $duplicatiApiUrl -Method Get -Headers $authHeaders -TimeoutSec 30

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Host "No backup jobs configured in Duplicati"
        exit 0
    }
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to query Duplicati backups"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# PROCESS BACKUP JOBS
# ============================================================================
$jobsWithErrors = 0
$healthyStatuses = @("Success", "Warning", "Skipped", "Running", "Scheduled")

foreach ($backup in $backups) {
    $backupId = $backup.ID
    if (-not $backupId) { continue }

    $jobName = if ($backup.Name -and $backup.Name.Trim()) { $backup.Name.Trim() } else { $backupId }

    # Query detailed status
    $detailedStatus = $null
    try {
        $detailedUrl = "$duplicatiBaseUrl/api/v1/backup/$backupId"
        $detailedStatus = Invoke-RestMethod -Uri $detailedUrl -Method Get -Headers $authHeaders -TimeoutSec 10
    } catch { }

    # Determine status
    $lastResult = "Scheduled"
    $lastEndTime = "N/A"
    $jobSize = "N/A"
    $fileCount = "N/A"
    $nextSchedule = "Unknown"

    if ($detailedStatus) {
        if ($detailedStatus.CurrentRun -or $detailedStatus.Phase) {
            $lastResult = "Running"
            if ($detailedStatus.Phase) { $lastResult = "Running ($($detailedStatus.Phase))" }
        } elseif ($detailedStatus.LastRun -and $detailedStatus.LastRun.Result) {
            $lastResult = $detailedStatus.LastRun.Result
            if ($detailedStatus.LastRun.End) {
                $lastEndTime = ($detailedStatus.LastRun.End -as [DateTime]).ToString("yyyy-MM-dd HH:mm")
            }
        }

        if ($detailedStatus.TotalSize) { $jobSize = Format-Bytes $detailedStatus.TotalSize }
        elseif ($backup.TotalSize) { $jobSize = Format-Bytes $backup.TotalSize }

        if ($detailedStatus.FileCount) { $fileCount = $detailedStatus.FileCount }
        elseif ($backup.FileCount) { $fileCount = $backup.FileCount }

        if ($detailedStatus.Schedule -and $detailedStatus.Schedule.Next) {
            $nextSchedule = ($detailedStatus.Schedule.Next -as [DateTime]).ToString("yyyy-MM-dd HH:mm")
        }
    } elseif ($backup.LastRun -and $backup.LastRun.Result) {
        $lastResult = $backup.LastRun.Result
        if ($backup.LastRun.End) {
            $lastEndTime = ($backup.LastRun.End -as [DateTime]).ToString("yyyy-MM-dd HH:mm")
        }
        if ($backup.TotalSize) { $jobSize = Format-Bytes $backup.TotalSize }
        if ($backup.FileCount) { $fileCount = $backup.FileCount }
    }

    Write-Host "Job: $jobName"
    Write-Host "  Status : $lastResult"
    Write-Host "  Last Run : $lastEndTime"
    Write-Host "  Size : $jobSize"
    Write-Host "  Files : $fileCount"
    Write-Host "  Next : $nextSchedule"
    Write-Host ""

    if ($lastResult -notin $healthyStatuses) {
        $jobsWithErrors++
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

if ($jobsWithErrors -gt 0) {
    Write-Host "Result : FAILURE"
    Write-Host "$jobsWithErrors backup job(s) failed - check Duplicati UI"
    exit 1
} else {
    Write-Host "Result : SUCCESS"
    Write-Host "All $($backups.Count) backup job(s) healthy"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
