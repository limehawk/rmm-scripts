$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : GCPW Cleanup                                                    v1.0.0
FILE   : gcpw_cleanup.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Removes Google Credential Provider for Windows (GCPW) registry keys and
    folders to allow for a clean reinstallation or complete removal.

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Deletes GCPW-related registry keys
    2. Deletes Chrome enrollment registry keys
    3. Removes GCPW policy and credential folders
    4. Reports results

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges

SECURITY NOTES:
    - No secrets in logs
    - Requires elevated privileges
    - Does NOT uninstall GCPW itself (use Programs & Features for that)

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ CLEANING REGISTRY KEYS ]
    --------------------------------------------------------------
    Chrome Enrollment    : Removed
    GCPW                 : Removed
    CloudManagement      : Removed

    [ CLEANING FOLDERS ]
    --------------------------------------------------------------
    Policies Folder      : Removed
    Credential Provider  : Removed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps (converted from batch)
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

function Remove-RegistryKeyIfExists {
    param([string]$Path, [string]$Label)

    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            PrintKV $Label "Removed"
            return $true
        } catch {
            PrintKV $Label "FAILED - $($_.Exception.Message)"
            return $false
        }
    } else {
        PrintKV $Label "Not found (skipped)"
        return $true
    }
}

function Remove-FolderIfExists {
    param([string]$Path, [string]$Label)

    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            PrintKV $Label "Removed"
            return $true
        } catch {
            PrintKV $Label "FAILED - $($_.Exception.Message)"
            return $false
        }
    } else {
        PrintKV $Label "Not found (skipped)"
        return $true
    }
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

    # Clean Registry Keys
    Write-Section "CLEANING REGISTRY KEYS"

    $registryKeys = @(
        @{ Path = "HKLM:\SOFTWARE\Google\Chrome\Enrollment"; Label = "Chrome Enrollment" },
        @{ Path = "HKLM:\SOFTWARE\Google\GCPW"; Label = "GCPW" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Google\Update\ClientState\{430FD4D0-B729-4F61-AA34-91526481799D}"; Label = "GCPW ClientState" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Google\Update\ClientState\{32987697-A14E-4B89-84D6-630D5431E831}"; Label = "Chrome ClientState" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Google\Enrollment"; Label = "Google Enrollment" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Google\CloudManagement"; Label = "CloudManagement" }
    )

    foreach ($key in $registryKeys) {
        if (-not (Remove-RegistryKeyIfExists -Path $key.Path -Label $key.Label)) {
            $errorCount++
        }
    }

    # Clean Folders
    Write-Section "CLEANING FOLDERS"

    $folders = @(
        @{ Path = "${env:ProgramFiles(x86)}\Google\Policies\Z29vZ2xlL21hY2hpbmUtbGV2ZWwtb21haGE="; Label = "Policies (Omaha)" },
        @{ Path = "${env:ProgramFiles(x86)}\Google\Policies\CachedPolicyInfo"; Label = "CachedPolicyInfo" },
        @{ Path = "${env:ProgramData}\Google\Credential Provider"; Label = "Credential Provider" }
    )

    foreach ($folder in $folders) {
        if (-not (Remove-FolderIfExists -Path $folder.Path -Label $folder.Label)) {
            $errorCount++
        }
    }

    # Final Status
    Write-Section "FINAL STATUS"

    if ($errorCount -eq 0) {
        Write-Host " SCRIPT SUCCEEDED"
    } else {
        Write-Host " SCRIPT COMPLETED WITH $errorCount ERROR(S)"
    }

    Write-Host ""
    Write-Host " NOTE: This script only cleans up GCPW configuration."
    Write-Host " To fully uninstall GCPW, use Programs & Features."

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
