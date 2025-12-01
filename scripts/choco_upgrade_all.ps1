$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Chocolatey Upgrade All                                         v1.0.0
FILE   : choco_upgrade_all.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Upgrades all Chocolatey-managed packages to their latest versions.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Checks if Chocolatey is installed
    2. Runs choco upgrade all with auto-confirmation
    3. Reports final status

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Chocolatey package manager installed

SECURITY NOTES:
    - No secrets in logs

EXIT CODES:
    0 = Success
    1 = Failure (Chocolatey not installed)

EXAMPLE RUN:
    [ CHOCOLATEY CHECK ]
    --------------------------------------------------------------
    Checking for Chocolatey...
    Chocolatey is installed

    [ UPGRADE ]
    --------------------------------------------------------------
    Upgrading all Chocolatey packages...
    [Chocolatey output...]
    Upgrade completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    All packages upgraded

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# CHOCOLATEY CHECK
# ============================================================================
Write-Host ""
Write-Host "[ CHOCOLATEY CHECK ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Checking for Chocolatey..."

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Chocolatey is not installed on this system"
    Write-Host "Install Chocolatey first: https://chocolatey.org/install"
    exit 1
}

Write-Host "Chocolatey is installed"

# ============================================================================
# UPGRADE
# ============================================================================
Write-Host ""
Write-Host "[ UPGRADE ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Upgrading all Chocolatey packages..."
choco upgrade all -y
Write-Host "Upgrade completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "All packages upgraded"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
