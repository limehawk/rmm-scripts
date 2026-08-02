$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Level Agent Install                                           v2.0.0
 AUTHOR   : Limehawk.io
 DATE     : August 2026
 USAGE    : .\level_agent_install.ps1
================================================================================
 FILE     : level_agent_install.ps1
 DESCRIPTION : Silently installs the Level RMM agent and verifies enrollment
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Downloads the Level Windows MSI and silently installs the agent, registering
   it to a specific Level device group. Install key and group id come from
   SuperOps runtime variables at run time — nothing secret is stored in the
   public script. The script verifies that the agent enrolled and connected to
   Level, not just that files landed on disk.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime: $YourLevelInstallKeyHere (Level UI install key)
   2) SuperOps runtime: $YourLevelGroupIdHere (numeric group id)
   3) Fixed MSI URL: https://downloads.level.io/level.msi

 REQUIRED INPUTS

   All inputs are hardcoded in the script body (SuperOps replaces placeholders):
     - $levelInstallKey : Level UI install key (NOT the REST API key)
                          SuperOps: $YourLevelInstallKeyHere
                          If the key already ends in :<groupId> (copied from a
                          group-scoped Add device modal), it is used verbatim.
     - $levelGroupId    : Numeric Level group id (e.g. 55904)
                          SuperOps: $YourLevelGroupIdHere
                          Script FAILS if empty or unreplaced

 SETTINGS

   - $InstallerUrl    : Level MSI download URL
   - $SkipIfHealthy   : Skip when Level is already enrolled and connected
   - $CleanupAfter    : Remove downloaded MSI after install (default $true)
   - $TempPath        : Directory for the downloaded MSI

 BEHAVIOR

   1. Validates install key and group id (hard-fail if either missing)
   2. Runs level.exe --check when Level is already present
      - Skips only when the agent reports a live connection
      - Reinstalls over a broken or unenrolled agent
   3. Downloads level.msi over HTTPS
   4. Runs msiexec with LEVEL_API_KEY=<key>:<groupId> /qn
   5. Verifies enrollment with level.exe --check (connection required)
   6. Cleans up the temporary MSI

   GROUP ASSIGNMENT CAVEAT (verified 2026-08-02 on a test VM):
   The group id in the install key only applies at FIRST enrollment. A machine
   with an existing agent identity re-attaches to its existing Level device
   record and keeps its current group (or no group). To re-home such a device,
   move it in the Level console, or wipe the agent identity first (stop the
   Level service, remove C:\Program Files\Level, then reinstall). A wipe
   creates a new device record; the old record goes offline as a duplicate.

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges
   - Network access to downloads.level.io, online.level.io, agents.level.io
   - SuperOps runtime variables set on the script trigger

 SECURITY NOTES

   - No secrets in the public repo — keys only via SuperOps runtime vars
   - Install key is masked in console output (prefix only)
   - Group id is logged in full (not secret)
   - Console output uses [masked], not angle brackets — some RMM log viewers
     strip angle-bracket text as HTML
   - Use the Level UI "Add device" install key, not the REST API token

 ENDPOINTS

   - https://downloads.level.io/level.msi - Level Windows agent MSI

 EXIT CODES

   0 = Success (enrolled and connected, or already healthy)
   1 = Failure (missing inputs, download, install, or enrollment not confirmed)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Install Key      : nRuy...***
 Group Id         : 55904
 Installer URL    : https://downloads.level.io/level.msi
 Inputs validated successfully

 [RUN] PRE-CHECK
 ==============================================================
 Checking for existing Level installation...
 Level not detected

 [RUN] DOWNLOAD
 ==============================================================
 Downloading Level MSI...
 Download complete (35.9 MB)

 [RUN] INSTALLATION
 ==============================================================
 Starting silent installation...
 msiexec property : LEVEL_API_KEY=[masked]:55904
 Installer completed with exit code: 0

 [RUN] VERIFICATION
 ==============================================================
 Attempt 1 : Running level.exe --check
 Level enrolled and connected
 Agent Id : 4e705b5f-93c0-403b-8fe1-6ea627746b91

 [RUN] CLEANUP
 ==============================================================
 Temporary files removed

 [OK] FINAL STATUS
 ==============================================================
 Result : SUCCESS

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-02 v2.0.0 Replace the Program Files existence check with level.exe
                   --check, so a failed enrollment no longer reports SUCCESS.
                   Skip an existing agent only when it reports a live
                   connection; reinstall over a broken one. Accept keys that
                   already carry :<groupId> without doubling the group. Log
                   [masked] instead of angle brackets (RMM consoles strip
                   angle-bracket text as HTML). Document that the group only
                   applies at first enrollment (verified on a test VM).
 2026-07-21 v1.0.0 Initial release - silent Level MSI install via SuperOps
                   runtime vars (install key + group id). No secrets in repo.
================================================================================
#>

# ==== HARDCODED INPUTS (MANDATORY) ====
# SuperOps replaces $Your*Here placeholders at runtime. Never put real keys here.
$levelInstallKey = "$YourLevelInstallKeyHere"   # Level UI install key (not REST API key)
$levelGroupId    = "$YourLevelGroupIdHere"      # Numeric group id (required)

# --- Installer options ---
$InstallerUrl  = "https://downloads.level.io/level.msi"
$SkipIfHealthy = $true
$CleanupAfter  = $true
$TempPath      = Join-Path $env:TEMP "level_agent_install"

# --- Verification ---
$MaxVerifyAttempts  = 6
$VerifyDelaySeconds = 10

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

$levelInstallKey = $levelInstallKey.Trim()
$levelGroupId    = $levelGroupId.Trim()

# A key copied from a group-scoped Add device modal already ends in :<groupId>.
# Use it verbatim in that case so the group is not doubled.
if ($levelInstallKey -match ':(\d+)$') {
    $embeddedGroup = $Matches[1]
    if ($embeddedGroup -ne $levelGroupId) {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "- Install key already carries group $embeddedGroup, but group id input is $levelGroupId. Fix one of the two inputs."
        Write-Host ""
        Write-Host "[ERROR] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 1
    }
    $fullInstallKey = $levelInstallKey
} else {
    $fullInstallKey = "${levelInstallKey}:${levelGroupId}"
}

# ==== HELPERS ====
function Get-LevelExe {
    $paths = @(
        "C:\Program Files\Level\level.exe",
        "C:\Program Files (x86)\Level\level.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-LevelCheck {
    # Returns a hashtable: Output (string), Connected (bool), AgentId (string).
    # Enrollment is proven by a live connection, not by files on disk.
    $exe = Get-LevelExe
    if (-not $exe) {
        return @{ Output = "level.exe not found"; Connected = $false; AgentId = "" }
    }

    $text = ""
    try {
        $text = (& $exe --check 2>&1 | Out-String)
    } catch {
        $text = "level.exe --check failed: $($_.Exception.Message)"
    }

    $connected = ($text -match '(?im)^\s*realtime client\s+Connected\s*$') -or
                 ($text -match '(?im)^\s*(online|agents)\.level\.io\s+OK\s*$')

    $agentId = ""
    if ($text -match '(?im)^\s*ID\s+([0-9a-f-]{36})\s*$') { $agentId = $Matches[1] }

    return @{ Output = $text; Connected = $connected; AgentId = $agentId }
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

$existingExe = Get-LevelExe
if ($existingExe) {
    Write-Host "Level present: $existingExe"
    $preCheck = Get-LevelCheck

    if ($preCheck.Connected -and $SkipIfHealthy) {
        if ($preCheck.AgentId) { Write-Host "Agent Id : $($preCheck.AgentId)" }
        Write-Host ""
        Write-Host "[OK] FINAL STATUS"
        Write-Host "=============================================================="
        Write-Host "Result : SUCCESS (already enrolled and connected)"
        Write-Host "Note   : an existing agent keeps its current Level group."
        Write-Host ""
        Write-Host "[OK] SCRIPT COMPLETED"
        Write-Host "=============================================================="
        exit 0
    }

    Write-Host "Agent is present but not connected. Reinstalling..."
    Write-Host "Note: a reinstall keeps the existing agent identity and group."
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
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : FAILED - could not download the Level MSI"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== INSTALLATION ====
Write-Host ""
Write-Host "[RUN] INSTALLATION"
Write-Host "=============================================================="

# Verified shape (2026-08-02, test VM landed in the target group):
#   msiexec /i level.msi LEVEL_API_KEY=<installKey>:<groupId> /qn
$levelProperty   = "LEVEL_API_KEY=$fullInstallKey"
$msiArgumentList = "/i `"$installerPath`" $levelProperty /qn"

try {
    Write-Host "Starting silent installation..."
    Write-Host "msiexec property : LEVEL_API_KEY=[masked]:$levelGroupId"
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
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : FAILED - msiexec did not complete"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== VERIFICATION ====
Write-Host ""
Write-Host "[RUN] VERIFICATION"
Write-Host "=============================================================="

$verified   = $false
$attempt    = 0
$lastOutput = "no output"

while (-not $verified -and $attempt -lt $MaxVerifyAttempts) {
    $attempt++
    Start-Sleep -Seconds $VerifyDelaySeconds
    Write-Host "Attempt $attempt : Running level.exe --check"

    $check      = Get-LevelCheck
    $lastOutput = $check.Output

    if ($check.Connected) {
        Write-Host "Level enrolled and connected"
        if ($check.AgentId) { Write-Host "Agent Id : $($check.AgentId)" }
        $verified = $true
    }
}

if (-not $verified) {
    Write-Host $lastOutput
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : FAILED - the agent installed but did not enroll"
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
