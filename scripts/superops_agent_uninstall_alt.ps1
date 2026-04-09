$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SuperOps Agent Uninstaller                                   v1.2.4
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\superops_agent_uninstall_alt.ps1
================================================================================
 FILE     : superops_agent_uninstall_alt.ps1
DESCRIPTION : Uninstalls SuperOps agent via WMI/CIM with diagnostic reporting
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 This script performs a quiet uninstallation of the SuperOps RMM Agent using the
 MSI ProductCode GUID. It reports which uninstall method (WMI or CIM) was used,
 provides diagnostic information such as version, publisher, and registry path
 detected, and checks for leftover services to suggest manual cleanup commands.

 DATA SOURCES & PRIORITY
 1. WMI (Get-WmiObject Win32_Product): Executes uninstall by ProductCode.
 2. CIM (Get-CimInstance Win32_Product): Preferred on newer systems if WMI fails.
 3. Service Check (Get-Service): After uninstall attempt, searches for *RMM* or
    *SuperOps* services that may remain.

 REQUIRED INPUTS
 - None at runtime. The IdentifyingNumber GUID for the SuperOps Agent MSI is
   hardcoded in the script.

 SUPEROPS SETTINGS
 - Designed for execution inside SuperOps RMM. Keep the module import on line 1.
 - No tenant-specific settings used.

 BEHAVIOR
 - Queries WMI for product info and attempts uninstall.
 - If WMI fails, queries CIM for the same GUID and attempts uninstall.
 - Prints product details (name, version, publisher, method used).
 - Reports clear success or error messages in Style A format.
 - If no product entry is found, reports as "Already removed" but does not fail.
 - Performs a post-uninstall service check to detect leftover services and
   display cleanup commands.

 PREREQUISITES
 - PowerShell 5.1+; run as Administrator.
 - '$SuperOpsModule' must be imported on line 1 for SuperOps execution.

 SECURITY NOTES
 - No secrets handled. Do not paste API keys. Logs never print secrets.

 ENDPOINTS
 - N/A (local OS operations only).

 EXIT CODES
 - 0: Success (uninstall executed, or product already absent).
 - 1: Script error occurred.

 EXAMPLE RUN
 [INFO] TARGET PARAMETERS
 ==============================================================
 Product GUID             : {3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}

 [RUN] UNINSTALL ACTION
 ==============================================================
 [RUN] STATUS             : Attempting uninstall via WMI...
 [WARN] STATUS            : No matching product found via WMI.
 [WARN] STATUS            : No matching product found via CIM.
 [OK] RESULT              : PRODUCT NOT INSTALLED OR ALREADY REMOVED

 [INFO] FINAL STATUS
 ==============================================================
 [OK] UNINSTALL PROCESS FINISHED (NO ACTION NEEDED).

 [INFO] SCRIPT COMPLETED
 ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.2.4 Updated to two-line ASCII console output style
 2025-12-23 v1.2.3 Updated to Limehawk Script Framework
 2025-08-20 v1.2.2 Treats missing product as success (already removed) instead of failure
 2025-08-20 v1.2.1 Fixed cleanup command string formatting in service check to prevent parse errors
 2025-08-20 v1.2.0 Added post-uninstall service check with cleanup command suggestions
 2025-08-20 v1.1.0 Added product details (name, version, publisher) and reported which uninstall method was used
 2025-08-20 v1.0.0 Initial script creation using WMI and CIM uninstall methods with hardcoded ProductCode GUID
================================================================================
#>

Set-StrictMode -Version Latest

#================================================================================
# HELPER FUNCTIONS
#================================================================================

function Write-Section {
    param([string]$prefix, [string]$title)
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $prefix, $title)
    Write-Host ("=" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

#================================================================================
# SCRIPT BODY
#================================================================================

$ProductGUID = '{3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}'
$uninstallAttempted = $false

try {
    Write-Section 'INFO' 'TARGET PARAMETERS'
    PrintKV 'Product GUID' $ProductGUID

    Write-Section 'RUN' 'UNINSTALL ACTION'
    Write-Host "[RUN] Attempting uninstall via WMI..."
    try {
        $wmiProduct = Get-WmiObject -Class Win32_Product -Filter "IdentifyingNumber='$ProductGUID'" -ErrorAction Stop | Select-Object -First 1
        if ($wmiProduct) {
            PrintKV 'PRODUCT NAME' $wmiProduct.Name
            PrintKV 'PRODUCT VERSION' $wmiProduct.Version
            PrintKV 'PUBLISHER' $wmiProduct.Vendor
            PrintKV 'METHOD USED' 'WMI (Win32_Product)'
            $wmiProduct.Uninstall() | Out-Null
            Write-Host "[OK] UNINSTALL SUCCESSFUL VIA WMI"
            $uninstallAttempted = $true
        } else {
            Write-Host "[WARN] No matching product found via WMI."
        }
    } catch {
        Write-Host "[WARN] WMI uninstall failed. Trying CIM..."
    }

    if (-not $uninstallAttempted) {
        try {
            $cimProduct = Get-CimInstance -Class Win32_Product -Filter "IdentifyingNumber ='$ProductGUID'" -ErrorAction Stop | Select-Object -First 1
            if ($cimProduct) {
                PrintKV 'PRODUCT NAME' $cimProduct.Name
                PrintKV 'PRODUCT VERSION' $cimProduct.Version
                PrintKV 'PUBLISHER' $cimProduct.Vendor
                PrintKV 'METHOD USED' 'CIM (Win32_Product)'
                $cimProduct | Invoke-CimMethod -MethodName Uninstall | Out-Null
                Write-Host "[OK] UNINSTALL SUCCESSFUL VIA CIM"
                $uninstallAttempted = $true
            } else {
                Write-Host "[WARN] No matching product found via CIM."
            }
        } catch {
            throw 'CIM uninstall also failed.'
        }
    }

    if (-not $uninstallAttempted) {
        Write-Host "[OK] PRODUCT NOT INSTALLED OR ALREADY REMOVED"
        $uninstallAttempted = $true  # Treat as success
    }

} catch {
    Write-Section 'ERROR' 'ERROR OCCURRED'
    PrintKV 'ERROR MESSAGE' $_.Exception.Message
} finally {
    Write-Section 'INFO' 'POST-UNINSTALL SERVICE CHECK'
    Write-Host "[RUN] Checking for leftover services (SuperOps/RMM)..."
    $leftoverServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'SuperOps|RMM' }

    if ($leftoverServices) {
        Write-Host "[WARN] LEFTOVER SERVICES FOUND. MANUAL DELETION MAY BE NEEDED."
        foreach ($service in $leftoverServices) {
            Write-Host ""
            PrintKV '  - Found Service' ("{0} ({1})" -f $service.DisplayName, $service.Name)
            $cleanupCmd = "sc.exe delete `"$($service.Name)`""
            PrintKV '    Cleanup Command' $cleanupCmd
        }
    } else {
        Write-Host "[OK] No leftover services found."
    }

    Write-Section 'INFO' 'FINAL STATUS'
    if ($uninstallAttempted) {
        if ($wmiProduct -or $cimProduct) {
            Write-Host '[OK] UNINSTALL PROCESS FINISHED.'
        } else {
            Write-Host '[OK] UNINSTALL PROCESS FINISHED (NO ACTION NEEDED).'
        }
        exit 0
    } else {
        Write-Host '[ERROR] SCRIPT FINISHED WITH ERRORS.'
        exit 1
    }

    Write-Section 'INFO' 'SCRIPT COMPLETED'
}
