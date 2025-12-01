$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : OneDrive Uninstall                                             v1.0.0
FILE   : onedrive_uninstall.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Completely removes Microsoft OneDrive from Windows. Stops processes,
    runs official uninstaller from multiple paths, removes scheduled tasks,
    and applies registry policies to prevent reinstallation.

REQUIRED INPUTS:
    None - all paths are auto-detected

BEHAVIOR:
    1. Stops all OneDrive processes
    2. Runs OneDriveSetup.exe /uninstall from multiple locations
    3. Removes OneDrive scheduled tasks
    4. Applies HKLM GPO to disable OneDrive
    5. Removes HKCU Run key entry
    6. Applies Explorer policy to hide OneDrive

PREREQUISITES:
    - Windows OS
    - Administrator privileges

SECURITY NOTES:
    - No secrets in logs
    - Modifies registry to prevent reinstallation

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ STOP PROCESSES ]
    --------------------------------------------------------------
    Stopping OneDrive processes...
    Processes stopped

    [ UNINSTALL ]
    --------------------------------------------------------------
    Running uninstaller from SysWOW64...
    Running uninstaller from System32...
    Uninstall commands executed

    [ CLEANUP TASKS ]
    --------------------------------------------------------------
    Removing OneDrive scheduled tasks...
    Tasks removed

    [ REGISTRY CLEANUP ]
    --------------------------------------------------------------
    Applying GPO to disable OneDrive...
    Removing Run key entry...
    Hiding Explorer shortcut...
    Registry cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    OneDrive removed - reboot recommended

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# ADMIN CHECK
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "This script must be run as Administrator"
    exit 1
}

# ============================================================================
# STOP PROCESSES
# ============================================================================
Write-Host ""
Write-Host "[ STOP PROCESSES ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Stopping OneDrive processes..."
Stop-Process -Name OneDrive* -Force -ErrorAction SilentlyContinue
Write-Host "Processes stopped"

# ============================================================================
# UNINSTALL
# ============================================================================
Write-Host ""
Write-Host "[ UNINSTALL ]"
Write-Host "--------------------------------------------------------------"

$oneDrivePaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:ProgramFiles\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe"
)

$uninstallCount = 0
foreach ($path in $oneDrivePaths) {
    if (Test-Path $path) {
        $location = Split-Path -Leaf (Split-Path -Parent $path)
        Write-Host "Running uninstaller from $location..."
        Start-Process $path "/uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        $uninstallCount++
    }
}

Write-Host "Uninstall commands executed : $uninstallCount"

# ============================================================================
# CLEANUP TASKS
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP TASKS ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Removing OneDrive scheduled tasks..."
Get-ScheduledTask -TaskName "OneDrive*" -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Tasks removed"

# ============================================================================
# REGISTRY CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ REGISTRY CLEANUP ]"
Write-Host "--------------------------------------------------------------"

# HKLM GPO to disable OneDrive
Write-Host "Applying GPO to disable OneDrive..."
$gpoPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $gpoPath -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $gpoPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force | Out-Null

# Remove HKCU Run key
Write-Host "Removing Run key entry..."
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "OneDrive" -ErrorAction SilentlyContinue | Out-Null

# Hide Explorer shortcut
Write-Host "Hiding Explorer shortcut..."
$explorerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
New-Item -Path $explorerPath -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $explorerPath -Name "DisableOneDriveFileSync" -Value 1 -Type DWord -Force | Out-Null

Write-Host "Registry cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "OneDrive removed - reboot recommended"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
