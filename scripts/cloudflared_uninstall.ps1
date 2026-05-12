$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Cloudflared Uninstall                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\cloudflared_uninstall.ps1
================================================================================
 FILE     : cloudflared_uninstall.ps1
 DESCRIPTION : Removes the Cloudflare Tunnel service and uninstalls cloudflared
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Tears down a Cloudflare Tunnel connector on a Windows endpoint by
   uninstalling the Cloudflare Tunnel service and removing the
   Cloudflare.cloudflared package via winget. Idempotent: a clean machine
   results in a no-op success.

 DATA SOURCES & PRIORITY

   1) Hardcoded script configuration (package id, service name)
   2) Local service registration and binary presence
   3) Winget package repository

 REQUIRED INPUTS

   None - all configuration is hardcoded

 SETTINGS

   - Package Id      : Cloudflare.cloudflared
   - Service Name    : Cloudflare Tunnel
   - Winget flags    : --exact --silent

 BEHAVIOR

   1. Detects current state (service present, binary present)
   2. Removes the Cloudflare Tunnel service:
      - Prefers cloudflared.exe service uninstall (graceful)
      - Falls back to sc.exe delete if binary is gone but service remains
   3. Uninstalls Cloudflare.cloudflared via winget
   4. Verifies service no longer present and binary not resolvable
   5. Reports a clean-state result (idempotent on already-clean machines)

 PREREQUISITES

   - Windows 10 1809+ / Windows Server 2019+
   - SYSTEM or Administrator privileges
   - Winget installed (used only if the package is registered)

 SECURITY NOTES

   - No secrets in logs
   - No tokens or credentials handled by this script

 EXIT CODES

   0 = Success - cloudflared removed (or already absent)
   1 = Failure - uninstall attempted but service or binary remains

 EXAMPLE RUN

   [INFO] DETECT
   ==============================================================
   Service Present : Yes
   Binary Present  : Yes

   [RUN] SERVICE UNINSTALL
   ==============================================================
   Running cloudflared service uninstall...
   Service uninstall complete

   [INFO] WINGET CHECK
   ==============================================================
   Winget          : Available
   Version         : v1.7.10861

   [RUN] WINGET UNINSTALL
   ==============================================================
   Uninstalling Cloudflare.cloudflared...
   Uninstall complete

   [INFO] VERIFY
   ==============================================================
   Service Present : No
   Binary Present  : No

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Result          : cloudflared removed

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-12 v1.0.0 Initial release - cloudflared service + package uninstall
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
# DETECT
# ============================================================================

Write-Host ""
Write-Host "[INFO] DETECT"
Write-Host "=============================================================="

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$servicePresent = [bool]$existingService

$cloudflaredExe = $null
$cloudflaredCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cloudflaredCmd) {
    $cloudflaredExe = $cloudflaredCmd.Source
} elseif (Test-Path $FallbackBinary) {
    $cloudflaredExe = $FallbackBinary
}
$binaryPresent = [bool]$cloudflaredExe

Write-Host "Service Present : $(if ($servicePresent) { 'Yes' } else { 'No' })"
Write-Host "Binary Present  : $(if ($binaryPresent) { 'Yes' } else { 'No' })"

if (-not $servicePresent -and -not $binaryPresent) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Result          : Nothing to remove (already clean)"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

# ============================================================================
# SERVICE UNINSTALL
# ============================================================================

Write-Host ""
Write-Host "[RUN] SERVICE UNINSTALL"
Write-Host "=============================================================="

if ($servicePresent) {
    if ($binaryPresent) {
        Write-Host "Running cloudflared service uninstall..."
        try {
            $proc = Start-Process -FilePath $cloudflaredExe -ArgumentList @("service", "uninstall") -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) {
                Write-Host "Service uninstall complete"
            } else {
                Write-Host "cloudflared service uninstall exit code : $($proc.ExitCode)"
                Write-Host "Falling back to sc.exe delete..."
                Start-Process -FilePath "sc.exe" -ArgumentList @("delete", $ServiceName) -Wait -NoNewWindow | Out-Null
            }
        } catch {
            Write-Host "Graceful uninstall failed: $($_.Exception.Message)"
            Write-Host "Falling back to sc.exe delete..."
            Start-Process -FilePath "sc.exe" -ArgumentList @("delete", $ServiceName) -Wait -NoNewWindow | Out-Null
        }
    } else {
        Write-Host "Binary missing - using sc.exe to delete orphaned service..."
        Start-Process -FilePath "sc.exe" -ArgumentList @("delete", $ServiceName) -Wait -NoNewWindow | Out-Null
        Write-Host "Service delete dispatched"
    }
    Start-Sleep -Seconds 2
} else {
    Write-Host "No service registration to remove"
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
# WINGET UNINSTALL
# ============================================================================

Write-Host ""
Write-Host "[RUN] WINGET UNINSTALL"
Write-Host "=============================================================="
Write-Host "Uninstalling $PackageId..."

try {
    $uninstallArgs = @(
        "uninstall"
        "--exact"
        "--id", $PackageId
        "--silent"
    )
    $proc = Start-Process -FilePath $wingetPath -ArgumentList $uninstallArgs -Wait -PassThru -NoNewWindow
    $exitCode = $proc.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "Uninstall complete"
    } elseif ($exitCode -eq -1978335212) {
        # APPINSTALLER_CLI_ERROR_NO_APPLICABLE_INSTALLER / not installed
        Write-Host "Package not installed (winget no-op)"
    } else {
        Write-Host "Winget exit code : $exitCode"
    }
} catch {
    Write-Host "Winget uninstall warning: $($_.Exception.Message)"
}

# ============================================================================
# VERIFY
# ============================================================================

Write-Host ""
Write-Host "[INFO] VERIFY"
Write-Host "=============================================================="

$svcAfter = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceStillPresent = [bool]$svcAfter

$cloudflaredCmdAfter = Get-Command cloudflared -ErrorAction SilentlyContinue
$binaryStillPresent = [bool]$cloudflaredCmdAfter -or (Test-Path $FallbackBinary)

Write-Host "Service Present : $(if ($serviceStillPresent) { 'Yes' } else { 'No' })"
Write-Host "Binary Present  : $(if ($binaryStillPresent) { 'Yes' } else { 'No' })"

# ============================================================================
# FINAL STATUS
# ============================================================================

if (-not $serviceStillPresent -and -not $binaryStillPresent) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Result          : cloudflared removed"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    if ($serviceStillPresent) { Write-Host "Issue           : Service still registered" }
    if ($binaryStillPresent) { Write-Host "Issue           : Binary still present" }
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
