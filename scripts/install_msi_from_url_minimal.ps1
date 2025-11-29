Import-Module $SuperOpsModule
$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT    : install_msi_from_url_minimal.ps1
 VERSION   : v1.5.0
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE – Downloads and silently installs an MSI package from the URL specified
 in $MsiScriptUrl. The file is saved to the temporary directory and cleaned up
 after installation completes.

 REQUIRED INPUTS – Edit $MsiScriptUrl with the full URL to the MSI file.

 PREREQUISITES – PowerShell 5.1+, Admin rights, Network connectivity.
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 v1.5.0   (2025-10-30)  Switched to curl for fastest, most reliable downloads
                        with automatic redirect handling and better error reporting.
 v1.4.0   (2025-10-30)  Added fallback filename logic for URLs without valid
                        filenames or .msi extensions.
 v1.3.0   (2025-09-22)  Minimal version, removing all non-essential diagnostic
                        placeholders and sections as requested.
 v1.2.0   (2025-09-22)  Reduced placeholders; adopted $MsiScriptUrl variable.
 v1.1.0   (2025-09-22)  Added $MsiUrl variable and logic for download/install.
 v1.0.0   (2025-09-22)  Initial release: silent MSI install wrapper.
================================================================================
#>

Set-StrictMode -Version Latest

# --- Script Variables ---
# NOTE: This is the URL placeholder that will be replaced.
$MsiScriptUrl = "$MSIURL"

# Extract filename from URL, use fallback if none found
$MsiFileName = [System.IO.Path]::GetFileName($MsiScriptUrl)
if ([string]::IsNullOrWhiteSpace($MsiFileName) -or $MsiFileName -notmatch '\.msi$') {
    $MsiFileName = "downloaded_package.msi"
}

$TempMsiPath = Join-Path -Path $env:TEMP -ChildPath $MsiFileName
$FinalExitCode = 1 # Assume failure

# --- Required Console Helper Functions (Kept for Style A output formatting) ---

function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}


# --- Function for cleanup ---
function Cleanup-TempFile {
    if (Test-Path -Path $TempMsiPath -PathType Leaf) {
        Remove-Item -Path $TempMsiPath -Force -ErrorAction SilentlyContinue
        return "SUCCESSFUL"
    }
    return "NOT REQUIRED"
}


# --- Start Script Execution ---

Write-Section "DOWNLOAD AND INSTALL"
PrintKV "MSI Source URL" $MsiScriptUrl
PrintKV "Filename Used" $MsiFileName
PrintKV "Temporary Path" $TempMsiPath

# 1. Download the MSI using curl
try {
    Write-Host " STARTING DOWNLOAD (CURL)..."

    # Use curl for fast, reliable downloads with progress
    $CurlArgs = @(
        '-L',                          # Follow redirects
        '-o', $TempMsiPath,           # Output file
        '--silent',                    # Silent mode (no progress bar cluttering output)
        '--show-error',                # But show errors
        '--fail',                      # Fail on HTTP errors
        '--connect-timeout', '30',     # Connection timeout
        '--max-time', '600',           # Max total time (10 minutes)
        $MsiScriptUrl
    )

    $CurlProcess = Start-Process -FilePath "curl.exe" -ArgumentList $CurlArgs -Wait -NoNewWindow -PassThru

    if ($CurlProcess.ExitCode -ne 0) {
        throw "Curl failed with exit code $($CurlProcess.ExitCode)"
    }

    PrintKV "Download Status" "SUCCESS"

    # Verify file was actually downloaded
    if (-not (Test-Path -Path $TempMsiPath -PathType Leaf)) {
        throw "File not found after download completed"
    }

    $FileSize = (Get-Item $TempMsiPath).Length
    $FileSizeMB = [math]::Round($FileSize / 1MB, 2)
    PrintKV "File Size" "$FileSizeMB MB"

} catch {
    Write-Section "ERROR OCCURRED"
    Write-Host " ERROR: Download failed for '$MsiScriptUrl'"
    Write-Host " ERROR DETAILS: $($_.Exception.Message)"
    if ($_.Exception.InnerException) {
        Write-Host " INNER ERROR: $($_.Exception.InnerException.Message)"
    }
    Cleanup-TempFile | Out-Null
    Write-Host " EXIT CODE 1: FAILURE"
    exit 1
}

# 2. Execute Silent Installation
Write-Host ""
PrintKV "Installation Status" "STARTING SILENT INSTALL"
$Arguments = "/i `"$TempMsiPath`" /qn /norestart"
PrintKV "Command Executed" "msiexec $Arguments"

# Start the process and wait for completion
$Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -PassThru -Wait -NoNewWindow
$ExitCode = $Process.ExitCode

PrintKV "Process Exit Code" $ExitCode

# 3. Final Status and Cleanup
Write-Section "FINAL STATUS"
$CleanupResult = Cleanup-TempFile
PrintKV "Cleanup Result" $CleanupResult

if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
    if ($ExitCode -eq 3010) {
        Write-Host " INSTALLATION COMPLETED SUCCESSFULLY (Reboot Required)"
    } else {
        Write-Host " INSTALLATION COMPLETED SUCCESSFULLY"
    }
    $FinalExitCode = 0
} else {
    Write-Host " INSTALLATION FAILED (msiexec returned $ExitCode)"
    $FinalExitCode = 1
}

Write-Section "SCRIPT COMPLETED"
exit $FinalExitCode
