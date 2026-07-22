$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows 11 25H2 Install                                      v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windows11_25h2_install.ps1
================================================================================
 FILE     : windows11_25h2_install.ps1
 DESCRIPTION : Silently install Windows 11 25H2 (KB5054156) for Level RMM
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Silently installs Windows 11, version 25H2 by applying Microsoft enablement
   package KB5054156. Built for Level RMM (run as System). On Windows 11 24H2
   (build 26100) with the required CU, this is a small "master switch" that
   activates already-present 25H2 features after one restart. Not a full ISO
   feature upgrade path.

 DATA SOURCES & PRIORITY

   - Registry HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion
     (DisplayVersion, CurrentBuild/CurrentBuildNumber, UBR, ProductName)
   - Win32_OperatingSystem Caption for OS family confirmation
   - PROCESSOR_ARCHITECTURE / PROCESSOR_ARCHITEW6432 for AMD64 vs ARM64
   - Microsoft Update Catalog MSU download URLs for KB5054156 (x64 + ARM64)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body (edit in Level script library
   or clone per-policy if you need different reboot behavior):
     - $downloadUrlX64       : x64 MSU URL for KB5054156
     - $downloadUrlArm64     : ARM64 MSU URL for KB5054156
     - $minUbr               : Minimum UBR required on build 26100 (5074)
     - $requiredBuild        : Required OS build number (26100 = 24H2 core)
     - $targetDisplayVersion : Target DisplayVersion after enablement (25H2)
     - $sourceDisplayVersion : Required source DisplayVersion (24H2)
     - $rebootAfterInstall   : If $true, schedule reboot after successful apply

 SETTINGS

   Configuration defaults:
     - Download URL (x64)  : Microsoft catalog MSU for windows11.0-kb5054156-x64
     - Download URL (ARM64): Microsoft catalog MSU for windows11.0-kb5054156-arm64
     - Min UBR             : 5074 (KB5064081 or later cumulative update)
     - Required Build      : 26100
     - Source Version      : 24H2
     - Target Version      : 25H2
     - Reboot After Install: false (safe Level default; reboot still required)
     - Installer Path      : %TEMP%\windows11.0-kb5054156.msu
     - Install method      : wusa.exe <msu> /quiet /norestart
     - Level run context   : System (SYSTEM_USER)
     - Level timeout       : 60 minutes recommended (download + wusa)

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates hardcoded input values
   2. Reads OS identity from registry (DisplayVersion, build, UBR, ProductName)
   3. If already on 25H2, exits 0 (idempotent success)
   4. Fails if not Windows 11
   5. Fails if not build 26100 / not 24H2 (enablement package only path)
   6. Fails if UBR is below 5074 (install latest CU / KB5064081+ first)
   7. Selects AMD64 or ARM64 download URL
   8. Downloads the MSU to TEMP
   9. Installs silently with wusa.exe /quiet /norestart
      (exit 0 and 3010 = success; 2359302 already-installed = success)
  10. Optionally schedules reboot if $rebootAfterInstall is true
  11. Cleans up the downloaded MSU
  12. Reports final DisplayVersion/build/UBR and reboot-pending status
      (console output is captured in Level activity / script run log)

 PREREQUISITES

   - Windows PowerShell 5.1 or later
   - Level agent online; script run as System
   - Administrator / SYSTEM privileges (wusa enablement package install)
   - Windows 11 version 24H2 only (OS build 26100)
   - August 29, 2025 cumulative update KB5064081 (OS Build 26100.5074) or later
   - Internet connectivity to download the Microsoft catalog MSU
   - A restart is required after install to activate 25H2 (unless already applied)

 SECURITY NOTES

   - No secrets in logs
   - Downloads only from hardcoded Microsoft delivery catalog URLs
   - Does not perform a full ISO upgrade; scoped to enablement package only
   - Default does not force reboot; set $rebootAfterInstall = $true to schedule

 ENDPOINTS

   - x64 MSU  : catalog.sf.dl.delivery.mp.microsoft.com ... windows11.0-kb5054156-x64_*.msu
   - ARM64 MSU: catalog.sf.dl.delivery.mp.microsoft.com ... windows11.0-kb5054156-arm64_*.msu

 EXIT CODES

   0 = Success (already on 25H2, package applied, or already installed)
   1 = Failure (unsupported OS/build/CU, download/install error)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Download URL (x64)   : https://catalog.sf.dl.delivery.mp.microsoft.com/...msu
     Download URL (ARM64) : https://catalog.sf.dl.delivery.mp.microsoft.com/...msu
     Min UBR              : 5074
     Required Build       : 26100
     Source Version       : 24H2
     Target Version       : 25H2
     Reboot After Install : False
     Inputs validated successfully

   [INFO] OS DETECTION
   ==============================================================
     Product Name    : Windows 11 Pro
     Display Version : 24H2
     Build           : 26100
     UBR             : 5074
     Architecture    : AMD64

   [RUN] DOWNLOAD
   ==============================================================
     Downloading KB5054156 enablement package...
     Download completed successfully

   [RUN] INSTALLATION
   ==============================================================
     Running wusa.exe quietly (no restart)...
     Installer exit code : 3010
     Installation completed successfully (reboot required)

   [RUN] CLEANUP
   ==============================================================
     Removing MSU file...
     Cleanup completed

   [OK] FINAL STATUS
   ==============================================================
     Result           : SUCCESS
     Display Version  : 24H2
     Build.UBR        : 26100.5074
     Reboot Pending   : True
     Note             : Restart required to activate Windows 11 25H2

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-22 v1.0.0 Initial release - silent Windows 11 25H2 enablement package
                   (KB5054156) for Level RMM; x64 + ARM64 catalog MSU URLs
================================================================================
#>

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$downloadUrlX64 = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/fa84cc49-18b2-4c26-b389-90c96e6ae0d2/public/windows11.0-kb5054156-x64_a0c1638cbcf4cf33dbe9a5bef69db374b4786974.msu'
$downloadUrlArm64 = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/78b265e5-83a8-4e0a-9060-efbe0bac5bde/public/windows11.0-kb5054156-arm64_3d5c91aaeb08a87e0717f263ad4a61186746e465.msu'
$minUbr = 5074
$requiredBuild = '26100'
$targetDisplayVersion = '25H2'
$sourceDisplayVersion = '24H2'
$rebootAfterInstall = $false

Set-StrictMode -Version Latest

# ==============================================================================
# CONSTANTS
# ==============================================================================
$installerPath = Join-Path $env:TEMP 'windows11.0-kb5054156.msu'
$ntCurrentVersionPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# wusa success codes: 0 = success, 3010 = success reboot required
# 2359302 = WU_S_ALREADY_INSTALLED (package already present)
$successExitCodes = @(0, 3010, 2359302)

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($downloadUrlX64)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Download URL (x64) is required"
}

if ($minUbr -isnot [int] -and $minUbr -isnot [long]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Min UBR must be an integer"
} elseif ([int]$minUbr -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Min UBR must be a positive integer"
}

if ([string]::IsNullOrWhiteSpace($requiredBuild)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Required Build is required"
}

if ([string]::IsNullOrWhiteSpace($targetDisplayVersion)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Target Display Version is required"
}

if ([string]::IsNullOrWhiteSpace($sourceDisplayVersion)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Source Display Version is required"
}

if ($rebootAfterInstall -isnot [bool]) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Reboot After Install must be a boolean"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

$arm64Display = if ([string]::IsNullOrWhiteSpace($downloadUrlArm64)) { '(empty)' } else { $downloadUrlArm64 }

Write-Host "  Download URL (x64)   : $downloadUrlX64"
Write-Host "  Download URL (ARM64) : $arm64Display"
Write-Host "  Min UBR              : $minUbr"
Write-Host "  Required Build       : $requiredBuild"
Write-Host "  Source Version       : $sourceDisplayVersion"
Write-Host "  Target Version       : $targetDisplayVersion"
Write-Host "  Reboot After Install : $rebootAfterInstall"
Write-Host "  Inputs validated successfully"

# ==============================================================================
# HELPERS
# ==============================================================================

function Get-WindowsVersionInfo {
    $props = Get-ItemProperty -Path $ntCurrentVersionPath -ErrorAction Stop

    $displayVersion = ''
    if ($props.PSObject.Properties.Name -contains 'DisplayVersion' -and -not [string]::IsNullOrWhiteSpace($props.DisplayVersion)) {
        $displayVersion = [string]$props.DisplayVersion
    }

    $build = ''
    if ($props.PSObject.Properties.Name -contains 'CurrentBuild' -and -not [string]::IsNullOrWhiteSpace($props.CurrentBuild)) {
        $build = [string]$props.CurrentBuild
    } elseif ($props.PSObject.Properties.Name -contains 'CurrentBuildNumber' -and -not [string]::IsNullOrWhiteSpace($props.CurrentBuildNumber)) {
        $build = [string]$props.CurrentBuildNumber
    }

    $ubr = 0
    if ($props.PSObject.Properties.Name -contains 'UBR') {
        try { $ubr = [int]$props.UBR } catch { $ubr = 0 }
    }

    $productName = ''
    if ($props.PSObject.Properties.Name -contains 'ProductName' -and -not [string]::IsNullOrWhiteSpace($props.ProductName)) {
        $productName = [string]$props.ProductName
    }

    $caption = ''
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($null -ne $os -and -not [string]::IsNullOrWhiteSpace($os.Caption)) {
            $caption = [string]$os.Caption
        }
    } catch {
        $caption = ''
    }

    # Prefer native architecture under WOW64 if present
    $arch = $env:PROCESSOR_ARCHITECTURE
    if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        $arch = $env:PROCESSOR_ARCHITEW6432
    }
    if ([string]::IsNullOrWhiteSpace($arch)) {
        $arch = 'UNKNOWN'
    }

    return @{
        DisplayVersion = $displayVersion
        Build          = $build
        Ubr            = $ubr
        ProductName    = $productName
        Caption        = $caption
        Architecture   = $arch.ToUpperInvariant()
    }
}

function Test-IsWindows11 {
    param(
        [string]$ProductName,
        [string]$Caption
    )

    $blob = ("$ProductName $Caption").ToLowerInvariant()
    return ($blob -match 'windows 11')
}

function Test-RebootPending {
    $pending = $false

    try {
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $pending = $true
        }
    } catch { }

    try {
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $pending = $true
        }
    } catch { }

    return $pending
}

# ==============================================================================
# OS DETECTION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] OS DETECTION"
Write-Host "=============================================================="

try {
    $osInfo = Get-WindowsVersionInfo
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to read Windows version information"
    Write-Host "  Path  : $ntCurrentVersionPath"
    Write-Host "  Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host "  Product Name    : $($osInfo.ProductName)"
if (-not [string]::IsNullOrWhiteSpace($osInfo.Caption)) {
    Write-Host "  Caption         : $($osInfo.Caption)"
}
Write-Host "  Display Version : $($osInfo.DisplayVersion)"
Write-Host "  Build           : $($osInfo.Build)"
Write-Host "  UBR             : $($osInfo.Ubr)"
Write-Host "  Architecture    : $($osInfo.Architecture)"

# Already on target version - idempotent success
if ($osInfo.DisplayVersion -eq $targetDisplayVersion) {
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Result           : SUCCESS"
    Write-Host "  Display Version  : $($osInfo.DisplayVersion)"
    Write-Host "  Build.UBR        : $($osInfo.Build).$($osInfo.Ubr)"
    Write-Host "  Note             : Already on Windows 11 $targetDisplayVersion - no action needed"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

if (-not (Test-IsWindows11 -ProductName $osInfo.ProductName -Caption $osInfo.Caption)) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  This script only supports Windows 11"
    Write-Host "  Product Name : $($osInfo.ProductName)"
    Write-Host "  Caption      : $($osInfo.Caption)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

if ($osInfo.Build -ne $requiredBuild -or $osInfo.DisplayVersion -ne $sourceDisplayVersion) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Enablement package KB5054156 only works from Windows 11 $sourceDisplayVersion (build $requiredBuild)"
    Write-Host "  Current Display Version : $($osInfo.DisplayVersion)"
    Write-Host "  Current Build           : $($osInfo.Build)"
    Write-Host "  This script does not perform a full feature update / ISO upgrade path"
    Write-Host "  Upgrade the device to Windows 11 $sourceDisplayVersion with a recent CU first"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

if ([int]$osInfo.Ubr -lt [int]$minUbr) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Cumulative update prerequisite not met"
    Write-Host "  Required : build $requiredBuild UBR $minUbr or later (KB5064081+)"
    Write-Host "  Current  : build $($osInfo.Build) UBR $($osInfo.Ubr)"
    Write-Host "  Install the latest Windows 11 cumulative update, then re-run this script"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# ARCHITECTURE / URL SELECTION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] ARCHITECTURE"
Write-Host "=============================================================="

$selectedUrl = ''
$selectedArch = $osInfo.Architecture

if ($selectedArch -eq 'AMD64' -or $selectedArch -eq 'X64') {
    $selectedUrl = $downloadUrlX64
    $selectedArch = 'AMD64'
    Write-Host "  Architecture : AMD64"
    Write-Host "  Package URL  : $selectedUrl"
} elseif ($selectedArch -eq 'ARM64') {
    Write-Host "  Architecture : ARM64"
    if ([string]::IsNullOrWhiteSpace($downloadUrlArm64)) {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "  ARM64 download URL is empty in hardcoded inputs"
        Write-Host "  Set `$downloadUrlArm64 to the Microsoft catalog MSU URL for KB5054156 ARM64"
        Write-Host "  Then re-run this script from Level on the ARM64 device"
        Write-Host ""
        Write-Host "[ERROR] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 1
    }
    $selectedUrl = $downloadUrlArm64
    Write-Host "  Package URL  : $selectedUrl"
} else {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Unsupported processor architecture: $($osInfo.Architecture)"
    Write-Host "  Supported architectures : AMD64, ARM64"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# DOWNLOAD
# ==============================================================================

Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="

try {
    Write-Host "  Downloading KB5054156 enablement package..."
    Write-Host "  Destination : $installerPath"
    Invoke-WebRequest -Uri $selectedUrl -OutFile $installerPath -UseBasicParsing

    if (-not (Test-Path -Path $installerPath -PathType Leaf)) {
        throw "MSU file was not downloaded"
    }

    $fileSize = (Get-Item -Path $installerPath).Length
    $fileSizeMb = [math]::Round($fileSize / 1MB, 2)
    Write-Host "  File Size   : $fileSizeMb MB"
    Write-Host "  Download completed successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to download KB5054156 enablement package"
    Write-Host "  URL   : $selectedUrl"
    Write-Host "  Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

$installExitCode = -1
$rebootRequired = $false

try {
    Write-Host "  Method     : wusa.exe /quiet /norestart"
    Write-Host "  Package    : $installerPath"
    Write-Host "  Running wusa.exe quietly (no restart)..."

    $process = Start-Process -FilePath 'wusa.exe' -ArgumentList "`"$installerPath`"", '/quiet', '/norestart' -Wait -PassThru -NoNewWindow
    $installExitCode = $process.ExitCode
    Write-Host "  Installer exit code : $installExitCode"

    if ($successExitCodes -notcontains $installExitCode) {
        throw "wusa.exe failed with exit code: $installExitCode"
    }

    if ($installExitCode -eq 3010) {
        $rebootRequired = $true
        Write-Host "  Installation completed successfully (reboot required)"
    } elseif ($installExitCode -eq 2359302) {
        Write-Host "  Package already installed (treated as success)"
        $rebootRequired = Test-RebootPending
    } else {
        Write-Host "  Installation completed successfully"
        $rebootRequired = Test-RebootPending
    }
} catch {
    if (Test-Path -Path $installerPath -PathType Leaf) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to install KB5054156 enablement package"
    Write-Host "  Exit Code : $installExitCode"
    Write-Host "  Error     : $($_.Exception.Message)"
    Write-Host "  Hint      : Confirm the device is Windows 11 24H2 build 26100 with CU UBR $minUbr+"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==============================================================================
# OPTIONAL REBOOT
# ==============================================================================

if ($rebootAfterInstall) {
    Write-Host ""
    Write-Host "[RUN] REBOOT"
    Write-Host "=============================================================="
    try {
        $rebootDelaySeconds = 60
        $rebootMessage = "Windows 11 $targetDisplayVersion enablement package (KB5054156) installed. Restarting to activate."
        Write-Host "  Scheduling restart in $rebootDelaySeconds seconds..."
        Write-Host "  Command : shutdown /r /t $rebootDelaySeconds"
        $shutdownArgs = "/r /t $rebootDelaySeconds /c `"$rebootMessage`" /d p:2:4"
        $shutdownProc = Start-Process -FilePath 'shutdown.exe' -ArgumentList $shutdownArgs -Wait -PassThru -NoNewWindow
        if ($null -ne $shutdownProc -and $shutdownProc.ExitCode -ne 0) {
            throw "shutdown.exe returned exit code $($shutdownProc.ExitCode)"
        }
        $rebootRequired = $true
        Write-Host "  Restart scheduled successfully"
    } catch {
        Write-Host ""
        Write-Host "[WARN] REBOOT SCHEDULING FAILED"
        Write-Host "=============================================================="
        Write-Host "  Package install succeeded but reboot could not be scheduled"
        Write-Host "  Error : $($_.Exception.Message)"
        Write-Host "  Restart the device manually to activate Windows 11 $targetDisplayVersion"
        $rebootRequired = $true
    }
} else {
    # Enablement still needs a reboot to activate even when we do not schedule one
    if ($installExitCode -eq 3010 -or $installExitCode -eq 0) {
        $rebootRequired = $true
    }
}

# ==============================================================================
# CLEANUP
# ==============================================================================

Write-Host ""
Write-Host "[RUN] CLEANUP"
Write-Host "=============================================================="
Write-Host "  Removing MSU file..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
if (Test-Path -Path $installerPath -PathType Leaf) {
    Write-Host "  [WARN] Could not remove MSU file: $installerPath"
} else {
    Write-Host "  Cleanup completed"
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

$finalInfo = $null
try {
    $finalInfo = Get-WindowsVersionInfo
} catch {
    $finalInfo = $osInfo
}

if (-not $rebootRequired) {
    $rebootRequired = Test-RebootPending
}

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result           : SUCCESS"
Write-Host "  Display Version  : $($finalInfo.DisplayVersion)"
Write-Host "  Build.UBR        : $($finalInfo.Build).$($finalInfo.Ubr)"
Write-Host "  Architecture     : $selectedArch"
Write-Host "  Install Exit     : $installExitCode"
Write-Host "  Reboot Pending   : $rebootRequired"
if ($finalInfo.DisplayVersion -ne $targetDisplayVersion) {
    Write-Host "  Note             : Restart required to activate Windows 11 $targetDisplayVersion"
} else {
    Write-Host "  Note             : DisplayVersion already reports $targetDisplayVersion"
}

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
