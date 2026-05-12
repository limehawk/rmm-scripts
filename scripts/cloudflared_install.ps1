$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Cloudflared Install                                          v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\cloudflared_install.ps1
================================================================================
 FILE     : cloudflared_install.ps1
 DESCRIPTION : Installs cloudflared via winget and registers the tunnel service
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Onboards a Windows endpoint to a Cloudflare named tunnel by installing the
   Cloudflare.cloudflared package via winget and registering the Cloudflare
   Tunnel service with a connector token supplied through SuperOps runtime
   replacement. The connector token is treated as a secret and is masked on
   any output path.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime variable (CloudflaredTunnelToken)
   2) Hardcoded script configuration (package id, service name)
   3) Winget package repository

 REQUIRED INPUTS

   - $TunnelToken    - SuperOps runtime replacement variable for the
                       Cloudflare connector token (required, non-empty)

 SETTINGS

   - Package Id      : Cloudflare.cloudflared
   - Service Name    : Cloudflare Tunnel
   - Service poll    : up to 10 seconds for Running state
   - Winget flags    : --exact --silent --accept-package-agreements
                       --accept-source-agreements

 BEHAVIOR

   1. Validates connector token is present and was replaced by SuperOps
   2. Resolves winget.exe (SYSTEM-aware path resolution)
   3. Installs Cloudflare.cloudflared via winget (treats already-installed
      exit codes as success)
   4. Resolves the cloudflared.exe binary
   5. Removes any pre-existing Cloudflare Tunnel service registration
   6. Registers the service with the connector token
   7. Polls the service for Running state up to 10 seconds
   8. Reports success or masked failure (token never echoed)

 PREREQUISITES

   - Windows 10 1809+ / Windows Server 2019+
   - SYSTEM or Administrator privileges
   - Winget installed (run winget_setup.ps1 first if missing)
   - Outbound internet connectivity to Cloudflare edge (port 7844)

 SECURITY NOTES

   - No secrets in logs
   - Connector token is never printed; if it appears in an error message
     it is masked as ****<last4>
   - Runtime variable validated against unreplaced placeholder

 EXIT CODES

   0 = Success - cloudflared installed and service running
   1 = Failure - validation, winget, install, or service registration failed

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Tunnel Token    : ****abcd
   Inputs validated

   [INFO] WINGET CHECK
   ==============================================================
   Winget          : Available
   Version         : v1.7.10861

   [RUN] INSTALL BINARY
   ==============================================================
   Installing Cloudflare.cloudflared...
   Installation complete

   [INFO] RESOLVE BINARY
   ==============================================================
   Binary Path     : C:\Program Files (x86)\cloudflared\cloudflared.exe

   [RUN] CLEAR STALE SERVICE
   ==============================================================
   No existing service registration found

   [RUN] REGISTER SERVICE
   ==============================================================
   Registering Cloudflare Tunnel service...
   Service install exit code : 0

   [INFO] VERIFY SERVICE
   ==============================================================
   Service Status  : Running

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Service         : Cloudflare Tunnel (Running)

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-12 v1.0.0 Initial release - cloudflared install + service registration
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS (SuperOps runtime replacement)
# ============================================================================

$TunnelToken     = "$CloudflaredTunnelToken"   # SuperOps replaces $CloudflaredTunnelToken
$PackageId       = "Cloudflare.cloudflared"
$ServiceName     = "Cloudflare Tunnel"
$FallbackBinary  = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$ServiceWaitSecs = 10

# ============================================================================
# INPUT VALIDATION
# ============================================================================

$errorOccurred = $false
$errorText = ""

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

if ([string]::IsNullOrWhiteSpace($TunnelToken) -or $TunnelToken -eq '$' + 'CloudflaredTunnelToken') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$CloudflaredTunnelToken was not replaced"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    exit 1
}

# Build a masked representation for any output path
$tokenMasked = if ($TunnelToken.Length -ge 4) {
    "****" + $TunnelToken.Substring($TunnelToken.Length - 4)
} else {
    "****"
}

Write-Host "Tunnel Token    : $tokenMasked"
Write-Host "Inputs validated"

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
# INSTALL BINARY
# ============================================================================

Write-Host ""
Write-Host "[RUN] INSTALL BINARY"
Write-Host "=============================================================="
Write-Host "Installing $PackageId..."

$installSuccess = $false
try {
    $installArgs = @(
        "install"
        "--exact"
        "--id", $PackageId
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    $process = Start-Process -FilePath $wingetPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "Installation complete"
        $installSuccess = $true
    } elseif ($exitCode -eq -1978335189 -or $exitCode -eq 0x80073D06) {
        Write-Host "Package already installed (or higher version present)"
        $installSuccess = $true
    } elseif ($exitCode -eq 0x80073CF0) {
        Write-Host "Package already installed (same version)"
        $installSuccess = $true
    } else {
        Write-Host "Winget exit code : $exitCode"
        $installSuccess = $false
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] INSTALLATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

if (-not $installSuccess) {
    Write-Host ""
    Write-Host "[ERROR] INSTALLATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Winget reported a non-success exit code"
    Write-Host ""
    exit 1
}

# ============================================================================
# RESOLVE BINARY
# ============================================================================

Write-Host ""
Write-Host "[INFO] RESOLVE BINARY"
Write-Host "=============================================================="

$cloudflaredExe = $null
$cloudflaredCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cloudflaredCmd) {
    $cloudflaredExe = $cloudflaredCmd.Source
} elseif (Test-Path $FallbackBinary) {
    $cloudflaredExe = $FallbackBinary
}

if (-not $cloudflaredExe) {
    Write-Host ""
    Write-Host "[ERROR] BINARY NOT FOUND"
    Write-Host "=============================================================="
    Write-Host "cloudflared.exe not found after winget install"
    Write-Host "Expected fallback path: $FallbackBinary"
    Write-Host ""
    exit 1
}

Write-Host "Binary Path     : $cloudflaredExe"

# ============================================================================
# CLEAR STALE SERVICE
# ============================================================================

Write-Host ""
Write-Host "[RUN] CLEAR STALE SERVICE"
Write-Host "=============================================================="

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Existing service registration found, removing..."
    try {
        $uninstallProc = Start-Process -FilePath $cloudflaredExe -ArgumentList @("service", "uninstall") -Wait -PassThru -NoNewWindow
        if ($uninstallProc.ExitCode -ne 0) {
            Write-Host "cloudflared service uninstall exit code : $($uninstallProc.ExitCode)"
            Write-Host "Falling back to sc.exe delete..."
            Start-Process -FilePath "sc.exe" -ArgumentList @("delete", $ServiceName) -Wait -NoNewWindow | Out-Null
        }
        Start-Sleep -Seconds 2
        Write-Host "Stale service entry cleared"
    } catch {
        Write-Host "Service uninstall warning: $($_.Exception.Message)"
    }
} else {
    Write-Host "No existing service registration found"
}

# ============================================================================
# REGISTER SERVICE
# ============================================================================

Write-Host ""
Write-Host "[RUN] REGISTER SERVICE"
Write-Host "=============================================================="
Write-Host "Registering $ServiceName service..."

try {
    # Token passed as argument; never echoed to console
    $registerProc = Start-Process -FilePath $cloudflaredExe -ArgumentList @("service", "install", $TunnelToken) -Wait -PassThru -NoNewWindow
    $registerExit = $registerProc.ExitCode

    Write-Host "Service install exit code : $registerExit"

    if ($registerExit -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] SERVICE REGISTRATION FAILED"
        Write-Host "=============================================================="
        Write-Host "cloudflared service install returned non-zero exit code"
        Write-Host "Token (masked) : $tokenMasked"
        Write-Host ""
        exit 1
    }
} catch {
    # Mask the raw token in any leaked error text
    $safeMessage = $_.Exception.Message
    if ($safeMessage -match [regex]::Escape($TunnelToken)) {
        $safeMessage = $safeMessage -replace [regex]::Escape($TunnelToken), $tokenMasked
    }
    Write-Host ""
    Write-Host "[ERROR] SERVICE REGISTRATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Error: $safeMessage"
    Write-Host ""
    exit 1
}

# ============================================================================
# VERIFY SERVICE
# ============================================================================

Write-Host ""
Write-Host "[INFO] VERIFY SERVICE"
Write-Host "=============================================================="

$serviceRunning = $false
$serviceStatus = "Unknown"
$pollStart = Get-Date

while (((Get-Date) - $pollStart).TotalSeconds -lt $ServiceWaitSecs) {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        $serviceStatus = $svc.Status.ToString()
        if ($serviceStatus -eq "Running") {
            $serviceRunning = $true
            break
        }
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "Service Status  : $serviceStatus"

if (-not $serviceRunning) {
    Write-Host ""
    Write-Host "[ERROR] SERVICE NOT RUNNING"
    Write-Host "=============================================================="
    Write-Host "Service did not reach Running state within $ServiceWaitSecs seconds"
    Write-Host ""
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status          : Success"
Write-Host "Package         : $PackageId installed"
Write-Host "Service         : $ServiceName ($serviceStatus)"
Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
