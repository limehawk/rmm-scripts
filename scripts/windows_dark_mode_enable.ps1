$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows Unactivated Dark Mode                                 v1.0.3
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\windows_dark_mode_enable.ps1
================================================================================
 FILE     : windows_dark_mode_enable.ps1
 DESCRIPTION : Sets wallpaper and dark mode on non-activated Windows 11
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Bypasses the locked personalization settings on non-activated Windows 11
   by applying wallpaper and dark mode settings directly via registry. Also
   optionally configures UTC hardware clock for dual-boot Linux compatibility.

 DATA SOURCES & PRIORITY

   - Wallpaper: Downloaded from configured URL to Public Pictures
   - Registry: Direct modification of personalization and timezone settings

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $wallpaperUrl: URL to download wallpaper image from
     - $wallpaperPath: Local path to save wallpaper (default: Public Pictures)
     - $enableDarkMode: Set to $true to enable dark mode, $false to skip
     - $fixUtcClock: Set to $true to enable RealTimeIsUniversal for dual-boot

 SETTINGS

   Configuration details and default values:
     - Dark mode affects both Apps and System themes
     - UTC clock fix requires SYSTEM hive access (admin required)
     - Explorer restart applies theme changes immediately

 BEHAVIOR

   The script performs the following actions in order:
   1. Downloads wallpaper from URL to local path
   2. Sets dark mode registry keys (Apps and System themes)
   3. Sets wallpaper path in registry
   4. Configures UTC hardware clock for dual-boot systems (optional)
   5. Applies wallpaper via UpdatePerUserSystemParameters
   6. Restarts Explorer to apply dark mode changes

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges (required for UTC clock fix)
   - Internet access (for wallpaper download)

 SECURITY NOTES

   - No secrets exposed in output
   - Wallpaper downloaded to public location
   - Registry modifications are standard Windows settings

 ENDPOINTS

   - Wallpaper download URL (configurable)

 EXIT CODES

   0 = Success
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   All required inputs are valid

   [RUN] WALLPAPER DOWNLOAD
   ==============================================================
   Downloading wallpaper...
   Saved to : C:\Users\Public\Pictures\wallpaper.jpg

   [RUN] DARK MODE
   ==============================================================
   Enabled dark mode for Apps
   Enabled dark mode for System

   [RUN] WALLPAPER CONFIGURATION
   ==============================================================
   Set wallpaper path in registry

   [RUN] UTC CLOCK FIX
   ==============================================================
   Enabled RealTimeIsUniversal for dual-boot compatibility

   [RUN] APPLY CHANGES
   ==============================================================
   Wallpaper applied via UpdatePerUserSystemParameters
   Restarting Explorer to apply theme changes...
   Explorer restarted

   [OK] FINAL STATUS
   ==============================================================
   Result : SUCCESS

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-02-12 v1.0.3 Switch wallpaper source to Unsplash for reliable direct downloads
 2026-02-12 v1.0.2 Fix console output to use [STATUS] SECTION format with = dividers
 2026-01-08 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================

$wallpaperUrl  = 'https://images.unsplash.com/photo-1439792675105-701e6a4ab6f0?ixlib=rb-4.1.0&q=85&fm=jpg&crop=entropy&cs=srgb&dl=elliott-engelmann-DjlKxYFJlTc-unsplash.jpg'
$wallpaperPath = 'C:\Users\Public\Pictures\wallpaper.jpg'
$enableDarkMode = $true
$fixUtcClock    = $true

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($wallpaperUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Wallpaper URL is required"
}

if ([string]::IsNullOrWhiteSpace($wallpaperPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Wallpaper path is required"
}

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

if ($errorOccurred) {
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Input validation failed. Please check the hardcoded values."
    exit 1
}

Write-Host "All required inputs are valid"

# ==============================================================================
# WALLPAPER DOWNLOAD
# ==============================================================================

Write-Host ""
Write-Host "[RUN] WALLPAPER DOWNLOAD"
Write-Host "=============================================================="

try {
    Write-Host "Downloading wallpaper..."

    $parentDir = Split-Path -Parent $wallpaperPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Invoke-WebRequest -Uri $wallpaperUrl -OutFile $wallpaperPath -UseBasicParsing
    Write-Host "Saved to : $wallpaperPath"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to download wallpaper"
    Write-Host "URL : $wallpaperUrl"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# DARK MODE
# ==============================================================================

if ($enableDarkMode) {
    Write-Host ""
    Write-Host "[RUN] DARK MODE"
    Write-Host "=============================================================="

    try {
        $personalizePath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

        if (-not (Test-Path $personalizePath)) {
            New-Item -Path $personalizePath -Force | Out-Null
        }

        Set-ItemProperty -Path $personalizePath -Name 'AppsUseLightTheme' -Value 0 -Type DWord -Force
        Write-Host "Enabled dark mode for Apps"

        Set-ItemProperty -Path $personalizePath -Name 'SystemUsesLightTheme' -Value 0 -Type DWord -Force
        Write-Host "Enabled dark mode for System"
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "Failed to set dark mode"
        Write-Host "Error : $($_.Exception.Message)"
        exit 1
    }
}

# ==============================================================================
# WALLPAPER CONFIGURATION
# ==============================================================================

Write-Host ""
Write-Host "[RUN] WALLPAPER CONFIGURATION"
Write-Host "=============================================================="

try {
    $desktopPath = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty -Path $desktopPath -Name 'Wallpaper' -Value $wallpaperPath -Type String -Force
    Write-Host "Set wallpaper path in registry"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to set wallpaper registry key"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# UTC CLOCK FIX
# ==============================================================================

if ($fixUtcClock) {
    Write-Host ""
    Write-Host "[RUN] UTC CLOCK FIX"
    Write-Host "=============================================================="

    try {
        $tzPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
        Set-ItemProperty -Path $tzPath -Name 'RealTimeIsUniversal' -Value 1 -Type DWord -Force
        Write-Host "Enabled RealTimeIsUniversal for dual-boot compatibility"
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "Failed to set UTC clock registry key (admin required)"
        Write-Host "Error : $($_.Exception.Message)"
        exit 1
    }
}

# ==============================================================================
# APPLY CHANGES
# ==============================================================================

Write-Host ""
Write-Host "[RUN] APPLY CHANGES"
Write-Host "=============================================================="

try {
    # Apply wallpaper
    RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
    Write-Host "Wallpaper applied via UpdatePerUserSystemParameters"

    # Restart Explorer to apply dark mode
    Write-Host "Restarting Explorer to apply theme changes..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "Explorer restarted"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to apply changes"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Result : SUCCESS"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
