$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : DeskView Install                                               v1.0.0
FILE   : deskview_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads deskview.exe utility to the Windows Startup folder so it runs
    automatically at user login. DeskView displays desktop icons in a compact
    window.

REQUIRED INPUTS:
    $downloadUrl : URL to download deskview.exe

BEHAVIOR:
    1. Validates input parameters
    2. Downloads deskview.exe to the common Startup folder
    3. Reports final status

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Downloads from trusted GitHub repository

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Download URL : https://github.com/focusmade/rmm-apps/raw/main/...
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Downloading deskview.exe to startup folder...
    Download completed successfully
    Destination : C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    DeskView installed to startup folder

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
$downloadUrl = 'https://github.com/focusmade/rmm-apps/raw/main/utilities/deskview/deskview.exe'
$startupPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Download URL is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Download URL : $downloadUrl"
Write-Host "Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

$localExePath = Join-Path -Path $startupPath -ChildPath "deskview.exe"

try {
    Write-Host "Downloading deskview.exe to startup folder..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $localExePath -UseBasicParsing

    if (-not (Test-Path $localExePath)) {
        throw "File was not downloaded"
    }

    Write-Host "Download completed successfully"
    Write-Host "Destination : $startupPath"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download deskview.exe"
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
Write-Host "DeskView installed to startup folder"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
