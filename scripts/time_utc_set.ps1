$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows Linux Set UTC Time                                    v1.0.1
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\time_utc_set.ps1
================================================================================
 FILE     : time_utc_set.ps1
 DESCRIPTION : Fixes time drift on Windows/Linux dual-boot systems
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Configures Windows to use UTC for the hardware clock instead of local time.
   This prevents the clock from being wrong when switching between Windows and
   Linux on dual-boot systems, as Linux uses UTC by default.

 DATA SOURCES & PRIORITY

   - Registry: HKLM\System\CurrentControlSet\Control\TimeZoneInformation

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - No configurable inputs required

 SETTINGS

   Configuration details and default values:
     - RealTimeIsUniversal: Set to 1 (enabled)

 BEHAVIOR

   The script performs the following actions in order:
   1. Sets RealTimeIsUniversal registry value to 1
   2. Reports success or failure

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges (required for HKLM access)

 SECURITY NOTES

   - No secrets exposed in output
   - Standard Windows registry modification

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Success
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] UTC CLOCK FIX
   ==============================================================
   [RUN] Setting RealTimeIsUniversal registry value...
   [OK] Enabled UTC hardware clock for dual-boot compatibility

   [INFO] FINAL STATUS
   ==============================================================
   Result : SUCCESS

   [INFO] SCRIPT COMPLETE
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.0.1 Updated to two-line ASCII console output style
 2026-01-08 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# UTC CLOCK FIX
# ==============================================================================

Write-Host ""
Write-Host "[INFO] UTC CLOCK FIX"
Write-Host "=============================================================="

try {
    Write-Host "[RUN] Setting RealTimeIsUniversal registry value..."

    $tzPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
    Set-ItemProperty -Path $tzPath -Name 'RealTimeIsUniversal' -Value 1 -Type DWord -Force

    Write-Host "[OK] Enabled UTC hardware clock for dual-boot compatibility"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to set UTC clock registry key"
    Write-Host "This script requires administrator privileges"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Host ""
Write-Host "[INFO] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Result : SUCCESS"

Write-Host ""
Write-Host "[INFO] SCRIPT COMPLETE"
Write-Host "=============================================================="

exit 0
