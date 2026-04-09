$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : DelProf2 Delete Specific Profile v1.1.0
 AUTHOR   : Limehawk.io
 DATE      : December 2025
 USAGE    : .\delprof2_specific_profile_delete.ps1
================================================================================
 FILE     : delprof2_specific_profile_delete.ps1
 DESCRIPTION : Deletes only the specified Windows user profile
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Deletes ONLY the specified Windows user profile. All other profiles are
 left untouched. Uses DelProf2 utility.

 DATA SOURCES & PRIORITY

 1) SuperOps runtime variables
 2) Direct download from helgeklein.com

 REQUIRED INPUTS (SuperOps Runtime Variables)

 - $profile_to_delete : Username of the profile to delete

 SETTINGS

 - Protects gaia, administrator from accidental deletion
 - Downloads DelProf2 directly (no Chocolatey required)
 - Cleans up after execution

 BEHAVIOR

 1. Validates profile is not protected
 2. Downloads/extracts DelProf2 if not cached
 3. Executes: delprof2.exe /u /id:PROFILENAME
 4. Cleans up cached files
 5. Reports results

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required
 - Internet access for DelProf2 download

 SECURITY NOTES

 - DESTRUCTIVE OPERATION - profile cannot be recovered
 - Downloads from official helgeklein.com source
 - Refuses to delete protected profiles

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

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== SUPEROPS RUNTIME VARIABLES ====
$ProfileToDelete = "$profile_to_delete"

# ==== CONSTANTS ====
$ProtectedProfiles = @("gaia", "administrator")
$DelProf2Url = "https://helgeklein.com/downloads/DelProf2/current/Delprof2%201.6.0.zip"
$DelProf2CacheDir = Join-Path $env:TEMP "delprof2_cache"

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($ProfileToDelete) -or $ProfileToDelete -eq '$profile_to_delete') {
    $errorOccurred = $true
    $errorText = "- profile_to_delete is required. Set this variable in SuperOps."
}

# Check if trying to delete a protected profile
if ($ProfileToDelete.ToLower() -in ($ProtectedProfiles | ForEach-Object { $_.ToLower() })) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Cannot delete protected profile '$ProfileToDelete'."
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
Write-Host "Profile to Delete : $ProfileToDelete"
Write-Host "Protected         : $($ProtectedProfiles -join ', ')"

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

    # Build arguments - only delete the specific profile
    $delprof2Args = @("/u", "/id:$ProfileToDelete")

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
    Write-Host "Profile '$ProfileToDelete' has been deleted."
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

if ($errorOccurred) { exit 1 } else { exit 0 }
