$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : USMT Profile Migration Tool                                  v1.1.4
 AUTHOR   : Limehawk.io
 DATE     : June 2026
 USAGE    : .\usmt_profile_migrate.ps1
================================================================================
 FILE     : usmt_profile_migrate.ps1
 DESCRIPTION : Interactive USMT backup/restore for remote terminal sessions
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Menu-driven USMT (User State Migration Tool) utility for backing up a
   Windows user profile on one machine and restoring it to another over a
   remote terminal session. Carries documents, settings, and application data
   (profile state) -- not installed applications. Restore can merge into an
   existing local account or create a brand-new one. USMT is auto-downloaded
   on first run. This is the single-machine / store-on-disk sibling of
   usmt_lan_migrate.ps1 (which moves the store across the LAN).

 DATA SOURCES & PRIORITY

   - User profiles: HKLM ProfileList registry (enumerated for backup/restore).
   - Migration stores: backup_info.json + USMT.MIG under the store base path.
   - All operator choices come from the interactive menu (no config inputs).

 REQUIRED INPUTS

   This tool is interactive -- there are no hardcoded operator inputs. The only
   hardcoded values are fixed endpoints/paths in the CONFIGURATION block:
     - $USMTx64URL / $USMTx86URL : USMT download mirrors (SuperGrate)
     - $USMTBasePath             : where USMT is installed (C:\USMT)
     - $DefaultStorePath         : default migration store base (C:\MigrationStore)

 SETTINGS

   - Backup options (interactive): Documents, Desktop, Downloads, Pictures,
     Music, Videos, Favorites, AppData (Roaming on by default, Local off),
     Printers, Wallpaper; compression, Volume Shadow Copy, continue-on-error,
     EFS handling, and optional password encryption.
   - Restore options (interactive): merge to existing account, or create a new
     local account (optionally Administrator); /mu source:target mapping.
   - USMT is auto-downloaded if absent. The encryption key is never persisted
     (backup_info.json records it only as the literal "[ENCRYPTED]" marker).

 BEHAVIOR

   1. Detect admin rights; pre-flight kill any stale scanstate/loadstate.
   2. Show a menu: backup, restore-to-existing, restore-to-new, view backups.
   3. Backup: install USMT, pick a profile, choose options, run scanstate to
      produce USMT.MIG + backup_info.json under the store path.
   4. Restore: install USMT, pick a store, pick/create the target account, run
      loadstate (with /mu mapping and /decrypt as needed).
   5. On exit/cancel, force-kill any tracked scanstate/loadstate child.

 PREREQUISITES

   - Windows 10/11 or Windows Server, PowerShell 5.1 or later
   - Administrator privileges (scanstate, loadstate, account creation)
   - Internet connectivity on first run (USMT download)
   - Sufficient disk space for the migration store

 SECURITY NOTES

   - No secrets in logs: the encryption key and any new-account password are
     never printed and never written to backup_info.json (key stored only as
     the "[ENCRYPTED]" marker).
   - Restore into a profile is destructive; the tool prompts before running.

 ENDPOINTS

   - https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x64.zip
   - https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x86.zip

 EXIT CODES

   0 = Success (or normal menu exit)
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] LIMEHAWK USMT PROFILE MIGRATION TOOL
   ==============================================================
     Computer: OLDLT-01
     User:     admin
     Admin:    Yes

   [INFO] MAIN MENU
   ==============================================================
     1. Backup a user profile
     2. Restore profile to EXISTING account (merge)
     3. Restore profile to NEW account (create user)
     4. View available backups
     5. Exit

   [OK] BACKUP COMPLETE
   ==============================================================
     Location: C:\MigrationStore\OLDLT-01_jdoe_2026-06-23_101500
     Size:     6.20 GB
     Source:   OLDLT-01\jdoe

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-06-23 v1.1.4 Fix StrictMode regression class (lockstep with usmt_lan_migrate v1.2.1): .Count/indexing on Get-UserProfiles and Get-MigrationStores threw "property 'Count' cannot be found" on WinPS 5.1 with a single profile/store or none; wrap returns and call sites in @()
 2026-06-23 v1.1.3 Parity-harden (lockstep with usmt_lan_migrate): track + force-kill scanstate/loadstate children on exit/cancel via Start-Tracked + per-wizard try-finally + Ctrl+C/exit handler (fixes orphan hang and scanstate code 29); pre-flight stale-process kill at startup
 2026-06-23 v1.1.2 Fix Install-USMT: SuperGrate zip extracts flat (no amd64 subfolder); extract into arch subfolder, add recursive scanstate.exe fallback + contents listing on failure
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2026-01-08 v1.1.0 Added full USMT options, new account creation on restore
 2026-01-08 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$USMTx64URL = 'https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x64.zip'
$USMTx86URL = 'https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x86.zip'
$USMTBasePath = 'C:\USMT'
$DefaultStorePath = 'C:\MigrationStore'

# Child processes this run has launched (scanstate/loadstate), so a cancel or
# exit can force-kill any survivor instead of orphaning it.
$script:TrackedChildren = @()

# Process names we own (no .exe) for stale detection and pre-flight cleanup.
$script:MigrationProcNames = @('scanstate', 'loadstate')

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "[INFO] $Title" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "[RUN] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

# ==============================================================================
# CHILD-PROCESS LIFECYCLE
#
# scanstate / loadstate are long-running children. If they orphan on a cancel
# they hold the remote terminal's console pipe open and keep USMT's single-
# instance lock (next scanstate then throws code 29). Every child we launch is
# tracked here; Stop-TrackedChildren force-kills any survivor and is called
# from each wizard's finally block and from the Ctrl+C / exit handler.
# ==============================================================================

function Start-Tracked {
    param(
        [string]$FilePath,
        [object]$ArgumentList,   # string or string[]
        [switch]$Wait
    )
    $spParams = @{
        FilePath    = $FilePath
        PassThru    = $true
        NoNewWindow = $true
    }
    if ($null -ne $ArgumentList) { $spParams.ArgumentList = $ArgumentList }
    if ($Wait) { $spParams.Wait = $true }

    $proc = Start-Process @spParams
    if ($proc) { $script:TrackedChildren += $proc }
    return $proc
}

function Stop-TrackedChildren {
    if (-not $script:TrackedChildren) { return }
    foreach ($proc in $script:TrackedChildren) {
        try {
            if ($proc -and -not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    $script:TrackedChildren = @()
}

function Stop-StaleMigrationProcesses {
    param([switch]$Force)
    $stale = Get-Process -Name $script:MigrationProcNames -ErrorAction SilentlyContinue
    if (-not $stale) { return }

    $names = ($stale | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
    if ($Force) {
        Write-Host "[WARN] Killing stale migration process(es) before starting: $names" -ForegroundColor Yellow
    } else {
        Write-Host "[WARN] Found stale migration process(es) from a prior/cancelled run: $names" -ForegroundColor Yellow
        Write-Host "[WARN] Killing them so this run does not hit USMT lock (scanstate code 29)." -ForegroundColor Yellow
    }
    foreach ($p in $stale) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-FolderSize {
    param([string]$Path)
    $size = 0
    if (Test-Path $Path) {
        $items = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        if ($items) { $size = ($items | Measure-Object -Property Length -Sum).Sum }
    }
    if ($null -eq $size) { $size = 0 }
    return $size
}

function Get-UserProfiles {
    $RegKey = 'Registry::HKey_Local_Machine\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\*'
    $profiles = @()

    Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $SID = New-Object System.Security.Principal.SecurityIdentifier($_.PSChildName)
            $User = $SID.Translate([System.Security.Principal.NTAccount]).Value

            if ($User -notlike 'NT AUTHORITY\*' -and $User -notlike 'NT SERVICE\*') {
                $profilePath = $_.ProfileImagePath
                $profileSize = Get-FolderSize -Path $profilePath

                $profiles += [PSCustomObject]@{
                    Account = $User
                    Path = $profilePath
                    Size = $profileSize
                    SizeFormatted = Format-FileSize $profileSize
                    SID = $_.PSChildName
                }
            }
        } catch { }
    }
    # Force array semantics so a single-profile (one item) or zero result still
    # supports .Count / indexing under Set-StrictMode (WinPS 5.1 throws
    # "property 'Count' cannot be found" on a bare scalar).
    return @($profiles)
}

function Get-MigrationStores {
    param([string]$BasePath)
    $stores = @()
    if (-not (Test-Path $BasePath)) { return @($stores) }

    Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $storePath = $_.FullName
        $infoFile = Join-Path $storePath 'backup_info.json'
        $usmtFile = Join-Path $storePath 'USMT\USMT.MIG'

        # Check for USMT files (@() so a single .MIG match still has a .Count)
        $hasMigFiles = @(Get-ChildItem -Path $storePath -Filter '*.MIG' -ErrorAction SilentlyContinue).Count -gt 0

        if ((Test-Path $infoFile) -or (Test-Path $usmtFile) -or $hasMigFiles) {
            $info = $null
            if (Test-Path $infoFile) {
                $info = Get-Content $infoFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            }

            $storeSize = Get-FolderSize -Path $storePath

            $stores += [PSCustomObject]@{
                Name = $_.Name
                Path = $storePath
                Size = $storeSize
                SizeFormatted = Format-FileSize $storeSize
                SourceAccount = if ($info) { $info.SourceAccount } else { 'Unknown' }
                SourceComputer = if ($info) { $info.SourceComputer } else { 'Unknown' }
                BackupDate = if ($info) { $info.BackupDate } else { $_.CreationTime }
                Encrypted = if ($info) { $info.Encrypted } else { $false }
                Options = if ($info -and $info.Options) { $info.Options } else { $null }
            }
        }
    }
    # Force array semantics for the single-store / no-store cases (see above).
    return @($stores)
}

function Install-USMT {
    $OSArch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    if ($OSArch -match '64') {
        $Arch = 'amd64'
        $URL = $USMTx64URL
    } else {
        $Arch = 'x86'
        $URL = $USMTx86URL
    }

    $script:USMTPath = Join-Path $USMTBasePath $Arch
    $ScanStateExe = Join-Path $script:USMTPath 'scanstate.exe'

    if (Test-Path $ScanStateExe) {
        Write-Success "USMT already installed at $script:USMTPath"
        return $script:USMTPath
    }

    Write-Step "Downloading USMT ($Arch)..."

    try {
        if (-not (Test-Path $USMTBasePath)) {
            New-Item -Path $USMTBasePath -ItemType Directory -Force | Out-Null
        }

        $zipPath = Join-Path $USMTBasePath "usmt_$Arch.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $URL -OutFile $zipPath -UseBasicParsing

        Write-Step "Extracting USMT..."
        # SuperGrate's USMT zips extract FLAT (scanstate.exe, *.xml at the zip root,
        # no amd64/ subfolder). Extract INTO the arch subfolder so binaries and the
        # MigUser/MigDocs/MigApp XMLs all land under $script:USMTPath.
        Expand-Archive -Path $zipPath -DestinationPath $script:USMTPath -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # Defensive fallback: if scanstate.exe isn't where we expect (e.g. SuperGrate
        # changes the zip layout), locate it anywhere under the USMT base and point
        # $script:USMTPath at its parent so the XML paths resolve too.
        if (-not (Test-Path $ScanStateExe)) {
            $found = Get-ChildItem -Path $USMTBasePath -Filter 'scanstate.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $script:USMTPath = $found.Directory.FullName
                $ScanStateExe = $found.FullName
            }
        }

        if (-not (Test-Path $ScanStateExe)) {
            $extracted = (Get-ChildItem -Path $USMTBasePath -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
            throw "scanstate.exe not found after extraction. Extracted contents under ${USMTBasePath}: $extracted"
        }

        Write-Success "USMT installed at $script:USMTPath"
        return $script:USMTPath
    } catch {
        Write-Failure "Failed to install USMT: $($_.Exception.Message)"
        return $null
    }
}

function New-LocalUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName = '',
        [switch]$Admin
    )

    try {
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

        # Check if user exists
        $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Info "User $Username already exists"
            return $true
        }

        # Create user
        $params = @{
            Name = $Username
            Password = $securePassword
            PasswordNeverExpires = $true
            UserMayNotChangePassword = $false
        }
        if (-not [string]::IsNullOrWhiteSpace($FullName)) {
            $params.FullName = $FullName
        }

        New-LocalUser @params | Out-Null
        Write-Success "Created local user: $Username"

        # Add to Administrators if requested
        if ($Admin) {
            Add-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction SilentlyContinue
            Write-Info "Added $Username to Administrators group"
        }

        # User needs to log in once to create profile
        Write-Info "User must log in once to create profile before restore"

        return $true
    } catch {
        Write-Failure "Failed to create user: $($_.Exception.Message)"
        return $false
    }
}

function Show-BackupOptions {
    Write-Host ""
    Write-Host "[INFO] BACKUP OPTIONS" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""

    $options = @{
        IncludeDocuments = $true
        IncludeDesktop = $true
        IncludeDownloads = $true
        IncludePictures = $true
        IncludeMusic = $true
        IncludeVideos = $true
        IncludeFavorites = $true
        IncludeAppData = $true
        IncludeLocalAppData = $false
        IncludePrinters = $true
        IncludeWallpaper = $true
        UseCompression = $true
        UseVSC = $true
        ContinueOnError = $true
        EFSHandling = 'skip'
        EncryptionKey = ''
    }

    # Quick or Advanced
    Write-Host "  1. Quick backup (recommended settings)" -ForegroundColor White
    Write-Host "  2. Advanced options" -ForegroundColor White
    Write-Host ""
    $modeChoice = Read-Host "  Select mode (1-2) [1]"

    if ($modeChoice -eq '2') {
        Write-Host ""
        Write-Host "  What to include (y/n for each):" -ForegroundColor Yellow

        $response = Read-Host "    Documents [$( if ($options.IncludeDocuments) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeDocuments = $false }

        $response = Read-Host "    Desktop [$( if ($options.IncludeDesktop) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeDesktop = $false }

        $response = Read-Host "    Downloads [$( if ($options.IncludeDownloads) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeDownloads = $false }

        $response = Read-Host "    Pictures [$( if ($options.IncludePictures) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludePictures = $false }

        $response = Read-Host "    Music [$( if ($options.IncludeMusic) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeMusic = $false }

        $response = Read-Host "    Videos [$( if ($options.IncludeVideos) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeVideos = $false }

        $response = Read-Host "    Favorites/Bookmarks [$( if ($options.IncludeFavorites) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeFavorites = $false }

        $response = Read-Host "    AppData (Roaming) [$( if ($options.IncludeAppData) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeAppData = $false }

        $response = Read-Host "    AppData (Local) - can be large [$( if ($options.IncludeLocalAppData) {'Y'} else {'n'} )]"
        if ($response -eq 'y' -or $response -eq 'Y') { $options.IncludeLocalAppData = $true }

        $response = Read-Host "    Printers [$( if ($options.IncludePrinters) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludePrinters = $false }

        $response = Read-Host "    Wallpaper [$( if ($options.IncludeWallpaper) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.IncludeWallpaper = $false }

        Write-Host ""
        Write-Host "  Technical options:" -ForegroundColor Yellow

        $response = Read-Host "    Use compression (smaller but slower) [$( if ($options.UseCompression) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.UseCompression = $false }

        $response = Read-Host "    Use Volume Shadow Copy (backup locked files) [$( if ($options.UseVSC) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.UseVSC = $false }

        $response = Read-Host "    Continue on errors [$( if ($options.ContinueOnError) {'Y'} else {'n'} )]"
        if ($response -eq 'n') { $options.ContinueOnError = $false }

        Write-Host ""
        Write-Host "  EFS (Encrypted File System) handling:" -ForegroundColor Yellow
        Write-Host "    1. skip - Skip encrypted files (default)"
        Write-Host "    2. abort - Stop if encrypted files found"
        Write-Host "    3. decryptcopy - Decrypt and copy (requires access)"
        Write-Host "    4. copyraw - Copy encrypted (same user only)"
        $efsChoice = Read-Host "    Select (1-4) [1]"
        switch ($efsChoice) {
            '2' { $options.EFSHandling = 'abort' }
            '3' { $options.EFSHandling = 'decryptcopy' }
            '4' { $options.EFSHandling = 'copyraw' }
            default { $options.EFSHandling = 'skip' }
        }
    }

    # Encryption (always ask)
    Write-Host ""
    $encryptChoice = Read-Host "  Encrypt backup with password? (y/N)"
    if ($encryptChoice -eq 'y' -or $encryptChoice -eq 'Y') {
        $options.EncryptionKey = Read-Host "  Enter encryption key"
        $confirmKey = Read-Host "  Confirm encryption key"
        if ($options.EncryptionKey -ne $confirmKey) {
            Write-Failure "Keys don't match!"
            $options.EncryptionKey = ''
        }
    }

    return $options
}

function Start-ProfileBackup {
    param(
        [string]$USMTPath,
        [string]$SourceAccount,
        [string]$StorePath,
        [hashtable]$Options
    )

    $ScanStateExe = Join-Path $USMTPath 'scanstate.exe'

    $scanArgs = @(
        "`"$StorePath`""
        '/o'
        '/ue:*'
        "/ui:`"$SourceAccount`""
        "/l:`"$StorePath\scan.log`""
        "/progress:`"$StorePath\scan_progress.log`""
        '/v:5'
    )

    # VSC option
    if ($Options.UseVSC) {
        $scanArgs += '/vsc'
    }

    # Compression
    if (-not $Options.UseCompression) {
        $scanArgs += '/nocompress'
    }

    # Continue on error
    if ($Options.ContinueOnError) {
        $scanArgs += '/c'
    }

    # EFS handling
    if ($Options.EFSHandling -ne 'abort') {
        $scanArgs += "/efs:$($Options.EFSHandling)"
    }

    # Encryption
    if (-not [string]::IsNullOrWhiteSpace($Options.EncryptionKey)) {
        $scanArgs += '/encrypt'
        $scanArgs += "/key:`"$($Options.EncryptionKey)`""
    }

    # Migration XMLs
    $scanArgs += "/i:`"$USMTPath\MigUser.xml`""
    $scanArgs += "/i:`"$USMTPath\MigDocs.xml`""

    if ($Options.IncludeAppData) {
        $scanArgs += "/i:`"$USMTPath\MigApp.xml`""
    }

    $argString = $scanArgs -join ' '

    Write-Step "Running scanstate.exe..."
    Write-Info "This may take several minutes depending on profile size."
    Write-Host ""

    $process = Start-Tracked -FilePath $ScanStateExe -ArgumentList $argString -Wait
    return $process.ExitCode
}

function Show-RestoreOptions {
    Write-Host ""
    Write-Host "[INFO] RESTORE OPTIONS" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""

    $options = @{
        ContinueOnError = $true
        CreateNewAccount = $false
        NewUsername = ''
        NewPassword = ''
        NewFullName = ''
        MakeAdmin = $false
    }

    Write-Host "  1. Quick restore (recommended settings)" -ForegroundColor White
    Write-Host "  2. Advanced options" -ForegroundColor White
    Write-Host ""
    $modeChoice = Read-Host "  Select mode (1-2) [1]"

    if ($modeChoice -eq '2') {
        Write-Host ""
        $response = Read-Host "  Continue on errors? (Y/n)"
        if ($response -eq 'n') { $options.ContinueOnError = $false }
    }

    return $options
}

function Start-ProfileRestore {
    param(
        [string]$USMTPath,
        [string]$StorePath,
        [string]$SourceAccount,
        [string]$TargetAccount,
        [string]$EncryptionKey,
        [hashtable]$Options
    )

    $LoadStateExe = Join-Path $USMTPath 'loadstate.exe'

    $loadArgs = @(
        "`"$StorePath`""
        "/l:`"$StorePath\load.log`""
        "/progress:`"$StorePath\load_progress.log`""
        '/v:5'
    )

    if ($Options.ContinueOnError) {
        $loadArgs += '/c'
    }

    # Migration XMLs
    $loadArgs += "/i:`"$USMTPath\MigUser.xml`""
    $loadArgs += "/i:`"$USMTPath\MigDocs.xml`""
    $loadArgs += "/i:`"$USMTPath\MigApp.xml`""

    # User mapping for merge
    if ($SourceAccount -ne $TargetAccount -and -not [string]::IsNullOrWhiteSpace($TargetAccount)) {
        $loadArgs += "/mu:`"$SourceAccount`":`"$TargetAccount`""
        Write-Info "Merging: $SourceAccount -> $TargetAccount"
    }

    # Decryption
    if (-not [string]::IsNullOrWhiteSpace($EncryptionKey)) {
        $loadArgs += '/decrypt'
        $loadArgs += "/key:`"$EncryptionKey`""
    }

    # Local account creation flags
    if ($Options.CreateNewAccount) {
        $loadArgs += '/lac'  # Create local account
        if (-not [string]::IsNullOrWhiteSpace($Options.NewPassword)) {
            $loadArgs += "/lac:`"$($Options.NewPassword)`""
        }
        $loadArgs += '/lae'  # Enable local account
    }

    $argString = $loadArgs -join ' '

    Write-Step "Running loadstate.exe..."
    Write-Info "This may take several minutes."
    Write-Host ""

    $process = Start-Tracked -FilePath $LoadStateExe -ArgumentList $argString -Wait
    return $process.ExitCode
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "[INFO] LIMEHAWK USMT PROFILE MIGRATION TOOL" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  Computer: $($env:COMPUTERNAME)" -ForegroundColor Gray
    Write-Host "  User:     $($env:USERNAME)" -ForegroundColor Gray
    Write-Host "  Admin:    $( if ($script:IsAdmin) { 'Yes' } else { 'No (limited features)' } )" -ForegroundColor $(if ($script:IsAdmin) { 'Green' } else { 'Yellow' })
    Write-Host ""
    Write-Host "[INFO] MAIN MENU" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  1. Backup a user profile"
    Write-Host "  2. Restore profile to EXISTING account (merge)"
    Write-Host "  3. Restore profile to NEW account (create user)"
    Write-Host "  4. View available backups"
    Write-Host "  5. Exit"
    Write-Host ""
}

function Start-BackupWizard {
    try {
    Write-Header "BACKUP USER PROFILE"

    $USMTPath = Install-USMT
    if (-not $USMTPath) {
        Write-Failure "Cannot proceed without USMT"
        Read-Host "Press Enter to continue"
        return
    }

    Write-Host ""
    Write-Step "Scanning for user profiles..."
    $profiles = @(Get-UserProfiles)

    if ($profiles.Count -eq 0) {
        Write-Failure "No user profiles found"
        Read-Host "Press Enter to continue"
        return
    }

    Write-Host ""
    Write-Host "  Available Profiles:" -ForegroundColor Yellow
    Write-Host "  -------------------"
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        Write-Host "  $($i + 1). $($p.Account)" -ForegroundColor White
        Write-Host "      Path: $($p.Path)" -ForegroundColor Gray
        Write-Host "      Size: ~$($p.SizeFormatted)" -ForegroundColor Gray
    }
    Write-Host ""

    $selection = Read-Host "Select profile to backup (1-$($profiles.Count))"
    $index = [int]$selection - 1

    if ($index -lt 0 -or $index -ge $profiles.Count) {
        Write-Failure "Invalid selection"
        Read-Host "Press Enter to continue"
        return
    }

    $selectedProfile = $profiles[$index]
    Write-Success "Selected: $($selectedProfile.Account)"

    # Get backup options
    $options = Show-BackupOptions

    # Get destination
    Write-Host ""
    $storePath = Read-Host "  Migration store path [$DefaultStorePath]"
    if ([string]::IsNullOrWhiteSpace($storePath)) {
        $storePath = $DefaultStorePath
    }

    # Create folder
    $dateStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $usernameClean = $selectedProfile.Account -replace '[\\/:*?"<>|]', '_'
    $backupFolderName = "${env:COMPUTERNAME}_${usernameClean}_${dateStamp}"
    $backupPath = Join-Path $storePath $backupFolderName

    Write-Host ""
    Write-Step "Creating migration store: $backupPath"

    try {
        if (-not (Test-Path $storePath)) {
            New-Item -Path $storePath -ItemType Directory -Force | Out-Null
        }
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    } catch {
        Write-Failure "Failed to create directory: $($_.Exception.Message)"
        Read-Host "Press Enter to continue"
        return
    }

    # Run backup
    Write-Host ""
    $exitCode = Start-ProfileBackup -USMTPath $USMTPath `
                                     -SourceAccount $selectedProfile.Account `
                                     -StorePath $backupPath `
                                     -Options $options

    # Save metadata
    $metadata = @{
        SourceAccount = $selectedProfile.Account
        SourceComputer = $env:COMPUTERNAME
        BackupDate = (Get-Date).ToString('o')
        Encrypted = (-not [string]::IsNullOrWhiteSpace($options.EncryptionKey))
        Options = $options
    }
    # Don't save the actual encryption key!
    if ($metadata.Options.EncryptionKey) {
        $metadata.Options.EncryptionKey = '[ENCRYPTED]'
    }
    $metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath "$backupPath\backup_info.json" -Encoding UTF8

    Write-Host ""
    if ($exitCode -le 1) {
        $storeSize = Get-FolderSize -Path $backupPath
        Write-Host ""
        Write-Host "[OK] BACKUP COMPLETE" -ForegroundColor Green
        Write-Host "==============================================================" -ForegroundColor Green
        Write-Host "  Location: $backupPath" -ForegroundColor White
        Write-Host "  Size:     $(Format-FileSize $storeSize)" -ForegroundColor White
        Write-Host "  Source:   $($selectedProfile.Account)" -ForegroundColor White
    } else {
        Write-Failure "Backup completed with errors (exit code: $exitCode)"
        Write-Host "  Check logs: $backupPath\scan.log" -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
    }
    finally {
        # Never leave a scanstate child alive when leaving this wizard or on cancel.
        Stop-TrackedChildren
    }
}

function Start-RestoreWizard {
    param([switch]$CreateNewAccount)

    try {
    if ($CreateNewAccount) {
        Write-Header "RESTORE TO NEW ACCOUNT"
    } else {
        Write-Header "RESTORE / MERGE TO EXISTING ACCOUNT"
    }

    if ($CreateNewAccount -and -not $script:IsAdmin) {
        Write-Failure "Creating new accounts requires Administrator privileges!"
        Write-Host ""
        Write-Host "  Please run this script as Administrator." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to continue"
        return
    }

    $USMTPath = Install-USMT
    if (-not $USMTPath) {
        Write-Failure "Cannot proceed without USMT"
        Read-Host "Press Enter to continue"
        return
    }

    Write-Host ""
    $storePath = Read-Host "Migration store base path [$DefaultStorePath]"
    if ([string]::IsNullOrWhiteSpace($storePath)) {
        $storePath = $DefaultStorePath
    }

    Write-Step "Scanning for backups..."
    $stores = @(Get-MigrationStores -BasePath $storePath)

    if ($stores.Count -eq 0) {
        Write-Failure "No backups found at: $storePath"
        Write-Host ""
        $specificPath = Read-Host "Enter full path to backup folder (or Enter to cancel)"
        if ([string]::IsNullOrWhiteSpace($specificPath) -or -not (Test-Path $specificPath)) {
            return
        }

        $infoFile = Join-Path $specificPath 'backup_info.json'
        $info = $null
        if (Test-Path $infoFile) {
            $info = Get-Content $infoFile -Raw | ConvertFrom-Json
        }

        $stores = @([PSCustomObject]@{
            Name = Split-Path $specificPath -Leaf
            Path = $specificPath
            SourceAccount = if ($info) { $info.SourceAccount } else { 'Unknown' }
            SourceComputer = if ($info) { $info.SourceComputer } else { 'Unknown' }
            Encrypted = if ($info) { $info.Encrypted } else { $false }
        })
    }

    Write-Host ""
    Write-Host "  Available Backups:" -ForegroundColor Yellow
    Write-Host "  ------------------"
    for ($i = 0; $i -lt $stores.Count; $i++) {
        $s = $stores[$i]
        Write-Host "  $($i + 1). $($s.Name)" -ForegroundColor White
        Write-Host "      Source: $($s.SourceAccount) @ $($s.SourceComputer)" -ForegroundColor Gray
        Write-Host "      Size:   $($s.SizeFormatted)" -ForegroundColor Gray
        if ($s.Encrypted) { Write-Host "      [ENCRYPTED]" -ForegroundColor Yellow }
    }
    Write-Host ""

    $selection = Read-Host "Select backup (1-$($stores.Count))"
    $index = [int]$selection - 1
    if ($index -lt 0 -or $index -ge $stores.Count) {
        Write-Failure "Invalid selection"
        Read-Host "Press Enter to continue"
        return
    }

    $selectedStore = $stores[$index]
    Write-Success "Selected: $($selectedStore.Name)"

    $targetAccount = ''
    $restoreOptions = Show-RestoreOptions

    if ($CreateNewAccount) {
        # Create new account flow
        Write-Host ""
        Write-Host "[INFO] CREATE NEW LOCAL ACCOUNT" -ForegroundColor Cyan
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host ""

        $newUsername = Read-Host "  Enter username for new account"
        if ([string]::IsNullOrWhiteSpace($newUsername)) {
            Write-Failure "Username required"
            Read-Host "Press Enter to continue"
            return
        }

        $newPassword = Read-Host "  Enter password for new account"
        $confirmPassword = Read-Host "  Confirm password"
        if ($newPassword -ne $confirmPassword) {
            Write-Failure "Passwords don't match"
            Read-Host "Press Enter to continue"
            return
        }

        $newFullName = Read-Host "  Full name (optional)"

        $makeAdmin = Read-Host "  Make this user an Administrator? (y/N)"
        $isAdmin = ($makeAdmin -eq 'y' -or $makeAdmin -eq 'Y')

        Write-Host ""
        Write-Step "Creating local user: $newUsername"

        $created = New-LocalUser -Username $newUsername -Password $newPassword -FullName $newFullName -Admin:$isAdmin
        if (-not $created) {
            Write-Failure "Failed to create user account"
            Read-Host "Press Enter to continue"
            return
        }

        $targetAccount = "$env:COMPUTERNAME\$newUsername"
        $restoreOptions.CreateNewAccount = $true
        $restoreOptions.NewUsername = $newUsername
        $restoreOptions.NewPassword = $newPassword

        Write-Host ""
        Write-Host "  IMPORTANT: The new user must log in ONCE before restore" -ForegroundColor Yellow
        Write-Host "  to initialize their profile. You can:" -ForegroundColor Yellow
        Write-Host "    1. Log in as $newUsername now, then log back in as admin" -ForegroundColor Gray
        Write-Host "    2. Or continue - USMT will attempt to create the profile" -ForegroundColor Gray
        Write-Host ""
        $continueChoice = Read-Host "  Continue with restore now? (y/N)"
        if ($continueChoice -ne 'y' -and $continueChoice -ne 'Y') {
            Write-Host ""
            Write-Host "  Restore cancelled. Run restore again after user logs in." -ForegroundColor Yellow
            Read-Host "Press Enter to continue"
            return
        }

    } else {
        # Existing account flow
        Write-Host ""
        Write-Host "  Select target account:" -ForegroundColor Yellow
        $profiles = @(Get-UserProfiles)

        for ($i = 0; $i -lt $profiles.Count; $i++) {
            Write-Host "  $($i + 1). $($profiles[$i].Account)" -ForegroundColor White
        }
        Write-Host "  $($profiles.Count + 1). Same as source ($($selectedStore.SourceAccount))" -ForegroundColor White
        Write-Host ""

        $targetSelection = Read-Host "Select target (1-$($profiles.Count + 1))"
        $targetIndex = [int]$targetSelection - 1

        if ($targetIndex -eq $profiles.Count) {
            $targetAccount = $selectedStore.SourceAccount
        } elseif ($targetIndex -ge 0 -and $targetIndex -lt $profiles.Count) {
            $targetAccount = $profiles[$targetIndex].Account
        } else {
            Write-Failure "Invalid selection"
            Read-Host "Press Enter to continue"
            return
        }
    }

    Write-Success "Target: $targetAccount"

    # Encryption key
    $encryptionKey = ''
    if ($selectedStore.Encrypted) {
        Write-Host ""
        $encryptionKey = Read-Host "This backup is encrypted. Enter decryption key"
    }

    # Confirmation
    Write-Host ""
    Write-Host "[WARN] RESTORE SUMMARY" -ForegroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Yellow
    Write-Host "  From: $($selectedStore.SourceAccount)" -ForegroundColor White
    Write-Host "  To:   $targetAccount" -ForegroundColor White

    if ($selectedStore.SourceAccount -ne $targetAccount) {
        Write-Host ""
        Write-Host "  Profile data will be MERGED into: $targetAccount" -ForegroundColor Cyan
    }

    Write-Host ""
    $confirm = Read-Host "Proceed? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Cancelled."
        Read-Host "Press Enter to continue"
        return
    }

    # Run restore
    Write-Host ""
    $exitCode = Start-ProfileRestore -USMTPath $USMTPath `
                                      -StorePath $selectedStore.Path `
                                      -SourceAccount $selectedStore.SourceAccount `
                                      -TargetAccount $targetAccount `
                                      -EncryptionKey $encryptionKey `
                                      -Options $restoreOptions

    Write-Host ""
    if ($exitCode -le 1) {
        Write-Success "Restore completed successfully!"
        Write-Host ""
        Write-Host "  The user should log out and back in for all settings to apply." -ForegroundColor Yellow
    } else {
        Write-Failure "Restore failed (exit code: $exitCode)"
        Write-Host "  Check logs: $($selectedStore.Path)\load.log" -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
    }
    finally {
        # Never leave a loadstate child alive when leaving this wizard or on cancel.
        Stop-TrackedChildren
    }
}

function Show-Backups {
    Write-Header "VIEW AVAILABLE BACKUPS"

    $storePath = Read-Host "Migration store path [$DefaultStorePath]"
    if ([string]::IsNullOrWhiteSpace($storePath)) {
        $storePath = $DefaultStorePath
    }

    Write-Step "Scanning..."
    $stores = @(Get-MigrationStores -BasePath $storePath)

    if ($stores.Count -eq 0) {
        Write-Failure "No backups found at: $storePath"
    } else {
        Write-Host ""
        Write-Success "Found $($stores.Count) backup(s):"
        Write-Host ""
        foreach ($s in $stores) {
            Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor Gray
            Write-Host "  Name:   $($s.Name)" -ForegroundColor White
            Write-Host "  Path:   $($s.Path)" -ForegroundColor Gray
            Write-Host "  Source: $($s.SourceAccount) @ $($s.SourceComputer)" -ForegroundColor Gray
            Write-Host "  Size:   $($s.SizeFormatted)" -ForegroundColor Gray
            Write-Host "  Date:   $($s.BackupDate)" -ForegroundColor Gray
            if ($s.Encrypted) { Write-Host "  Status: ENCRYPTED" -ForegroundColor Yellow }
        }
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

# ==============================================================================
# MAIN
# ==============================================================================

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')

# Route Ctrl+C / engine exit through the same child-process cleanup so a cancel
# (including from inside a wizard's Read-Host) never orphans scanstate/loadstate
# -- which would hold USMT's lock and the console pipe. Fires on the menu's
# exit paths and on Ctrl+C alike.
$null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
    if ($script:TrackedChildren) {
        foreach ($proc in $script:TrackedChildren) {
            try { if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
        }
    }
}

# Pre-flight: a prior cancelled run can leave scanstate/loadstate alive, which
# poisons a fresh run with USMT's single-instance lock (scanstate code 29).
Stop-StaleMigrationProcesses

while ($true) {
    Show-MainMenu
    $choice = Read-Host "  Select option (1-5)"

    switch ($choice) {
        '1' { Start-BackupWizard }
        '2' { Start-RestoreWizard }
        '3' { Start-RestoreWizard -CreateNewAccount }
        '4' { Show-Backups }
        '5' {
            Write-Host ""
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            exit 0
        }
        default {
            Write-Host "  Invalid option" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
