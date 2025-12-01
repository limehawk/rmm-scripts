$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : DNSFilter Agent Uninstall                                       v1.0.0
FILE   : dnsfilter_uninstall.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Completely removes DNSFilter agent from a Windows system including:
    - Uninstalling the MSI package
    - Stopping and removing services
    - Deleting installation folders
    - Cleaning up registry keys
    - Resetting DNS settings to DHCP
    - Flushing DNS cache

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Uninstalls DNS Agent via WMI if installed
    2. Stops and deletes related Windows services
    3. Removes installation folders
    4. Cleans up registry keys
    5. Resets all NICs to use DHCP for DNS
    6. Flushes DNS cache

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges

SECURITY NOTES:
    - No secrets in logs
    - Requires elevated privileges
    - Resets DNS to DHCP (may affect connectivity)

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ UNINSTALLING DNS AGENT ]
    --------------------------------------------------------------
    DNS Agent            : Found
    Uninstall            : SUCCESS

    [ REMOVING SERVICES ]
    --------------------------------------------------------------
    DNS Agent            : Stopped and deleted
    DNSFilter Agent      : Not found (skipped)

    [ REMOVING FOLDERS ]
    --------------------------------------------------------------
    C:\Program Files\DNS Agent : Removed

    [ CLEANING REGISTRY ]
    --------------------------------------------------------------
    HKLM:\SOFTWARE\DNSAgent : Removed

    [ RESETTING DNS ]
    --------------------------------------------------------------
    Ethernet             : Reset to DHCP
    Wi-Fi                : Reset to DHCP
    DNS Cache            : Flushed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
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
    $errorCount = 0

    # Uninstall DNS Agent MSI
    Write-Section "UNINSTALLING DNS AGENT"

    $dnsAgent = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'DNS Agent' }

    if ($dnsAgent) {
        PrintKV "DNS Agent" "Found"
        $result = $dnsAgent.Uninstall()

        if ($result.ReturnValue -eq 0) {
            PrintKV "Uninstall" "SUCCESS"
        } else {
            PrintKV "Uninstall" "FAILED (code $($result.ReturnValue))"
            $errorCount++
        }
    } else {
        PrintKV "DNS Agent" "Not installed (skipped)"
    }

    # Remove Services
    Write-Section "REMOVING SERVICES"

    $services = @("DNS Agent", "DNSFilter Agent")
    foreach ($svc in $services) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            sc.exe delete "$svc" | Out-Null
            PrintKV $svc "Stopped and deleted"
        } else {
            PrintKV $svc "Not found (skipped)"
        }
    }

    # Remove Folders
    Write-Section "REMOVING FOLDERS"

    $paths = @(
        "C:\Program Files\DNS Agent",
        "C:\Program Files\DNSFilter"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            PrintKV $path "Removed"
        } else {
            PrintKV $path "Not found (skipped)"
        }
    }

    # Clean Registry
    Write-Section "CLEANING REGISTRY"

    $regKeys = @(
        "HKLM:\SOFTWARE\DNSAgent",
        "HKLM:\SOFTWARE\DNSFilter"
    )
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            PrintKV $key "Removed"
        } else {
            PrintKV $key "Not found (skipped)"
        }
    }

    # Reset DNS Settings
    Write-Section "RESETTING DNS"

    $interfaces = Get-DnsClient -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -ne $null }

    if ($interfaces) {
        foreach ($iface in $interfaces) {
            Set-DnsClientServerAddress -InterfaceAlias $iface.InterfaceAlias -ResetServerAddresses -ErrorAction SilentlyContinue
            PrintKV $iface.InterfaceAlias "Reset to DHCP"
        }
    } else {
        PrintKV "Interfaces" "No DNS interfaces found"
    }

    # Flush DNS Cache
    Clear-DnsClientCache
    PrintKV "DNS Cache" "Flushed"

    # Final Status
    Write-Section "FINAL STATUS"

    if ($errorCount -eq 0) {
        Write-Host " SCRIPT SUCCEEDED"
    } else {
        Write-Host " SCRIPT COMPLETED WITH $errorCount ERROR(S)"
    }

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
