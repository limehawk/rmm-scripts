$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Disable Wi-Fi Adapters                                         v1.0.5
FILE   : wifi_adapters_disable.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Identifies and disables all physical and virtual Wi-Fi network adapters on
    a Windows system. Enforces a "wired-only" network policy by ensuring that
    wireless connectivity is turned off while leaving Ethernet adapters enabled.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Checks for administrative privileges
    2. Enumerates all network adapters including hidden ones
    3. Categorizes adapters as Wi-Fi, Wired, or Other
    4. Displays detailed list of all adapters for review
    5. Disables all Wi-Fi adapters
    6. Reports results

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - Get-NetAdapter cmdlet available

SECURITY NOTES:
    - No secrets in logs
    - Requires elevated privileges
    - Does not affect wired (Ethernet) adapters

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ ADAPTER DISCOVERY ]
    --------------------------------------------------------------
    Total Adapters Found     : 5
    Categorized as Wired     : 1
    Categorized as Wi-Fi     : 2

    [ PROCESSING WI-FI ADAPTERS ]
    --------------------------------------------------------------
    Adapter Name             : Wi-Fi
    ACTION                   : DISABLING
    RESULT                   : DISABLED

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Wi-Fi Adapters Disabled  : 2
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.5  Migrated from SuperOps - removed module dependency
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Section "ERROR OCCURRED"
    Write-Host " This script requires administrative privileges to run."
    Write-Section "SCRIPT HALTED"
    exit 1
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    # Discover and Categorize Adapters
    Write-Section "ADAPTER DISCOVERY"
    $allAdapters = Get-NetAdapter -IncludeHidden

    $wifiAdapters = $allAdapters | Where-Object {
        $_.InterfaceDescription -like '*Wi-Fi*' -or $_.InterfaceDescription -like '*Wireless*' -or
        $_.Name -like '*Wi-Fi*' -or $_.Name -like '*Wireless*'
    }

    $wiredAdapters = $allAdapters | Where-Object {
        $_.NdisPhysicalMediumType -eq '802_3' -or $_.InterfaceDescription -like '*Ethernet*' -or $_.Name -like '*Ethernet*'
    }

    PrintKV "Total Adapters Found" $allAdapters.Count
    PrintKV "Categorized as Wired" $wiredAdapters.Count
    PrintKV "Categorized as Wi-Fi" $wifiAdapters.Count

    # Display Detailed List for Review
    Write-Section "DETECTED NETWORK ADAPTERS"
    $wifiAdapterIds = $wifiAdapters.InstanceID
    $wiredAdapterIds = $wiredAdapters.InstanceID

    foreach ($adapter in $allAdapters) {
        $category = "OTHER"
        if ($wiredAdapterIds -contains $adapter.InstanceID) {
            $category = "WIRED (WILL BE IGNORED)"
        }
        if ($wifiAdapterIds -contains $adapter.InstanceID) {
            $category = "WI-FI (WILL BE PROCESSED)"
        }

        PrintKV "Name" $adapter.Name
        PrintKV "Description" $adapter.InterfaceDescription
        PrintKV "Status" $adapter.Status
        PrintKV "Category" $category
        Write-Host ""
    }

    # Process Wi-Fi Adapters
    Write-Section "PROCESSING WI-FI ADAPTERS"
    $disabledCount = 0

    if ($wifiAdapters.Count -eq 0) {
        Write-Host " No adapters categorized as Wi-Fi were found to process."
    }
    else {
        foreach ($adapter in $wifiAdapters) {
            $currentTarget = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue

            if (-not $currentTarget) {
                Write-Host ""
                PrintKV "Adapter Name" $adapter.Name
                PrintKV "STATUS" "SKIPPING (Adapter no longer exists)"
                continue
            }

            if ($currentTarget.Status -ne "Disabled") {
                Write-Host ""
                PrintKV "Adapter Name" $currentTarget.Name
                PrintKV "ACTION" "DISABLING"
                $currentTarget | Disable-NetAdapter -Confirm:$false
                PrintKV "RESULT" "DISABLED"
                $disabledCount++
            }
        }
        if ($disabledCount -eq 0) {
            Write-Host " All Wi-Fi adapters were already disabled or skipped."
        }
    }

    # Final Summary
    Write-Section "FINAL STATUS"
    PrintKV "Wi-Fi Adapters Disabled" $disabledCount
    PrintKV "Adapters Unchanged" ($allAdapters.Count - $disabledCount)
    Write-Host " SCRIPT SUCCEEDED"

    Write-Section "SCRIPT COMPLETED"
    exit 0
}
catch {
    Write-Section "ERROR OCCURRED"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Section "SCRIPT HALTED"
    exit 1
}
