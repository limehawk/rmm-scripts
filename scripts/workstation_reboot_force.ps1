$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Reboot Force Now                                              v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\workstation_reboot_force.ps1
================================================================================
 FILE     : workstation_reboot_force.ps1
 DESCRIPTION : Forces an immediate system reboot without user prompts
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Forces an immediate system reboot, closing all applications without saving
   or prompting. Designed for RMM deployment when a machine needs to be
   rebooted regardless of user activity or open applications.

 DATA SOURCES & PRIORITY

   - Not applicable (no external data sources)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - No configurable inputs required

 SETTINGS

   - Force mode: Enabled (closes applications without prompting)
   - Timeout: 0 seconds (immediate reboot)

 BEHAVIOR

   The script performs the following actions in order:
   1. Displays system information
   2. Initiates forced immediate reboot via shutdown.exe
   3. Script exits (system reboots immediately)

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges

 SECURITY NOTES

   - No secrets exposed in output
   - Requires admin privileges to execute reboot
   - Users will lose unsaved work

 ENDPOINTS

   - Not applicable (no network endpoints)

 EXIT CODES

   0 = Success (reboot initiated)
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] SYSTEM INFO
   ==============================================================
     Computer : WORKSTATION-01
     User     : SYSTEM

   [RUN] REBOOT
   ==============================================================
     Initiating forced immediate reboot...

   [OK] FINAL STATUS
   ==============================================================
     Reboot initiated successfully

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-22 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

try {
    # Display system info
    Write-Section -Type 'info' -Name 'SYSTEM INFO'
    Write-Host "  Computer : $env:COMPUTERNAME"
    Write-Host "  User     : $env:USERNAME"

    # Initiate forced reboot
    Write-Section -Type 'run' -Name 'REBOOT'
    Write-Host "  Initiating forced immediate reboot..."

    # Use shutdown.exe for maximum compatibility in RMM/SYSTEM context
    # /r = restart, /f = force close applications, /t 0 = no delay
    & shutdown.exe /r /f /t 0

    Write-Section -Type 'ok' -Name 'FINAL STATUS'
    Write-Host "  Reboot initiated successfully"

    Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
    exit 0
}
catch {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host "  Failed to initiate reboot"
    Write-Host "  Error : $($_.Exception.Message)"
    exit 1
}
