$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : WindowsApps Orphan Cleanup                                   v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windowsapps_orphan_cleanup.ps1
================================================================================
 FILE     : windowsapps_orphan_cleanup.ps1
 DESCRIPTION : Cleans orphaned/deleted Windows Store (AppX) packages under WindowsApps
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Cleans residual Microsoft Store / UWP packages left under
 C:\Program Files\WindowsApps\Deleted after uninstall. Runs the native
 AppxCleanupOrphanPackages routine, optionally removes still-registered
 packages matching a name filter (e.g. DuckDuckGo), and reports leftover
 paths. Use after AV/EDR kills leftovers in WindowsApps\Deleted.

 DATA SOURCES & PRIORITY

 1) SuperOps runtime variables (optional package filter and reboot flag)
 2) Get-AppxPackage / Get-AppxProvisionedPackage for registered packages
 3) Filesystem under Program Files\WindowsApps\Deleted for residual folders
 4) AppxDeploymentClient.dll AppxCleanupOrphanPackages for native cleanup

 REQUIRED INPUTS

 - $packageFilter : Optional AppX name substring (SuperOps $YourPackageFilterHere).
                    Empty = system-wide orphan cleanup only. Example: DuckDuckGo
 - $rebootAfter   : Optional yes/no (SuperOps $YourRebootAfterHere). Default no.
                    A reboot finishes emptying many Deleted folder entries.

 SETTINGS

 - WindowsApps Deleted path: $env:ProgramFiles\WindowsApps\Deleted
 - Does not take ownership of WindowsApps or force-delete protected folders
 - Reboot delay: 60 seconds when reboot is requested
 - Package removal uses Remove-AppxPackage -AllUsers when filter is set

 BEHAVIOR

 1. Validates admin privileges and normalizes optional inputs
 2. Reports size/count of WindowsApps\Deleted before cleanup
 3. If package filter set: lists and removes matching registered AppX packages
 4. If package filter set: removes matching provisioned packages
 5. Runs rundll32 AppxDeploymentClient.dll,AppxCleanupOrphanPackages
 6. Reports Deleted folder status after cleanup (and filter matches if any)
 7. Optionally schedules a reboot to complete Deleted cleanup

 PREREQUISITES

 - Windows 10/11
 - PowerShell 5.1 or later
 - Administrator / SYSTEM privileges
 - AppxDeploymentClient.dll present (standard on Windows)

 SECURITY NOTES

 - No secrets in logs
 - Does not take ownership of WindowsApps (avoids breaking Store installs)
 - Package filter limits removal scope when provided
 - Reboot is opt-in only

 ENDPOINTS

 - Not applicable (local system operations only)

 EXIT CODES

 - 0: Success
 - 1: Failure (admin check, cleanup error)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Package Filter    : DuckDuckGo
 Reboot After      : No
 Running as Admin  : True
 Deleted Path      : C:\Program Files\WindowsApps\Deleted

 [RUN] PRE-CLEANUP STATUS
 ==============================================================
 Deleted folder    : Present
 Package folders   : 3
 Total size        : 412.5 MB
 Filter matches    : 1
 Match             : DuckDuckGo.DesktopBrowser_0.161.2.0_x64__...

 [RUN] REMOVE REGISTERED PACKAGES
 ==============================================================
 Registered matches: 0
 No registered packages matching filter

 [RUN] REMOVE PROVISIONED PACKAGES
 ==============================================================
 Provisioned matches: 0
 No provisioned packages matching filter

 [RUN] ORPHAN PACKAGE CLEANUP
 ==============================================================
 Invoking AppxCleanupOrphanPackages...
 Orphan cleanup invoked successfully

 [INFO] POST-CLEANUP STATUS
 ==============================================================
 Deleted folder    : Present
 Package folders   : 3
 Total size        : 412.5 MB
 Filter matches    : 1
 Note              : Reboot recommended to finish emptying Deleted

 [OK] FINAL STATUS
 ==============================================================
 Status            : Success
 Orphan cleanup    : Invoked
 Packages removed  : 0
 Reboot scheduled  : No

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-17 v1.0.0 Initial release - Appx orphan cleanup + optional package filter
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""
$packagesRemoved = 0
$provisionedRemoved = 0
$orphanCleanupOk = $false
$rebootScheduled = $false

# ==== HARDCODED INPUTS ====
$packageFilter = "$YourPackageFilterHere"
$rebootAfter = "$YourRebootAfterHere"

Set-StrictMode -Version Latest

# ==== HELPERS ====
function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{
        'info'  = 'INFO'
        'run'   = 'RUN'
        'ok'    = 'OK'
        'warn'  = 'WARN'
        'error' = 'ERROR'
    }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N1} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
    return "$Bytes bytes"
}

function Test-IsPlaceholder {
    param([string]$Value, [string]$PlaceholderName)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    if ($Value -eq ('$' + $PlaceholderName)) { return $true }
    return $false
}

function Get-DeletedFolderReport {
    param(
        [string]$DeletedPath,
        [string]$Filter
    )

    $report = [ordered]@{
        Exists        = $false
        FolderCount   = 0
        TotalBytes    = [long]0
        FilterMatches = @()
        AccessError   = $null
    }

    if (-not (Test-Path -LiteralPath $DeletedPath)) {
        return $report
    }

    $report.Exists = $true

    try {
        $items = Get-ChildItem -LiteralPath $DeletedPath -Force -ErrorAction Stop
        $dirs = @($items | Where-Object { $_.PSIsContainer })
        $report.FolderCount = $dirs.Count

        foreach ($dir in $dirs) {
            try {
                $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($null -eq $size) { $size = 0 }
                $report.TotalBytes += [long]$size
            } catch {
                # size is best-effort under ACL restrictions
            }

            if (-not [string]::IsNullOrWhiteSpace($Filter) -and $dir.Name -like "*$Filter*") {
                $report.FilterMatches += $dir.Name
            }
        }
    } catch {
        $report.AccessError = $_.Exception.Message
    }

    return $report
}

function Write-DeletedReport {
    param(
        $Report,
        [string]$Filter
    )

    if (-not $Report.Exists) {
        Write-Host "Deleted folder    : Not present"
        return
    }

    Write-Host "Deleted folder    : Present"
    if ($Report.AccessError) {
        Write-Host "Access            : Restricted - $($Report.AccessError)"
        return
    }

    Write-Host "Package folders   : $($Report.FolderCount)"
    Write-Host "Total size        : $(Format-Bytes -Bytes $Report.TotalBytes)"

    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        Write-Host "Filter matches    : $($Report.FilterMatches.Count)"
        foreach ($match in $Report.FilterMatches) {
            Write-Host "Match             : $match"
        }
    }
}

# ==== NORMALIZE OPTIONAL INPUTS ====
if (Test-IsPlaceholder -Value $packageFilter -PlaceholderName 'YourPackageFilterHere') {
    $packageFilter = ''
} else {
    $packageFilter = $packageFilter.Trim()
}

if (Test-IsPlaceholder -Value $rebootAfter -PlaceholderName 'YourRebootAfterHere') {
    $rebootAfter = 'no'
} else {
    $rebootAfter = $rebootAfter.Trim().ToLowerInvariant()
}

$doReboot = $false
switch -Regex ($rebootAfter) {
    '^(y|yes|true|1)$' { $doReboot = $true }
    '^(n|no|false|0)$' { $doReboot = $false }
    default {
        $errorOccurred = $true
        $errorText += "- RebootAfter must be yes/no (got: $rebootAfter)"
    }
}

# ==== ADMIN CHECK ====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host "Script requires Administrator or SYSTEM privileges."
    Write-Host "Relaunch elevated or run from RMM as SYSTEM."
    exit 1
}

if ($errorOccurred) {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host $errorText
    exit 1
}

$deletedPath = Join-Path $env:ProgramFiles 'WindowsApps\Deleted'

Write-Section -Type 'info' -Name 'INPUT VALIDATION'
Write-Host "Package Filter    : $(if ([string]::IsNullOrWhiteSpace($packageFilter)) { '(none - system-wide orphan cleanup)' } else { $packageFilter })"
Write-Host "Reboot After      : $(if ($doReboot) { 'Yes' } else { 'No' })"
Write-Host "Running as Admin  : $isAdmin"
Write-Host "Deleted Path      : $deletedPath"

try {
    Write-Section -Type 'run' -Name 'PRE-CLEANUP STATUS'
    $before = Get-DeletedFolderReport -DeletedPath $deletedPath -Filter $packageFilter
    Write-DeletedReport -Report $before -Filter $packageFilter

    if (-not [string]::IsNullOrWhiteSpace($packageFilter)) {
        Write-Section -Type 'run' -Name 'REMOVE REGISTERED PACKAGES'
        $registered = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$packageFilter*" -or $_.PackageFullName -like "*$packageFilter*" })

        Write-Host "Registered matches: $($registered.Count)"
        if ($registered.Count -eq 0) {
            Write-Host "No registered packages matching filter"
        } else {
            foreach ($pkg in $registered) {
                try {
                    Write-Host "Removing          : $($pkg.PackageFullName)"
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    $packagesRemoved++
                    Write-Host "Removed           : $($pkg.PackageFullName)"
                } catch {
                    Write-Host "FAILED            : $($pkg.PackageFullName) - $($_.Exception.Message)"
                }
            }
        }

        Write-Section -Type 'run' -Name 'REMOVE PROVISIONED PACKAGES'
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like "*$packageFilter*" -or
                $_.PackageName -like "*$packageFilter*"
            })

        Write-Host "Provisioned matches: $($provisioned.Count)"
        if ($provisioned.Count -eq 0) {
            Write-Host "No provisioned packages matching filter"
        } else {
            foreach ($pkg in $provisioned) {
                try {
                    Write-Host "Removing          : $($pkg.PackageName)"
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                    $provisionedRemoved++
                    Write-Host "Removed           : $($pkg.PackageName)"
                } catch {
                    Write-Host "FAILED            : $($pkg.PackageName) - $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Section -Type 'info' -Name 'PACKAGE FILTER'
        Write-Host "No package filter set - skipping targeted AppX removal"
    }

    Write-Section -Type 'run' -Name 'ORPHAN PACKAGE CLEANUP'
    Write-Host "Invoking AppxCleanupOrphanPackages..."
    $rundll = Join-Path $env:SystemRoot 'System32\rundll32.exe'
    $dll = Join-Path $env:SystemRoot 'System32\AppxDeploymentClient.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        throw "AppxDeploymentClient.dll not found at $dll"
    }

    $proc = Start-Process -FilePath $rundll -ArgumentList 'AppxDeploymentClient.dll,AppxCleanupOrphanPackages' -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0 -and $null -ne $proc.ExitCode) {
        Write-Host "rundll32 exit code: $($proc.ExitCode) (may still have succeeded)"
    }
    $orphanCleanupOk = $true
    Write-Host "Orphan cleanup invoked successfully"

    Write-Section -Type 'info' -Name 'POST-CLEANUP STATUS'
    $after = Get-DeletedFolderReport -DeletedPath $deletedPath -Filter $packageFilter
    Write-DeletedReport -Report $after -Filter $packageFilter
    if ($after.Exists -and $after.FolderCount -gt 0) {
        Write-Host "Note              : Reboot recommended to finish emptying Deleted"
    }

    if ($doReboot) {
        Write-Section -Type 'run' -Name 'SCHEDULE REBOOT'
        Write-Host "Scheduling reboot in 60 seconds..."
        shutdown.exe /r /t 60 /c "WindowsApps orphan cleanup completed"
        $rebootScheduled = $true
        Write-Host "Reboot scheduled  : Yes (cancel with shutdown /a if needed)"
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
    if ($_.InvocationInfo) {
        $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
        $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber)"
    }
}

if ($errorOccurred) {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host $errorText
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "Status            : Failure"
    exit 1
}

Write-Section -Type 'ok' -Name 'FINAL STATUS'
Write-Host "Status            : Success"
Write-Host "Orphan cleanup    : $(if ($orphanCleanupOk) { 'Invoked' } else { 'Skipped' })"
Write-Host "Packages removed  : $packagesRemoved"
Write-Host "Provisioned removed: $provisionedRemoved"
Write-Host "Reboot scheduled  : $(if ($rebootScheduled) { 'Yes' } else { 'No' })"

Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
exit 0
