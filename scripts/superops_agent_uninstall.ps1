<#
 ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
 ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
 ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
 ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
 ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
 ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SuperOps Agent Uninstall (Windows)                            v1.1.2
 AUTHOR   : Limehawk.io
 DATE      : August 2026
 USAGE    : .\superops_agent_uninstall.ps1
================================================================================
 FILE     : superops_agent_uninstall.ps1
DESCRIPTION : Uninstalls SuperOps RMM agent using official or registry method
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Uninstalls the SuperOps RMM agent from Windows systems. Attempts to use the
 vendor's official uninstall program first, then falls back to registry-based
 MSI uninstallation if the official uninstaller is not found.

 DATA SOURCES & PRIORITY
 1) SuperOps uninstall program (C:\Program Files\SuperOps\uninstall.exe)
 2) Windows Registry (HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall)
 3) Windows Registry 32-bit (HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall)

 REQUIRED INPUTS
 None - Script will automatically detect installed SuperOps agent

 SETTINGS
 - SuperOpsInstallPaths : List of common installation directories to check
 - UninstallRegistryPaths : Registry paths to search for uninstall strings
 - ProductNamePattern : Pattern to match SuperOps product names
 - SilentUninstallArgs : Arguments for silent MSI uninstall

 BEHAVIOR
 - Searches for SuperOps uninstall program in common installation directories
 - If found, executes vendor's official uninstaller
 - If not found, searches registry for MSI uninstall information
 - Executes MSI uninstall with silent parameters
 - Reports progress and status to stdout
 - Exits with code 0 on success, 1 on failure

 PREREQUISITES
 - Windows PowerShell 5.1 or later
 - Administrator privileges (required for uninstallation)
 - SuperOps RMM agent currently installed

 SECURITY NOTES
 - No secrets hardcoded
 - No network calls required
 - Requires administrator elevation
 - Uses vendor's official uninstall method when available
 - Falls back to standard MSI uninstall procedures

 ENDPOINTS
 None - Local operation only

 EXIT CODES
 - 0 success
 - 1 failure

 EXAMPLE RUN
 [INFO] INPUT VALIDATION
 ==============================================================
 Administrator privileges: Confirmed
 Searching for SuperOps installation...

 [RUN] OPERATION
 ==============================================================
 Found SuperOps uninstall program: C:\Program Files\SuperOps\uninstall.exe
 Executing vendor uninstaller...
 Uninstallation process started
 Waiting for uninstaller to complete...
 Uninstallation completed successfully

 [OK] RESULT
 ==============================================================
 Status: Success

 [OK] FINAL STATUS
 ==============================================================
 SuperOps agent uninstalled successfully

 [INFO] SCRIPT COMPLETED
 ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-07 v1.1.2 Fix strict-mode crash in the registry fallback: uninstall
                   entries without DisplayName (patch/hotfix keys) threw
                   "property cannot be found" and aborted the search. Guard
                   DisplayName and UninstallString reads.
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-02 v1.0.0 Initial release
================================================================================
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== HARDCODED INPUTS (MANDATORY) ====
$superOpsInstallPaths = @(
    "${env:ProgramFiles}\SuperOps",
    "${env:ProgramFiles(x86)}\SuperOps",
    "${env:ProgramData}\SuperOps"
)

$uninstallRegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$productNamePattern = "*SuperOps*"
$silentUninstallArgs = "/qn /norestart"

# ==== VALIDATION ====
# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    $errorText = "This script requires administrator privileges.
Please run PowerShell as Administrator and try again."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] RESULT"
    Write-Host "=============================================================="
    Write-Host "Status: Failure"
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script cannot proceed. See error details above."
    Write-Host ""
    Write-Host "[INFO] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Administrator privileges: Confirmed"
Write-Host "Searching for SuperOps installation..."

$uninstallerFound = $false
$uninstallerPath = ""

# Search for vendor's official uninstaller
foreach ($path in $superOpsInstallPaths) {
    $uninstallExe = Join-Path $path "uninstall.exe"
    if (Test-Path $uninstallExe) {
        $uninstallerFound = $true
        $uninstallerPath = $uninstallExe
        Write-Host "Found vendor uninstaller: $uninstallerPath"
        break
    }
}

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    if ($uninstallerFound) {
        # Method 1: Use vendor's official uninstaller
        Write-Host "Executing vendor uninstaller..."
        Write-Host "Command: $uninstallerPath"

        $process = Start-Process -FilePath $uninstallerPath -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Host "Vendor uninstaller completed successfully"
        } else {
            $errorOccurred = $true
            $errorText = "Vendor uninstaller exited with code: $($process.ExitCode)"
        }

    } else {
        # Method 2: Registry-based MSI uninstall
        Write-Host "Vendor uninstaller not found, searching registry for MSI uninstall information..."

        $uninstallInfo = $null
        foreach ($regPath in $uninstallRegistryPaths) {
            if (Test-Path $regPath) {
                # Guard the property reads: patch/hotfix registry entries have no
                # DisplayName, and strict mode throws on missing properties.
                $apps = Get-ChildItem $regPath | Get-ItemProperty |
                    Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like $productNamePattern }
                if ($apps) {
                    $uninstallInfo = $apps | Select-Object -First 1
                    break
                }
            }
        }

        if ($uninstallInfo) {
            Write-Host "Found SuperOps installation: $($uninstallInfo.DisplayName)"

            if ($uninstallInfo.PSObject.Properties['UninstallString'] -and $uninstallInfo.UninstallString) {
                $uninstallString = $uninstallInfo.UninstallString
                Write-Host "Uninstall string: $uninstallString"

                # Parse MSI uninstall string
                if ($uninstallString -match 'msiexec\.exe\s+/[IX]\s*(\{[A-F0-9\-]+\})') {
                    $productCode = $matches[1]
                    $msiArgs = "/x $productCode $silentUninstallArgs"

                    Write-Host "Executing MSI uninstall..."
                    Write-Host "Command: msiexec.exe $msiArgs"

                    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

                    if ($process.ExitCode -eq 0) {
                        Write-Host "MSI uninstallation completed successfully"
                    } else {
                        $errorOccurred = $true
                        $errorText = "MSI uninstaller exited with code: $($process.ExitCode)"
                    }
                } else {
                    # Direct execution of uninstall string
                    Write-Host "Executing uninstall command directly..."

                    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString`" $silentUninstallArgs" -Wait -PassThru -NoNewWindow

                    if ($process.ExitCode -eq 0) {
                        Write-Host "Uninstallation completed successfully"
                    } else {
                        $errorOccurred = $true
                        $errorText = "Uninstaller exited with code: $($process.ExitCode)"
                    }
                }
            } else {
                $errorOccurred = $true
                $errorText = "Found SuperOps installation but no UninstallString in registry"
            }
        } else {
            $errorOccurred = $true
            $errorText = "SuperOps installation not found in registry.
Searched paths:
$($uninstallRegistryPaths -join "`n")

The agent may not be installed, or may have been manually removed."
        }
    }

} catch {
    $errorOccurred = $true
    $errorText = "Uninstallation failed with error: $($_.Exception.Message)"
}

# ==== OUTPUT RESULTS ====
if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] RESULT"
} else {
    Write-Host "[OK] RESULT"
}
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Status: Failure"
} else {
    Write-Host "Status: Success"
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] FINAL STATUS"
} else {
    Write-Host "[OK] FINAL STATUS"
}
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "SuperOps agent uninstallation failed. See error details above."
} else {
    Write-Host "SuperOps agent uninstalled successfully"
}

Write-Host ""
Write-Host "[INFO] SCRIPT COMPLETED"
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
