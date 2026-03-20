$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search via Everything                                  v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\file_search_everything.ps1
================================================================================
 FILE     : file_search_everything.ps1
 DESCRIPTION : Searches entire system for files matching a pattern using Everything
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Deploys Voidtools Everything to a Windows endpoint, searches for files
   matching a hardcoded pattern, and outputs results to stdout. Everything
   indexes NTFS volumes in seconds, making full-drive searches near-instant.
   If Everything was not previously installed, the script cleans it up afterward.

 DATA SOURCES & PRIORITY

   1) Everything NTFS index (built at runtime)
   2) winget package manager (for install/uninstall)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $searchTerm : File name pattern to search for (Everything syntax)

 SETTINGS

   Configuration defaults:
     - Index Timeout: 60 seconds max wait for Everything to build its index
     - Search Scope: All NTFS volumes indexed by Everything

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates the search term input
   2. Detects execution context (SYSTEM vs user) and resolves winget
   3. Checks if Everything is already installed and/or running
   4. Installs Everything via winget if not present
   5. Starts Everything service for indexing
   6. Waits for index to build (polls every 2s, 60s timeout)
   7. Runs search and outputs matching file paths to stdout
   8. Cleans up: stops service, uninstalls if script installed it

 PREREQUISITES

   - Windows 10 1709+ or Windows 11 (winget required)
   - Administrator privileges
   - NTFS filesystem

 SECURITY NOTES

   - No secrets in logs
   - No file contents are read or transmitted — only file paths are output
   - Everything runs temporarily and is removed if not pre-existing

 ENDPOINTS

   - Not applicable (no network endpoints beyond winget)

 EXIT CODES

   0 = Success (search completed, results or no results)
   1 = Failure (winget unavailable, install failed, index timeout)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Search Term : landtrust

   [INFO] ENVIRONMENT DETECTION
   ==============================================================
     Context             : SYSTEM
     Winget              : Found
     Everything Installed : No
     Everything Running  : No

   [RUN] INSTALL EVERYTHING
   ==============================================================
     [RUN] Installing via winget...
     [OK] Everything installed

   [RUN] BUILD INDEX
   ==============================================================
     [RUN] Starting Everything service...
     [RUN] Waiting for index to build...
     [OK] Index ready (4 seconds)

   [RUN] FILE SEARCH
   ==============================================================
     [RUN] Searching for: landtrust

   [INFO] SEARCH RESULTS
   ==============================================================
     C:\Users\jsmith\Documents\landtrust_agreement.pdf
     C:\Users\jsmith\Desktop\landtrust_docs\deed.pdf
     C:\Users\jsmith\Downloads\landtrust_application.xlsx
     --------------------------------------------------------------
     Total Matches : 3

   [RUN] CLEANUP
   ==============================================================
     [RUN] Stopping Everything service...
     [RUN] Uninstalling Everything...
     [OK] Cleanup complete

   [OK] FINAL STATUS
   ==============================================================
     Search completed successfully

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-20 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ── Hardcoded Inputs ─────────────────────────────────────────────────────────
$searchTerm = 'landtrust'

# ── State Variables ──────────────────────────────────────────────────────────
$errorOccurred = $false
$errorText = ""
$scriptInstalledEverything = $false
$scriptStartedService = $false
$everythingExe = ""
$indexTimeout = 60

# ── Helper Function ──────────────────────────────────────────────────────────
function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

# ── Input Validation ─────────────────────────────────────────────────────────
Write-Section 'info' 'INPUT VALIDATION'

if ([string]::IsNullOrWhiteSpace($searchTerm)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Search term is required"
}

if ($errorOccurred) {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host $errorText
    exit 1
}

Write-Host "  Search Term : $searchTerm"

# ── Environment Detection ───────────────────────────────────────────────────
Write-Section 'info' 'ENVIRONMENT DETECTION'

$isSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
$contextLabel = if ($isSystem) { 'SYSTEM' } else { 'User' }
Write-Host "  Context             : $contextLabel"

# Resolve winget
$wingetExe = ""
if ($isSystem) {
    $wingetResolved = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object | Select-Object -Last 1
    if ($wingetResolved) {
        $wingetExe = $wingetResolved.Path
    }
} else {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $wingetExe = $wingetCmd.Source
    }
}

if ([string]::IsNullOrWhiteSpace($wingetExe)) {
    Write-Host "  Winget              : Not found"
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  winget is not available. Windows 10 1709+ or Windows 11 required."
    exit 1
}
Write-Host "  Winget              : Found"

# Check if Everything is already installed
$everythingDir = Join-Path $env:ProgramFiles "Everything"
$everythingExe = Join-Path $everythingDir "Everything.exe"
$everythingAlreadyInstalled = Test-Path $everythingExe

Write-Host "  Everything Installed : $(if ($everythingAlreadyInstalled) { 'Yes' } else { 'No' })"

# Check if Everything service is already running
$everythingServiceRunning = $false
$svc = Get-Service -Name "Everything" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    $everythingServiceRunning = $true
}

Write-Host "  Everything Running  : $(if ($everythingServiceRunning) { 'Yes' } else { 'No' })"

# ── Install Everything (conditional) ────────────────────────────────────────
if (-not $everythingAlreadyInstalled) {
    Write-Section 'run' 'INSTALL EVERYTHING'
    Write-Host "  [RUN] Installing via winget..."

    try {
        $installOutput = & $wingetExe install -e --id voidtools.Everything --silent --accept-source-agreements --accept-package-agreements 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "winget install exited with code $LASTEXITCODE`n$installOutput"
        }
        $scriptInstalledEverything = $true
        Write-Host "  [OK] Everything installed"
    }
    catch {
        Write-Section 'error' 'ERROR OCCURRED'
        Write-Host "  Failed to install Everything: $_"
        exit 1
    }

    # Verify the exe exists after install
    if (-not (Test-Path $everythingExe)) {
        Write-Section 'error' 'ERROR OCCURRED'
        Write-Host "  Everything.exe not found after install at: $everythingExe"
        exit 1
    }
}

# ── Build Index ─────────────────────────────────────────────────────────────
if (-not $everythingServiceRunning) {
    Write-Section 'run' 'BUILD INDEX'
    Write-Host "  [RUN] Starting Everything service..."

    try {
        & $everythingExe -install-service 2>&1 | Out-Null
        & $everythingExe -start-service 2>&1 | Out-Null
        $scriptStartedService = $true
    }
    catch {
        Write-Section 'error' 'ERROR OCCURRED'
        Write-Host "  Failed to start Everything service: $_"
        if ($scriptInstalledEverything) {
            & $wingetExe uninstall -e --id voidtools.Everything --silent --force 2>&1 | Out-Null
        }
        exit 1
    }

    Write-Host "  [RUN] Waiting for index to build..."

    $elapsed = 0
    $indexReady = $false
    while ($elapsed -lt $indexTimeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        try {
            $testResult = & $everythingExe -search "notepad.exe" -no-display 2>&1
            if ($LASTEXITCODE -eq 0 -and $testResult) {
                $indexReady = $true
                break
            }
        }
        catch {
            # Index not ready yet, keep waiting
        }
    }

    if (-not $indexReady) {
        Write-Host "  [ERROR] Index did not build within $indexTimeout seconds"
        Write-Section 'error' 'ERROR OCCURRED'
        Write-Host "  Everything failed to build its NTFS index in time."
        if ($scriptStartedService) {
            & $everythingExe -stop-service 2>&1 | Out-Null
            & $everythingExe -uninstall-service 2>&1 | Out-Null
        }
        if ($scriptInstalledEverything) {
            & $wingetExe uninstall -e --id voidtools.Everything --silent --force 2>&1 | Out-Null
        }
        exit 1
    }

    Write-Host "  [OK] Index ready ($elapsed seconds)"
} else {
    Write-Section 'run' 'BUILD INDEX'
    Write-Host "  [OK] Everything service already running — index available"
}

# ── File Search ─────────────────────────────────────────────────────────────
Write-Section 'run' 'FILE SEARCH'
Write-Host "  [RUN] Searching for: $searchTerm"

try {
    $results = & $everythingExe -search $searchTerm -no-display 2>&1
    if ($null -eq $results) {
        $results = @()
    }
    if ($results -is [string]) {
        $results = @($results)
    }
    # Filter out empty lines
    $results = $results | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
catch {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  Search failed: $_"
    if ($scriptStartedService) {
        & $everythingExe -stop-service 2>&1 | Out-Null
        & $everythingExe -uninstall-service 2>&1 | Out-Null
    }
    if ($scriptInstalledEverything) {
        & $wingetExe uninstall -e --id voidtools.Everything --silent --force 2>&1 | Out-Null
    }
    exit 1
}

# ── Search Results ──────────────────────────────────────────────────────────
Write-Section 'info' 'SEARCH RESULTS'

$matchCount = 0
if ($results -and $results.Count -gt 0) {
    foreach ($line in $results) {
        Write-Host "  $line"
        $matchCount++
    }
    Write-Host "  --------------------------------------------------------------"
    Write-Host "  Total Matches : $matchCount"
} else {
    Write-Host "  No files found matching: $searchTerm"
}

# ── Cleanup ─────────────────────────────────────────────────────────────────
if ($scriptStartedService -or $scriptInstalledEverything) {
    Write-Section 'run' 'CLEANUP'

    if ($scriptStartedService) {
        Write-Host "  [RUN] Stopping Everything service..."
        try {
            & $everythingExe -stop-service 2>&1 | Out-Null
            & $everythingExe -uninstall-service 2>&1 | Out-Null
        }
        catch {
            Write-Host "  [WARN] Could not stop Everything service: $_"
        }
    }

    if ($scriptInstalledEverything) {
        Write-Host "  [RUN] Uninstalling Everything..."
        try {
            & $wingetExe uninstall -e --id voidtools.Everything --silent --force 2>&1 | Out-Null

            # Clean up leftover directories
            $leftoverPaths = @(
                (Join-Path $env:ProgramFiles "Everything"),
                (Join-Path $env:ProgramData "Everything")
            )
            foreach ($path in $leftoverPaths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Host "  [WARN] Cleanup issue: $_"
        }
    }

    Write-Host "  [OK] Cleanup complete"
}

# ── Final Status ────────────────────────────────────────────────────────────
Write-Section 'ok' 'FINAL STATUS'
Write-Host "  Search completed successfully"

Write-Section 'ok' 'SCRIPT COMPLETED'

exit 0
