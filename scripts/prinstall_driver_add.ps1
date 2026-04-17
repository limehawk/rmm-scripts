$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Driver Add v0.4.15
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_driver_add.ps1
FILE    : prinstall_driver_add.ps1
DESCRIPTION : Stages a driver into the Windows driver store (no printer queue)
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Stages a print driver on Windows using prinstall 0.4.12+ without creating
   a printer queue. The target can be either:
     1. A filesystem path — INF file or folder of INFs (pnputil /add-driver)
     2. A model string — matches embedded driver sources (known_matches.toml,
        drivers.toml), downloads the manufacturer pack, and stages it
   Prinstall auto-detects which mode based on the target. Useful for
   pre-loading drivers onto a box before a USB printer is plugged in or
   before a first `Add-Printer` call fires from another runbook.

 DATA SOURCES & PRIORITY
   1) SuperOps runtime variable for the target (path or model)
   2) Prinstall's embedded manifest + known_matches database
   3) Manufacturer download URLs (HP, Xerox, Kyocera today)

 REQUIRED INPUTS
   - $driverTarget  : Path (C:\Drivers\HP_M404 or C:\Drivers\brother.inf)
                        OR a model string ("HP LaserJet 1320", "hp universal")
                        (SuperOps: $YourDriverTargetHere)
   - $driverName    : (optional) Explicit driver name to pick when the model
                        string has multiple matches. Ignored for path targets.
                        (SuperOps: $YourDriverNameHere)
   - $noVerify      : (optional) Skip Authenticode .cat signature verification.
                        Leave $false unless a vendor pack legitimately ships
                        without signed catalogs.
   - $prinstallDir  : Directory where prinstall.exe is installed

 SETTINGS
   - Verbose output enabled for RMM console visibility
   - Default verification gate runs Get-AuthenticodeSignature on every .cat

 BEHAVIOR
   Path target:
     1. Validates the path exists
     2. Verifies .cat signatures (unless $noVerify)
     3. Runs pnputil /add-driver on the INF(s)
     4. Best-effort Add-PrinterDriver so the driver shows up in
        `prinstall driver list`

   Model target:
     1. Matches against known_matches.toml + drivers.toml
     2. If a curated exact match exists (score 1000) and $driverName is
        empty, auto-picks it
     3. If multiple matches, fails with a candidate list unless
        $driverName explicitly picks one
     4. Downloads the manufacturer pack to the staging dir
     5. Verifies .cat signatures (unless $noVerify)
     6. Runs pnputil /add-driver on all INFs in the pack
     7. Registers the driver in the print spooler

 PREREQUISITES
   - Windows OS
   - Administrator privileges
   - prinstall.exe 0.4.12+ installed (run prinstall_setup.ps1 first)
   - Internet connectivity (model target only — path target is offline)

 SECURITY NOTES
   - Authenticode verification is on by default; $noVerify tags the result
     [UNVERIFIED] so the audit trail makes the bypass explicit
   - No secrets in logs

 ENDPOINTS
   - Manufacturer vendor download URLs (embedded in prinstall's manifest)

 EXIT CODES
   - 0 = Success - driver staged
   - 1 = Failure - staging failed or explicit pick required

 EXAMPLE RUN (model target, curated match)

   [INFO] INPUT VALIDATION
   ==============================================================
   Target          : hp 1320
   Driver pick     : (auto)
   Verify          : Enabled
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.4.15
   Inputs validated successfully

   [RUN] STAGE DRIVER
   ==============================================================
   ★ Curated match: HP LaserJet 1320 PCL 5e
   Downloading from vendor URL...
   ✓ Staged and registered 'HP LaserJet 1320 PCL 5e' (signed by Hewlett-Packard Co.)

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Target          : hp 1320

   [OK] SCRIPT COMPLETED
   ==============================================================

 EXAMPLE RUN (path target)

   [INFO] INPUT VALIDATION
   ==============================================================
   Target          : C:\Drivers\HP_M404
   Driver pick     : (ignored for path targets)
   Verify          : Enabled
   Prinstall       : C:\ProgramData\prinstall\prinstall.exe
   Version         : prinstall 0.4.15
   Inputs validated successfully

   [RUN] STAGE DRIVER
   ==============================================================
   ✓ Verified: 6 .cat file(s), signed by Microsoft Windows Hardware Compatibility Publisher
   ✓ Driver staged successfully (4/4 registered in spooler)

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Target          : C:\Drivers\HP_M404

CHANGELOG
--------------------------------------------------------------------------------
2026-04-15 v0.4.15 Initial release - wraps `prinstall driver add <target>`.
                   Supports both path-based and model-based staging, with
                   optional --driver pick-one and --no-verify audit bypass.
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$driverTarget = "$YourDriverTargetHere"    # Path OR model string
$driverName   = "$YourDriverNameHere"      # Optional: explicit driver pick for model targets
$noVerify     = $false                     # Set $true to skip .cat signature verification
$prinstallDir = "$env:ProgramData\prinstall"   # Where prinstall.exe is installed

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($driverTarget) -or $driverTarget -eq '$' + 'YourDriverTargetHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourDriverTargetHere was not replaced. Set it to a path (e.g. 'C:\Drivers\HP_M404') or a model string (e.g. 'HP LaserJet 1320')."
}

if ([string]::IsNullOrWhiteSpace($prinstallDir)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Prinstall directory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

# Treat an unreplaced optional placeholder as empty
$useDriverPick = $driverName
if ($useDriverPick -eq '$' + 'YourDriverNameHere') { $useDriverPick = '' }

$exePath = "$prinstallDir\prinstall.exe"

Write-Host "Target          : $driverTarget"
if ([string]::IsNullOrWhiteSpace($useDriverPick)) {
    Write-Host "Driver pick     : (auto)"
} else {
    Write-Host "Driver pick     : $useDriverPick"
}
Write-Host "Verify          : $(if ($noVerify) { 'Disabled (UNVERIFIED)' } else { 'Enabled' })"
Write-Host "Prinstall       : $exePath"
Write-Host "Inputs validated successfully"

# ============================================================================
# PRINSTALL CHECK
# ============================================================================
Write-Host ""
Write-Host "[INFO] PRINSTALL CHECK"
Write-Host "=============================================================="

if (-not (Test-Path $exePath)) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "prinstall.exe not found at $exePath"
    Write-Host "Run prinstall_setup.ps1 first to install prinstall"
    exit 1
}

try {
    $versionOutput = & $exePath --version 2>&1
    Write-Host "Version         : $versionOutput"
} catch {
    Write-Host "Version         : Unknown"
}

# ============================================================================
# STAGE DRIVER
# ============================================================================
Write-Host ""
Write-Host "[RUN] STAGE DRIVER"
Write-Host "=============================================================="
Write-Host "Staging '$driverTarget'..."
Write-Host ""

try {
    $addArgs = @('driver', 'add', $driverTarget, '--verbose')

    if (-not [string]::IsNullOrWhiteSpace($useDriverPick)) {
        $addArgs += '--driver'
        $addArgs += $useDriverPick
    }

    if ($noVerify) {
        $addArgs += '--no-verify'
    }

    # See prinstall_scan.ps1 for why we swap EAP for the subprocess call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exePath @addArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $addExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Prinstall driver add failed"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

if ($addExitCode -eq 0) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Success"
    Write-Host "Target          : $driverTarget"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Failed"
    Write-Host "Exit code       : $addExitCode"
    Write-Host "Target          : $driverTarget"
    Write-Host ""
    Write-Host "Hint: if the model has multiple matches, set `$YourDriverNameHere to pick one."
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}
