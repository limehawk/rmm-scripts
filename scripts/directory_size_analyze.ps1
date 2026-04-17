$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Directory Size Analyze                                        v2.2.1
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\directory_size_analyze.ps1
================================================================================
 FILE     : directory_size_analyze.ps1
 DESCRIPTION : Analyzes disk usage with gdu utility for directory size reports
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Runs a command-line disk usage analysis on a specified directory using gdu
 (Go Disk Usage analyzer).

 This script is designed for unattended RMM execution. It downloads the gdu
 utility from GitHub releases if not already present, extracts it to a local
 cache directory, and executes it against the target path in non-interactive
 mode to return text or JSON output.

 DATA SOURCES & PRIORITY
 1) SuperOps runtime variable ($YourTargetDirectoryHere)
 2) Hardcoded values (all other settings)

 REQUIRED INPUTS
 - ScanPath        : $YourTargetDirectoryHere (SuperOps runtime variable)
   (The target directory to scan. Must be set in SuperOps.)
 - ScanDepth       : 1
   (The number of levels deep to report sizes for. Controls top N items shown.)
 - ScanTimeout     : 600
   (Maximum seconds to allow for the scan operation. 0 = no timeout.)
 - OutputFormat    : text
   (Output format: 'text' or 'json')
 - GduVersion      : v5.31.0
   (The GitHub release version to download.)
 - GduDownloadUrl  : https://github.com/dundee/gdu/releases/download/...
   (Direct download URL for the gdu Windows executable zip.)
 - GduCacheDir     : Dynamic based on Windows TEMP directory
   (Local directory to cache the gdu executable. Uses $env:TEMP for automatic cleanup.)
 - CleanupAfterRun : $true
   (Whether to delete the gdu cache directory after execution.)

 SETTINGS
 - Downloads and extracts gdu to a cache directory if not present.
 - No package manager dependencies (winget, chocolatey, etc.).
 - Includes timeout protection for long-running scans.
 - Supports multiple output formats (text or JSON).
 - Optional cleanup of downloaded files after completion.

 BEHAVIOR
 - This script is all-or-nothing. If any step fails (e.g., download, extract,
   or scan), the script will stop and report an error.
 - The gdu executable is cached locally to avoid repeated downloads.
 - If CleanupAfterRun is true, all cached files are deleted after execution.

 PREREQUISITES
 - PowerShell 5.1 or later.
 - Internet access to reach github.com for initial download.
 - Write permissions to the cache directory.

 SECURITY NOTES
 - No secrets are printed to the console.
 - Downloads from official GitHub releases.
 - Consider verifying SHA256 checksums in production environments.

 ENDPOINTS
 - github.com (for gdu releases)

 EXIT CODES
 - 0 success
 - 1 failure

 EXAMPLE RUN
 (This script is intended for unattended RMM execution.)
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-29 v2.2.1 Added runtime variable to yaml metadata for sync
 2026-01-29 v2.2.0 Added SuperOps runtime variable for ScanPath, updated console output format
 2025-12-23 v2.1.0 Updated to Limehawk Script Framework
 2025-10-30 v2.0.0 Complete rewrite using direct gdu download
 2025-10-01 v1.0.0 Initial release
================================================================================
#>

# Set strict mode (placed after README block)
# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""   # Accumulate newline-delimited messages.
$scanOutput    = ""   # Store the final output from gdu.

# ==== HARDCODED INPUTS (MANDATORY) ====
$ScanPath         = "$YourTargetDirectoryHere"
$ScanDepth        = 1
$ScanTimeout      = 600  # seconds (10 minutes) - set to 0 to disable timeout
$OutputFormat     = 'text'  # 'text' or 'json'
$GduVersion       = 'v5.31.0'
$GduDownloadUrl   = 'https://github.com/dundee/gdu/releases/download/v5.31.0/gdu_windows_amd64.exe.zip'
$GduCacheDir      = Join-Path $env:TEMP "gdu_rmm_cache"  # Uses Windows TEMP directory
$GduExeName       = 'gdu.exe'
$CleanupAfterRun  = $true  # Set to $false to keep gdu cached for future runs

# ==== VALIDATION ====

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ScanPath) -or $ScanPath -eq '$' + 'YourTargetDirectoryHere') {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- SuperOps runtime variable `$YourTargetDirectoryHere was not replaced."
}
if ($ScanDepth -le 0) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- ScanDepth must be 1 or greater."
}
if ($ScanTimeout -lt 0) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- ScanTimeout must be 0 or greater."
}
if ($OutputFormat -notin @('text', 'json')) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- OutputFormat must be 'text' or 'json'."
}
if ([string]::IsNullOrWhiteSpace($GduVersion)) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- GduVersion is required."
}
if ([string]::IsNullOrWhiteSpace($GduDownloadUrl)) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- GduDownloadUrl is required."
}
if ([string]::IsNullOrWhiteSpace($GduCacheDir)) {
     $errorOccurred = $true
     if ($errorText.Length -gt 0) { $errorText += "`n" }
     $errorText += "- GduCacheDir is required."
}
if (-not (Test-Path $ScanPath -PathType Container)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- ScanPath directory does not exist: $ScanPath"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Input validation failed:"
    Write-Host $errorText

    Write-Host ""
    Write-Host "[INFO] RESULT"
    Write-Host "=============================================================="
    Write-Host "Status : Failure"

    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script cannot proceed due to invalid inputs."

    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "ScanPath        : $ScanPath"
Write-Host "ScanDepth       : $ScanDepth"
Write-Host "ScanTimeout     : $ScanTimeout seconds"
Write-Host "OutputFormat    : $OutputFormat"
Write-Host "GduVersion      : $GduVersion"
Write-Host "GduCacheDir     : $GduCacheDir"
Write-Host "CleanupAfterRun : $CleanupAfterRun"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # 1. Ensure cache directory exists
    Write-Host "Checking cache directory: $GduCacheDir"
    if (-not (Test-Path $GduCacheDir)) {
        Write-Host "Cache directory does not exist. Creating..."
        New-Item -Path $GduCacheDir -ItemType Directory -Force | Out-Null
        Write-Host "Cache directory created."
    } else {
        Write-Host "Cache directory exists."
    }

    # 2. Check for existing gdu executable
    $gduExePath = Join-Path $GduCacheDir $GduExeName
    Write-Host "Checking for gdu executable: $gduExePath"

    if (-not (Test-Path $gduExePath)) {
        Write-Host "gdu executable not found. Downloading from GitHub..."

        # Download zip file
        $zipPath = Join-Path $GduCacheDir "gdu.zip"
        Write-Host "Downloading: $GduDownloadUrl"
        Write-Host "Destination: $zipPath"

        try {
            # Use TLS 1.2 for GitHub
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($GduDownloadUrl, $zipPath)
            $webClient.Dispose()

            Write-Host "Download complete."
        } catch {
            throw "Failed to download gdu: $($_.Exception.Message)"
        }

        # Extract zip file
        Write-Host "Extracting archive..."
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $GduCacheDir)
            Write-Host "Extraction complete."
        } catch {
            throw "Failed to extract gdu: $($_.Exception.Message)"
        }

        # Rename extracted executable if needed
        $extractedExe = Join-Path $GduCacheDir "gdu_windows_amd64.exe"
        if (Test-Path $extractedExe) {
            Write-Host "Renaming executable to $GduExeName"
            Move-Item -Path $extractedExe -Destination $gduExePath -Force
        }

        # Clean up zip file
        Write-Host "Cleaning up temporary files..."
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # Verify executable exists
        if (-not (Test-Path $gduExePath)) {
            throw "gdu executable not found after extraction. Expected: $gduExePath"
        }

        Write-Host "gdu installation complete."
    } else {
        Write-Host "gdu executable already present."
    }

    # 3. Run the scan
    Write-Host "Preparing to execute gdu scan..."

    # Build gdu command arguments
    # gdu flags for non-interactive output:
    # -n = non-interactive mode (essential for RMM)
    # -p = no progress bar (cleaner output)
    # -c = no color
    # -a = show apparent size (logical size)
    # -t N = show top N items (provides output in non-interactive mode)

    $gduArgs = @('-n', '-p', '-c', '-a')

    if ($ScanDepth -gt 0) {
        # Use -t (top) to show the largest items
        $gduArgs += '-t'
        $gduArgs += '50'  # Show top 50 items
    }

    if ($OutputFormat -eq 'json') {
        # For JSON, use -o flag to output to stdout
        $gduArgs += '-o'
        $gduArgs += '-'  # - means stdout
    }

    $gduArgs += $ScanPath

    $gduCommand = "$gduExePath $($gduArgs -join ' ')"
    Write-Host "Executing: $gduCommand"

    if ($ScanTimeout -gt 0) {
        Write-Host "Timeout protection enabled: $ScanTimeout seconds"

        $job = Start-Job -ScriptBlock {
            param($exePath, $arguments)
            & $exePath $arguments 2>&1
        } -ArgumentList $gduExePath, $gduArgs

        $completed = Wait-Job $job -Timeout $ScanTimeout

        if ($job.State -eq 'Running') {
            Stop-Job $job
            Remove-Job $job
            throw "Scan operation exceeded timeout of $ScanTimeout seconds and was terminated."
        }

        $scanOutput = Receive-Job $job -ErrorAction Stop | Out-String -Width 4096
        Remove-Job $job

    } else {
        Write-Host "Timeout protection disabled."
        $scanOutput = & $gduExePath $gduArgs 2>&1 | Out-String -Width 4096
    }

    Write-Host "Scan finished successfully."

} catch {
    $errorOccurred = $true
    if ($_.Exception.Message.Length -gt 0) { $errorText = $_.Exception.Message }
    else { $errorText = $_.ToString() }
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

Write-Host ""
Write-Host "[INFO] RESULT"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Status : Failure"
} else {
    Write-Host "Status : Success"
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script failed during operation. See error details above."
} else {
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Directory scan complete. Output:"
    Write-Host $scanOutput
}

# ==== CLEANUP ====
if ($CleanupAfterRun) {
    Write-Host ""
    Write-Host "[RUN] CLEANUP"
    Write-Host "=============================================================="
    Write-Host "Cleaning up gdu cache directory: $GduCacheDir"

    try {
        if (Test-Path $GduCacheDir) {
            Remove-Item -Path $GduCacheDir -Recurse -Force -ErrorAction Stop
            Write-Host "Cleanup complete. Cache directory removed."
        } else {
            Write-Host "Cache directory not found. Nothing to clean up."
        }
    } catch {
        Write-Host "Warning: Failed to clean up cache directory: $($_.Exception.Message)"
        Write-Host "You may need to manually delete: $GduCacheDir"
    }
} else {
    Write-Host ""
    Write-Host "[RUN] CLEANUP"
    Write-Host "=============================================================="
    Write-Host "Cleanup disabled. gdu executable cached at: $GduCacheDir"
    Write-Host "This will speed up future runs of this script."
}

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
