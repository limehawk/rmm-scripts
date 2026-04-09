$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Remote Wipe                                                  v1.0.3
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\workstation_remote_wipe.ps1
================================================================================
 FILE     : workstation_remote_wipe.ps1
 DESCRIPTION : Initiates MDM remote wipe to factory reset Windows device
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Initiates a remote wipe of the Windows device using the MDM RemoteWipe CSP.
   This completely erases all data on the device and resets it to factory state.

   *** WARNING: THIS ACTION IS IRREVERSIBLE ***
   *** ALL DATA ON THE DEVICE WILL BE PERMANENTLY DELETED ***

 DATA SOURCES & PRIORITY

   - Local MDM namespace (root\cimv2\mdm\dmmap)
   - MDM_RemoteWipe class instance

 REQUIRED INPUTS

   None - all configuration is internal to the MDM subsystem

 SETTINGS

   - No configurable settings; wipe executes immediately upon script run

 BEHAVIOR

   The script performs the following actions in order:
   1. Creates CIM session to local MDM namespace
   2. Retrieves MDM_RemoteWipe instance
   3. Invokes the doWipeMethod
   4. Device begins factory reset process

 PREREQUISITES

   - Windows 10/11 (MDM enrolled or Azure AD joined)
   - Administrator privileges
   - Device must have MDM RemoteWipe capability

 SECURITY NOTES

   - THIS IS A DESTRUCTIVE OPERATION
   - Use only on lost/stolen devices or for secure decommissioning
   - Cannot be undone once initiated
   - Ensure proper authorization before running
   - No secrets in logs

 ENDPOINTS

   - Not applicable (local CIM/WMI operations only)

 EXIT CODES

   0 = Wipe initiated successfully
   1 = Failure (CIM session, instance not found, or wipe failed)

 EXAMPLE RUN

   [WARN] INITIALIZING REMOTE WIPE
   ==============================================================
   CIM Session          : Created
   MDM Instance         : Found

   [RUN] EXECUTING WIPE
   ==============================================================
   Status               : Invoking doWipeMethod...
   Result               : Wipe initiated successfully

   [OK] FINAL STATUS
   ==============================================================
   REMOTE WIPE INITIATED - DEVICE WILL RESET

   [OK] SCRIPT COMPLETE
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.0.3 Updated to two-line ASCII console output style
 2026-01-17 v1.0.2 Fixed framework compliance: header format, section names,
                   removed param() blocks, added missing README sections
 2025-12-23 v1.0.1 Updated to Limehawk Script Framework
 2024-12-01 v1.0.0 Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title, [string]$status = "INFO")
    Write-Host ""
    Write-Host ("[$status] $title")
    Write-Host ("=" * 62)
}

function PrintKV($label, $value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    # MDM Configuration
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_RemoteWipe"
    $methodName = "doWipeMethod"

    Write-Section "INITIALIZING REMOTE WIPE" "WARN"
    Write-Host ""
    Write-Host " *** WARNING: THIS WILL ERASE ALL DATA ON THIS DEVICE ***"
    Write-Host " *** THIS ACTION CANNOT BE UNDONE ***"
    Write-Host ""

    # Create CIM session
    $session = New-CimSession -ErrorAction Stop

    if (-not $session) {
        PrintKV "CIM Session" "FAILED"
        throw "Failed to create CIM session"
    }

    PrintKV "CIM Session" "Created"

    # Get MDM_RemoteWipe instance
    $instance = Get-CimInstance -Namespace $namespaceName -ClassName $className `
        -Filter "ParentID='./Vendor/MSFT' and InstanceID='RemoteWipe'" -ErrorAction Stop

    if (-not $instance) {
        PrintKV "MDM Instance" "NOT FOUND"
        throw "MDM_RemoteWipe instance not found. Device may not be MDM enrolled."
    }

    PrintKV "MDM Instance" "Found"

    # Create method parameters
    $params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
    $param = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create("param", "", "String", "In")
    $params.Add($param)

    # Execute wipe
    Write-Section "EXECUTING WIPE" "RUN"

    PrintKV "Status" "Invoking doWipeMethod..."

    $result = $session.InvokeMethod($namespaceName, $instance, $methodName, $params)

    # Check result
    switch ($result.ReturnValue) {
        0 {
            PrintKV "Result" "Wipe initiated successfully"

            Write-Section "FINAL STATUS" "OK"
            Write-Host " REMOTE WIPE INITIATED - DEVICE WILL RESET"
            Write-Host ""
            Write-Host " The device will restart and begin the factory reset process."
            Write-Host " All data will be permanently erased."

            Write-Section "SCRIPT COMPLETE" "OK"
            exit 0
        }
        default {
            PrintKV "Result" "FAILED (Return code: $($result.ReturnValue))"

            Write-Section "FINAL STATUS" "ERROR"
            Write-Host " REMOTE WIPE FAILED"

            Write-Section "SCRIPT COMPLETE" "ERROR"
            exit 1
        }
    }
}
catch {
    Write-Section "ERROR OCCURRED" "ERROR"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Host ""
    Write-Host " Common causes:"
    Write-Host "  - Device is not MDM enrolled"
    Write-Host "  - Device is not Azure AD joined"
    Write-Host "  - Insufficient permissions"
    Write-Host "  - MDM policies not configured"
    Write-Section "SCRIPT COMPLETE" "ERROR"
    exit 1
}
finally {
    # Clean up CIM session
    if ($session) {
        Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
    }
}
