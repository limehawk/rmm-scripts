$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : DelProf2 Delete All Profiles                                v1.2.1
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\delprof2_profiles_delete_all.ps1
================================================================================
 FILE     : delprof2_profiles_delete_all.ps1
 DESCRIPTION : Deletes ALL Windows user profiles except protected ones
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Deletes ALL Windows user profiles except protected ones (gaia, administrator).
   Uses DelProf2 utility downloaded directly from helgeklein.com.

 DATA SOURCES & PRIORITY

   1) Direct download from helgeklein.com

 REQUIRED INPUTS

   None - no runtime variables needed.

 SETTINGS

   - Always protects: gaia, administrator profiles
   - Downloads DelProf2 directly (no Chocolatey required)
   - Cleans up after execution

 BEHAVIOR

   1. Downloads/extracts DelProf2 if not cached
   2. Executes: delprof2.exe /u /ed:gaia /ed:administrator
   3. Cleans up cached files
   4. Reports results

 PREREQUISITES

   - Windows 10/11
   - Admin privileges required
   - Internet access for DelProf2 download

 SECURITY NOTES

   - DESTRUCTIVE OPERATION - profiles cannot be recovered
   - Downloads from official helgeklein.com source

 ENDPOINTS

   - https://helgeklein.com/downloads/DelProf2/current/Delprof2%201.6.0.zip

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Mode      : Delete All Profiles
     Protected : gaia, administrator

   [RUN] OPERATION
   ==============================================================
     Downloading DelProf2...
     Extracting...
     DelProf2 ready
     Executing: DelProf2.exe /u /ed:gaia /ed:administrator
     <DelProf2 output>
     Cleaning up...

   [INFO] RESULT
   ==============================================================
     Status : Success
     All profiles deleted except: gaia, administrator

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.2.1 Updated to two-line ASCII console output style
 2026-01-19 v1.2.0 Updated to corner bracket style section headers
 2026-01-14 v1.1.1 Fixed header formatting for framework compliance
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-29 v1.0.0 Initial release - separated from combined script
================================================================================
#>

Set-StrictMode -Version Latest

# ==============================================================================
# STATE
# ==============================================================================
$errorOccurred = $false
$errorText = ""

# ==============================================================================
# CONSTANTS
# ==============================================================================
$ProtectedProfiles = @("gaia", "administrator")
$DelProf2Url = "https://helgeklein.com/downloads/DelProf2/current/Delprof2%201.6.0.zip"
$DelProf2CacheDir = Join-Path $env:TEMP "delprof2_cache"

# ==============================================================================
# RUNTIME OUTPUT
# ==============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  Mode      : Delete All Profiles"
Write-Host "  Protected : $($ProtectedProfiles -join ', ')"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # Ensure cache directory exists
    if (-not (Test-Path $DelProf2CacheDir)) {
        New-Item -Path $DelProf2CacheDir -ItemType Directory -Force | Out-Null
    }

    $delprof2Exe = Join-Path $DelProf2CacheDir "DelProf2.exe"

    # Download and extract DelProf2 if not present
    if (-not (Test-Path $delprof2Exe)) {
        Write-Host "  Downloading DelProf2..."
        $zipPath = Join-Path $DelProf2CacheDir "DelProf2.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($DelProf2Url, $zipPath)
        $webClient.Dispose()

        Write-Host "  Extracting..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $DelProf2CacheDir)
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path $delprof2Exe)) {
            throw "DelProf2.exe not found after extraction"
        }
        Write-Host "  DelProf2 ready"
    } else {
        Write-Host "  Using cached DelProf2"
    }

    # Build arguments
    $delprof2Args = @("/u")
    foreach ($profile in $ProtectedProfiles) {
        $delprof2Args += "/ed:$profile"
    }

    Write-Host "  Executing: DelProf2.exe $($delprof2Args -join ' ')"

    # Execute
    $result = & $delprof2Exe $delprof2Args 2>&1
    Write-Host "  $result"

    # Cleanup
    Write-Host "  Cleaning up..."
    Remove-Item $DelProf2CacheDir -Recurse -Force -ErrorAction SilentlyContinue

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  $errorText"
}

Write-Host ""
Write-Host "[INFO] RESULT"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "  Status : Failure"
} else {
    Write-Host "  Status : Success"
    Write-Host "  All profiles deleted except: $($ProtectedProfiles -join ', ')"
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
} else {
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}
