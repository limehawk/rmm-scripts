$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SuperOps Tray Icon Always Show                                v1.5.0
 AUTHOR   : Limehawk.io
 DATE     : August 2026
 USAGE    : .\superops_tray_icon_show_always.ps1
================================================================================
 FILE     : superops_tray_icon_show_always.ps1
DESCRIPTION : Configures Windows to always show SuperOps tray icon
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   *** MUST RUN AS LOGGED-IN USER - NOT SYSTEM ***

   Configures Windows system tray settings to always show the SuperOps RMM
   agent tray icon. This ensures the SuperOps icon remains visible in the
   system tray notification area rather than being hidden in the overflow.

   Modifies HKCU registry which is per-user. Running as SYSTEM will modify
   SYSTEM's registry, not the user's - and will have no effect.

 DATA SOURCES & PRIORITY
 1) Windows Registry (HKCU:\Control Panel\NotifyIconSettings)
 2) Hardcoded search pattern (limehawkrmm or superops)

 REQUIRED INPUTS
 None - Script automatically detects and configures SuperOps tray icon settings

 SETTINGS
 - Searches all notification icon registry entries for SuperOps-related entries
 - Sets IsPromoted=1 for matching entries (makes icon always visible)
 - Processes all users' notification area settings under HKCU context
 - Matches limehawkrmm or superops in any icon property (path or name)

 BEHAVIOR
 - Checks Windows version and exits with error on unsupported OS
 - Exits gracefully (exit 0) if registry path doesn't exist yet
 - Enumerates all subkeys in HKCU:\Control Panel\NotifyIconSettings
 - Searches each key's properties for limehawkrmm or superops
 - When a match is found, sets the IsPromoted DWORD value to 1
 - Reports each modification made to the console
 - Continues processing even if individual keys fail to read
 - No restart required - changes take effect on next tray icon update

 PREREQUISITES

   - Windows 11 (build 22000 or later) - older Windows versions not supported
   - PowerShell 5.1 or later
   - *** MUST RUN AS LOGGED-IN USER (NOT SYSTEM) ***
   - SuperOps agent must be installed (creates notification icon entries)
   - No elevation required (modifies current user's registry only)

 SECURITY NOTES
 - No secrets or credentials used
 - Only modifies current user's notification settings
 - Does not affect system-wide or other users' settings
 - Read-only access to detect SuperOps entries
 - Write access only to IsPromoted value (standard Windows setting)

 ENDPOINTS
 - N/A (local registry modification only)

 EXIT CODES
 - 0 success
 - 1 failure

 EXAMPLE RUN
 [INFO] INPUT VALIDATION
 ==============================================================
 Registry Path : HKCU:\Control Panel\NotifyIconSettings
 Search Pattern : limehawkrmm|superops

 [RUN] OPERATION
 ==============================================================
 [RUN] Scanning notification icon settings...
 Found 15 registered notification icons
 [RUN] Checking for SuperOps entries...
 [OK] Set IsPromoted=1 for key: 1234567890
 [OK] Processing complete

 [INFO] RESULT
 ==============================================================
 [OK] Status : Success
 Icons Modified : 1

 [INFO] FINAL STATUS
 ==============================================================
 [OK] SuperOps tray icon configured to always show

 [INFO] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-19 v1.5.0 Match limehawkrmm or superops (Limehawk-branded agent)
 2026-01-19 v1.4.1 Updated to two-line ASCII console output style
 2025-12-28 v1.4.0 Add OS version check - requires Windows 11 (build 22000+)
 2025-12-28 v1.3.0 Handle missing registry path gracefully (exit 0 instead of error)
 2025-12-28 v1.2.0 Added user context check, made warning more obvious
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2024-11-02 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""
$iconsFound    = 0
$iconsModified = 0

# ==== HARDCODED INPUTS (MANDATORY) ====
$notifyIconPath = "HKCU:\Control Panel\NotifyIconSettings"
$searchPattern  = '(?i)limehawkrmm|superops'

# ==== USER CONTEXT CHECK ====
Write-Host ""
Write-Host "[INFO] USER CHECK"
Write-Host "=============================================================="

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Running as : $currentUser"

if ($currentUser -match "SYSTEM$") {
    Write-Host ""
    Write-Host "[ERROR] INVALID USER CONTEXT"
    Write-Host "=============================================================="
    Write-Host "This script must run as the logged-in user, not SYSTEM"
    Write-Host ""
    Write-Host "Tray icon settings are per-user (stored in HKCU)."
    Write-Host "Running as SYSTEM modifies SYSTEM's registry, not the user's."
    Write-Host ""
    Write-Host "Solutions:"
    Write-Host "  - RMM: Run as 'logged-in user' instead of 'SYSTEM'"
    Write-Host "  - GPO: Use a logon script"
    Write-Host "  - Manual: Run from user's PowerShell session"
    Write-Host ""
    Write-Host "[INFO] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
Write-Host "[OK] Context is valid (not SYSTEM)"

# ==== OS VERSION CHECK ====
$osVersion = [System.Environment]::OSVersion.Version
$osBuild = $osVersion.Build
$minBuild = 22000  # Windows 11

Write-Host ""
Write-Host "[INFO] OS CHECK"
Write-Host "=============================================================="
Write-Host "OS Build   : $osBuild"

if ($osBuild -lt $minBuild) {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Host "OS Name    : $($osInfo.Caption)"
    Write-Host ""
    Write-Host "[ERROR] UNSUPPORTED OS"
    Write-Host "=============================================================="
    Write-Host "This script requires Windows 11 (build $minBuild or later)."
    Write-Host ""
    Write-Host "Your system (build $osBuild) uses a different registry structure"
    Write-Host "for notification icon settings that this script does not support."
    Write-Host ""
    Write-Host "Affected OS versions:"
    Write-Host "  - Windows 10 (all versions)"
    Write-Host "  - Windows Server 2016, 2019, 2022"
    Write-Host ""
    Write-Host "Workaround for older systems:"
    Write-Host "  Right-click the taskbar > Taskbar settings > Notification area"
    Write-Host "  > Select which icons appear on the taskbar > Toggle SuperOps on"
    Write-Host ""
    Write-Host "[INFO] RESULT"
    Write-Host "=============================================================="
    Write-Host "[ERROR] Status : Not Supported (OS too old)"
    Write-Host ""
    Write-Host "[INFO] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
Write-Host "[OK] OS version supported"

# ==== VALIDATION ====
if (-not (Test-Path $notifyIconPath)) {
    Write-Host ""
    Write-Host "[WARN] REGISTRY PATH NOT FOUND"
    Write-Host "=============================================================="
    Write-Host "Path: $notifyIconPath"
    Write-Host ""
    Write-Host "This registry key is created by Windows when notification icons"
    Write-Host "are first displayed. It may not exist yet if:"
    Write-Host "  - SuperOps agent hasn't shown a tray icon yet"
    Write-Host "  - User hasn't logged in with a GUI session"
    Write-Host "  - No apps have registered notification icons"
    Write-Host ""
    Write-Host "[INFO] RESULT"
    Write-Host "=============================================================="
    Write-Host "[OK] Status : Skipped (no icons registered yet)"
    Write-Host ""
    Write-Host "[INFO] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Registry Path  : $notifyIconPath"
Write-Host "Search Pattern : $searchPattern"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    Write-Host "[RUN] Scanning notification icon settings..."

    # Get all subkeys
    $subKeys = Get-ChildItem -Path $notifyIconPath -ErrorAction Stop

    $iconsFound = $subKeys.Count
    Write-Host "Found $iconsFound registered notification icons"
    Write-Host "[RUN] Checking for SuperOps entries..."

    foreach ($key in $subKeys) {
        try {
            $values = Get-ItemProperty -Path $key.PSPath -ErrorAction Stop

            $matchFound = $false
            foreach ($property in $values.PSObject.Properties) {
                if ($property.Value -is [string] -and $property.Value -match $searchPattern) {
                    $matchFound = $true
                    break
                }
            }

            # Set IsPromoted to 1 if we find a match
            if ($matchFound) {
                try {
                    Set-ItemProperty -Path $key.PSPath -Name "IsPromoted" -Value 1 -Type DWord -ErrorAction Stop
                    Write-Host "[OK] Set IsPromoted=1 for key: $($key.PSChildName)"
                    $iconsModified++
                } catch {
                    Write-Host "[WARN] Failed to set IsPromoted for key $($key.PSChildName): $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Host "[WARN] Could not read key $($key.PSChildName): $($_.Exception.Message)"
            # Continue processing other keys
        }
    }

    Write-Host "[OK] Processing complete"

    if ($iconsModified -eq 0) {
        Write-Host "[WARN] No SuperOps entries found. This could mean:"
        Write-Host "  - SuperOps agent is not installed"
        Write-Host "  - SuperOps tray icon has not been displayed yet"
        Write-Host "  - SuperOps tray icon is already configured to always show"
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

Write-Host ""
Write-Host "[INFO] RESULT"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "[ERROR] Status         : Failure"
} else {
    Write-Host "[OK] Status         : Success"
}
Write-Host "Icons Found    : $iconsFound"
Write-Host "Icons Modified : $iconsModified"

Write-Host ""
Write-Host "[INFO] FINAL STATUS"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "[ERROR] Failed to configure SuperOps tray icon settings. See error details above."
} else {
    if ($iconsModified -gt 0) {
        Write-Host "[OK] SuperOps tray icon configured to always show"
    } else {
        Write-Host "[WARN] No SuperOps tray icon entries found to configure"
    }
}

Write-Host ""
Write-Host "[INFO] SCRIPT COMPLETED"
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
