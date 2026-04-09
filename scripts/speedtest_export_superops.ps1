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
 SCRIPT   : Speedtest to SuperOps                                         v1.1.1
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\speedtest_export_superops.ps1
================================================================================
 FILE     : speedtest_export_superops.ps1
DESCRIPTION : Runs Ookla Speedtest and syncs results to SuperOps custom fields
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

Downloads and runs Ookla Speedtest CLI, captures network performance metrics,
and synchronizes the results to SuperOps custom fields for monitoring and
reporting. Designed for RMM automation to track internet connectivity quality.

DATA SOURCES & PRIORITY

1. Ookla Speedtest CLI (primary) - official binary from install.speedtest.net
2. SuperOps custom fields (output) - decimal and text fields for metrics

REQUIRED INPUTS

All inputs are hardcoded in the script body:
  - $superOpsModule      : SuperOps PowerShell module variable (non-empty string)
  - $downloadUrl         : Speedtest CLI download URL (valid HTTPS URL)
  - $zipPath             : Temporary ZIP file location (valid path string)
  - $extractPath         : CLI extraction directory (valid path string)
  - $exePath             : Path to speedtest.exe after extraction (valid path string)

SuperOps Custom Fields (must exist in tenant):
  - "Download Speed"     : Decimal field for Mbps download rate
  - "Upload Speed"       : Decimal field for Mbps upload rate
  - "ISP"                : Short Text field for ISP name
  - "Speedtest URL"      : Short Text field for result URL

SETTINGS

  - Download URL     : https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip
  - Extraction Path  : $env:TEMP\SpeedtestCLI
  - Speed Units      : Mbps (megabits per second)
  - Precision        : Full decimal precision (no rounding)
  - Timeout          : Uses PowerShell defaults (Invoke-WebRequest, Expand-Archive)

BEHAVIOR

1. Validates all hardcoded input values are present
2. Creates extraction directory if it doesn't exist
3. Downloads Speedtest CLI ZIP if speedtest.exe is not present
4. Extracts ZIP archive and removes temporary ZIP file
5. Executes speedtest with JSON output format (auto-accepts license/GDPR)
6. Parses JSON results and calculates Mbps from bandwidth bytes
7. Sends four custom fields to SuperOps: Download Speed, Upload Speed, ISP, URL
8. Reports detailed metrics to console (ping, jitter, packet loss, server info)
9. Exits 0 on success, exits 1 if any critical step fails

PREREQUISITES

  - SuperOps PowerShell module must be available and authenticated
  - Internet connectivity for downloading CLI and running speedtest
  - Write permissions to $env:TEMP directory
  - Windows OS with PowerShell 5.1+ or PowerShell 7+
  - No admin privileges required

SECURITY NOTES

  - No secrets are printed to console output or logs
  - External IP address is displayed but not sent to SuperOps (informational only)
  - Speedtest CLI auto-accepts license and GDPR terms
  - All network operations use HTTPS where applicable

ENDPOINTS

  - Speedtest CLI Download : https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip
  - Speedtest Servers      : Ookla server network (auto-selected based on location)
  - SuperOps API           : Via Send-CustomField cmdlet (module handles endpoint)

EXIT CODES

  0 = Success - speedtest completed and data sent to SuperOps
  1 = Failure - input validation, module import, download, extraction, speedtest, or sync failed

EXAMPLE RUN

  [INFO] INPUT VALIDATION
  ==============================================================
  All required inputs are present

  [INFO] DOWNLOAD
  ==============================================================
  Created extraction directory
  Extraction Path : C:\Users\admin\AppData\Local\Temp\SpeedtestCLI
  Downloading Speedtest CLI archive
  Source URL : https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip
  Downloaded Speedtest CLI archive
  Archive Size : 7.3 MB

  [INFO] EXTRACTION
  ==============================================================
  Extracting Speedtest CLI archive
  Extracted Speedtest CLI successfully
  Executable Path : C:\Users\admin\AppData\Local\Temp\SpeedtestCLI\speedtest.exe
  Removed temporary ZIP file

  [RUN] SPEED TEST
  ==============================================================
  Executing speedtest (this may take 30-60 seconds)
  Speedtest completed successfully

  [OK] RESULTS
  ==============================================================
  Download Speed  : 357.32 Mbps
  Upload Speed    : 41.93 Mbps
  Ping Latency    : 12.5 ms
  Ping Jitter     : 0.8 ms
  Packet Loss     : 0%
  ISP             : Comcast Cable
  External IP     : 73.XXX.XXX.XXX
  Server Name     : Speedtest.net Server
  Server Location : Seattle, WA
  Server Host     : speedtest.example.net
  Server IP       : 198.XXX.XXX.XXX
  Result URL      : https://www.speedtest.net/result/c/a1b2c3d4-e5f6

  [RUN] SUPEROPS SYNC
  ==============================================================
  Sent Download Speed to SuperOps
  Sent Upload Speed to SuperOps
  Sent ISP to SuperOps
  Sent Speedtest URL to SuperOps
  All custom fields synchronized successfully

  [OK] FINAL STATUS
  ==============================================================
  Status : Success
  Metrics captured and synchronized to SuperOps

  [OK] SCRIPT COMPLETED
  ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-10-31 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

$downloadUrl    = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'
$zipPath        = "$env:TEMP\speedtest.zip"
$extractPath    = "$env:TEMP\SpeedtestCLI"
$exePath        = Join-Path $extractPath "speedtest.exe"

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText     = ""

if ([string]::IsNullOrWhiteSpace($superOpsModule)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps module variable is not set"
}

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Download URL is required"
}

if ([string]::IsNullOrWhiteSpace($extractPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Extract path is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify SuperOps module is configured in RMM environment"
    Write-Host "- Check hardcoded variables in script body"
    exit 1
}

Write-Host "All required inputs are present"

# ============================================================================
# DOWNLOAD
# ============================================================================

Write-Host ""
Write-Host "[INFO] DOWNLOAD"
Write-Host "=============================================================="

# Create extraction directory if needed
if (-not (Test-Path $extractPath)) {
    try {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Write-Host "Created extraction directory"
        Write-Host "Extraction Path : $extractPath"
    } catch {
        Write-Host ""
        Write-Host "[ERROR] FAILED TO CREATE EXTRACTION DIRECTORY"
        Write-Host "=============================================================="
        Write-Host "Error Message:"
        Write-Host $_.Exception.Message
        Write-Host ""
        Write-Host "Attempted Path:"
        Write-Host $extractPath
        Write-Host ""
        Write-Host "Troubleshooting:"
        Write-Host "- Verify write permissions to TEMP directory"
        Write-Host "- Check available disk space"
        exit 1
    }
}

# Download if speedtest.exe is not already present
if (-not (Test-Path $exePath)) {
    try {
        Write-Host "Downloading Speedtest CLI archive"
        Write-Host "Source URL : $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -ErrorAction Stop

        $zipSize = (Get-Item $zipPath).Length
        $zipSizeMB = [math]::Round($zipSize / 1MB, 1)
        Write-Host "Downloaded Speedtest CLI archive"
        Write-Host "Archive Size : $zipSizeMB MB"
    } catch {
        Write-Host ""
        Write-Host "[ERROR] FAILED TO DOWNLOAD SPEEDTEST CLI"
        Write-Host "=============================================================="
        Write-Host "Error Message:"
        Write-Host $_.Exception.Message
        Write-Host ""
        Write-Host "Download URL:"
        Write-Host $downloadUrl
        Write-Host ""
        Write-Host "Troubleshooting:"
        Write-Host "- Verify internet connectivity"
        Write-Host "- Check if URL is accessible from this network"
        Write-Host "- Ensure no proxy or firewall is blocking the download"
        exit 1
    }
} else {
    Write-Host "Speedtest CLI already present"
    Write-Host "Executable Path : $exePath"
}

# ============================================================================
# EXTRACTION
# ============================================================================

Write-Host ""
Write-Host "[INFO] EXTRACTION"
Write-Host "=============================================================="

if (Test-Path $exePath) {
    Write-Host "Speedtest executable already extracted"
    Write-Host "Skipping extraction step"
} else {
    try {
        Write-Host "Extracting Speedtest CLI archive"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Write-Host "Extracted Speedtest CLI successfully"
        Write-Host "Executable Path : $exePath"

        # Clean up ZIP file
        Remove-Item $zipPath -Force
        Write-Host "Removed temporary ZIP file"
    } catch {
        Write-Host ""
        Write-Host "[ERROR] FAILED TO EXTRACT SPEEDTEST CLI"
        Write-Host "=============================================================="
        Write-Host "Error Message:"
        Write-Host $_.Exception.Message
        Write-Host ""
        Write-Host "Archive Path:"
        Write-Host $zipPath
        Write-Host ""
        Write-Host "Troubleshooting:"
        Write-Host "- Verify ZIP file was downloaded completely"
        Write-Host "- Check for disk space in extraction directory"
        Write-Host "- Ensure no antivirus is blocking the extraction"
        exit 1
    }
}

# ============================================================================
# SPEED TEST
# ============================================================================

Write-Host ""
Write-Host "[RUN] SPEED TEST"
Write-Host "=============================================================="

try {
    Write-Host "Executing speedtest (this may take 30-60 seconds)"
    $speedtestResult = & "$exePath" --accept-license --accept-gdpr --format json

    # Parse JSON output
    $speedData = $speedtestResult | ConvertFrom-Json

    Write-Host "Speedtest completed successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] FAILED TO EXECUTE SPEEDTEST"
    Write-Host "=============================================================="
    Write-Host "Error Message:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Executable Path:"
    Write-Host $exePath
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify internet connectivity for speedtest servers"
    Write-Host "- Check if speedtest.exe has execute permissions"
    Write-Host "- Ensure no firewall is blocking speedtest traffic"
    exit 1
}

# Validate essential data is present
if (-not $speedData.download -or -not $speedData.upload) {
    Write-Host ""
    Write-Host "[ERROR] INVALID SPEEDTEST DATA"
    Write-Host "=============================================================="
    Write-Host "Speedtest did not return valid upload/download data"
    Write-Host ""
    Write-Host "Returned Data:"
    Write-Host ($speedData | ConvertTo-Json -Depth 2)
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Check network connection stability"
    Write-Host "- Verify speedtest servers are accessible"
    Write-Host "- Try running speedtest.exe manually to diagnose"
    exit 1
}

# ============================================================================
# RESULTS
# ============================================================================

Write-Host ""
Write-Host "[OK] RESULTS"
Write-Host "=============================================================="

# Calculate speeds in Mbps (no rounding for decimal precision)
$downloadMbps = ($speedData.download.bandwidth * 8 / 1MB)
$uploadMbps   = ($speedData.upload.bandwidth * 8 / 1MB)
$pingLatency  = $speedData.ping.latency
$pingJitter   = $speedData.ping.jitter

# Handle optional properties that may not always be present
$packetLoss   = if ($speedData.PSObject.Properties.Name -contains 'packetLoss') { $speedData.packetLoss } else { 0 }
$ispName      = if ($speedData.PSObject.Properties.Name -contains 'isp') { $speedData.isp } else { 'Unknown' }
$externalIP   = if ($speedData.interface.PSObject.Properties.Name -contains 'externalIp') { $speedData.interface.externalIp } else { 'Unknown' }
$serverName   = if ($speedData.server.PSObject.Properties.Name -contains 'name') { $speedData.server.name } else { 'Unknown' }
$serverLoc    = if ($speedData.server.PSObject.Properties.Name -contains 'location') { $speedData.server.location } else { 'Unknown' }
$serverHost   = if ($speedData.server.PSObject.Properties.Name -contains 'host') { $speedData.server.host } else { 'Unknown' }
$serverIP     = if ($speedData.server.PSObject.Properties.Name -contains 'ip') { $speedData.server.ip } else { 'Unknown' }
$resultUrl    = if ($speedData.result.PSObject.Properties.Name -contains 'url') { $speedData.result.url } else { 'Not available' }

Write-Host "Download Speed  : $downloadMbps Mbps"
Write-Host "Upload Speed    : $uploadMbps Mbps"
Write-Host "Ping Latency    : $pingLatency ms"
Write-Host "Ping Jitter     : $pingJitter ms"
Write-Host "Packet Loss     : $packetLoss%"
Write-Host "ISP             : $ispName"
Write-Host "External IP     : $externalIP"
Write-Host "Server Name     : $serverName"
Write-Host "Server Location : $serverLoc"
Write-Host "Server Host     : $serverHost"
Write-Host "Server IP       : $serverIP"
Write-Host "Result URL      : $resultUrl"

# ============================================================================
# SUPEROPS SYNC
# ============================================================================

Write-Host ""
Write-Host "[RUN] SUPEROPS SYNC"
Write-Host "=============================================================="

$syncErrorOccurred = $false
$syncErrorText     = ""

# Send Download Speed
try {
    Send-CustomField -CustomFieldName "Download Speed" -Value $downloadMbps -ErrorAction Stop
    Write-Host "Sent Download Speed to SuperOps"
} catch {
    $syncErrorOccurred = $true
    if ($syncErrorText.Length -gt 0) { $syncErrorText += "`n" }
    $syncErrorText += "- Download Speed: $($_.Exception.Message)"
}

# Send Upload Speed
try {
    Send-CustomField -CustomFieldName "Upload Speed" -Value $uploadMbps -ErrorAction Stop
    Write-Host "Sent Upload Speed to SuperOps"
} catch {
    $syncErrorOccurred = $true
    if ($syncErrorText.Length -gt 0) { $syncErrorText += "`n" }
    $syncErrorText += "- Upload Speed: $($_.Exception.Message)"
}

# Send ISP
try {
    Send-CustomField -CustomFieldName "ISP" -Value $ispName -ErrorAction Stop
    Write-Host "Sent ISP to SuperOps"
} catch {
    $syncErrorOccurred = $true
    if ($syncErrorText.Length -gt 0) { $syncErrorText += "`n" }
    $syncErrorText += "- ISP: $($_.Exception.Message)"
}

# Send Speedtest URL
try {
    Send-CustomField -CustomFieldName "Speedtest URL" -Value $resultUrl -ErrorAction Stop
    Write-Host "Sent Speedtest URL to SuperOps"
} catch {
    $syncErrorOccurred = $true
    if ($syncErrorText.Length -gt 0) { $syncErrorText += "`n" }
    $syncErrorText += "- Speedtest URL: $($_.Exception.Message)"
}

if ($syncErrorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] SUPEROPS SYNC FAILED"
    Write-Host "=============================================================="
    Write-Host "Failed to send one or more custom fields:"
    Write-Host $syncErrorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify custom fields exist in SuperOps tenant"
    Write-Host "- Check field names match exactly (case-sensitive)"
    Write-Host "- Ensure field types are correct (Decimal for speeds, Short Text for ISP/URL)"
    Write-Host "- Verify SuperOps authentication is still valid"
    exit 1
}

Write-Host "All custom fields synchronized successfully"

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status : Success"
Write-Host "Metrics captured and synchronized to SuperOps"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
