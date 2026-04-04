$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rustic Uninstall                                            v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\rustic_uninstall.ps1
================================================================================
 FILE     : rustic_uninstall.ps1
 DESCRIPTION : Removes rustic binary, config, scheduled task, and logs
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Removes all local Rustic components from the machine: the Windows Scheduled
   Task and the entire install directory (binary, config, backup script, and
   logs). Does NOT delete the remote backup repository. Safe to run even if
   components are already absent — partial removal is acceptable.

 BEHAVIOR

   The script performs the following actions in order:
   1. Removes the Windows Scheduled Task if it exists
   2. Removes the install directory and all contents recursively
   3. Reports final status and exits 0

 PREREQUISITES

   - Windows 10/11 or Windows Server 2016+
   - Administrator privileges (runs as SYSTEM via RMM)

 EXIT CODES

   0 = Success (always — partial removal is acceptable)

 EXAMPLE RUN

   [RUN] REMOVE SCHEDULED TASK
   ==============================================================
     Task 'Limehawk Rustic Backup' found
     Task removed

   [RUN] REMOVE FILES
   ==============================================================
     Directory found: C:\ProgramData\Limehawk\Rustic
     Directory removed

   [OK] FINAL STATUS
   ==============================================================
     Result : SUCCESS
     Note   : Remote backup repository was NOT deleted

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-04 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== HARDCODED INPUTS ====
$installDir = 'C:\ProgramData\Limehawk\Rustic'
$taskName   = 'Limehawk Rustic Backup'

# ==== REMOVE SCHEDULED TASK ====
Write-Host ""
Write-Host "[RUN] REMOVE SCHEDULED TASK"
Write-Host "=============================================================="

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "  Task '$taskName' found"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "  Task removed"
} else {
    Write-Host "  Task '$taskName' not found — skipping"
}

# ==== REMOVE FILES ====
Write-Host ""
Write-Host "[RUN] REMOVE FILES"
Write-Host "=============================================================="

if (Test-Path $installDir) {
    Write-Host "  Directory found: $installDir"
    Remove-Item -Path $installDir -Recurse -Force
    Write-Host "  Directory removed"
} else {
    Write-Host "  Directory not found: $installDir — skipping"
}

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result : SUCCESS"
Write-Host "  Note   : Remote backup repository was NOT deleted"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
