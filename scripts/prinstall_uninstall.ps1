$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Uninstall v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_uninstall.ps1
FILE    : prinstall_uninstall.ps1
DESCRIPTION : Removes prinstall binary, data directory, and audit history
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Uninstalls prinstall completely. Removes the binary, the machine-wide data
   directory at C:\ProgramData\prinstall\ (install history, config, driver
   staging), and any audit state. Use this when decommissioning prinstall on a
   machine or resetting it to a clean state.

 DATA REMOVED
   - C:\ProgramData\prinstall\prinstall.exe
   - C:\ProgramData\prinstall\history.toml (install audit log)
   - C:\ProgramData\prinstall\config.toml  (persisted TUI settings)
   - C:\ProgramData\prinstall\staging\     (downloaded driver packages)
   - Any remaining files in C:\ProgramData\prinstall\

 REQUIRED INPUTS
   - $ConfirmUninstallHere : Must be set to 'yes' to execute
                             (SuperOps: $ConfirmUninstallHere)

 BEHAVIOR
   1. Validates the confirmation input (prevents accidental execution)
   2. Checks whether C:\ProgramData\prinstall\ exists
   3. Recursively removes the entire directory and all contents
   4. Verifies the directory no longer exists

 PREREQUISITES
   - Windows OS
   - Administrator privileges

 SECURITY NOTES
   - No secrets in logs
   - Does NOT uninstall printers that prinstall previously added — use
     prinstall_remove.ps1 for that first if you want a clean teardown
   - Destructive: this script does not create backups of history.toml

 ENDPOINTS
   - Local filesystem only (no network I/O)

 EXIT CODES
   - 0 = Success - prinstall removed or already absent
   - 1 = Failure - removal failed or confirmation missing

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Confirmation    : yes
   Install Dir     : C:\ProgramData\prinstall
   Inputs validated successfully

   [RUN] REMOVE PRINSTALL
   ==============================================================
   Found C:\ProgramData\prinstall (contains 4 file(s), 1 dir(s))
   Removing C:\ProgramData\prinstall...
   Directory removed

   [RUN] VERIFY
   ==============================================================
   Install directory no longer exists: confirmed

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Action          : Prinstall fully uninstalled
   Location        : C:\ProgramData\prinstall (removed)

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 Initial release - standalone dedicated uninstall script.
                  Complements prinstall_setup.ps1 (which has a built-in
                  uninstall action). Use this for one-click teardown from the
                  RMM console without a yes/no action toggle.
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$confirmInput = "$ConfirmUninstallHere"   # Must be 'yes' to execute
$installDir   = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($confirmInput) -or $confirmInput -eq '$' + 'ConfirmUninstallHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$ConfirmUninstallHere was not replaced. Set it to 'yes' to confirm uninstall."
}

$confirmed = $false
if (-not $errorOccurred) {
    switch ($confirmInput.Trim().ToLower()) {
        'yes'     { $confirmed = $true }
        'confirm' { $confirmed = $true }
        default   {
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Confirmation must be 'yes' to proceed, got: $confirmInput"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($installDir)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Install directory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

Write-Host "Confirmation    : $confirmInput"
Write-Host "Install Dir     : $installDir"
Write-Host "Inputs validated successfully"

# ============================================================================
# REMOVE PRINSTALL
# ============================================================================
Write-Host ""
Write-Host "[RUN] REMOVE PRINSTALL"
Write-Host "=============================================================="

if (-not (Test-Path $installDir)) {
    Write-Host "$installDir does not exist, nothing to remove"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Action          : Prinstall was already absent"
    Write-Host "Location        : $installDir (not found)"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

try {
    $contents = Get-ChildItem -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
    $fileCount = ($contents | Where-Object { -not $_.PSIsContainer } | Measure-Object).Count
    $dirCount  = ($contents | Where-Object { $_.PSIsContainer } | Measure-Object).Count
    Write-Host "Found $installDir (contains $fileCount file(s), $dirCount dir(s))"

    Write-Host "Removing $installDir..."
    Remove-Item -Path $installDir -Recurse -Force
    Write-Host "Directory removed"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to remove $installDir"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# Clean up the mDNS firewall rule created by prinstall_setup.ps1 so
# uninstall leaves no state behind. Best-effort — a missing rule is
# fine, we just don't want stale rules polluting the firewall table.
try {
    $rule = Get-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
    if ($rule) {
        Remove-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
        Write-Host "Removed firewall rule 'Prinstall (mDNS discovery)'"
    }
} catch {
    Write-Host "Warning: could not remove firewall rule: $($_.Exception.Message)"
}

# ============================================================================
# VERIFY
# ============================================================================
Write-Host ""
Write-Host "[RUN] VERIFY"
Write-Host "=============================================================="

if (Test-Path $installDir) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Directory still exists after removal attempt: $installDir"
    exit 1
}

Write-Host "Install directory no longer exists: confirmed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status          : Success"
Write-Host "Action          : Prinstall fully uninstalled"
Write-Host "Location        : $installDir (removed)"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
