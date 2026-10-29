$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SentinelOne Install                                           v2.0.1
 AUTHOR   : Limehawk.io
 DATE     : October 2026
 USAGE    : .\sentinelone_install.ps1
================================================================================
 FILE     : sentinelone_install.ps1
 DESCRIPTION : Silently installs the SentinelOne agent from a Level-staged, signature-verified installer with a site token
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Installs the SentinelOne endpoint agent silently using a site token from
   a Level custom field. The installer is staged on the device ahead of time
   by a Level automation step; this script never downloads anything. Before
   running the installer it checks the Authenticode signature is valid and
   was issued to SentinelOne, so a swapped or tampered file is never run.
   Skips if the agent is already installed.

   NOTE: The installed version will auto-update based on your S1 console
   Auto-Upgrade Policy settings. Initial installer version doesn't matter.

 DATA SOURCES & PRIORITY

   1) Level custom field {{cf_s1_site_token}}: site token (REQUIRED)
   2) C:\Windows\Temp\SentinelAgent.msi (x64) staged by Level, preferred
   3) C:\Windows\Temp\SentinelAgent.exe (ARM64) staged by Level, fallback

 REQUIRED INPUTS

   - $SiteToken : SentinelOne site token for agent registration (REQUIRED)
                  Injected at runtime from the Level custom field
                  cf_s1_site_token ({{cf_s1_site_token}} placeholder)

 SETTINGS

   - $MsiPath            : Staged MSI installer (x64)
   - $ExePath            : Staged EXE installer (ARM64)
   - $SignerOrgPattern   : Regex the signing certificate Subject O= must match
   - $MaxVerifyAttempts  : Post-install service checks before giving up
   - $VerifyDelaySeconds : Seconds between verification attempts

 BEHAVIOR

   1. Validates the site token is present and was substituted by Level
   2. Exits 0 without changes if the SentinelAgent service already exists
   3. Picks the staged MSI, or the EXE if no MSI; fails if neither exists
   4. Verifies the Authenticode signature: Status must be Valid and the
      signer certificate Subject O= must be "SentinelOne Inc." (current
      installers) or "Sentinelone, Inc." (older), case-insensitive
   5. Runs the installer silently with the site token
   6. Verifies the SentinelAgent service appears
   7. Removes the staged installer whether the install succeeded or not

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges (Level runs as SYSTEM)
   - Installer already staged at C:\Windows\Temp\SentinelAgent.msi or .exe
   - Level custom field cf_s1_site_token set on the device's group

 SECURITY NOTES

   - No third-party downloads: only the Level-staged file is ever run
   - Installer must carry a valid Authenticode signature from SentinelOne
   - Site token is never printed in full (first 10 characters + ***)
   - No secrets in logs

 ENDPOINTS

   Not applicable - the installer is staged by a separate Level step

 EXIT CODES

   0 = Success (installed or already present)
   1 = Failure (bad token, installer missing, signature rejected,
       install or verification failed)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Site Token : eyJ1cmwiOi***

 [RUN] PRE-CHECK
 ==============================================================
 SentinelOne not detected

 [RUN] SIGNATURE CHECK
 ==============================================================
 Installer : C:\Windows\Temp\SentinelAgent.msi
 Status    : Valid
 Signer    : SentinelOne Inc.
 Signature accepted

 [RUN] INSTALLATION
 ==============================================================
 Starting silent installation...
 Installer completed with exit code : 0
 Staged installer removed

 [RUN] VERIFICATION
 ==============================================================
 Attempt 1 : Checking...
 SentinelAgent service detected

 [OK] FINAL STATUS
 ==============================================================
 Result : SUCCESS

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-10-29 v2.0.1 Accept the signer Subject SentinelOne uses on current
                   installers (O=SentinelOne Inc.) as well as the older
                   O="Sentinelone, Inc."; anchored on the O= attribute so
                   look-alike names are still rejected
 2026-10-29 v2.0.0 Install only the Level-staged installer; drop the CDN
                   download and custom URL; require a valid Authenticode
                   signature from SentinelOne before running it; detect the
                   agent by the SentinelAgent service; EXE path for ARM64
 2026-07-24 v1.0.2 SiteToken from Level custom field {{cf_s1_site_token}} (adopts
                   edit made in Level UI); fail if placeholder is unsubstituted
 2026-01-19 v1.0.1 Updated to two-line ASCII console output style
 2025-12-28 v1.0.0 Initial release
================================================================================
#>

# ==== HARDCODED INPUTS (MANDATORY) ====

# --- REQUIRED: Your SentinelOne Site Token ---
$SiteToken = "{{cf_s1_site_token}}"  # Get from S1 Console > Sentinels > Site Info

# --- Staged installers (placed by the Level automation, MSI preferred) ---
$MsiPath = "C:\Windows\Temp\SentinelAgent.msi"   # x64
$ExePath = "C:\Windows\Temp\SentinelAgent.exe"   # ARM64

# --- Signer the installer certificate must belong to (Subject O= attribute) ---
# Current installers: O=SentinelOne Inc.   Older / installed binaries: O="Sentinelone, Inc."
$SignerOrgPattern = '(^|,\s*)O="?SentinelOne,? Inc\."?(,|$)'

# --- Verification Settings ---
$MaxVerifyAttempts  = 5
$VerifyDelaySeconds = 3

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($SiteToken)) {
    $errorOccurred = $true
    $errorText = "SiteToken is required. Get from S1 Console > Sentinels > Site Info"
} elseif ($SiteToken -match '^\{\{.*\}\}$') {
    # Level custom-field placeholder was not substituted (cf_s1_site_token unset)
    $errorOccurred = $true
    $errorText = "SiteToken custom field was not substituted - set cf_s1_site_token in Level"
}

# ==== HELPER FUNCTIONS ====
function Test-SentinelOneInstalled {
    return $null -ne (Get-Service -Name 'SentinelAgent' -ErrorAction SilentlyContinue)
}

function Exit-WithError {
    param([string]$Message)
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $Message
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : FAILED"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

if ($errorOccurred) { Exit-WithError $errorText }

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
$maskedToken = if ($SiteToken.Length -gt 10) { $SiteToken.Substring(0,10) + "***" } else { "***" }
Write-Host "Site Token : $maskedToken"

# ==== PRE-CHECK ====
Write-Host ""
Write-Host "[RUN] PRE-CHECK"
Write-Host "=============================================================="

if (Test-SentinelOneInstalled) {
    Write-Host "SentinelOne already installed (SentinelAgent service present)"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : SUCCESS (already installed)"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}
Write-Host "SentinelOne not detected"

# ==== SIGNATURE CHECK ====
Write-Host ""
Write-Host "[RUN] SIGNATURE CHECK"
Write-Host "=============================================================="

if (Test-Path $MsiPath) {
    $installerPath = $MsiPath
} elseif (Test-Path $ExePath) {
    $installerPath = $ExePath
} else {
    Exit-WithError "No installer at $MsiPath or $ExePath. The Level staging step did not run or failed."
}
Write-Host "Installer : $installerPath"

$sig    = Get-AuthenticodeSignature -FilePath $installerPath
$signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.GetNameInfo('SimpleName', $false) } else { "(unsigned)" }
Write-Host "Status    : $($sig.Status)"
Write-Host "Signer    : $signer"

# Both conditions: a trusted chain AND the cert belongs to SentinelOne. -match is case-insensitive.
$signerOk = $sig.SignerCertificate -and ($sig.SignerCertificate.Subject -match $SignerOrgPattern)
if ($sig.Status -ne 'Valid' -or -not $signerOk) {
    Exit-WithError "Installer signature is not a valid SentinelOne signature. Not running it. Status: $($sig.Status); Subject: $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'none' })"
}
Write-Host "Signature accepted"

# ==== INSTALLATION ====
Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

try {
    Write-Host "Starting silent installation..."

    if ($installerPath -like '*.msi') {
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn SITE_TOKEN=`"$SiteToken`"" -Wait -PassThru
    } else {
        # -q = quiet (SentinelOne EXE installer switch)
        $proc = Start-Process -FilePath $installerPath -ArgumentList "-q -t `"$SiteToken`" --dont_fail_on_config_preserving_failures" -Wait -PassThru
    }

    Write-Host "Installer completed with exit code : $($proc.ExitCode)"
} catch {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Exit-WithError "Installation failed: $($_.Exception.Message)"
}

# Staged file is single-use; the automation re-stages it next run
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "Staged installer removed"

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

    if (Test-SentinelOneInstalled) {
        Write-Host "SentinelAgent service detected"
        $verified = $true
    }
}

if (-not $verified) {
    Exit-WithError "SentinelAgent service not found after $MaxVerifyAttempts attempts - installation could not be verified"
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
