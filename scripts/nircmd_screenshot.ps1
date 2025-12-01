$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Screenshot Capture using NirCmd                                v1.0.0
FILE   : nircmd_screenshot.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Captures a screenshot of the current display using NirSoft's NirCmd utility.
    Downloads NirCmd if not already present, then saves a timestamped screenshot.

REQUIRED INPUTS:
    $destinationFolder : Folder to store NirCmd and screenshots
    $screenshotFolder  : Subfolder for screenshot files

BEHAVIOR:
    1. Creates destination directories if they don't exist
    2. Downloads NirCmd (x64 or x86 based on OS architecture)
    3. Extracts NirCmd from zip archive
    4. Captures screenshot with timestamped filename
    5. Cleans up temporary zip file

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Internet access for NirCmd download
    - Write permissions to destination folder

SECURITY NOTES:
    - Downloads from official NirSoft website
    - No secrets in logs
    - Screenshots saved locally only

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Destination : C:\limehawk\nirsoft
    Screenshot Dir : C:\limehawk\nirsoft\screenshots

    [ DOWNLOADING NIRCMD ]
    --------------------------------------------------------------
    Architecture : x64
    Download URL : https://www.nirsoft.net/utils/nircmd-x64.zip
    Download complete

    [ CAPTURING SCREENSHOT ]
    --------------------------------------------------------------
    Filename : screenshot_20241201-143022.png
    Saved to : C:\limehawk\nirsoft\screenshots\screenshot_20241201-143022.png

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$destinationFolder = "$env:SystemDrive\limehawk\nirsoft"
$screenshotFolder = "$destinationFolder\screenshots"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Destination    : $destinationFolder"
Write-Host "Screenshot Dir : $screenshotFolder"

# ============================================================================
# DETERMINE DOWNLOAD URL
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOADING NIRCMD ]"
Write-Host "--------------------------------------------------------------"

if ([Environment]::Is64BitOperatingSystem) {
    $downloadUrl = "https://www.nirsoft.net/utils/nircmd-x64.zip"
    Write-Host "Architecture   : x64"
}
else {
    $downloadUrl = "https://www.nirsoft.net/utils/nircmd.zip"
    Write-Host "Architecture   : x86"
}

Write-Host "Download URL   : $downloadUrl"

$zipFileName = Split-Path -Leaf $downloadUrl
$zipPath = Join-Path -Path $destinationFolder -ChildPath $zipFileName
$exePath = Join-Path -Path $destinationFolder -ChildPath "nircmd.exe"

try {
    # Create destination directory
    if (-not (Test-Path -Path $destinationFolder)) {
        New-Item -ItemType Directory -Force -Path $destinationFolder | Out-Null
        Write-Host "Created destination directory"
    }

    # Create screenshot directory
    if (-not (Test-Path -Path $screenshotFolder)) {
        New-Item -ItemType Directory -Force -Path $screenshotFolder | Out-Null
        Write-Host "Created screenshot directory"
    }

    # Download NirCmd if not present
    if (-not (Test-Path -Path $exePath)) {
        Write-Host "Downloading NirCmd..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Write-Host "Download complete"

        Write-Host "Extracting..."
        Expand-Archive -Path $zipPath -DestinationPath $destinationFolder -Force
        Write-Host "Extraction complete"

        # Clean up zip file
        Remove-Item -Path $zipPath -Force
        Write-Host "Cleaned up zip file"
    }
    else {
        Write-Host "NirCmd already installed"
    }
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download/install NirCmd"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# CAPTURE SCREENSHOT
# ============================================================================
Write-Host ""
Write-Host "[ CAPTURING SCREENSHOT ]"
Write-Host "--------------------------------------------------------------"

try {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $screenshotPath = Join-Path -Path $screenshotFolder -ChildPath "screenshot_$timestamp.png"

    Write-Host "Filename       : screenshot_$timestamp.png"

    Start-Process -FilePath $exePath -ArgumentList "savescreenshot `"$screenshotPath`"" -Wait -NoNewWindow

    if (Test-Path -Path $screenshotPath) {
        Write-Host "Saved to       : $screenshotPath"
    }
    else {
        throw "Screenshot file was not created"
    }
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to capture screenshot"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Screenshot saved to: $screenshotPath"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
