$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : PotPlayer Install                                              v1.0.0
FILE   : potplayer_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads and silently installs PotPlayer media player. Automatically
    selects the correct version (32-bit or 64-bit) based on system architecture.

REQUIRED INPUTS:
    $baseUrl : Base URL for PotPlayer website to scrape download links

BEHAVIOR:
    1. Validates input parameters
    2. Fetches PotPlayer website to find download links
    3. Selects appropriate version based on OS architecture
    4. Downloads installer to temp directory
    5. Installs silently using /S switch
    6. Cleans up installer file

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Internet connectivity

SECURITY NOTES:
    - No secrets in logs
    - Downloads from official PotPlayer website

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Base URL : https://potplayer.daum.net
    System : 64-bit
    Inputs validated successfully

    [ DOWNLOAD ]
    --------------------------------------------------------------
    Fetching download links from PotPlayer website...
    Found installer for 64-bit system
    Downloading PotPlayer installer...
    Download completed successfully

    [ INSTALLATION ]
    --------------------------------------------------------------
    Installing PotPlayer silently...
    Installation completed successfully

    [ CLEANUP ]
    --------------------------------------------------------------
    Removing installer file...
    Cleanup completed

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    PotPlayer installed successfully

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
$baseUrl = 'https://potplayer.daum.net'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Base URL is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

$systemArch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
Write-Host "Base URL : $baseUrl"
Write-Host "System : $systemArch"
Write-Host "Inputs validated successfully"

# ============================================================================
# DOWNLOAD
# ============================================================================
Write-Host ""
Write-Host "[ DOWNLOAD ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Fetching download links from PotPlayer website..."
    $webContent = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing
    $links = $webContent.Links.Href | Where-Object { $_ -match '.*PotPlayerSetup(64)?.exe$' } | Select-Object -Unique

    if (-not $links) {
        throw "Could not find download links on PotPlayer website"
    }

    $installerLink = if ([Environment]::Is64BitOperatingSystem) {
        $links | Where-Object { $_ -match '64' } | Select-Object -First 1
    } else {
        $links | Where-Object { $_ -notmatch '64' } | Select-Object -First 1
    }

    if (-not $installerLink) {
        throw "Could not find appropriate installer for $systemArch system"
    }

    Write-Host "Found installer for $systemArch system"

    $installerPath = Join-Path -Path $env:TEMP -ChildPath (Split-Path -Leaf $installerLink)
    Write-Host "Downloading PotPlayer installer..."
    Invoke-WebRequest -Uri $installerLink -OutFile $installerPath -UseBasicParsing
    Write-Host "Download completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download PotPlayer"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# INSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

try {
    Write-Host "Installing PotPlayer silently..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "Installation failed with exit code: $($process.ExitCode)"
    }

    Write-Host "Installation completed successfully"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to install PotPlayer"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Removing installer file..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "Cleanup completed"

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "PotPlayer installed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
