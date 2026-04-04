$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rustic Backup Runner                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\rustic_backup.ps1
================================================================================
 FILE     : rustic_backup.ps1
 DESCRIPTION : Runs rustic backup, prune, and integrity check using existing profile
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Scheduled backup runner for Rustic. Reads configuration from the TOML
   profile written by rustic_install.ps1 and executes a full backup cycle:
   backup snapshot, retention prune, and a lightweight integrity check on
   a random 1% data subset. Intended to be invoked by the Windows Scheduled
   Task created during installation, or manually via SuperOps RMM.

 USAGE NOTES

   No runtime variables are required. All configuration (backend credentials,
   repository path, backup sources, retention policy) is read from the TOML
   profile at C:\ProgramData\Limehawk\Rustic\rustic.toml.

   Run the rustic_install.ps1 script first to set up the binary, TOML profile,
   and Scheduled Task before using this runner.

   Exit behavior:
     - Backup failure  : exits 1 (fatal — snapshot was not created)
     - Prune failure   : warns and continues (non-fatal)
     - Check failure   : warns and continues (non-fatal)

 REQUIREMENTS

   - rustic_install.ps1 must have been run successfully
   - rustic.exe at C:\ProgramData\Limehawk\Rustic\bin\rustic.exe
   - rustic.toml at C:\ProgramData\Limehawk\Rustic\rustic.toml
   - Windows 10/11 or Windows Server 2016+
   - Administrator privileges (runs as SYSTEM via RMM or Scheduled Task)

 EXAMPLE RUN

   [INFO] RUSTIC BACKUP
   ==============================================================
     Binary : C:\ProgramData\Limehawk\Rustic\bin\rustic.exe
     Config : C:\ProgramData\Limehawk\Rustic\rustic.toml
     Log Dir: C:\ProgramData\Limehawk\Rustic\Logs
     Start  : 2026-04-04 02:00:01

   [RUN] BACKUP
   ==============================================================
     Running rustic backup...
     No snapshots found, creating initial snapshot
     snapshot abc12345 saved
     Backup completed successfully

   [RUN] RETENTION
   ==============================================================
     Running rustic forget --prune...
     keep 1 snapshots: [abc12345]
     Retention policy applied successfully

   [RUN] INTEGRITY CHECK
   ==============================================================
     Running rustic check --read-data-subset=1/100...
     checking pack files
     check completed successfully
     Integrity check completed successfully

   [OK] FINAL STATUS
   ==============================================================
     Result   : SUCCESS
     Duration : 00:01:42
     Backup   : OK
     Prune    : OK
     Check    : OK

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-04 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== HARDCODED PATHS ====
$rusticExe  = 'C:\ProgramData\Limehawk\Rustic\bin\rustic.exe'
$configFile = 'C:\ProgramData\Limehawk\Rustic\rustic.toml'
$logDir     = 'C:\ProgramData\Limehawk\Rustic\Logs'

# ==== STATE ====
$startTime    = Get-Date
$backupOk     = $false
$pruneOk      = $true
$checkOk      = $true
$pruneWarning = ""
$checkWarning = ""

# ==== PREFLIGHT ====
Write-Host ""
Write-Host "[INFO] RUSTIC BACKUP"
Write-Host "=============================================================="
Write-Host "  Binary : $rusticExe"
Write-Host "  Config : $configFile"
Write-Host "  Log Dir: $logDir"
Write-Host "  Start  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

if (-not (Test-Path $rusticExe)) {
    Write-Host ""
    Write-Host "[ERROR] PREFLIGHT FAILED"
    Write-Host "=============================================================="
    Write-Host "  Rustic binary not found: $rusticExe"
    Write-Host "  Run rustic_install.ps1 first."
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

if (-not (Test-Path $configFile)) {
    Write-Host ""
    Write-Host "[ERROR] PREFLIGHT FAILED"
    Write-Host "=============================================================="
    Write-Host "  TOML config not found: $configFile"
    Write-Host "  Run rustic_install.ps1 first."
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# ==== SET CONFIG ENV ====
$env:RUSTIC_CONFIG_FILE = $configFile

try {

    # ==== BACKUP ====
    Write-Host ""
    Write-Host "[RUN] BACKUP"
    Write-Host "=============================================================="
    Write-Host "  Running rustic backup..."

    $ErrorActionPreference = 'Continue'
    & $rusticExe backup 2>&1 | ForEach-Object { Write-Host "  $_" }
    $backupExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($backupExit -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] BACKUP FAILED"
        Write-Host "=============================================================="
        Write-Host "  rustic backup exited with code $backupExit"
        Write-Host ""
        Write-Host "[ERROR] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 1
    }

    $backupOk = $true
    Write-Host "  Backup completed successfully"

    # ==== RETENTION ====
    Write-Host ""
    Write-Host "[RUN] RETENTION"
    Write-Host "=============================================================="
    Write-Host "  Running rustic forget --prune..."

    $ErrorActionPreference = 'Continue'
    & $rusticExe forget --prune 2>&1 | ForEach-Object { Write-Host "  $_" }
    $pruneExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($pruneExit -ne 0) {
        $pruneOk      = $false
        $pruneWarning = "rustic forget --prune exited with code $pruneExit"
        Write-Host "  [WARN] Retention policy failed (exit $pruneExit) — continuing"
    } else {
        Write-Host "  Retention policy applied successfully"
    }

    # ==== INTEGRITY CHECK ====
    Write-Host ""
    Write-Host "[RUN] INTEGRITY CHECK"
    Write-Host "=============================================================="
    Write-Host "  Running rustic check --read-data-subset=1/100..."

    $ErrorActionPreference = 'Continue'
    & $rusticExe check --read-data-subset=1/100 2>&1 | ForEach-Object { Write-Host "  $_" }
    $checkExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($checkExit -ne 0) {
        $checkOk      = $false
        $checkWarning = "rustic check exited with code $checkExit"
        Write-Host "  [WARN] Integrity check failed (exit $checkExit) — continuing"
    } else {
        Write-Host "  Integrity check completed successfully"
    }

} finally {
    $env:RUSTIC_CONFIG_FILE = $null
}

# ==== DURATION ====
$duration = (Get-Date) - $startTime
$durationStr = '{0:D2}:{1:D2}:{2:D2}' -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result   : SUCCESS"
Write-Host "  Duration : $durationStr"
Write-Host "  Backup   : $(if ($backupOk) { 'OK' } else { 'FAILED' })"
Write-Host "  Prune    : $(if ($pruneOk) { 'OK' } else { "WARN - $pruneWarning" })"
Write-Host "  Check    : $(if ($checkOk) { 'OK' } else { "WARN - $checkWarning" })"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
