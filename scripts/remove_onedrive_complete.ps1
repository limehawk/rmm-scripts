$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Complete OneDrive Removal v1.1.0
 VERSION  : v1.1.0
================================================================================
 FILE     : remove_onedrive_complete.ps1
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Performs a complete, multi-path uninstallation of Microsoft OneDrive with
 permanent startup suppression. Stops running processes, executes the official
 Microsoft uninstall utility against all known install paths (system and Office),
 removes scheduled tasks, and applies registry policies to prevent reinstallation.

 DATA SOURCES & PRIORITY

 1) Hardcoded OneDriveSetup.exe paths (system and Office locations)
 2) Registry keys for GPO, Explorer, and Run persistence
 3) Task Scheduler for OneDrive scheduled tasks
 4) WMI/CIM for system diagnostics

 REQUIRED INPUTS

 - No runtime parameters required
 - All operations use hardcoded paths and registry locations

 SETTINGS

 - OneDrive Setup Paths: System32, SysWOW64, Office x86, Office x64
 - Registry GPO Path: HKLM:\Software\Policies\Microsoft\Windows\OneDrive
 - Registry Explorer Path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer
 - Registry Run Key: HKCU:\Software\Microsoft\Windows\CurrentVersion\Run

 BEHAVIOR

 1. Validates administrative privileges
 2. Stops all running OneDrive processes
 3. Executes OneDriveSetup.exe /uninstall for each found path
 4. Removes all OneDrive scheduled tasks
 5. Sets HKLM GPO DisableFileSyncNGSC=1 to prevent startup for all users
 6. Removes HKCU Run key OneDrive entry
 7. Sets Explorer policy to hide OneDrive from navigation pane
 8. Reports completion status with reboot recommendation

 PREREQUISITES

 - PowerShell 5.1 or later
 - Administrator privileges required
 - No network requirements (local operations only)

 SECURITY NOTES

 - No secrets (API keys, passwords) are used or logged
 - All actions confined to local files, registry, and task scheduler
 - Registry modifications use Group Policy paths for proper enforcement

 ENDPOINTS

 - N/A (local machine only)

 EXIT CODES

 - 0 : Success - all cleanup steps completed
 - 1 : Failure - critical error (likely permission-related)

 EXAMPLE RUN

 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 Computer Name    : WKSTN-FIN-01
 Username         : SYSTEM
 Admin Privileges : Confirmed
 Paths to Check   : 4

 [ STOP PROCESSES ]
 --------------------------------------------------------------
 Stopping OneDrive processes...
 OneDrive processes terminated

 [ UNINSTALL ONEDRIVE ]
 --------------------------------------------------------------
 Checking path   : C:\Windows\SysWOW64\OneDriveSetup.exe
 Status          : Found - executing uninstall
 Result          : Uninstall command completed

 Checking path   : C:\Windows\System32\OneDriveSetup.exe
 Status          : Not found - skipping

 Checking path   : C:\Program Files\Microsoft Office\root\...
 Status          : Not found - skipping

 Checking path   : C:\Program Files (x86)\Microsoft Office\root\...
 Status          : Not found - skipping

 Uninstallers Run : 1

 [ REMOVE SCHEDULED TASKS ]
 --------------------------------------------------------------
 Removing OneDrive scheduled tasks...
 Scheduled tasks removed

 [ REGISTRY CLEANUP ]
 --------------------------------------------------------------
 Setting HKLM GPO DisableFileSyncNGSC = 1
 HKLM GPO policy applied

 Removing HKCU Run key OneDrive entry
 HKCU Run key cleaned

 Setting Explorer DisableOneDriveFileSync = 1
 Explorer policy applied

 [ FINAL STATUS ]
 --------------------------------------------------------------
 Result           : SUCCESS
 Uninstallers Run : 1
 OneDrive removal complete - reboot recommended for full cleanup

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2025-11-29 v1.1.0 Refactored to Limehawk Style A with improved validation,
                   cleaner section organization, and enhanced error handling.
 2025-09-19 v1.0.0 Initial version for complete multi-path OneDrive uninstall.
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# STATE VARIABLES
# ============================================================================

$errorOccurred = $false
$errorText     = ""
$uninstallCount = 0

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

# OneDriveSetup.exe paths across various Windows/Office installations
$oneDrivePaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:ProgramFiles\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe"
)

# Registry paths for persistence cleanup
$gpoPath      = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
$explorerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
$runKeyPath   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

# Validate admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Script must be run with Administrator privileges"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Run PowerShell as Administrator"
    Write-Host "- Deploy via RMM with SYSTEM context"
    exit 1
}

Write-Host "Computer Name    : $env:COMPUTERNAME"
Write-Host "Username         : $env:USERNAME"
Write-Host "Admin Privileges : Confirmed"
Write-Host "Paths to Check   : $($oneDrivePaths.Count)"

# ============================================================================
# STOP PROCESSES
# ============================================================================

Write-Host ""
Write-Host "[ STOP PROCESSES ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Stopping OneDrive processes..."
Stop-Process -Name "OneDrive*" -Force -ErrorAction SilentlyContinue
Write-Host "OneDrive processes terminated"

# ============================================================================
# UNINSTALL ONEDRIVE
# ============================================================================

Write-Host ""
Write-Host "[ UNINSTALL ONEDRIVE ]"
Write-Host "--------------------------------------------------------------"

foreach ($path in $oneDrivePaths) {
    Write-Host "Checking path   : $path"

    if (Test-Path $path) {
        Write-Host "Status          : Found - executing uninstall"

        try {
            $process = Start-Process -FilePath $path -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow -ErrorAction Stop
            Write-Host "Result          : Uninstall command completed (Exit: $($process.ExitCode))"
            $uninstallCount++
        } catch {
            Write-Host "Result          : Failed - $($_.Exception.Message)"
        }
    } else {
        Write-Host "Status          : Not found - skipping"
    }
    Write-Host ""
}

Write-Host "Uninstallers Run : $uninstallCount"

# ============================================================================
# REMOVE SCHEDULED TASKS
# ============================================================================

Write-Host ""
Write-Host "[ REMOVE SCHEDULED TASKS ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Removing OneDrive scheduled tasks..."

try {
    $tasks = Get-ScheduledTask -TaskName "OneDrive*" -ErrorAction SilentlyContinue
    if ($tasks) {
        $tasks | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Scheduled tasks removed : $($tasks.Count) task(s)"
    } else {
        Write-Host "No OneDrive scheduled tasks found"
    }
} catch {
    Write-Host "Task removal skipped : $($_.Exception.Message)"
}

# ============================================================================
# REGISTRY CLEANUP
# ============================================================================

Write-Host ""
Write-Host "[ REGISTRY CLEANUP ]"
Write-Host "--------------------------------------------------------------"

# HKLM GPO - Disable OneDrive file sync for all users
Write-Host "Setting HKLM GPO DisableFileSyncNGSC = 1"
try {
    if (-not (Test-Path $gpoPath)) {
        New-Item -Path $gpoPath -Force | Out-Null
    }
    Set-ItemProperty -Path $gpoPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    Write-Host "HKLM GPO policy applied"
} catch {
    Write-Host "HKLM GPO failed : $($_.Exception.Message)"
}

Write-Host ""

# HKCU Run Key - Remove OneDrive auto-start entry
Write-Host "Removing HKCU Run key OneDrive entry"
try {
    $runKeyExists = Get-ItemProperty -Path $runKeyPath -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($runKeyExists) {
        Remove-ItemProperty -Path $runKeyPath -Name "OneDrive" -Force -ErrorAction Stop
        Write-Host "HKCU Run key removed"
    } else {
        Write-Host "HKCU Run key not present - skipping"
    }
} catch {
    Write-Host "HKCU Run key removal skipped : $($_.Exception.Message)"
}

Write-Host ""

# Explorer Policy - Hide OneDrive from navigation pane
Write-Host "Setting Explorer DisableOneDriveFileSync = 1"
try {
    if (-not (Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }
    Set-ItemProperty -Path $explorerPath -Name "DisableOneDriveFileSync" -Value 1 -Type DWord -Force
    Write-Host "Explorer policy applied"
} catch {
    Write-Host "Explorer policy failed : $($_.Exception.Message)"
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Result           : SUCCESS"
Write-Host "Uninstallers Run : $uninstallCount"
Write-Host "OneDrive removal complete - reboot recommended for full cleanup"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
