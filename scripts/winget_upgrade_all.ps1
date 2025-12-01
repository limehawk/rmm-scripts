$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Winget Upgrade All                                             v1.0.0
FILE   : winget_upgrade_all.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Upgrades all winget-managed packages to their latest versions. Includes
    logging and automatic cleanup of old log files.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Checks Windows version requirements
    2. Locates winget executable in WindowsApps
    3. Runs winget upgrade --all with silent options
    4. Logs output to Windows temp directory
    5. Cleans up logs older than 14 days

PREREQUISITES:
    - Windows 10 1809+ or Windows 11 or Server 2022
    - Administrator privileges
    - winget (App Installer) installed

SECURITY NOTES:
    - No secrets in logs
    - Accepts all package agreements automatically

EXIT CODES:
    0 = Success
    1 = Failure (system requirements not met)

EXAMPLE RUN:
    [ SYSTEM CHECK ]
    --------------------------------------------------------------
    Windows Version : 10.0.22631
    Product Type : Workstation
    Requirements met

    [ UPGRADE ]
    --------------------------------------------------------------
    Locating winget executable...
    Running winget upgrade --all...
    [Upgrade output...]
    Upgrade completed

    [ LOG CLEANUP ]
    --------------------------------------------------------------
    Cleaning up logs older than 14 days...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Log file : C:\Windows\temp\winget-upgrade-log_2024-12-01.txt

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# SYSTEM CHECK
# ============================================================================
Write-Host ""
Write-Host "[ SYSTEM CHECK ]"
Write-Host "--------------------------------------------------------------"

$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$version = [Version]$osInfo.Version
$productType = $osInfo.ProductType

Write-Host "Windows Version : $version"
Write-Host "Product Type : $(if ($productType -eq 1) { 'Workstation' } elseif ($productType -eq 3) { 'Server' } else { 'Unknown' })"

$meetsRequirements = ($productType -eq 1 -and $version -ge [Version]"10.0.17763") -or
                     ($productType -eq 3 -and $version -ge [Version]"10.0.20348")

if (-not $meetsRequirements) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "System does not meet minimum requirements"
    Write-Host "Requires: Windows 10 1809+, Windows 11, or Server 2022"
    exit 1
}

Write-Host "Requirements met"

# ============================================================================
# UPGRADE
# ============================================================================
Write-Host ""
Write-Host "[ UPGRADE ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Locating winget executable..."
    Set-Location "C:\Program Files\WindowsApps\"

    $installer = "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
    $appxDirs = Get-ChildItem $installer -ErrorAction SilentlyContinue

    if (-not $appxDirs) {
        throw "Could not find winget installation directory"
    }

    $appx = if ($appxDirs.Count -gt 1) { $appxDirs[1] } else { $appxDirs }
    Set-Location $appx

    $logPath = "$env:windir\temp\"
    $logFile = "winget-upgrade-log_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".txt"
    $fullLogPath = Join-Path -Path $logPath -ChildPath $logFile

    Write-Host "Running winget upgrade --all..."
    .\winget.exe upgrade --all --silent --include-unknown --include-pinned --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-File -FilePath $fullLogPath -Append

    Get-Content -Path $fullLogPath | Where-Object {
        $_ -notmatch "^\s*([/\-\|\\])" -and
        $_ -notmatch "\sMB" -and
        $_ -notmatch "%" -and
        $_.Trim() -ne ""
    } | ForEach-Object { Write-Host $_ }

    Write-Host "Upgrade completed"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to run winget upgrade"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# LOG CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ LOG CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Cleaning up logs older than 14 days..."
Get-ChildItem -Path $logPath -Filter "winget-upgrade-log_*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "Cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Log file : $fullLogPath"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
