$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Set Display Resolution using NirCmd                            v1.0.0
FILE   : nircmd_set_resolution.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Changes the display resolution using NirSoft's NirCmd utility.
    Downloads NirCmd if not already present, then sets the specified resolution.

REQUIRED INPUTS:
    $resolutionWidth  : Desired screen width in pixels (e.g., 1920)
    $resolutionHeight : Desired screen height in pixels (e.g., 1080)
    $colorDepth       : Color depth in bits (e.g., 32)
    $destinationFolder : Folder to store NirCmd utility

BEHAVIOR:
    1. Creates destination directory if it doesn't exist
    2. Downloads NirCmd (x86 version for compatibility)
    3. Extracts NirCmd from zip archive
    4. Sets display resolution to specified values
    5. Cleans up temporary zip file

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Internet access for NirCmd download
    - Display must support the requested resolution

SECURITY NOTES:
    - Downloads from official NirSoft website
    - No secrets in logs

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Resolution : 1920 x 1080
    Color Depth : 32-bit
    Destination : C:\limehawk\nircmd

    [ DOWNLOADING NIRCMD ]
    --------------------------------------------------------------
    Download URL : https://www.nirsoft.net/utils/nircmd.zip
    Download complete

    [ CHANGING RESOLUTION ]
    --------------------------------------------------------------
    Executing : nircmd.exe setdisplay 1920 1080 32
    Resolution changed successfully

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
$resolutionWidth = 1920
$resolutionHeight = 1080
$colorDepth = 32
$destinationFolder = "$env:SystemDrive\limehawk\nircmd"

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ($resolutionWidth -lt 640 -or $resolutionWidth -gt 7680) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Resolution width must be between 640 and 7680"
}

if ($resolutionHeight -lt 480 -or $resolutionHeight -gt 4320) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Resolution height must be between 480 and 4320"
}

if ($colorDepth -notin @(8, 16, 24, 32)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Color depth must be 8, 16, 24, or 32"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"
    exit 1
}

Write-Host "Resolution   : $resolutionWidth x $resolutionHeight"
Write-Host "Color Depth  : $colorDepth-bit"
Write-Host "Destination  : $destinationFolder"

# ============================================================================
# DOWNLOAD NIRCMD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOADING NIRCMD ]"
Write-Host "--------------------------------------------------------------"

$downloadUrl = "https://www.nirsoft.net/utils/nircmd.zip"
$zipPath = Join-Path -Path $destinationFolder -ChildPath "nircmd.zip"
$exePath = Join-Path -Path $destinationFolder -ChildPath "nircmd.exe"

Write-Host "Download URL : $downloadUrl"

try {
    # Create destination directory
    if (-not (Test-Path -Path $destinationFolder)) {
        New-Item -ItemType Directory -Force -Path $destinationFolder | Out-Null
        Write-Host "Created destination directory"
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
# CHANGE RESOLUTION
# ============================================================================
Write-Host ""
Write-Host "[ CHANGING RESOLUTION ]"
Write-Host "--------------------------------------------------------------"

try {
    $arguments = "setdisplay $resolutionWidth $resolutionHeight $colorDepth"
    Write-Host "Executing    : nircmd.exe $arguments"

    Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -NoNewWindow

    Write-Host "Resolution changed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to change resolution"
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
Write-Host "Display resolution set to $resolutionWidth x $resolutionHeight @ $colorDepth-bit"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
