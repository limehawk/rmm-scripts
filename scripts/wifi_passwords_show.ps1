$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Show Saved Wi-Fi Passwords                                     v1.0.0
FILE   : wifi_passwords_show.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Retrieves and displays all saved Wi-Fi network profiles and their passwords
    stored on the Windows system. Useful for recovering forgotten passwords or
    auditing saved wireless credentials.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Queries all saved wireless network profiles
    2. Retrieves the password (key content) for each profile
    3. Displays results in a formatted table

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges (for key retrieval)
    - Wireless adapter present (or previously present)

SECURITY NOTES:
    - This script displays sensitive credential information
    - Run only on systems you are authorized to audit
    - Passwords are retrieved from Windows credential store

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ RETRIEVING WI-FI PROFILES ]
    --------------------------------------------------------------

    SSID_NAME          WIFI_PASSWORD
    ---------          -------------
    HomeNetwork        MySecurePass123
    OfficeWiFi         Corp0r@teKey!
    GuestNetwork       guest2024

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : 3 network(s) found

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# RETRIEVE WI-FI PROFILES
# ============================================================================
Write-Host ""
Write-Host "[ RETRIEVING WI-FI PROFILES ]"
Write-Host "--------------------------------------------------------------"

try {
    $profiles = (netsh wlan show profiles) | Select-String "\:(.+)$" | ForEach-Object {
        $_.Matches.Groups[1].Value.Trim()
    }

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Host "No saved Wi-Fi profiles found"
        Write-Host ""
        Write-Host "[ FINAL STATUS ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Result : No networks found"
        exit 0
    }

    $results = @()

    foreach ($profile in $profiles) {
        $password = ""

        try {
            $keyContent = (netsh wlan show profile name="$profile" key=clear) |
                Select-String "Key Content\W+\:(.+)$"

            if ($keyContent) {
                $password = $keyContent.Matches.Groups[1].Value.Trim()
            }
        }
        catch {
            $password = "(unable to retrieve)"
        }

        $results += [PSCustomObject]@{
            SSID_NAME     = $profile
            WIFI_PASSWORD = if ($password) { $password } else { "(no password)" }
        }
    }

    Write-Host ""
    $results | Format-Table -AutoSize
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to retrieve Wi-Fi profiles"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : $($results.Count) network(s) found"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
