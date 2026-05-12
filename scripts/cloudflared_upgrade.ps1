$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Cloudflared Upgrade                                          v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\cloudflared_upgrade.ps1
================================================================================
 FILE     : cloudflared_upgrade.ps1
 DESCRIPTION : Upgrades cloudflared via winget and verifies tunnel service health
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Patches the Cloudflare.cloudflared package on a Windows endpoint via
   winget and confirms the Cloudflare Tunnel service remains healthy
   after the upgrade. Idempotent: machines without cloudflared installed
   exit 0 with a no-op.

 DATA SOURCES & PRIORITY

   1) Hardcoded script configuration (package id, service name)
   2) Local cloudflared.exe version output
   3) Winget package repository

 REQUIRED INPUTS

   None - all configuration is hardcoded

 SETTINGS

   - Package Id      : Cloudflare.cloudflared
   - Service Name    : Cloudflare Tunnel
   - Winget flags    : --exact --silent --accept-package-agreements
                       --accept-source-agreements

 BEHAVIOR

   1. Pre-checks for an existing cloudflared install (no-op exit 0 if absent)
   2. Captures current version
   3. Captures pre-upgrade service state
   4. Runs winget upgrade (treats 0x8A15002B no-applicable-update as success)
   5. Captures new version
   6. Verifies service still Running if it was Running before
   7. Reports old to new version transition

 PREREQUISITES

   - Windows 10 1809+ / Windows Server 2019+
   - SYSTEM or Administrator privileges
   - Winget installed
   - Outbound internet connectivity to Cloudflare edge (port 7844)

 SECURITY NOTES

   - No secrets in logs
   - No tokens or credentials handled by this script

 EXIT CODES

   0 = Success - upgraded, already current, or not installed
   1 = Failure - service regression detected after upgrade

 EXAMPLE RUN

   [INFO] PRE-CHECK
   ==============================================================
   Binary Present  : Yes
   Binary Path     : C:\Program Files (x86)\cloudflared\cloudflared.exe
   Old Version     : 2025.4.0
   Service State   : Running

   [INFO] WINGET CHECK
   ==============================================================
   Winget          : Available
   Version         : v1.7.10861

   [RUN] WINGET UPGRADE
   ==============================================================
   Upgrading Cloudflare.cloudflared...
   Upgrade complete

   [INFO] VERIFY
   ==============================================================
   New Version     : 2025.5.0
   Service State   : Running

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Transition      : 2025.4.0 -> 2025.5.0

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-12 v1.0.0 Initial release - cloudflared winget upgrade with health check
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================

$PackageId      = "Cloudflare.cloudflared"
$ServiceName    = "Cloudflare Tunnel"
$FallbackBinary = "C:\Program Files (x86)\cloudflared\cloudflared.exe"

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "No runtime inputs required"

# ============================================================================
# PRE-CHECK
# ============================================================================

Write-Host ""
Write-Host "[INFO] PRE-CHECK"
Write-Host "=============================================================="

$cloudflaredExe = $null
$cloudflaredCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cloudflaredCmd) {
    $cloudflaredExe = $cloudflaredCmd.Source
} elseif (Test-Path $FallbackBinary) {
    $cloudflaredExe = $FallbackBinary
}

if (-not $cloudflaredExe) {
    Write-Host "Binary Present  : No"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Result          : Nothing to upgrade (cloudflared not installed)"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

Write-Host "Binary Present  : Yes"
Write-Host "Binary Path     : $cloudflaredExe"

# Capture old version
$oldVersion = "Unknown"
try {
    $versionOutput = & $cloudflaredExe --version 2>&1
    if ($versionOutput -match '([\d]+\.[\d]+\.[\d]+)') {
        $oldVersion = $matches[1]
    }
} catch {
    $oldVersion = "Unknown"
}
Write-Host "Old Version     : $oldVersion"

# Capture pre-upgrade service state
$serviceWasPresent = $false
$serviceWasRunning = $false
$preSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($preSvc) {
    $serviceWasPresent = $true
    if ($preSvc.Status.ToString() -eq "Running") {
        $serviceWasRunning = $true
    }
    Write-Host "Service State   : $($preSvc.Status)"
} else {
    Write-Host "Service State   : Not registered"
}

# ============================================================================
# WINGET CHECK
# ============================================================================

Write-Host ""
Write-Host "[INFO] WINGET CHECK"
Write-Host "=============================================================="

$wingetPath = $null
$runAsSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")

try {
    if ($runAsSystem) {
        $resolvedPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
                        Sort-Object | Select-Object -Last 1
        if ($resolvedPath) {
            $wingetPath = Join-Path $resolvedPath.Path "winget.exe"
            if (-not (Test-Path $wingetPath)) {
                $wingetPath = $null
            }
        }
    } else {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $wingetPath = $wingetCmd.Source
        }
    }
} catch {
    $wingetPath = $null
}

if (-not $wingetPath) {
    Write-Host ""
    Write-Host "[ERROR] WINGET NOT AVAILABLE"
    Write-Host "=============================================================="
    Write-Host "Winget is not installed or not available"
    Write-Host "Run winget_setup.ps1 first to install winget"
    Write-Host ""
    exit 1
}

try {
    $versionOutput = & $wingetPath --version 2>&1
    $wingetVersion = if ($versionOutput -match 'v[\d.]+') { $matches[0] } else { "Unknown" }
} catch {
    $wingetVersion = "Unknown"
}

Write-Host "Winget          : Available"
Write-Host "Version         : $wingetVersion"

# ============================================================================
# WINGET UPGRADE
# ============================================================================

Write-Host ""
Write-Host "[RUN] WINGET UPGRADE"
Write-Host "=============================================================="
Write-Host "Upgrading $PackageId..."

$upgradeSuccess = $false
try {
    $upgradeArgs = @(
        "upgrade"
        "--exact"
        "--id", $PackageId
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    $process = Start-Process -FilePath $wingetPath -ArgumentList $upgradeArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "Upgrade complete"
        $upgradeSuccess = $true
    } elseif ($exitCode -eq -1978335189 -or $exitCode -eq 0x8A15002B) {
        # No applicable update found
        Write-Host "No applicable update (already current)"
        $upgradeSuccess = $true
    } elseif ($exitCode -eq 0x80073CF0) {
        Write-Host "Same version already installed"
        $upgradeSuccess = $true
    } else {
        Write-Host "Winget exit code : $exitCode"
        $upgradeSuccess = $false
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] UPGRADE FAILED"
    Write-Host "=============================================================="
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

if (-not $upgradeSuccess) {
    Write-Host ""
    Write-Host "[ERROR] UPGRADE FAILED"
    Write-Host "=============================================================="
    Write-Host "Winget reported a non-success exit code"
    Write-Host ""
    exit 1
}

# ============================================================================
# VERIFY
# ============================================================================

Write-Host ""
Write-Host "[INFO] VERIFY"
Write-Host "=============================================================="

# Re-resolve binary in case install path changed
$cloudflaredCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cloudflaredCmd) {
    $cloudflaredExe = $cloudflaredCmd.Source
} elseif (Test-Path $FallbackBinary) {
    $cloudflaredExe = $FallbackBinary
}

$newVersion = "Unknown"
try {
    $versionOutput = & $cloudflaredExe --version 2>&1
    if ($versionOutput -match '([\d]+\.[\d]+\.[\d]+)') {
        $newVersion = $matches[1]
    }
} catch {
    $newVersion = "Unknown"
}
Write-Host "New Version     : $newVersion"

$postSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$postStatus = if ($postSvc) { $postSvc.Status.ToString() } else { "Not registered" }
Write-Host "Service State   : $postStatus"

$regression = $false
if ($serviceWasRunning) {
    if (-not $postSvc -or $postSvc.Status.ToString() -ne "Running") {
        $regression = $true
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($regression) {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Issue           : Service was Running before upgrade, now $postStatus"
    Write-Host "Transition      : $oldVersion -> $newVersion"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
} else {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    if ($oldVersion -eq $newVersion) {
        Write-Host "Version         : $newVersion (no change)"
    } else {
        Write-Host "Transition      : $oldVersion -> $newVersion"
    }
    if ($serviceWasPresent) {
        Write-Host "Service         : $ServiceName ($postStatus)"
    } else {
        Write-Host "Service         : Not registered (version-only check)"
    }
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}
