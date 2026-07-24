$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SentinelOne Install                                           v1.0.2
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\sentinelone_install.ps1
================================================================================
 FILE     : sentinelone_install.ps1
DESCRIPTION : Silently installs SentinelOne endpoint agent with site token
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Installs SentinelOne endpoint agent silently using a site token. Downloads
   the installer from ConnectWise CDN (or custom URL) and performs installation
   with verification. Skips if already installed.

   NOTE: The installed version will auto-update based on your S1 console
   Auto-Upgrade Policy settings. Initial installer version doesn't matter.

 DATA SOURCES & PRIORITY

   1) Hardcoded site token (REQUIRED)
   2) ConnectWise CDN for installer (default) or custom URL

 REQUIRED INPUTS

   - $SiteToken : SentinelOne site token for agent registration (REQUIRED)
                  Injected at runtime from the Level custom field
                  cf_s1_site_token ({{cf_s1_site_token}} placeholder)

 SETTINGS

   - $InstallerUrl    : URL to download installer (defaults to CW CDN)
   - $UseExe          : Use EXE installer ($true) or MSI ($false)
   - $TempPath        : Local path for downloaded installer
   - $SkipIfInstalled : Skip if SentinelOne already present
   - $CleanupAfter    : Remove installer after completion

 BEHAVIOR

   1. Checks if SentinelOne is already installed (optional skip)
   2. Auto-detects 32-bit vs 64-bit OS
   3. Downloads installer from URL
   4. Runs silent installation with site token
   5. Verifies installation success
   6. Cleans up temporary files

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges required
   - Network access to download URL

 SECURITY NOTES

   - Site token is embedded in script - protect accordingly
   - Default CDN URL uses HTTPS

 EXIT CODES

   0 = Success (installed or already present)
   1 = Failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Site Token       : eyJ...***
 Architecture     : 64-bit
 Installer Type   : EXE

 [RUN] PRE-CHECK
 ==============================================================
 Checking for existing installation...
 SentinelOne not detected

 [RUN] DOWNLOAD
 ==============================================================
 Downloading 64-bit EXE installer...
 Download complete (61.5 MB)

 [RUN] INSTALLATION
 ==============================================================
 Starting silent installation...
 Installer completed with exit code 0

 [RUN] VERIFICATION
 ==============================================================
 Attempt 1: Checking...
 SentinelOne detected

 [OK] FINAL STATUS
 ==============================================================
 Result : SUCCESS

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-24 v1.0.2 SiteToken from Level custom field {{cf_s1_site_token}} (adopts
                   edit made in Level UI); fail if placeholder is unsubstituted
 2026-01-19 v1.0.1 Updated to two-line ASCII console output style
 2025-12-28 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== HARDCODED INPUTS (MANDATORY) ====

# --- REQUIRED: Your SentinelOne Site Token ---
$SiteToken = "{{cf_s1_site_token}}"  # Get from S1 Console > Sentinels > Site Info

# --- Installer Options ---
$UseExe          = $false  # $true = EXE installer, $false = MSI installer (recommended)
$SkipIfInstalled = $true   # Skip if SentinelOne already present
$CleanupAfter    = $true   # Remove installer after completion
$TempPath        = "C:\temp\SentinelOne"

# --- Custom URL (leave empty to use ConnectWise CDN) ---
$CustomInstallerUrl = ""

# --- Verification Settings ---
$MaxVerifyAttempts  = 5
$VerifyDelaySeconds = 3

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($SiteToken)) {
    $errorOccurred = $true
    $errorText = "SiteToken is required. Get from S1 Console > Sentinels > Site Info"
} elseif ($SiteToken -match '^\{\{.*\}\}$') {
    # Level custom-field placeholder was not substituted (cf_s1_site_token unset)
    $errorOccurred = $true
    $errorText = "SiteToken custom field was not substituted - set cf_s1_site_token in Level"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== DETECT ARCHITECTURE ====
$is64Bit = [Environment]::Is64BitOperatingSystem
$arch = if ($is64Bit) { "64bit" } else { "32bit" }
$archDisplay = if ($is64Bit) { "64-bit" } else { "32-bit" }

# ==== BUILD INSTALLER URL ====
if ([string]::IsNullOrWhiteSpace($CustomInstallerUrl)) {
    $ext = if ($UseExe) { "exe" } else { "msi" }
    $InstallerUrl = "https://cwa.connectwise.com/tools/sentinelone/SentinelOneAgent-Windows_$arch.$ext"
} else {
    $InstallerUrl = $CustomInstallerUrl
}

# ==== HELPER FUNCTION ====
function Test-SentinelOneInstalled {
    $paths = @(
        "C:\Program Files\SentinelOne",
        "C:\Program Files (x86)\SentinelOne"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
$maskedToken = if ($SiteToken.Length -gt 10) { $SiteToken.Substring(0,10) + "***" } else { "***" }
Write-Host "Site Token       : $maskedToken"
Write-Host "Architecture     : $archDisplay"
Write-Host "Installer Type   : $(if ($UseExe) { 'EXE' } else { 'MSI' })"

# ==== PRE-CHECK ====
Write-Host ""
Write-Host "[RUN] PRE-CHECK"
Write-Host "=============================================================="
Write-Host "Checking for existing installation..."

$existingPath = Test-SentinelOneInstalled
if ($existingPath) {
    if ($SkipIfInstalled) {
        Write-Host "SentinelOne already installed at: $existingPath"
        Write-Host ""
        Write-Host "[OK] FINAL STATUS"
        Write-Host "=============================================================="
        Write-Host "Result : SUCCESS (already installed)"
        Write-Host ""
        Write-Host "[OK] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 0
    } else {
        Write-Host "SentinelOne detected, reinstalling..."
    }
} else {
    Write-Host "SentinelOne not detected"
}

# ==== DOWNLOAD ====
Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="

$installerExt = if ($UseExe) { "exe" } else { "msi" }
$installerPath = "$TempPath\SentinelOneInstaller.$installerExt"

try {
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Downloading $archDisplay $($installerExt.ToUpper()) installer..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($InstallerUrl, $installerPath)

    if (Test-Path $installerPath) {
        $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
        Write-Host "Download complete ($sizeMB MB)"
    } else {
        throw "Installer not found after download"
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] DOWNLOAD FAILED"
    Write-Host "=============================================================="
    Write-Host "Download failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== INSTALLATION ====
Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

try {
    Write-Host "Starting silent installation..."

    if ($UseExe) {
        # EXE installer
        $args = "-t `"$SiteToken`" --dont_fail_on_config_preserving_failures"
        $proc = Start-Process -FilePath $installerPath -ArgumentList $args -Wait -PassThru
    } else {
        # MSI installer
        $args = "/i `"$installerPath`" /qn SITE_TOKEN=`"$SiteToken`""
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru
    }

    Write-Host "Installer completed with exit code: $($proc.ExitCode)"

} catch {
    Write-Host ""
    Write-Host "[ERROR] INSTALLATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Installation failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== VERIFICATION ====
Write-Host ""
Write-Host "[RUN] VERIFICATION"
Write-Host "=============================================================="

$verified = $false
$attempt = 0

while (-not $verified -and $attempt -lt $MaxVerifyAttempts) {
    $attempt++
    Start-Sleep -Seconds $VerifyDelaySeconds
    Write-Host "Attempt $attempt : Checking..."

    $installedPath = Test-SentinelOneInstalled
    if ($installedPath) {
        Write-Host "SentinelOne detected at $installedPath"
        $verified = $true
    }
}

if (-not $verified) {
    Write-Host "SentinelOne not detected after $MaxVerifyAttempts attempts"
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : FAILED - Installation could not be verified"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== CLEANUP ====
if ($CleanupAfter) {
    Write-Host ""
    Write-Host "[RUN] CLEANUP"
    Write-Host "=============================================================="
    try {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Temporary files removed"
    } catch {
        Write-Host "Cleanup warning: $($_.Exception.Message)"
    }
}

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Result : SUCCESS"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
