$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : DelProf2 Delete Old Profiles v1.1.0
 AUTHOR   : Limehawk.io
 DATE      : December 2025
 USAGE    : .\delprof2_old_profiles_delete.ps1
================================================================================
 FILE     : delprof2_old_profiles_delete.ps1
 DESCRIPTION : Deletes Windows user profiles older than specified days
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Deletes Windows user profiles older than a specified number of days.
 Uses DelProf2 utility downloaded directly from helgeklein.com.

 DATA SOURCES & PRIORITY

 1) SuperOps runtime variables
 2) Direct download from helgeklein.com

 REQUIRED INPUTS (SuperOps Runtime Variables)

 - $days_old : Number of days - profiles older than this are deleted (default: 30)

 SETTINGS

 - Always protects: gaia, administrator profiles
 - Downloads DelProf2 directly (no Chocolatey required)
 - Cleans up after execution

 BEHAVIOR

 1. Downloads/extracts DelProf2 if not cached
 2. Executes: delprof2.exe /u /d:X /ed:gaia /ed:administrator
 3. Cleans up cached files
 4. Reports results

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required
 - Internet access for DelProf2 download

 SECURITY NOTES

 - DESTRUCTIVE OPERATION - profiles cannot be recovered
 - Downloads from official helgeklein.com source

 EXIT CODES

 - 0: Success
 - 1: Failure
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-29 v1.0.0 Initial release - separated from combined script
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== SUPEROPS RUNTIME VARIABLES ====
$DaysOld = "$days_old"

# ==== CONSTANTS ====
$ProtectedProfiles = @("gaia", "administrator")
$DelProf2Url = "https://helgeklein.com/downloads/DelProf2/current/Delprof2%201.6.0.zip"
$DelProf2CacheDir = Join-Path $env:TEMP "delprof2_cache"

# ==== APPLY DEFAULTS ====

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($DaysOld) -or $DaysOld -eq '$days_old') {
    $DaysOld = "30"
}

$DaysOldInt = 0
if (-not [int]::TryParse($DaysOld, [ref]$DaysOldInt)) {
    $DaysOldInt = 30
}

# ==== VALIDATION ====
if ($DaysOldInt -lt 1) {
    $errorOccurred = $true
    $errorText = "- DaysOld must be at least 1."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Days Old  : $DaysOldInt"
Write-Host "Protected : $($ProtectedProfiles -join ', ')"

Write-Host ""
Write-Host "[ OPERATION ]"
Write-Host "--------------------------------------------------------------"

try {
    # Ensure cache directory exists
    if (-not (Test-Path $DelProf2CacheDir)) {
        New-Item -Path $DelProf2CacheDir -ItemType Directory -Force | Out-Null
    }

    $delprof2Exe = Join-Path $DelProf2CacheDir "DelProf2.exe"

    # Download and extract DelProf2 if not present
    if (-not (Test-Path $delprof2Exe)) {
        Write-Host "Downloading DelProf2..."
        $zipPath = Join-Path $DelProf2CacheDir "DelProf2.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($DelProf2Url, $zipPath)
        $webClient.Dispose()

        Write-Host "Extracting..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $DelProf2CacheDir)
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path $delprof2Exe)) {
            throw "DelProf2.exe not found after extraction"
        }
        Write-Host "DelProf2 ready"
    } else {
        Write-Host "Using cached DelProf2"
    }

    # Build arguments
    $delprof2Args = @("/u", "/d:$DaysOldInt")
    foreach ($profile in $ProtectedProfiles) {
        $delprof2Args += "/ed:$profile"
    }

    Write-Host "Executing: DelProf2.exe $($delprof2Args -join ' ')"

    # Execute
    $result = & $delprof2Exe $delprof2Args 2>&1
    Write-Host $result

    # Cleanup
    Write-Host "Cleaning up..."
    Remove-Item $DelProf2CacheDir -Recurse -Force -ErrorAction SilentlyContinue

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
}

Write-Host ""
Write-Host "[ RESULT ]"
Write-Host "--------------------------------------------------------------"
if ($errorOccurred) {
    Write-Host "Status : Failure"
} else {
    Write-Host "Status : Success"
    Write-Host "Profiles older than $DaysOldInt days deleted."
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

if ($errorOccurred) { exit 1 } else { exit 0 }
