$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rustic Restore                                              v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\rustic_restore.ps1
================================================================================
 FILE     : rustic_restore.ps1
 DESCRIPTION : Restores files from a rustic backup snapshot to a local destination
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Targeted file restore from a rustic backup snapshot. Operator provides
   a snapshot ID (or "latest"), a source path within the snapshot, and a
   local destination path via SuperOps runtime variables. Uses the existing
   rustic binary and TOML configuration deployed by rustic_install.ps1.

 DATA SOURCES & PRIORITY

   - Rustic binary and TOML config installed by rustic_install.ps1
   - SuperOps runtime variables (operator fills at deploy time)

 REQUIRED INPUTS

   SuperOps runtime variables (prompted at deploy time):
     - $YourSnapshotId  : Snapshot ID to restore from, or "latest" (default: latest)
     - $YourRestorePath : Path within the snapshot to restore (e.g., C:\Users\alice\Documents)
     - $YourDestination : Local destination path (e.g., C:\Restore\Documents)

 SETTINGS

   None — all settings are in the TOML profile deployed by rustic_install.ps1.

 BEHAVIOR

   The script performs the following actions in order:
   1. Parses inputs; defaults snapshot ID to "latest" if empty or unreplaced
   2. Validates rustic binary exists, config exists, restorePath is provided,
      and destination is provided
   3. Sets RUSTIC_CONFIG_FILE environment variable
   4. Displays input summary
   5. Lists available snapshots so the operator can confirm the snapshot ID
   6. Creates the destination directory if it does not already exist
   7. Runs: rustic restore "<snapshotId>:<restorePath>" <destination>
   8. Reports final status including the destination path
   9. Clears RUSTIC_CONFIG_FILE and exits 0 or 1

 PREREQUISITES

   - Windows 10/11 or Windows Server 2016+
   - Administrator privileges (runs as SYSTEM via RMM)
   - rustic_install.ps1 previously deployed on this machine
   - Rustic binary at C:\ProgramData\Limehawk\Rustic\bin\rustic.exe
   - Config at C:\ProgramData\Limehawk\Rustic\rustic.toml

 SECURITY NOTES

   - No credentials are printed to console output
   - All secrets remain in the TOML config file
   - RUSTIC_CONFIG_FILE env var is cleared after execution

 ENDPOINTS

   - None — all backend endpoints are defined in the TOML profile

 EXIT CODES

   0 = Success
   1 = Failure (validation, restore error)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Snapshot ID  : latest
     Restore Path : C:\Users\alice\Documents
     Destination  : C:\Restore\Documents
     Binary       : C:\ProgramData\Limehawk\Rustic\bin\rustic.exe
     Config       : C:\ProgramData\Limehawk\Rustic\rustic.toml

   [INFO] AVAILABLE SNAPSHOTS
   ==============================================================
   ID        Time                 Host         Tags
   --------  -------------------  -----------  ----
   a1b2c3d4  2026-04-03 02:00:13  WORKSTATION1
   e5f6a7b8  2026-04-04 02:00:11  WORKSTATION1

   [RUN] RESTORE
   ==============================================================
     Source  : latest:C:\Users\alice\Documents
     Dest    : C:\Restore\Documents
     ...
     restore done

   [OK] FINAL STATUS
   ==============================================================
     Result      : SUCCESS
     Destination : C:\Restore\Documents

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-04 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== HARDCODED INPUTS (MANDATORY) ====

# --- OPTIONAL: Snapshot ID; defaults to "latest" if empty or unreplaced ---
$snapshotIdRaw = "$YourSnapshotId"

# --- REQUIRED: Path within the snapshot to restore ---
$restorePath = "$YourRestorePath"

# --- REQUIRED: Local destination path ---
$destination = "$YourDestination"

# ==== HARDCODED PATHS ====
$rusticExe  = 'C:\ProgramData\Limehawk\Rustic\bin\rustic.exe'
$configFile = 'C:\ProgramData\Limehawk\Rustic\rustic.toml'

# ==== RESOLVE OPTIONAL INPUTS ====

# Snapshot ID: default to "latest" if empty or unreplaced
$isSnapshotIdEmpty = [string]::IsNullOrWhiteSpace($snapshotIdRaw) -or $snapshotIdRaw -eq '$' + 'YourSnapshotId'
if ($isSnapshotIdEmpty) {
    $snapshotId = 'latest'
} else {
    $snapshotId = $snapshotIdRaw.Trim()
}

# ==== VALIDATION ====

if (-not (Test-Path $rusticExe)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Rustic binary not found at: $rusticExe"
}

if (-not (Test-Path $configFile)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Rustic config not found at: $configFile"
}

if ([string]::IsNullOrWhiteSpace($restorePath) -or $restorePath -eq '$' + 'YourRestorePath') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourRestorePath was not replaced."
}

if ([string]::IsNullOrWhiteSpace($destination) -or $destination -eq '$' + 'YourDestination') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourDestination was not replaced."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== SET ENVIRONMENT ====
$env:RUSTIC_CONFIG_FILE = $configFile

# ==== INPUT VALIDATION OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  Snapshot ID  : $snapshotId"
Write-Host "  Restore Path : $restorePath"
Write-Host "  Destination  : $destination"
Write-Host "  Binary       : $rusticExe"
Write-Host "  Config       : $configFile"

# ==== LIST AVAILABLE SNAPSHOTS ====
Write-Host ""
Write-Host "[INFO] AVAILABLE SNAPSHOTS"
Write-Host "=============================================================="

try {
    $ErrorActionPreference = 'Continue'
    & $rusticExe snapshots 2>&1 | ForEach-Object { Write-Host "  $_" }
    $snapshotExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($snapshotExitCode -ne 0) {
        Write-Host "  [WARN] rustic snapshots exited with code $snapshotExitCode"
    }
} catch {
    Write-Host "  [WARN] Could not list snapshots: $_"
}

# ==== CREATE DESTINATION DIRECTORY ====
if (-not (Test-Path $destination)) {
    try {
        New-Item -Path $destination -ItemType Directory -Force | Out-Null
        Write-Host ""
        Write-Host "  [INFO] Created destination directory: $destination"
    } catch {
        $env:RUSTIC_CONFIG_FILE = $null
        Write-Host ""
        Write-Host "[ERROR] Failed to create destination directory '$destination': $_"
        Write-Host ""
        Write-Host "[ERROR] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 1
    }
}

# ==== RESTORE ====
Write-Host ""
Write-Host "[RUN] RESTORE"
Write-Host "=============================================================="
Write-Host "  Source  : ${snapshotId}:${restorePath}"
Write-Host "  Dest    : $destination"

$restoreTarget = "${snapshotId}:${restorePath}"

$ErrorActionPreference = 'Continue'
& $rusticExe restore $restoreTarget $destination 2>&1 | ForEach-Object { Write-Host "  $_" }
$restoreExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

# ==== CLEAR ENV VAR ====
$env:RUSTIC_CONFIG_FILE = $null

# ==== FINAL STATUS ====
Write-Host ""
if ($restoreExitCode -eq 0) {
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Result      : SUCCESS"
    Write-Host "  Destination : $destination"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Result      : FAILED"
    Write-Host "  Exit Code   : $restoreExitCode"
    Write-Host "  Destination : $destination"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
