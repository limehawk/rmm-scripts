$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Level Agent Install                                           v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\level_agent_install.ps1
================================================================================
 FILE     : level_agent_install.ps1
 DESCRIPTION : Silently installs Level RMM agent with install key and group id
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Downloads the Level Windows MSI and silently installs the agent, registering
   it to a specific Level device group. Install key and group id come from
   SuperOps runtime variables at run time — nothing secret is stored in the
   public script.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime: $YourLevelInstallKeyHere (Level UI install key)
   2) SuperOps runtime: $YourLevelGroupIdHere (numeric group id)
   3) Fixed MSI URL: https://downloads.level.io/level.msi

 REQUIRED INPUTS

   All inputs are hardcoded in the script body (SuperOps replaces placeholders):
     - $levelInstallKey : Level UI install key (NOT the REST API key)
                          SuperOps: $YourLevelInstallKeyHere
     - $levelGroupId    : Numeric Level group id (e.g. 55904)
                          SuperOps: $YourLevelGroupIdHere
                          Script FAILS if empty or unreplaced

 SETTINGS

   - $InstallerUrl    : Level MSI download URL
   - $SkipIfInstalled : Skip when Level is already present (default $true)
   - $CleanupAfter    : Remove downloaded MSI after install (default $true)
   - $TempPath        : Directory for the downloaded MSI

 BEHAVIOR

   1. Validates install key and group id (hard-fail if either missing)
   2. Optionally skips if Level is already installed
   3. Downloads level.msi over HTTPS
   4. Runs msiexec with LEVEL_API_KEY=<key>:<groupId> /qn
   5. Verifies Level is present on disk
   6. Cleans up the temporary MSI

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges
   - Network access to downloads.level.io
   - SuperOps runtime variables set on the script trigger

 SECURITY NOTES

   - No secrets in the public repo — keys only via SuperOps runtime vars
   - Install key is masked in console output (prefix only)
   - Group id is logged in full (not secret)
   - Use the Level UI "Add device" install key, not the REST API token

 ENDPOINTS

   - https://downloads.level.io/level.msi - Level Windows agent MSI

 EXIT CODES

   0 = Success (installed or already present)
   1 = Failure (missing inputs, download, install, or verify)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Install Key      : nRuy...***
 Group Id         : 55904
 Inputs validated successfully

 [RUN] PRE-CHECK
 ==============================================================
 Level not detected

 [RUN] DOWNLOAD
 ==============================================================
 Downloading Level MSI...
 Download complete (12.3 MB)

 [RUN] INSTALLATION
 ==============================================================
 Starting silent installation...
 Installer completed with exit code: 0

 [RUN] VERIFICATION
 ==============================================================
 Attempt 1: Checking...
 Level detected

 [OK] FINAL STATUS
 ==============================================================
 Result : SUCCESS

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-21 v1.0.0 Initial release - silent Level MSI install via SuperOps
                   runtime vars (install key + group id). No secrets in repo.
================================================================================
#>

# ==== HARDCODED INPUTS (MANDATORY) ====
# SuperOps replaces $Your*Here placeholders at runtime. Never put real keys here.
$levelInstallKey = "$YourLevelInstallKeyHere"   # Level UI install key (not REST API key)
$levelGroupId    = "$YourLevelGroupIdHere"      # Numeric group id (required)

# --- Installer options ---
$InstallerUrl    = "https://downloads.level.io/level.msi"
$SkipIfInstalled = $true
$CleanupAfter    = $true
$TempPath        = Join-Path $env:TEMP "level_agent_install"

# --- Verification ---
$MaxVerifyAttempts  = 5
$VerifyDelaySeconds = 3

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($levelInstallKey) -or $levelInstallKey -eq '$' + 'YourLevelInstallKeyHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourLevelInstallKeyHere was not replaced. Set it to the Level UI install key from Add device (not the REST API key)."
}

if ([string]::IsNullOrWhiteSpace($levelGroupId) -or $levelGroupId -eq '$' + 'YourLevelGroupIdHere') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourLevelGroupIdHere was not replaced. Set it to the numeric Level group id (e.g. 55904). Group id is required."
}

if (-not $errorOccurred -and $levelGroupId -notmatch '^\d+$') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Level group id must be numeric digits only (got: $levelGroupId)."
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

# ==== HELPER ====
function Test-LevelInstalled {
    $paths = @(
        "C:\Program Files\Level",
        "C:\Program Files (x86)\Level"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    # Service name fallback
    $svc = Get-Service -Name "Level*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { return $svc.Name }
    return $null
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
$maskedKey = if ($levelInstallKey.Length -gt 4) {
    $levelInstallKey.Substring(0, 4) + "...***"
} else {
    "***"
}
Write-Host "Install Key      : $maskedKey"
Write-Host "Group Id         : $levelGroupId"
Write-Host "Installer URL    : $InstallerUrl"
Write-Host "Inputs validated successfully"

# ==== PRE-CHECK ====
Write-Host ""
Write-Host "[RUN] PRE-CHECK"
Write-Host "=============================================================="
Write-Host "Checking for existing Level installation..."

$existing = Test-LevelInstalled
if ($existing) {
    if ($SkipIfInstalled) {
        Write-Host "Level already present: $existing"
        Write-Host ""
        Write-Host "[OK] FINAL STATUS"
        Write-Host "=============================================================="
        Write-Host "Result : SUCCESS (already installed)"
        Write-Host ""
        Write-Host "[OK] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 0
    } else {
        Write-Host "Level detected, reinstalling..."
    }
} else {
    Write-Host "Level not detected"
}

# ==== DOWNLOAD ====
Write-Host ""
Write-Host "[RUN] DOWNLOAD"
Write-Host "=============================================================="

$installerPath = Join-Path $TempPath "level.msi"

try {
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Downloading Level MSI..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath -UseBasicParsing
    $ProgressPreference = 'Continue'

    if (-not (Test-Path $installerPath)) {
        throw "Installer not found after download"
    }
    $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
    Write-Host "Download complete ($sizeMB MB)"
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

# Level silent property (UI shape): LEVEL_API_KEY=<installKey>:<groupNum>
$levelProperty = "LEVEL_API_KEY=${levelInstallKey}:${levelGroupId}"
$msiArgumentList = "/i `"$installerPath`" $levelProperty /qn"

try {
    Write-Host "Starting silent installation..."
    Write-Host "msiexec property : LEVEL_API_KEY=<masked>:$levelGroupId"
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgumentList -Wait -PassThru -NoNewWindow
    Write-Host "Installer completed with exit code: $($proc.ExitCode)"

    # 0 = success, 3010 = success reboot required
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "msiexec returned exit code $($proc.ExitCode)"
    }
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

    $installed = Test-LevelInstalled
    if ($installed) {
        Write-Host "Level detected: $installed"
        $verified = $true
    }
}

if (-not $verified) {
    Write-Host "Level not detected after $MaxVerifyAttempts attempts"
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
