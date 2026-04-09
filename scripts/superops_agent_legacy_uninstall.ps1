<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT    : SuperOps Agent Uninstall (Legacy Windows) 1.1.2
 AUTHOR    : Limehawk.io
 DATE      : January 2026
 USAGE     : .\superops_agent_legacy_uninstall.ps1
 FILE      : superops_agent_legacy_uninstall.ps1
DESCRIPTION : Uninstalls legacy SuperOps agent via WMI IdentifyingNumber
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE
   Uninstalls the legacy SuperOps agent on Windows systems using the product's
   IdentifyingNumber. This script is intended for environments where the agent
   cannot be uninstalled via standard methods or newer uninstallers.

 DATA SOURCES & PRIORITY
   1) Hardcoded IdentifyingNumber for the legacy SuperOps agent.
   2) WMI (Win32_Product class) to locate and uninstall the product.

 REQUIRED INPUTS
   - None. The IdentifyingNumber is hardcoded within the script.

 SETTINGS
   - None.

 BEHAVIOR
   - Queries WMI for products matching the hardcoded IdentifyingNumber.
   - Invokes the Uninstall method on any found product.
   - Designed for silent, unattended execution.

 PREREQUISITES
   - PowerShell 2.0 or later.
   - Administrative privileges are required to uninstall software.
   - WMI service must be running.

 SECURITY NOTES
   - This script does not handle sensitive data or credentials.
   - The IdentifyingNumber is publicly known for the SuperOps agent.

 ENDPOINTS
   - Local WMI service.

 EXIT CODES
   - 0: Success (product uninstalled or not found).
   - 1: Failure (e.g., insufficient permissions, WMI error).

 EXAMPLE RUN
   [RUN] OPERATION
   ==============================================================
   Attempting to uninstall SuperOps agent with IdentifyingNumber...
   SuperOps agent uninstallation command executed.

   [OK] FINAL STATUS
   ==============================================================
   SuperOps agent uninstallation completed.
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.2 Fixed EXAMPLE RUN section formatting
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-02 v1.0.0 Initial version, extracted from SuperOps.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Helper Functions ---
function Write-Section([string]$prefix, [string]$title) {
    Write-Host ""
    Write-Host "[$prefix] $title"
    Write-Host ("=" * 62)
}

function Write-Log([string]$message, [string]$level = "INFO") {
    $prefix = switch ($level) {
        "INFO" { "[INFO]" }
        "RUN" { "[RUN]" }
        "OK" { "[OK]" }
        "WARN" { "[WARN]" }
        "ERROR" { "[ERROR]" }
        default { "[$level]" }
    }
    Write-Host "$prefix $message"
}

# --- Main Script Body ---

Write-Section "INFO" "INPUT VALIDATION"
# No inputs to validate for this script
Write-Log "No specific inputs to validate." "OK"

Write-Section "RUN" "OPERATION"
Write-Log "Attempting to uninstall SuperOps agent with IdentifyingNumber '{3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}'..." "RUN"
try {
    Get-WmiObject -Class Win32_Product -Filter "IdentifyingNumber='{3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}'" | ForEach-Object { $_.Uninstall() }
    Write-Log "SuperOps agent uninstallation command executed." "OK"
    $script:exitCode = 0
} catch {
    Write-Log "Error during uninstallation: $($_.Exception.Message)" "ERROR"
    $script:exitCode = 1
}

Write-Section "INFO" "RESULT"
if ($script:exitCode -eq 0) {
    Write-Log "Uninstallation process completed without critical errors." "OK"
} else {
    Write-Log "Uninstallation process encountered errors." "ERROR"
}

Write-Section "INFO" "FINAL STATUS"
if ($script:exitCode -eq 0) {
    Write-Log "SuperOps agent uninstallation completed." "OK"
} else {
    Write-Log "SuperOps agent uninstallation failed." "ERROR"
}

Write-Section "INFO" "SCRIPT COMPLETED"
exit $script:exitCode