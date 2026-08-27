$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Software Blacklist Uninstall                                 v1.1.0
 AUTHOR   : Limehawk.io
 DATE     : August 2026
 USAGE    : .\software_blacklist_uninstall.ps1
================================================================================
 FILE     : software_blacklist_uninstall.ps1
 DESCRIPTION : Uninstalls blacklisted Windows programs in sequence and verifies each removal
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   This script removes blacklisted programs from a Windows endpoint. Add each
   DisplayName to the hardcoded list. The script checks the Uninstall registry
   for each name in order. If it finds a match, it runs a silent uninstall. It
   then checks the registry again to confirm removal.

 DATA SOURCES & PRIORITY

   1. HKLM Uninstall registry (64-bit)
   2. HKLM Wow6432Node Uninstall registry (32-bit)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $blacklistNames : DisplayName values to remove. Supports * and ? wildcards.
                         Default includes DNS Agent and *McAfee*.
     - $uninstallTimeoutSec : Max seconds to wait for each uninstall. Default 300.

 SETTINGS

   - Match is exact unless the name contains * or ?
   - QuietUninstallString is preferred
   - MSI product codes use msiexec /x /qn /norestart
   - msiexec exit 0, 1641, and 3010 count as success
   - Missing software is a skip
   - A failed uninstall does not stop the list

 BEHAVIOR

   1. Validates the hardcoded list and timeout
   2. Confirms administrator rights
   3. Reads Uninstall registry entries
   4. For each list name, finds matching DisplayName values
   5. Runs silent uninstall for each match and waits
   6. Reads the registry again to confirm the name is gone
   7. Reports removed, skipped, and failed counts

 PREREQUISITES

   - Windows PowerShell 5.1 or later
   - Administrator privileges

 SECURITY NOTES

   - No secrets in logs
   - Requires elevation
   - Removes software named in the list

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Success (removed or not installed)
   1 = Failure (validation, rights, or uninstall did not verify)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Blacklist count : 2
     Timeout seconds : 300

   [INFO] SETUP
   ==============================================================
     Administrator : Yes
     Computer      : WKSTN-01

   [RUN] UNINSTALL
   ==============================================================
     Target : DNS Agent
     Status : Found
     Method : msiexec
     Verify : Removed

   [OK] FINAL STATUS
   ==============================================================
     Removed : 1
     Skipped : 0
     Failed  : 0

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-27 v1.1.0 Add *McAfee* to the default blacklist
 2026-08-27 v1.0.0 Initial release
================================================================================
#>

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$blacklistNames = @(
    'DNS Agent',
    '*McAfee*'
)
$uninstallTimeoutSec = 300

Set-StrictMode -Version Latest

function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info' = 'INFO'; 'run' = 'RUN'; 'ok' = 'OK'; 'warn' = 'WARN'; 'error' = 'ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Get-MsiProductCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }
    if ($Text -match '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') {
        return $Matches[0]
    }
    return ''
}

function Test-NameMatch {
    param([string]$DisplayName, [string]$Pattern)
    if ($Pattern -match '[*?]') {
        return $DisplayName -like $Pattern
    }
    return $DisplayName -eq $Pattern
}

function Get-UninstallEntries {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) {
            continue
        }
        $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $item = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $item) {
                continue
            }
            $displayName = Get-Prop $item 'DisplayName'
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }
            $item
        }
    }
}

function Invoke-UninstallProcess {
    param([string]$FilePath, [string[]]$ArgumentList)
    Write-Host ("  Command : {0} {1}" -f $FilePath, ($ArgumentList -join ' '))
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -NoNewWindow
    $finished = $proc.WaitForExit($uninstallTimeoutSec * 1000)
    if (-not $finished) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Uninstall timed out after $uninstallTimeoutSec seconds"
    }
    return $proc.ExitCode
}

function Test-MsiSuccess {
    param([int]$Code)
    return ($Code -eq 0 -or $Code -eq 1641 -or $Code -eq 3010)
}

# ============================================================================
# STATE
# ============================================================================
$errorOccurred = $false
$errorText = ""
$removedCount = 0
$skippedCount = 0
$failedCount = 0

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Section 'info' 'INPUT VALIDATION'

if ($null -eq $blacklistNames -or $blacklistNames.Count -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Blacklist must contain at least one DisplayName."
}

if ($uninstallTimeoutSec -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Timeout must be a positive number of seconds."
}

Write-Host ("  Blacklist count : {0}" -f $blacklistNames.Count)
Write-Host ("  Timeout seconds : {0}" -f $uninstallTimeoutSec)

if ($errorOccurred) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host $errorText
    Write-Section 'error' 'FINAL STATUS'
    exit 1
}

Write-Host "  All required inputs are valid"

# ============================================================================
# SETUP
# ============================================================================
Write-Section 'info' 'SETUP'

$currentUser = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Administrator : No"
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  This script requires administrator privileges."
    Write-Section 'error' 'FINAL STATUS'
    exit 1
}

Write-Host "  Administrator : Yes"
Write-Host ("  Computer      : {0}" -f $env:COMPUTERNAME)

# ============================================================================
# UNINSTALL
# ============================================================================
Write-Section 'run' 'UNINSTALL'

try {
    foreach ($pattern in $blacklistNames) {
        Write-Host ("  Target : {0}" -f $pattern)

        $entries = @(Get-UninstallEntries | Where-Object { Test-NameMatch (Get-Prop $_ 'DisplayName') $pattern })
        if ($entries.Count -lt 1) {
            Write-Host "  Status : Not installed"
            $skippedCount++
            continue
        }

        foreach ($entry in $entries) {
            $displayName = Get-Prop $entry 'DisplayName'
            $quiet = Get-Prop $entry 'QuietUninstallString'
            $uninstall = Get-Prop $entry 'UninstallString'
            $productCode = Get-MsiProductCode (Get-Prop $entry 'PSChildName')
            if ([string]::IsNullOrWhiteSpace($productCode)) {
                $productCode = Get-MsiProductCode $uninstall
            }
            if ([string]::IsNullOrWhiteSpace($productCode)) {
                $productCode = Get-MsiProductCode $quiet
            }

            Write-Host ("  Found  : {0}" -f $displayName)

            try {
                $exitCode = $null
                if (-not [string]::IsNullOrWhiteSpace($productCode)) {
                    Write-Host "  Method : msiexec"
                    $exitCode = Invoke-UninstallProcess -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/x', $productCode, '/qn', '/norestart')
                    if (-not (Test-MsiSuccess $exitCode)) {
                        throw "msiexec exit code $exitCode"
                    }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($quiet)) {
                    Write-Host "  Method : QuietUninstallString"
                    $exitCode = Invoke-UninstallProcess -FilePath $env:ComSpec -ArgumentList @('/c', $quiet)
                    if ($exitCode -ne 0) {
                        throw "Quiet uninstall exit code $exitCode"
                    }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($uninstall)) {
                    Write-Host "  Method : UninstallString"
                    $exitCode = Invoke-UninstallProcess -FilePath $env:ComSpec -ArgumentList @('/c', $uninstall)
                    if ($exitCode -ne 0) {
                        throw "Uninstall exit code $exitCode"
                    }
                }
                else {
                    throw "No uninstall command found"
                }

                $stillThere = @(Get-UninstallEntries | Where-Object { (Get-Prop $_ 'DisplayName') -eq $displayName })
                if ($stillThere.Count -gt 0) {
                    throw "Registry still lists $displayName"
                }

                Write-Host "  Verify : Removed"
                $removedCount++
            }
            catch {
                Write-Host ("  Verify : Failed ({0})" -f $_.Exception.Message)
                $failedCount++
                if ($errorText.Length -gt 0) { $errorText += "`n" }
                $errorText += "- ${displayName}: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host ("  Error : {0}" -f $_.Exception.Message)
    Write-Section 'error' 'FINAL STATUS'
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ("  Removed : {0}" -f $removedCount)
Write-Host ("  Skipped : {0}" -f $skippedCount)
Write-Host ("  Failed  : {0}" -f $failedCount)

if ($failedCount -gt 0) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host $errorText
    Write-Section 'error' 'FINAL STATUS'
    Write-Host "  Result : Failure"
    exit 1
}

Write-Section 'ok' 'FINAL STATUS'
Write-Host "  Result : Success"
Write-Section 'ok' 'SCRIPT COMPLETED'
exit 0
