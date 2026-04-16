$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Setup v0.4.18
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
   from GitHub, extracts the binary to C:\ProgramData\prinstall\, and adds
   that directory to the machine PATH so techs can run `prinstall scan`
   (etc.) without a full path. Uninstall mode removes the binary, the install
   directory, the firewall rule, and the PATH entry. Prinstall is a CLI/TUI
   tool for discovering network printers, matching drivers, and installing them.

 DATA SOURCES & PRIORITY
   1) GitHub Releases API (latest release metadata)
   2) GitHub release asset (prinstall-windows-amd64.zip)

 REQUIRED INPUTS
   - $actionInput : 'install' or 'uninstall' (SuperOps: $InstallOrUninstall)
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
   6. Pre-creates Windows Firewall rule for mDNS (UDP 5353)
   7. Adds install directory to machine PATH (idempotent)
   8. Cleans up temporary files

   Uninstall:
   1. Validates input parameters
   2. Removes install directory and all contents
   3. Removes the 'Prinstall (mDNS discovery)' firewall rule
   4. Removes the install directory from the machine PATH

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - Internet connectivity to github.com (install only)

 SECURITY NOTES
   - No secrets in logs
   - Downloads only from official GitHub releases
   - Modifies the machine PATH env var (HKLM\...\Session Manager\Environment)
     — reverted on uninstall

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

   [RUN] UNBLOCK
   ==============================================================
   Stripped Mark-of-the-Web from 4 file(s)

   [RUN] VERIFY
   ==============================================================
   prinstall 0.2.0
   Binary verified successfully

   [RUN] FIREWALL
   ==============================================================
   Created firewall rule 'Prinstall (mDNS discovery)'

   [RUN] PATH
   ==============================================================
   Added C:\ProgramData\prinstall to machine PATH

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
   Removed firewall rule 'Prinstall (mDNS discovery)'
   Removed C:\ProgramData\prinstall from machine PATH

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Action          : Prinstall uninstalled

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-16 v0.4.18 Strip Mark-of-the-Web from extracted files in a dedicated
                   [RUN] UNBLOCK step between INSTALL and VERIFY. Without
                   this, the unsigned prinstall.exe trips SmartScreen /
                   Defender SmartScreen on the very next invocation because
                   the downloaded file is tagged as internet-sourced
                   (Zone.Identifier ADS = Internet zone). The new step pipes
                   every extracted file through Unblock-File and prints the
                   count for the audit trail. Smart App Control on full-enforce
                   boxes still blocks unsigned exes — that requires a real
                   signing cert and is tracked separately. Also picks up
                   prinstall v0.4.18 (driver add auto-picks unambiguous
                   input).
2026-04-15 v0.4.17 VERIFY step no longer reports "Status: Success" when the
                   binary is blocked by Application Control / AppLocker. On
                   WDAC-enforced boxes the extract + firewall + PATH steps
                   all complete, but `--version` hits a native-command
                   exception. Script now:
                     1. Tracks a $verifyOk flag through to FINAL STATUS
                     2. Matches the WDAC signature ("Application Control",
                        "AppLocker", "blocked this file") and emits an
                        ERROR branch pointing at prinstall_trust_codesign.ps1
                     3. Exits 1 on any verify failure so RMM flags it for
                        remediation instead of burying the fault
                   Other verify failures (rare) get a WARN + exit 1. Happy
                   path unchanged — still Success + exit 0.
2026-04-14 v0.4.0 Add install dir to machine PATH during install; remove on
                  uninstall. Techs can now run `prinstall scan` (etc.) from
                  any new shell without the full path. The current process
                  PATH is patched in-memory too so follow-up commands in the
                  same SuperOps run work immediately.
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
$actionInput = "$InstallOrUninstall"   # 'install' or 'uninstall'
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

if ([string]::IsNullOrWhiteSpace($actionInput) -or $actionInput -eq '$' + 'InstallOrUninstall') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$InstallOrUninstall was not replaced. Use 'install' or 'uninstall'."
}

# Accept literal 'install'/'uninstall' plus the legacy 'yes'/'no' forms
# for any SuperOps jobs that haven't updated their runtime variable yet.
$action = switch ($actionInput.Trim().ToLower()) {
    'install'   { 'install' }
    'uninstall' { 'uninstall' }
    'yes'       { 'install' }
    'no'        { 'uninstall' }
    default {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Must be 'install' or 'uninstall', got: $actionInput"
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

    # Strip the install dir from the machine PATH so uninstall leaves no
    # stale entries behind. Case-insensitive, tolerant of trailing slashes.
    try {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if (-not $machinePath) { $machinePath = '' }
        $entries  = $machinePath -split ';' | Where-Object { $_ -ne '' }
        $target   = $installDir.TrimEnd('\')
        $filtered = @($entries | Where-Object { $_.TrimEnd('\') -ine $target })

        if ($entries.Count -ne $filtered.Count) {
            [Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'Machine')
            Write-Host "Removed $installDir from machine PATH"
        }
    } catch {
        Write-Host "Warning: could not update machine PATH: $($_.Exception.Message)"
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
# UNBLOCK
# ============================================================================
# Strip Mark-of-the-Web (Zone.Identifier ADS) from every extracted file.
# Without this, the unsigned prinstall.exe trips SmartScreen / Defender
# SmartScreen on the very next invocation ("Windows protected your PC")
# because the file is tagged as internet-sourced. Unblock-File removes the
# ADS so Windows treats the binary as locally trusted.
# Smart App Control on full-enforce boxes still blocks unsigned exes —
# that needs a real signing cert and is tracked separately.
Write-Host ""
Write-Host "[RUN] UNBLOCK"
Write-Host "=============================================================="

try {
    $files = Get-ChildItem -Path $installDir -Recurse -File
    $files | Unblock-File
    Write-Host "Stripped Mark-of-the-Web from $($files.Count) file(s)"
} catch {
    Write-Host "[WARN] Failed to strip Mark-of-the-Web: $($_.Exception.Message)"
    Write-Host "       prinstall.exe may trigger SmartScreen on first run."
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

# Track verify outcome so FINAL STATUS can reflect reality instead of
# reporting "Success" on WDAC-blocked boxes where the binary was extracted
# but cannot execute. Firewall + PATH steps still run below so a later
# signing-cert deployment leaves no cleanup behind.
$verifyOk = $false
$blockedByPolicy = $false
$verifyError = ''

try {
    $versionOutput = & $exePath --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $versionOutput
        Write-Host "Binary verified successfully"
        $verifyOk = $true
    } else {
        $verifyError = ($versionOutput | Out-String).Trim()
    }
} catch {
    $verifyError = $_.Exception.Message
    # Windows wraps WDAC / AppLocker denials in a NativeCommandException
    # whose message contains one of these phrases. Match broadly so Smart
    # App Control denials ("blocked this file") and classic AppLocker
    # denials ("Application Control") both trip the same branch.
    if ($verifyError -match 'Application Control|AppLocker|blocked this file') {
        $blockedByPolicy = $true
    }
}

if (-not $verifyOk) {
    Write-Host ""
    if ($blockedByPolicy) {
        Write-Host "[ERROR] VERIFICATION"
        Write-Host "=============================================================="
        Write-Host "Binary was blocked by Application Control / AppLocker policy:"
        Write-Host "  $verifyError"
        Write-Host ""
        Write-Host "Files are in place but prinstall.exe cannot execute until the fleet"
        Write-Host "trusts the code-signing cert. To fix:"
        Write-Host "  1. Ensure this release is signed (selfsign setup in prinstall repo docs)"
        Write-Host "  2. Run prinstall_trust_codesign.ps1 on this endpoint to import the cert"
        Write-Host "  3. Re-run prinstall_setup.ps1"
    } else {
        Write-Host "[WARN] VERIFICATION"
        Write-Host "=============================================================="
        Write-Host "Binary exists but --version check failed"
        Write-Host "Error : $verifyError"
    }
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
# PATH
# ============================================================================
# Add the install dir to the machine PATH so techs can run `prinstall scan`
# (etc.) without typing the full path. New shells pick it up immediately;
# the current process PATH is patched in-memory too so any follow-up
# commands in this same SuperOps run can use the bare command.
Write-Host ""
Write-Host "[RUN] PATH"
Write-Host "=============================================================="

try {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not $machinePath) { $machinePath = '' }
    $entries = $machinePath -split ';' | Where-Object { $_ -ne '' }
    $target  = $installDir.TrimEnd('\')

    if ($entries | Where-Object { $_.TrimEnd('\') -ieq $target }) {
        Write-Host "Install dir already on machine PATH"
    } else {
        $newPath = (@($entries) + $installDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
        Write-Host "Added $installDir to machine PATH"
    }

    # Patch the running process too so the rest of this job can use the
    # bare `prinstall` command without a reboot or new session.
    if (($env:Path -split ';') -notcontains $installDir) {
        $env:Path = "$env:Path;$installDir"
    }
} catch {
    Write-Host "Warning: could not update machine PATH: $($_.Exception.Message)"
    Write-Host "         Techs will need to use the full path to prinstall.exe."
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
if ($verifyOk) {
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Version         : $tagName"
    Write-Host "Location        : $exePath"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} elseif ($blockedByPolicy) {
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Blocked by Application Control policy"
    Write-Host "Version         : $tagName (files extracted, binary cannot execute)"
    Write-Host "Location        : $exePath"
    Write-Host "Action needed   : Import code-signing cert via prinstall_trust_codesign.ps1"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
} else {
    Write-Host "[WARN] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Installed but verification failed"
    Write-Host "Version         : $tagName"
    Write-Host "Location        : $exePath"
    Write-Host "Warning         : --version check did not succeed; see earlier output"
    Write-Host ""
    Write-Host "[WARN] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
