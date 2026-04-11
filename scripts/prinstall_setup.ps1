$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Setup v0.3.0
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_setup.ps1
FILE    : prinstall_setup.ps1
DESCRIPTION : Installs or uninstalls prinstall from GitHub releases
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Installs or uninstalls prinstall. Install mode downloads the latest release
   from GitHub and extracts the binary to C:\ProgramData\prinstall\. Uninstall
   mode removes the binary and install directory. Prinstall is a CLI/TUI tool
   for discovering network printers, matching drivers, and installing them.

 DATA SOURCES & PRIORITY
   1) GitHub Releases API (latest release metadata)
   2) GitHub release asset (prinstall-windows-amd64.zip)

 REQUIRED INPUTS
   - $actionInput : 'yes' to install, 'no' to uninstall (SuperOps: $InstallYesUninstallNo)
   - $repoOwner   : GitHub repository owner
   - $repoName    : GitHub repository name
   - $installDir  : Directory to install/uninstall prinstall.exe

 SETTINGS
   - Downloads latest release automatically via GitHub API
   - Extracts ZIP to install directory
   - Verifies binary by running prinstall --version
   - Uninstall removes entire install directory

 BEHAVIOR
   Install:
   1. Validates input parameters
   2. Queries GitHub Releases API for latest version
   3. Downloads the release ZIP asset
   4. Extracts prinstall.exe to install directory
   5. Verifies the binary runs successfully
   6. Cleans up temporary files

   Uninstall:
   1. Validates input parameters
   2. Removes install directory and all contents

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - Internet connectivity to github.com (install only)

 SECURITY NOTES
   - No secrets in logs
   - Downloads only from official GitHub releases

 ENDPOINTS
   - https://api.github.com/repos/limehawk/prinstall/releases/latest
   - https://github.com/limehawk/prinstall/releases/download/

 EXIT CODES
   - 0 = Success
   - 1 = Failure

 EXAMPLE RUN (install)

   [INFO] INPUT VALIDATION
   ==============================================================
   Action          : install
   Repo            : limehawk/prinstall
   Install Dir     : C:\ProgramData\prinstall
   Inputs validated successfully

   [RUN] FETCH LATEST RELEASE
   ==============================================================
   API endpoint    : https://api.github.com/repos/limehawk/prinstall/releases/latest
   Latest version  : v0.2.0
   Asset           : prinstall-windows-amd64.zip
   Asset size      : 3.37 MB

   [RUN] DOWNLOAD
   ==============================================================
   Downloading prinstall-windows-amd64.zip...
   Download completed successfully

   [RUN] INSTALL
   ==============================================================
   Extracting to C:\ProgramData\prinstall...
   Extraction complete

   [RUN] VERIFY
   ==============================================================
   prinstall 0.2.0
   Binary verified successfully

   [RUN] CLEANUP
   ==============================================================
   Removed temporary files

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Version         : v0.2.0
   Location        : C:\ProgramData\prinstall\prinstall.exe

   [OK] SCRIPT COMPLETED
   ==============================================================

 EXAMPLE RUN (uninstall)

   [INFO] INPUT VALIDATION
   ==============================================================
   Action          : uninstall
   Install Dir     : C:\ProgramData\prinstall
   Inputs validated successfully

   [RUN] UNINSTALL
   ==============================================================
   Removing C:\ProgramData\prinstall...
   Directory removed

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Action          : Prinstall uninstalled

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-11 v0.3.0 Realign version scheme with prinstall app version (was v1.2.1).
                  No functional changes — GitHub releases API already pulls the
                  latest version automatically.
2026-03-25 v1.2.1 Rename runtime var to YourActionHere, accept install/uninstall directly
2026-03-25 v1.2.0 Use SuperOps runtime variable for install/uninstall
2026-03-25 v1.1.1 Fix curl stderr triggering ErrorActionPreference Stop
2026-03-25 v1.1.0 Add uninstall action mode
2026-03-25 v1.0.0 Initial release - prinstall setup via GitHub releases
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$actionInput = "$InstallYesUninstallNo"   # 'yes' = install, 'no' = uninstall
$repoOwner  = 'limehawk'
$repoName   = 'prinstall'
$installDir = "$env:ProgramData\prinstall"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($actionInput) -or $actionInput -eq '$' + 'InstallYesUninstallNo') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$InstallYesUninstallNo was not replaced. Use 'yes' or 'no'."
}

# Map yes/no to install/uninstall
$action = switch ($actionInput.Trim().ToLower()) {
    'yes' { 'install' }
    'no'  { 'uninstall' }
    default {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Must be 'yes' (install) or 'no' (uninstall), got: $actionInput"
        ''
    }
}

if ($action -eq 'install') {
    if ([string]::IsNullOrWhiteSpace($repoOwner)) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Repository owner is required"
    }

    if ([string]::IsNullOrWhiteSpace($repoName)) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Repository name is required"
    }
}

if ([string]::IsNullOrWhiteSpace($installDir)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Install directory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

Write-Host "Action          : $action"
if ($action -eq 'install') {
    Write-Host "Repo            : $repoOwner/$repoName"
}
Write-Host "Install Dir     : $installDir"
Write-Host "Inputs validated successfully"

# ============================================================================
# UNINSTALL PATH
# ============================================================================
if ($action -eq 'uninstall') {
    Write-Host ""
    Write-Host "[RUN] UNINSTALL"
    Write-Host "=============================================================="

    if (-not (Test-Path $installDir)) {
        Write-Host "Directory does not exist, nothing to remove"
    } else {
        try {
            Remove-Item -Path $installDir -Recurse -Force
            Write-Host "Removing $installDir..."
            Write-Host "Directory removed"
        } catch {
            Write-Host ""
            Write-Host "[ERROR] ERROR OCCURRED"
            Write-Host "=============================================================="
            Write-Host "Failed to remove $installDir"
            Write-Host "Error : $($_.Exception.Message)"
            exit 1
        }
    }

    # Clean up the firewall rule so uninstall leaves no state behind
    try {
        $rule = Get-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
            Write-Host "Removed firewall rule 'Prinstall (mDNS discovery)'"
        }
    } catch {
        Write-Host "Warning: could not remove firewall rule: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Action          : Prinstall uninstalled"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

# ============================================================================
# FETCH LATEST RELEASE
# ============================================================================
Write-Host ""
Write-Host "[RUN] FETCH LATEST RELEASE"
Write-Host "=============================================================="

$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
Write-Host "API endpoint    : $apiUrl"

try {
    $releaseJson = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'prinstall-setup/1.0' }
    $tagName = $releaseJson.tag_name

    $asset = $releaseJson.assets | Where-Object { $_.name -eq 'prinstall-windows-amd64.zip' }
    if (-not $asset) {
        throw "Asset 'prinstall-windows-amd64.zip' not found in release $tagName"
    }

    $downloadUrl = $asset.browser_download_url
    $assetSize = [math]::Round($asset.size / 1MB, 2)

    Write-Host "Latest version  : $tagName"
    Write-Host "Asset           : $($asset.name)"
    Write-Host "Asset size      : $assetSize MB"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to fetch release info from GitHub API"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="

$tempDir = "$env:TEMP\prinstall_setup"
$zipPath = "$tempDir\prinstall-windows-amd64.zip"

if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

try {
    Write-Host "Downloading $($asset.name)..."

    $curlPath = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curlPath) {
        & $curlPath --silent --show-error --fail -L -o $zipPath $downloadUrl
    } else {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    }

    if (-not (Test-Path $zipPath)) {
        throw "ZIP file was not downloaded"
    }

    Write-Host "Download completed successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to download release asset"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# INSTALL
# ============================================================================
Write-Host ""
Write-Host "[RUN] INSTALL"
Write-Host "=============================================================="

try {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    Write-Host "Extracting to $installDir..."
    Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
    Write-Host "Extraction complete"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to extract archive"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# VERIFY
# ============================================================================
Write-Host ""
Write-Host "[RUN] VERIFY"
Write-Host "=============================================================="

$exePath = "$installDir\prinstall.exe"

if (-not (Test-Path $exePath)) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "prinstall.exe not found at $exePath after extraction"
    exit 1
}

try {
    $versionOutput = & $exePath --version 2>&1
    Write-Host $versionOutput
    Write-Host "Binary verified successfully"
} catch {
    Write-Host ""
    Write-Host "[WARN] VERIFICATION"
    Write-Host "=============================================================="
    Write-Host "Binary exists but --version check failed"
    Write-Host "Error : $($_.Exception.Message)"
}

# ============================================================================
# FIREWALL
# ============================================================================
# prinstall 0.3.1+ runs an mDNS browse pass as part of `scan`. Multicast
# responses come back on UDP 5353 and hit Windows Firewall on first run —
# interactive users see a UAC-style prompt, SYSTEM-context RMM runs just
# get silently blocked with no way to click through. Pre-create a rule
# keyed to the binary path so the mDNS traffic flows without friction.
Write-Host ""
Write-Host "[RUN] FIREWALL"
Write-Host "=============================================================="

try {
    $existing = Get-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName 'Prinstall (mDNS discovery)' -ErrorAction SilentlyContinue
    }
    New-NetFirewallRule `
        -DisplayName 'Prinstall (mDNS discovery)' `
        -Description 'Allow prinstall.exe to receive mDNS multicast responses on UDP 5353 for network printer discovery.' `
        -Direction Inbound `
        -Action Allow `
        -Program $exePath `
        -Protocol UDP `
        -LocalPort 5353 `
        -Profile Any `
        -Enabled True | Out-Null
    Write-Host "Created firewall rule 'Prinstall (mDNS discovery)'"
} catch {
    Write-Host "Warning: could not create firewall rule: $($_.Exception.Message)"
    Write-Host "         First interactive scan will prompt; SYSTEM-context scans may be blocked."
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[RUN] CLEANUP"
Write-Host "=============================================================="

try {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed temporary files"
} catch {
    Write-Host "Warning: Could not remove temp files at $tempDir"
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status          : Success"
Write-Host "Version         : $tagName"
Write-Host "Location        : $exePath"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
