$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : WebView2 Repair Install                                      v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\webview2_repair_install.ps1
================================================================================
 FILE     : webview2_repair_install.ps1
 DESCRIPTION : Detects and repairs broken Microsoft Edge WebView2 Runtime installs
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Detects broken installations of the Microsoft Edge WebView2 Runtime where
   the registry still references a version that no longer exists on disk, and
   repairs them by removing stale ClientState keys and reinstalling the current
   Evergreen Runtime via Microsoft's official bootstrapper.

 DATA SOURCES & PRIORITY

   - Registry (HKLM 64-bit, HKLM 32-bit, HKCU) ClientState keys for the
     WebView2 Runtime GUID {F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
   - Filesystem verification of the Application\<version> install folder
   - Microsoft Evergreen bootstrapper (go.microsoft.com fwlink)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $downloadUrl    : URL of the Evergreen WebView2 bootstrapper
     - $forceReinstall : If $true, remove registry keys and reinstall even
                         when the existing install appears healthy

 SETTINGS

   Configuration defaults:
     - Download URL    : https://go.microsoft.com/fwlink/p/?LinkId=2124703
     - Force Reinstall : false

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates input parameters
   2. Detects existing WebView2 install across HKLM 64-bit, HKLM 32-bit, HKCU
   3. Verifies the on-disk install folder matches the registry version
   4. If broken (or force), removes stale ClientState registry keys
   5. Downloads the Evergreen bootstrapper to TEMP
   6. Runs the bootstrapper silently with /silent /install
   7. Re-verifies the install (registry + filesystem)
   8. Cleans up the installer

 PREREQUISITES

   - Windows PowerShell 5.1 or later
   - Administrator privileges (required for HKLM key removal and system-wide install)
   - Internet connectivity to go.microsoft.com

 SECURITY NOTES

   - No secrets in logs
   - Downloads only from the official Microsoft fwlink endpoint
   - Registry modifications limited to the WebView2 Runtime ClientState GUID

 ENDPOINTS

   - https://go.microsoft.com/fwlink/p/?LinkId=2124703 - Evergreen bootstrapper

 EXIT CODES

   0 = Success (WebView2 installed and verified)
   1 = Failure (download, install, or post-install verification failed)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Download URL    : https://go.microsoft.com/fwlink/p/?LinkId=2124703
     Force Reinstall : False
     Inputs validated successfully

   [INFO] DETECTION
   ==============================================================
     Scope    : HKLM (64-bit)
     Version  : 120.0.2210.91
     Folder   : C:\Program Files (x86)\Microsoft\EdgeWebView\Application\120.0.2210.91
     Status   : BROKEN (registry version, folder missing)

   [RUN] CLEANUP
   ==============================================================
     Removing stale ClientState registry key...
     Registry cleanup completed

   [RUN] DOWNLOAD
   ==============================================================
     Downloading WebView2 bootstrapper...
     Download completed successfully

   [RUN] INSTALLATION
   ==============================================================
     Running bootstrapper silently...
     Installer exit code : 0
     Installation completed successfully

   [INFO] VERIFICATION
   ==============================================================
     Scope    : HKLM (64-bit)
     Version  : 124.0.2478.97
     Folder   : C:\Program Files (x86)\Microsoft\EdgeWebView\Application\124.0.2478.97
     Status   : HEALTHY

   [RUN] CLEANUP
   ==============================================================
     Removing installer file...
     Cleanup completed

   [OK] FINAL STATUS
   ==============================================================
     Result : SUCCESS
     WebView2 Runtime installed and verified

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-11 v1.0.0 Initial release - detect and repair broken WebView2 installs, install Evergreen Runtime
================================================================================
#>

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$downloadUrl    = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$forceReinstall = $false

Set-StrictMode -Version Latest

# ==============================================================================
# CONSTANTS
# ==============================================================================
$webview2Guid    = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$regPath64       = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\$webview2Guid"
$regPath32       = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\ClientState\$webview2Guid"
$regPathUser     = "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\ClientState\$webview2Guid"
$installerPath   = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Download URL is required"
}

if ($forceReinstall -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Force Reinstall must be a boolean"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host "  Download URL    : $downloadUrl"
Write-Host "  Force Reinstall : $forceReinstall"
Write-Host "  Inputs validated successfully"

# ==============================================================================
# HELPERS
# ==============================================================================

function Get-WebView2Install {
    # Returns a hashtable describing the highest-priority install found, or $null.
    # Priority: HKLM 64-bit > HKLM 32-bit > HKCU.
    $candidates = @(
        @{ Scope = 'HKLM (64-bit)'; RegPath = $regPath64; BaseDir = (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application') }
        @{ Scope = 'HKLM (32-bit)'; RegPath = $regPath32; BaseDir = (Join-Path $env:ProgramFiles 'Microsoft\EdgeWebView\Application') }
        @{ Scope = 'HKCU';          RegPath = $regPathUser; BaseDir = (Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeWebView\Application') }
    )

    foreach ($c in $candidates) {
        if (Test-Path $c.RegPath) {
            $pv = $null
            try {
                $props = Get-ItemProperty -Path $c.RegPath -ErrorAction Stop
                if ($props.PSObject.Properties.Name -contains 'pv') {
                    $pv = $props.pv
                }
            } catch {
                $pv = $null
            }

            if (-not [string]::IsNullOrWhiteSpace($pv)) {
                $folder = Join-Path $c.BaseDir $pv
                $folderExists = Test-Path $folder
                return @{
                    Scope        = $c.Scope
                    RegPath      = $c.RegPath
                    Version      = $pv
                    Folder       = $folder
                    FolderExists = $folderExists
                }
            }
        }
    }

    return $null
}

# ==============================================================================
# DETECTION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] DETECTION"
Write-Host "=============================================================="

$detected = Get-WebView2Install
$needsRepair = $false

if ($null -eq $detected) {
    Write-Host "  Status   : NOT INSTALLED"
    $needsRepair = $true
} else {
    Write-Host "  Scope    : $($detected.Scope)"
    Write-Host "  Version  : $($detected.Version)"
    Write-Host "  Folder   : $($detected.Folder)"
    if ($detected.FolderExists) {
        Write-Host "  Status   : HEALTHY"
        if ($forceReinstall) {
            Write-Host "  Note     : Force Reinstall is enabled - will reinstall anyway"
            $needsRepair = $true
        }
    } else {
        Write-Host "  Status   : BROKEN (registry version, folder missing)"
        $needsRepair = $true
    }
}

if (-not $needsRepair) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Result : SUCCESS"
    Write-Host "  WebView2 Runtime is already installed and healthy"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

# ==============================================================================
# CLEANUP (STALE REGISTRY)
# ==============================================================================

if ($null -ne $detected -and (-not $detected.FolderExists -or $forceReinstall)) {
    Write-Host ""
    Write-Host "[RUN] CLEANUP"
    Write-Host "=============================================================="

    try {
        Write-Host "  Removing stale ClientState registry key..."
        Write-Host "  Path : $($detected.RegPath)"
        Remove-Item -Path $detected.RegPath -Recurse -Force -ErrorAction Stop
        Write-Host "  Registry cleanup completed"
    } catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "  Failed to remove stale registry key"
        Write-Host "  Path  : $($detected.RegPath)"
        Write-Host "  Error : $($_.Exception.Message)"
        Write-Host ""
        Write-Host "[ERROR] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 1
    }
}

# ==============================================================================
# DOWNLOAD
# ==============================================================================

Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="

try {
    Write-Host "  Downloading WebView2 bootstrapper..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    if (-not (Test-Path $installerPath)) {
        throw "Installer file was not downloaded"
    }

    Write-Host "  Download completed successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to download WebView2 bootstrapper"
    Write-Host "  Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

try {
    Write-Host "  Running bootstrapper silently..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/silent", "/install" -Wait -PassThru -NoNewWindow
    Write-Host "  Installer exit code : $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "Bootstrapper failed with exit code: $($process.ExitCode)"
    }

    Write-Host "  Installation completed successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to install WebView2 Runtime"
    Write-Host "  Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# VERIFICATION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] VERIFICATION"
Write-Host "=============================================================="

$verified = Get-WebView2Install

if ($null -eq $verified) {
    Write-Host "  Status   : NOT FOUND"
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Post-install verification failed - no registry entry detected"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host "  Scope    : $($verified.Scope)"
Write-Host "  Version  : $($verified.Version)"
Write-Host "  Folder   : $($verified.Folder)"

if (-not $verified.FolderExists) {
    Write-Host "  Status   : BROKEN (folder still missing after install)"
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Post-install verification failed - install folder missing"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host "  Status   : HEALTHY"

# ==============================================================================
# CLEANUP
# ==============================================================================

Write-Host ""
Write-Host "[RUN] CLEANUP"
Write-Host "=============================================================="
Write-Host "  Removing installer file..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "  Cleanup completed"

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result : SUCCESS"
Write-Host "  WebView2 Runtime installed and verified"

# ==============================================================================
# SCRIPT COMPLETED
# ==============================================================================

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
