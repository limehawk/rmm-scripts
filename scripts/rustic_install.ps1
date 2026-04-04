$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rustic Install                                              v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\rustic_install.ps1
================================================================================
 FILE     : rustic_install.ps1
 DESCRIPTION : Installs Rustic, configures backend repository, schedules daily backups
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   All-in-one installer for Rustic backup with multi-backend support.
   Downloads the Rustic binary from GitHub releases (SHA256-verified),
   generates a TOML configuration profile with backend-specific settings,
   initializes an encrypted repository scoped to the machine hostname,
   deploys a daily backup runner script, and creates a Windows Scheduled
   Task. Designed for deployment via SuperOps RMM to client workstations
   and servers.

 DATA SOURCES & PRIORITY

   - Hardcoded backend credentials and repo password (operator fills per deployment)
   - Rustic binary from GitHub releases (SHA256-verified)

 REQUIRED INPUTS

   SuperOps runtime variables (prompted at deploy time):
     - $YourBackendType   : Backend type: b2, s3, local, sftp, rest
     - $YourBackendPath   : Bucket name (B2/S3), local path, host:port (SFTP), or URL (REST)
     - $YourRepoPassword  : Encryption passphrase (create one, store in 1Password)
     - $YourClientName    : Short client ID for logs (e.g., bell, gruman)

   Conditional (B2/S3 only):
     - $YourBackendKeyId  : Access key ID (B2 keyID or S3 access key)
     - $YourBackendAppKey : Secret key (B2 applicationKey or S3 secret)

   Conditional (S3 only):
     - $YourBackendRegion : S3 region (e.g., us-east-1)

   Optional:
     - $YourBackupPaths    : Comma-separated paths (empty = defaults)
     - $YourExcludePatterns: Comma-separated globs (empty = defaults)
     - $YourBackupHour     : Hour 0-23 (empty = default 2)

 SETTINGS

   Configuration with sensible defaults:
     - Backup paths      : User data (Documents, Desktop, Downloads, Pictures, Videos)
     - Exclude patterns  : Temp files, caches, OneDrive, Recycle Bin, large binaries
     - Retention         : 7 daily, 4 weekly, 6 monthly
     - Rustic version    : 0.11.1

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates all hardcoded inputs are non-empty and backend-appropriate
   2. Downloads Rustic binary from GitHub (skips if correct version installed)
   3. ACL-locks install directory to SYSTEM + Administrators only
   4. Generates TOML configuration profile for the selected backend
   5. Initializes repository (skips if already exists)
   6. Generates daily backup script with log rotation
   7. Creates Windows Scheduled Task for daily execution
   8. Runs dry-run backup to verify connectivity and path access

 PREREQUISITES

   - Windows 10/11 or Windows Server 2016+
   - Administrator privileges (runs as SYSTEM via RMM)
   - Network access to GitHub releases and the configured backend
   - tar.exe available (built into Windows 10 1803+)

 SECURITY NOTES

   - Backend credentials are embedded in the TOML config file
   - Install directory is ACL-locked to SYSTEM + Administrators
   - No secrets printed to console output
   - Repo password encrypts all backup data at rest

 ENDPOINTS

   - GitHub Releases (rustic-rs/rustic) - binary download
   - Configured backend (B2/S3/SFTP/REST/local) - backup storage

 EXIT CODES

   0 = Success
   1 = Failure (validation, download, init, or config error)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Backend    : b2
     Bucket     : limehawk-backups-bell
     Client     : bell
     Repository : opendal:b2 -> /bell/WORKSTATION01
     Rustic     : v0.11.1 (GitHub release)
     Schedule   : Daily at 02:00
     Retention  : 7 daily, 4 weekly, 6 monthly
     Backup Paths : 5 paths configured
     Excludes     : 17 patterns configured

   [RUN] INSTALL RUSTIC
   ==============================================================
     Downloading rustic v0.11.1...
     SHA256 verified
     Installed at C:\ProgramData\Limehawk\Rustic\bin\rustic.exe
     Directory ACL locked to SYSTEM + Administrators

   [RUN] GENERATE CONFIGURATION
   ==============================================================
     Generated C:\ProgramData\Limehawk\Rustic\rustic.toml
     Backend: b2

   [RUN] INITIALIZE REPOSITORY
   ==============================================================
     Initializing new repository...
     Repository initialized successfully

   [RUN] CREATE BACKUP SCRIPT
   ==============================================================
     Generated C:\ProgramData\Limehawk\Rustic\rustic-backup.ps1
     File ACL locked to SYSTEM + Administrators

   [RUN] CREATE SCHEDULED TASK
   ==============================================================
     Task Name : Limehawk Rustic Backup
     Schedule  : Daily at 02:00
     Run As    : SYSTEM
     Task created successfully

   [RUN] TEST BACKUP
   ==============================================================
     Running dry-run backup...
     Dry-run completed successfully

   [OK] FINAL STATUS
   ==============================================================
     Result   : SUCCESS
     Rustic   : v0.11.1
     Backend  : b2
     Client   : bell
     Schedule : Daily at 02:00

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-04 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText     = ""

# ==== HARDCODED INPUTS (MANDATORY) ====

# --- REQUIRED: SuperOps runtime variables (prompted at deploy time) ---
$backendType    = "$YourBackendType"       # b2, s3, local, sftp, rest
$backendPath    = "$YourBackendPath"       # Bucket name, local path, host:port, or URL
$repoPassword   = "$YourRepoPassword"     # Encryption passphrase (store in 1Password)
$clientName     = "$YourClientName"        # Short client ID (e.g., bell, gruman)

# --- CONDITIONAL: B2/S3 only ---
$backendKeyId   = "$YourBackendKeyId"      # B2 keyID or S3 access key ID
$backendAppKey  = "$YourBackendAppKey"     # B2 applicationKey or S3 secret key

# --- CONDITIONAL: S3 only ---
$backendRegion  = "$YourBackendRegion"     # S3 region (e.g., us-east-1)

# --- OPTIONAL: Comma-separated overrides (empty = defaults) ---
$backupPathsRaw     = "$YourBackupPaths"       # Comma-separated paths (empty = defaults)
$excludePatternsRaw = "$YourExcludePatterns"   # Comma-separated globs (empty = defaults)
$backupHourRaw      = "$YourBackupHour"        # Hour 0-23 (empty = default 2)

# ==== DEFAULTS ====
$rusticVersion = '0.11.1'

$defaultBackupPaths = @(
    'C:\Users\*\Documents'
    'C:\Users\*\Desktop'
    'C:\Users\*\Downloads'
    'C:\Users\*\Pictures'
    'C:\Users\*\Videos'
)

$defaultExcludePatterns = @(
    '*.tmp'
    '*.temp'
    'Thumbs.db'
    'desktop.ini'
    '~$*'
    'C:\Users\*\AppData\Local\Google\Chrome\User Data\*\Cache\*'
    'C:\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Cache\*'
    'C:\Users\*\AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*'
    'C:\Users\*\AppData\Local\Temp\*'
    'C:\Users\*\OneDrive\*'
    '$RECYCLE.BIN'
    '*.iso'
    '*.vmdk'
    '*.vhdx'
    'node_modules'
    '.git'
    '__pycache__'
)

$keepDaily   = 7
$keepWeekly  = 4
$keepMonthly = 6

# ==== DERIVED VALUES ====
$installDir    = 'C:\ProgramData\Limehawk\Rustic'
$binDir        = "$installDir\bin"
$rusticExe     = "$binDir\rustic.exe"
$configFile    = "$installDir\rustic.toml"
$backupScript  = "$installDir\rustic-backup.ps1"
$logDir        = "$installDir\Logs"
$taskName      = 'Limehawk Rustic Backup'
$downloadUrl   = "https://github.com/rustic-rs/rustic/releases/download/v${rusticVersion}/rustic-v${rusticVersion}-x86_64-pc-windows-msvc.tar.gz"
$sha256Url     = "${downloadUrl}.sha256"

# ==== RESOLVE OPTIONAL INPUTS ====

# Backup paths: use custom if provided, otherwise defaults
$isBackupPathsEmpty = [string]::IsNullOrWhiteSpace($backupPathsRaw) -or $backupPathsRaw -eq '$' + 'YourBackupPaths'
if ($isBackupPathsEmpty) {
    $backupPaths = $defaultBackupPaths
} else {
    $backupPaths = ($backupPathsRaw -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

# Exclude patterns: use custom if provided, otherwise defaults
$isExcludePatternsEmpty = [string]::IsNullOrWhiteSpace($excludePatternsRaw) -or $excludePatternsRaw -eq '$' + 'YourExcludePatterns'
if ($isExcludePatternsEmpty) {
    $excludePatterns = $defaultExcludePatterns
} else {
    $excludePatterns = ($excludePatternsRaw -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

# Backup hour: use custom if provided, otherwise default 2
$isBackupHourEmpty = [string]::IsNullOrWhiteSpace($backupHourRaw) -or $backupHourRaw -eq '$' + 'YourBackupHour'
if ($isBackupHourEmpty) {
    $backupHour = 2
} else {
    $parsed = 0
    if (-not [int]::TryParse($backupHourRaw, [ref]$parsed)) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Backup hour '$backupHourRaw' is not a valid integer."
        $backupHour = 2
    } else {
        $backupHour = $parsed
    }
}

# ==== VALIDATION ====

# Normalize backend type
$backendType = $backendType.ToLower().Trim()

if ([string]::IsNullOrWhiteSpace($backendType) -or $backendType -eq '$' + 'YourBackendType') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourBackendType was not replaced."
}
if ([string]::IsNullOrWhiteSpace($backendPath) -or $backendPath -eq '$' + 'YourBackendPath') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourBackendPath was not replaced."
}
if ([string]::IsNullOrWhiteSpace($repoPassword) -or $repoPassword -eq '$' + 'YourRepoPassword') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourRepoPassword was not replaced."
}
if ([string]::IsNullOrWhiteSpace($clientName) -or $clientName -eq '$' + 'YourClientName') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$YourClientName was not replaced."
}

# Validate backend type is recognized
$validBackends = @('b2', 's3', 'local', 'sftp', 'rest')
if (-not $errorOccurred -and $backendType -notin $validBackends) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Invalid backend type '$backendType'. Must be one of: $($validBackends -join ', ')"
}

# Conditional validation: B2 and S3 require key credentials
if ($backendType -in @('b2', 's3')) {
    if ([string]::IsNullOrWhiteSpace($backendKeyId) -or $backendKeyId -eq '$' + 'YourBackendKeyId') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- SuperOps runtime variable `$YourBackendKeyId is required for $backendType backend."
    }
    if ([string]::IsNullOrWhiteSpace($backendAppKey) -or $backendAppKey -eq '$' + 'YourBackendAppKey') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- SuperOps runtime variable `$YourBackendAppKey is required for $backendType backend."
    }
}

# Conditional validation: S3 requires region
if ($backendType -eq 's3') {
    if ([string]::IsNullOrWhiteSpace($backendRegion) -or $backendRegion -eq '$' + 'YourBackendRegion') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- SuperOps runtime variable `$YourBackendRegion is required for s3 backend."
    }
}

if ($backupPaths.Count -eq 0) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- At least one backup path is required."
}

if ($backupHour -lt 0 -or $backupHour -gt 23) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Backup hour must be between 0 and 23 (got $backupHour)."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== BUILD DISPLAY VALUES (no secrets) ====
$hostName = $env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($hostName)) {
    $hostName = 'UNKNOWN'
    Write-Host "[WARN] COMPUTERNAME is empty, using 'UNKNOWN' as hostname"
}
$repoRoot = "/$clientName/$hostName"

switch ($backendType) {
    'b2'    { $displayRepo = "opendal:b2 -> $repoRoot" }
    's3'    { $displayRepo = "opendal:s3 -> $repoRoot" }
    'local' { $displayRepo = "$backendPath\$clientName\$hostName" }
    'sftp'  { $displayRepo = "opendal:sftp -> $repoRoot" }
    'rest'  { $displayRepo = "rest:$backendPath/$clientName/$hostName" }
}

# ==== INPUT VALIDATION OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  Backend      : $backendType"
Write-Host "  Path         : $backendPath"
Write-Host "  Client       : $clientName"
Write-Host "  Repository   : $displayRepo"
Write-Host "  Rustic       : v$rusticVersion (GitHub release)"
Write-Host "  Schedule     : Daily at $($backupHour.ToString('00')):00"
Write-Host "  Retention    : $keepDaily daily, $keepWeekly weekly, $keepMonthly monthly"
Write-Host "  Backup Paths : $($backupPaths.Count) paths configured"
Write-Host "  Excludes     : $($excludePatterns.Count) patterns configured"

# ==== INSTALL RUSTIC ====
Write-Host ""
Write-Host "[RUN] INSTALL RUSTIC"
Write-Host "=============================================================="

try {
    # Create directory structure
    foreach ($dir in @($installDir, $binDir, $logDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Check if rustic is already installed at the correct version
    $skipDownload = $false
    if (Test-Path $rusticExe) {
        $ErrorActionPreference = 'Continue'
        $currentVersion = & $rusticExe --version 2>&1 | Select-Object -First 1
        $ErrorActionPreference = 'Stop'
        if ($currentVersion -match $rusticVersion) {
            Write-Host "  Rustic v$rusticVersion already installed, skipping download"
            $skipDownload = $true
        }
    }

    if (-not $skipDownload) {
        $tempDir = Join-Path $env:TEMP "rustic-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            $archivePath = Join-Path $tempDir 'rustic.tar.gz'
            $sha256Path  = Join-Path $tempDir 'rustic.tar.gz.sha256'

            # Download archive and checksum
            Write-Host "  Downloading rustic v$rusticVersion..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($downloadUrl, $archivePath)
            $wc.DownloadFile($sha256Url, $sha256Path)
            $wc.Dispose()

            # Verify SHA256
            $expectedHash = (Get-Content $sha256Path -Raw).Trim().Split(' ')[0].ToUpper()
            $actualHash   = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToUpper()
            if ($actualHash -ne $expectedHash) {
                throw "SHA256 mismatch: expected $expectedHash, got $actualHash"
            }
            Write-Host "  SHA256 verified"

            # Extract with tar
            & tar -xzf $archivePath -C $tempDir
            if ($LASTEXITCODE -ne 0) {
                throw "tar extraction failed (exit $LASTEXITCODE)"
            }

            # Find and copy rustic.exe
            $extractedExe = Get-ChildItem -Path $tempDir -Filter 'rustic.exe' -Recurse | Select-Object -First 1
            if (-not $extractedExe) {
                throw "rustic.exe not found in extracted archive"
            }
            Copy-Item -Path $extractedExe.FullName -Destination $rusticExe -Force
            Write-Host "  Installed at $rusticExe"

        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ACL-lock install directory: SYSTEM + Administrators only, disable inheritance
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($systemRule)
    $acl.AddAccessRule($adminRule)
    Set-Acl -Path $installDir -AclObject $acl
    Write-Host "  Directory ACL locked to SYSTEM + Administrators"

} catch {
    Write-Host ""
    Write-Host "[ERROR] INSTALL RUSTIC FAILED"
    Write-Host "=============================================================="
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== GENERATE CONFIGURATION ====
Write-Host ""
Write-Host "[RUN] GENERATE CONFIGURATION"
Write-Host "=============================================================="

try {
    # Build TOML paths with forward slashes
    $logFilePath = ($logDir -replace '\\', '/') + '/rustic.log'

    # Build backup sources array for TOML
    $tomlSources = ($backupPaths | ForEach-Object { "  `"$($_ -replace '\\', '/')`"" }) -join ",`n"

    # Build exclude globs for TOML (prefix with ! for rustic)
    $tomlGlobs = ($excludePatterns | ForEach-Object { "  `"!$_`"" }) -join ",`n"

    # Build repository-specific TOML sections
    $repoSection = ""
    switch ($backendType) {
        'b2' {
            $repoSection = @"
[repository]
repository = "opendal:b2"
password = "$repoPassword"

[repository.options]
application_key_id = "$backendKeyId"
application_key = "$backendAppKey"
bucket = "$backendPath"
root = "/$clientName/$hostName"
"@
        }
        's3' {
            $repoSection = @"
[repository]
repository = "opendal:s3"
password = "$repoPassword"

[repository.options]
access_key_id = "$backendKeyId"
secret_access_key = "$backendAppKey"
bucket = "$backendPath"
region = "$backendRegion"
root = "/$clientName/$hostName"
"@
        }
        'local' {
            $localRepoPath = ($backendPath -replace '\\', '/') + "/$clientName/$hostName"
            $repoSection = @"
[repository]
repository = "$localRepoPath"
password = "$repoPassword"
no-cache = true
"@
        }
        'sftp' {
            # Parse user@host:port format if present
            $sftpUser = ""
            $sftpEndpoint = $backendPath
            if ($backendPath -match '^([^@]+)@(.+)$') {
                $sftpUser = $Matches[1]
                $sftpEndpoint = $Matches[2]
            }
            $repoSection = @"
[repository]
repository = "opendal:sftp"
password = "$repoPassword"

[repository.options]
endpoint = "$sftpEndpoint"
$(if ($sftpUser) { "user = `"$sftpUser`"" })
root = "/$clientName/$hostName"
"@
        }
        'rest' {
            $restUrl = $backendPath.TrimEnd('/')
            $repoSection = @"
[repository]
repository = "rest:${restUrl}/$clientName/$hostName"
password = "$repoPassword"
"@
        }
    }

    # Build full TOML config
    $tomlContent = @"
# Limehawk Rustic Backup Configuration
# Generated $(Get-Date -Format 'yyyy-MM-dd') by rustic_install.ps1
# Client: $clientName | Host: $hostName | Backend: $backendType

$repoSection

[global]
log-level = "info"
log-file = "$logFilePath"
no-progress = true

[backup]
exclude-if-present = [".nobackup", "CACHEDIR.TAG"]
host = "$hostName"

[[backup.snapshots]]
sources = [
$tomlSources
]
globs = [
$tomlGlobs
]

[forget]
prune = true
keep-daily = $keepDaily
keep-weekly = $keepWeekly
keep-monthly = $keepMonthly
"@

    Set-Content -Path $configFile -Value $tomlContent -Force -Encoding UTF8
    Write-Host "  Generated $configFile"
    Write-Host "  Backend: $backendType"

} catch {
    Write-Host ""
    Write-Host "[ERROR] GENERATE CONFIGURATION FAILED"
    Write-Host "=============================================================="
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== INITIALIZE REPOSITORY ====
Write-Host ""
Write-Host "[RUN] INITIALIZE REPOSITORY"
Write-Host "=============================================================="

try {
    $env:RUSTIC_CONFIG_FILE = $configFile

    Write-Host "  Repository : $displayRepo"

    # Check if repo already exists (snapshots returns 0 if repo exists)
    $ErrorActionPreference = 'Continue'
    & $rusticExe snapshots --json 2>&1 | Out-Null
    $repoExists = $LASTEXITCODE -eq 0
    $ErrorActionPreference = 'Stop'

    if ($repoExists) {
        Write-Host "  Repository already initialized, skipping"
    } else {
        Write-Host "  Initializing new repository..."
        $ErrorActionPreference = 'Continue'
        $initOutput = & $rusticExe init 2>&1
        $initExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($initExit -ne 0) {
            throw "rustic init failed (exit $initExit): $initOutput"
        }
        Write-Host "  Repository initialized successfully"
    }

} catch {
    Write-Host ""
    Write-Host "[ERROR] INITIALIZE REPOSITORY FAILED"
    Write-Host "=============================================================="
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
} finally {
    $env:RUSTIC_CONFIG_FILE = $null
}

# ==== CREATE BACKUP SCRIPT ====
Write-Host ""
Write-Host "[RUN] CREATE BACKUP SCRIPT"
Write-Host "=============================================================="

try {
    $scriptContent = @"
`$ErrorActionPreference = 'Stop'
# Limehawk Rustic Daily Backup - $clientName
# Generated $(Get-Date -Format 'yyyy-MM-dd') by rustic_install.ps1
# DO NOT EDIT - regenerate by re-running the installer

`$logDir    = '$logDir'
`$logFile   = "`$logDir\rustic-backup-`$(Get-Date -Format 'yyyy-MM-dd').log"
`$rusticExe = '$rusticExe'
`$configFile = '$configFile'

# Ensure log directory exists
if (-not (Test-Path `$logDir)) { New-Item -Path `$logDir -ItemType Directory -Force | Out-Null }

# Start transcript logging
Start-Transcript -Path `$logFile -Append

try {
    `$env:RUSTIC_CONFIG_FILE = `$configFile

    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting backup"

    # Run backup
    & `$rusticExe backup 2>&1
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Backup completed with exit code `$LASTEXITCODE"

    # Run retention policy with prune
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Applying retention policy"
    & `$rusticExe forget --prune 2>&1
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Retention policy applied (exit code `$LASTEXITCODE)"

    # Integrity check on a small subset of data
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Running integrity check"
    & `$rusticExe check --read-data-subset=1/100 2>&1
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Integrity check completed (exit code `$LASTEXITCODE)"

} catch {
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: `$(`$_.Exception.Message)"
} finally {
    `$env:RUSTIC_CONFIG_FILE = `$null
    Stop-Transcript
}

# Rotate logs - keep last 30
Get-ChildItem -Path `$logDir -Filter 'rustic-backup-*.log' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 30 |
    Remove-Item -Force -ErrorAction SilentlyContinue
"@

    Set-Content -Path $backupScript -Value $scriptContent -Force
    Write-Host "  Generated $backupScript"

    # ACL-lock the backup script file
    $fileAcl = New-Object System.Security.AccessControl.FileSecurity
    $fileAcl.SetAccessRuleProtection($true, $false)
    $fileSystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM', 'FullControl', 'None', 'None', 'Allow')
    $fileAdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators', 'FullControl', 'None', 'None', 'Allow')
    $fileAcl.AddAccessRule($fileSystemRule)
    $fileAcl.AddAccessRule($fileAdminRule)
    Set-Acl -Path $backupScript -AclObject $fileAcl
    Write-Host "  File ACL locked to SYSTEM + Administrators"

} catch {
    Write-Host ""
    Write-Host "[ERROR] CREATE BACKUP SCRIPT FAILED"
    Write-Host "=============================================================="
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== CREATE SCHEDULED TASK ====
Write-Host ""
Write-Host "[RUN] CREATE SCHEDULED TASK"
Write-Host "=============================================================="

try {
    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "  Removed existing task"
    }

    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$backupScript`""
    $trigger   = New-ScheduledTaskTrigger -Daily -At "$($backupHour.ToString('00')):00"
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
        -RestartCount 1 `
        -RestartInterval (New-TimeSpan -Minutes 15)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Limehawk Rustic backup ($clientName)" | Out-Null

    Write-Host "  Task Name : $taskName"
    Write-Host "  Schedule  : Daily at $($backupHour.ToString('00')):00"
    Write-Host "  Run As    : SYSTEM"
    Write-Host "  Task created successfully"

} catch {
    Write-Host ""
    Write-Host "[ERROR] CREATE SCHEDULED TASK FAILED"
    Write-Host "=============================================================="
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[ERROR] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

# ==== TEST BACKUP ====
Write-Host ""
Write-Host "[RUN] TEST BACKUP"
Write-Host "=============================================================="

try {
    $env:RUSTIC_CONFIG_FILE = $configFile

    Write-Host "  Running dry-run backup..."
    $ErrorActionPreference = 'Continue'
    $dryRunOutput = & $rusticExe backup --dry-run 2>&1
    $dryRunExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($dryRunExit -ne 0) {
        throw "Dry-run failed (exit $dryRunExit): $dryRunOutput"
    }
    Write-Host "  Dry-run completed successfully"

} catch {
    Write-Host ""
    Write-Host "[WARN] TEST BACKUP"
    Write-Host "=============================================================="
    Write-Host "  Dry-run failed: $($_.Exception.Message)"
    Write-Host "  Installation is complete but verify backend connectivity manually"
} finally {
    $env:RUSTIC_CONFIG_FILE = $null
}

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result   : SUCCESS"
Write-Host "  Rustic   : v$rusticVersion"
Write-Host "  Backend  : $backendType"
Write-Host "  Client   : $clientName"
Write-Host "  Schedule : Daily at $($backupHour.ToString('00')):00"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
