$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SentinelOne Uninstall                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\sentinelone_uninstall.ps1
================================================================================
 FILE     : sentinelone_uninstall.ps1
 DESCRIPTION : Offline-uninstalls SentinelOne on Windows using the agent passphrase
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Removes the SentinelOne Windows agent when console online-uninstall is not
   completing (offline endpoints, expired pending commands). Uses the per-agent
   passphrase from the S1 console (Actions > Show Passphrase) and runs
   uninstall.exe with offline verification.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime variable $YourPassphraseHere (REQUIRED)
   2) Local install path under Program Files\SentinelOne

 REQUIRED INPUTS

   - $YourPassphraseHere : Agent uninstall passphrase from S1 console
     (12-word style string; unique per agent). Set per device when running
     in SuperOps.

 SETTINGS

   - $NoRestart : Pass /norestart to uninstall.exe (default $true)
   - $Quiet     : Pass /q for quiet uninstall (default $true)

 BEHAVIOR

   1. Validates passphrase runtime variable was supplied
   2. Confirms Administrator / SYSTEM context
   3. Locates Sentinel Agent install directory and uninstall.exe
   4. If SentinelOne is not installed, exits 0 (idempotent success)
   5. Runs uninstall.exe with passphrase (/k) for offline verification
   6. Verifies Program Files\SentinelOne is gone (or reduced)
   7. Reports result; does not print the passphrase

 PREREQUISITES

   - Windows 10/11 or Windows Server
   - PowerShell 5.1 or later
   - Administrator or SYSTEM (SuperOps runAs SYSTEM_USER)
   - Correct per-agent passphrase from S1 console

 SECURITY NOTES

   - Passphrase is never written to stdout/logs
   - Treat SuperOps script run output as non-secret (we redact)

 EXIT CODES

   0 = Success (uninstalled, or already absent)
   1 = Failure (missing passphrase, uninstall.exe missing, or agent remains)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Passphrase       : provided (12 words)
 Administrator    : Yes

 [INFO] DETECT
 ==============================================================
 Install Path     : C:\Program Files\SentinelOne\Sentinel Agent 25.1.4.434
 Uninstall Exe    : Found

 [RUN] UNINSTALL
 ==============================================================
 Running offline uninstall...
 Uninstall process exit code : 0

 [INFO] VERIFY
 ==============================================================
 SentinelOne path remaining : No

 [OK] FINAL STATUS
 ==============================================================
 Result : SUCCESS

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-23 v1.0.0 Initial release - offline passphrase uninstall for SuperOps
================================================================================
#>

# ==== HARDCODED INPUTS (read SuperOps placeholders BEFORE StrictMode) ====
$Passphrase = "$YourPassphraseHere"
$NoRestart  = $true
$Quiet      = $true

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== VALIDATION ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

if ([string]::IsNullOrWhiteSpace($Passphrase) -or $Passphrase -eq ('$' + 'YourPassphraseHere')) {
    $errorOccurred = $true
    $errorText = "SuperOps runtime variable `$YourPassphraseHere was not set. Get passphrase from S1 console: agent > Actions > Show Passphrase."
}

$wordCount = 0
if (-not $errorOccurred) {
    $Passphrase = $Passphrase.Trim()
    $wordCount = (@($Passphrase -split '\s+' | Where-Object { $_ })).Count
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host ("Passphrase       : provided ({0} words)" -f $wordCount)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[ERROR] ADMINISTRATOR REQUIRED"
    Write-Host "=============================================================="
    Write-Host "Run as SYSTEM (SuperOps) or Administrator."
    exit 1
}
Write-Host "Administrator    : Yes"

# ==== DETECT ====
Write-Host ""
Write-Host "[INFO] DETECT"
Write-Host "=============================================================="

$searchRoots = @(
    "${env:ProgramFiles}\SentinelOne",
    "${env:ProgramFiles(x86)}\SentinelOne"
) | Where-Object { $_ -and (Test-Path $_) }

$uninstallExe = $null
$installDir   = $null

foreach ($root in $searchRoots) {
    $candidates = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Sentinel Agent*' } |
        Sort-Object Name -Descending

    foreach ($dir in $candidates) {
        $exe = Join-Path $dir.FullName 'uninstall.exe'
        if (Test-Path -LiteralPath $exe) {
            $uninstallExe = $exe
            $installDir   = $dir.FullName
            break
        }
    }
    if ($uninstallExe) { break }
}

if (-not $uninstallExe) {
    # Already gone?
    $anyLeft = $false
    foreach ($root in @(
        "${env:ProgramFiles}\SentinelOne",
        "${env:ProgramFiles(x86)}\SentinelOne"
    )) {
        if ($root -and (Test-Path $root)) {
            $anyLeft = $true
            break
        }
    }

    if (-not $anyLeft) {
        Write-Host "Install Path     : Not found"
        Write-Host "Uninstall Exe    : N/A"
        Write-Host ""
        Write-Host "[OK] FINAL STATUS"
        Write-Host "=============================================================="
        Write-Host "Result : SUCCESS (already uninstalled)"
        Write-Host ""
        Write-Host "[OK] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 0
    }

    Write-Host ""
    Write-Host "[ERROR] UNINSTALL EXE NOT FOUND"
    Write-Host "=============================================================="
    Write-Host "SentinelOne folder exists but uninstall.exe was not found."
    Write-Host "Tried under Program Files\SentinelOne\Sentinel Agent*"
    exit 1
}

Write-Host "Install Path     : $installDir"
Write-Host "Uninstall Exe    : Found"

# ==== UNINSTALL ====
Write-Host ""
Write-Host "[RUN] UNINSTALL"
Write-Host "=============================================================="

# Build args carefully so passphrase is not echoed via Start-Process logging
$argList = @()
if ($NoRestart) { $argList += '/norestart' }
if ($Quiet)     { $argList += '/q' }
$argList += '/k'
$argList += $Passphrase

Write-Host "Running offline uninstall..."

$proc = Start-Process -FilePath $uninstallExe `
    -ArgumentList $argList `
    -Wait `
    -PassThru `
    -WindowStyle Hidden

$exitCode = $proc.ExitCode
Write-Host "Uninstall process exit code : $exitCode"

# Clear passphrase from memory best-effort
$Passphrase = $null
$argList = $null

# ==== VERIFY ====
Write-Host ""
Write-Host "[INFO] VERIFY"
Write-Host "=============================================================="

Start-Sleep -Seconds 3

$remaining = $false
$remainingPaths = @()
foreach ($root in @(
    "${env:ProgramFiles}\SentinelOne",
    "${env:ProgramFiles(x86)}\SentinelOne"
)) {
    if ($root -and (Test-Path $root)) {
        $agents = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Sentinel Agent*' }
        if ($agents) {
            $remaining = $true
            foreach ($a in $agents) { $remainingPaths += $a.FullName }
        }
    }
}

$svcLeft = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Sentinel|LogProcessorService' }

Write-Host ("SentinelOne path remaining : {0}" -f ($(if ($remaining) { 'Yes' } else { 'No' })))
if ($remainingPaths.Count -gt 0) {
    foreach ($p in $remainingPaths) {
        Write-Host "  Still present : $p"
    }
}
Write-Host ("Sentinel services remaining : {0}" -f ($(if ($svcLeft) { ($svcLeft | ForEach-Object Name) -join ', ' } else { 'None' })))

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="

# Exit 0 if folder gone even if uninstall returned non-zero (some S1 builds do that)
if (-not $remaining) {
    Write-Host "Result : SUCCESS"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

Write-Host "Result : FAILED - agent still present after uninstall"
Write-Host "Tip    : Confirm passphrase matches this agent in S1 console"
Write-Host "Tip    : Reboot and re-run, or decommission the agent in console"
Write-Host ""
Write-Host "[ERROR] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 1
