$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Clear Windows 10 Start Menu Tiles                              v1.0.0
FILE   : start_menu_clear_tiles.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Removes all default pinned app tiles from the Windows 10 Start menu by
    modifying the registry. Restarts Explorer to apply changes immediately.
    Creates a clean Start menu without pre-configured tiles.

REQUIRED INPUTS:
    None - operates on current user's Start menu configuration

BEHAVIOR:
    1. Modifies Start menu tile collection registry data
    2. Stops Explorer process to release lock on settings
    3. Waits briefly for system to stabilize
    4. Restarts Explorer automatically
    5. Opens Start menu to initialize new layout

PREREQUISITES:
    - Windows 10 (does not apply to Windows 11)
    - Must run in user context (not SYSTEM) to affect user's Start menu
    - Registry access to HKCU

SECURITY NOTES:
    - No secrets in logs
    - Only modifies current user's Start menu
    - Registry modification is reversible

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Target User : DOMAIN\username
    Registry Path : HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\...

    [ MODIFYING START MENU ]
    --------------------------------------------------------------
    Reading current tile configuration...
    Applying clean tile layout...
    Registry updated successfully

    [ RESTARTING EXPLORER ]
    --------------------------------------------------------------
    Stopping Explorer process...
    Waiting for system to stabilize...
    Explorer restarted successfully
    Initializing Start menu...

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Start menu tiles have been cleared

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$registryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\*start.tilegrid`$windows.data.curatedtilecollection.tilecollection\Current"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Target User   : $currentUser"

# Check if running on Windows 10
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Build -ge 22000) {
    Write-Host ""
    Write-Host "[ WARNING ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Windows 11 detected - this script is designed for Windows 10"
    Write-Host "Windows 11 uses a different Start menu system"
}

# ============================================================================
# MODIFY START MENU
# ============================================================================
Write-Host ""
Write-Host "[ MODIFYING START MENU ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Reading current tile configuration..."

    $key = Get-ItemProperty -Path $registryPath -ErrorAction Stop

    if (-not $key) {
        throw "Failed to retrieve Start menu layout from the registry"
    }

    Write-Host "Applying clean tile layout..."

    # Create minimal tile data (clears all pinned apps)
    $data = $key.Data[0..25] + ([byte[]](202, 50, 0, 226, 44, 1, 1, 0, 0))

    Set-ItemProperty -Path $key.PSPath -Name "Data" -Type Binary -Value $data

    Write-Host "Registry updated successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to modify Start menu configuration"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# RESTART EXPLORER
# ============================================================================
Write-Host ""
Write-Host "[ RESTARTING EXPLORER ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Stopping Explorer process..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

    Write-Host "Waiting for system to stabilize..."
    Start-Sleep -Seconds 3

    # Explorer should restart automatically, but let's make sure
    $explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue
    if (-not $explorer) {
        Write-Host "Starting Explorer..."
        Start-Process explorer.exe
        Start-Sleep -Seconds 2
    }

    Write-Host "Explorer restarted successfully"

    # Open Start menu to initialize the new layout
    Write-Host "Initializing Start menu..."
    Start-Sleep -Seconds 2

    $wshell = New-Object -ComObject wscript.shell
    $wshell.SendKeys('^{ESCAPE}')

    Start-Sleep -Seconds 2

    # Close Start menu
    $wshell.SendKeys('{ESCAPE}')
}
catch {
    Write-Host ""
    Write-Host "[ WARNING ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Explorer restart may have encountered issues"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host "The Start menu changes should still take effect after manual restart"
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Start menu tiles have been cleared"
Write-Host "Changes are effective immediately"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
