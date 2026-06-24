$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : USMT LAN Migration Tool                                      v1.2.2
 AUTHOR   : Limehawk.io
 DATE     : June 2026
 USAGE    : .\usmt_lan_migrate.ps1
================================================================================
 FILE     : usmt_lan_migrate.ps1
 DESCRIPTION : LAN profile migration over USMT, store moved via LocalSend or path
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Migrates a Windows local-account user profile from an OLD laptop to a NEW
   laptop across the same local network using USMT (User State Migration Tool).
   The SAME script is dropped on both machines; a role selector decides whether
   this machine is the Sender (old) or the Receiver (new). The compressed USMT
   migration store (USMT.MIG) is moved between machines by LocalSend (primary)
   or a plain file path (UNC / SMB / USB) fallback. It carries profile data and
   settings only -- not installed applications. Targets are LOCAL accounts in a
   workgroup; Entra / Azure AD joined accounts are out of scope (USMT does not
   support them).

 DATA SOURCES & PRIORITY

   - Role / transport / accounts: the hardcoded CONFIG block below. Empty values
     trigger interactive prompts; populated values run unattended.
   - User profiles: HKLM ProfileList registry (Sender enumerates local profiles).
   - Migration store metadata: backup_info.json written alongside USMT.MIG.

 REQUIRED INPUTS

   All inputs are hardcoded in the CONFIG block (no param blocks). Leave any
   value empty for an interactive prompt:
     - $Role           : '' (ask) | 'Sender' | 'Receiver'
     - $Transport      : 'localsend' (default) | 'path'
     - $ReceiverName   : Receiver hostname or IP (Sender + localsend transport)
     - $StorePath      : path-backend store location, or local staging dir
     - $SourceAccount  : 'DOMAIN\user' on the OLD machine to migrate
     - $TargetAccount  : 'COMPUTER\user' on the NEW machine to receive into
     - $CreateAccount  : $true to create the target local account (Receiver)
     - $NewUserName    : username for the created account
     - $NewPassword    : password for the created account (never logged/persisted)
     - $EncryptionKey  : USMT store encryption key (never logged/persisted)
     - $Force          : $true to skip the destructive-loadstate confirm (unattended)
                          and force-kill stale migration processes at pre-flight
     - $IncludeLocalAppData : $false (advanced; AppData\Local can be very large)
     - $ReceiverWaitSeconds : 180; Sender+localsend wait for the receiver's recv
                          listener (TCP 53317) before starting the capture

 SETTINGS

   - Compression is FORCED ON so the store is a single USMT.MIG file (clean
     LocalSend send). This is intentional and not configurable.
   - LocalSend default port : 53317 (TCP for transfer, UDP for mDNS discovery).
     A temporary inbound firewall rule is opened on the Receiver for the
     duration of the receive and removed afterward.
   - Default staging / store path : C:\MigrationStore
   - USMT is auto-downloaded if absent (x64/x86 zip from the SuperGrate mirror).
   - LocalSend CLI is auto-downloaded if absent (0w0mewo/localsend-cli release).
   - Every scanstate/loadstate/localsend child is tracked and force-killed on
     exit or cancel; a pre-flight pass kills any stale ones from a prior run.

 BEHAVIOR

   Sender (OLD laptop):
   1. Verify admin, install USMT, install LocalSend CLI (if transport=localsend)
   2. Pick the source profile (menu or from CONFIG)
   3. Network pre-flight (localsend): show this machine's own IPs; auto-discover
      receivers via mDNS scan (pick-list) before manual IP entry; reject the
      sender's own IP; warn (confirm unless -Force) if the receiver is on a
      different subnet/WiFi. Path transport instead verifies the destination is
      writable.
   4. Fail-fast: wait for the Receiver's recv listener on 53317 BEFORE capturing
   5. Run scanstate /p first for a space estimate, then scanstate with
      compression to produce USMT.MIG + backup_info.json
   6. Move the store to the Receiver via LocalSend (--ip) or write to a path

   Receiver (NEW laptop):
   1. Verify admin, install USMT, install LocalSend CLI (if transport=localsend)
   2. Print this machine's own LAN IP(s) prominently so the operator can tell
      the Sender exactly what to target
   3. Open a temporary inbound firewall rule, run LocalSend recv into staging
      (auto-saves; no interactive accept), then remove the firewall rule -- OR
      read the store from a path
   4. Optionally create + initialize the target local account
   5. Confirm (or -Force), run loadstate with /mu source:target mapping
   6. Tell the user to log out and back in

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges (loadstate, account creation, firewall rule)
   - Both machines on the same subnet (LocalSend discovery uses mDNS)
   - Internet connectivity on first run (USMT + LocalSend CLI download)
   - Sufficient disk for the migration store on both ends

 SECURITY NOTES

   - No secrets in logs: encryption key and new-account password are never
     printed and never written to backup_info.json (key is recorded as the
     literal "[ENCRYPTED]" marker only).
   - The temporary firewall rule is named so it can be found and is always
     removed in a finally block, even on failure.
   - LocalSend transfer is HTTPS by default (CLI --https true).

 ENDPOINTS

   - https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x64.zip
   - https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x86.zip
   - https://github.com/0w0mewo/localsend-cli/releases (LocalSend CLI binary)
   - LAN: receiver:53317 (LocalSend transfer + discovery), same subnet only

 EXIT CODES

   0 = Success
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] ROLE SELECTION
   ==============================================================
     This machine : OLDLT-01  (Admin: Yes)
     Role         : Sender

   [RUN] USMT SETUP
   ==============================================================
     [OK] USMT installed successfully

   [RUN] PROFILE BACKUP
   ==============================================================
     Source  : OLDLT-01\jdoe
     Estimate : ~6.20 GB
     [OK] scanstate complete

   [RUN] STORE TRANSPORT
   ==============================================================
     Transport : localsend
     Target    : NEWLT-01 (192.168.1.42)
     [OK] Store sent

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 LOCALSEND CLI SYNTAX (source-verified, not invented)
--------------------------------------------------------------------------------
   CLI used : 0w0mewo/localsend-cli (Go), release v0.0.7, asset
              localsend-v0.0.7-windows-amd64.zip -> localsend.exe
   Verified against the command source on github.com/0w0mewo/localsend-cli
   (cmd/send/send.go, cmd/recv/recv.go, cmd/scan/scan.go) and
   internal/localsend/localsend.go + recv/recv.go for the port. The official
   localsend/localsend cli/README.md is a stub with no flag docs, so the Go
   CLI is the authoritative, deployable reference.

     Send : localsend send --ip <IP> -f <file> [-f <file2>] [-p <PIN>]
            (--ip required; -f/--file repeatable; files also accepted as
             positional args; --https defaults true)
     Recv : localsend recv -d <dir> [-n <devname>] [-p <PIN>]
            (daemon: auto-saves received files into <dir>, runs until killed;
             this CLI has no interactive accept prompt -- receipt is automatic)
     Scan : localsend scan -t <seconds>
            (prints "Name: .., Address: IP:PORT, .." for discovered devices)
     Port : 53317  (net.JoinHostPort(ip,"53317") on send;
                    Listen "0.0.0.0:53317" on recv)

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-06-24 v1.2.2 Fix LAN discovery abort + localsend orphan: neutralize $ErrorActionPreference around the localsend scan native call so benign stderr INFO lines no longer throw NativeCommandError on PowerShell 5.1
 2026-06-23 v1.2.1 Fix StrictMode regression: .Count/indexing on Get-LocalIPv4 and Find-Receivers threw "property 'Count' cannot be found" on WinPS 5.1 when the result was a single item or none; wrap returns and call sites in @() (also Get-UserProfiles)
 2026-06-23 v1.2.0 Network pre-flight (from live wrong-IP run): Receiver prints its own LAN IP(s) for the operator to relay; Sender auto-discovers receivers via localsend mDNS scan with a pick-list before manual entry; self-IP rejection; same-subnet check (interface IP + prefix) with a clear cross-WiFi warning and confirm-unless-Force; readiness wait kept as the final gate
 2026-06-23 v1.1.0 Hardening from live run: (1) Sender fail-fast receiver-readiness wait (poll recv listener on 53317, $ReceiverWaitSeconds, or path writability) BEFORE capture; (2) track + force-kill scanstate/loadstate/localsend children on exit/cancel via try-finally + Ctrl+C/exit handler (fixes orphan hang and scanstate code 29); (3) pre-flight stale-process kill
 2026-06-23 v1.0.0 Initial release (LAN sibling of usmt_profile_migrate.ps1)
================================================================================
#>

# ==============================================================================
# CONFIGURATION (hardcoded inputs -- empty = interactive, populated = unattended)
# ==============================================================================

# --- Role / transport ---------------------------------------------------------
$Role          = ''            # '' | 'Sender' | 'Receiver'
$Transport     = 'localsend'   # 'localsend' | 'path'
$ReceiverName  = ''            # receiver hostname/IP (Sender + localsend)
$StorePath     = ''            # path backend store, or local staging dir

# --- Accounts -----------------------------------------------------------------
$SourceAccount = ''            # 'DOMAIN\user' on the OLD machine
$TargetAccount = ''            # 'COMPUTER\user' on the NEW machine
$CreateAccount = $false        # Receiver: create the target local account
$NewUserName   = ''            # username for the created account
$NewPassword   = ''            # password for the created account (not logged)
$EncryptionKey = ''            # USMT store encryption key (not logged)

# --- Behaviour ----------------------------------------------------------------
$Force             = $false    # skip the destructive-loadstate confirm (unattended)
$IncludeLocalAppData = $false  # advanced: include AppData\Local (can be huge)
$ReceiverWaitSeconds = 180     # Sender+localsend: how long to wait for the receiver's recv listener

# --- Fixed endpoints / paths (not user inputs) --------------------------------
$USMTx64URL       = 'https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x64.zip'
$USMTx86URL       = 'https://github.com/belowaverage-org/SuperGrate/raw/master/USMT/x86.zip'
$USMTBasePath     = 'C:\USMT'
$DefaultStorePath = 'C:\MigrationStore'
$LocalSendVersion = 'v0.0.7'
$LocalSendBase    = 'C:\LocalSend'
$LocalSendPort    = 53317
$FirewallRuleName = 'Limehawk USMT LAN Migrate (LocalSend)'

# ==============================================================================
# Set-StrictMode AFTER the hardcoded CONFIG block (framework rule)
# ==============================================================================
Set-StrictMode -Version Latest

# Child processes this run has launched (scanstate/loadstate/localsend), so a
# cancel or exit can force-kill any survivor instead of orphaning it.
$script:TrackedChildren = @()

# ==============================================================================
# CONSOLE HELPERS
# ==============================================================================

function Write-Header {
    param([string]$Type = 'info', [string]$Title)
    $labels = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $colors = @{ 'info'='Cyan'; 'run'='Yellow'; 'ok'='Green'; 'warn'='Yellow'; 'error'='Red' }
    Write-Host ""
    Write-Host "[$($labels[$Type])] $Title" -ForegroundColor $colors[$Type]
    Write-Host "==============================================================" -ForegroundColor $colors[$Type]
}

function Write-Step    { param([string]$Message) Write-Host "[RUN] $Message"   -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message"    -ForegroundColor Green }
function Write-Failure { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Warn    { param([string]$Message) Write-Host "[WARN] $Message"  -ForegroundColor Yellow }
function Write-Info    { param([string]$Message) Write-Host "    $Message"     -ForegroundColor Gray }

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

# ==============================================================================
# CHILD-PROCESS LIFECYCLE
#
# scanstate / loadstate / localsend are long-running children. If they orphan
# on cancel they hold the remote terminal's console pipe open and keep USMT's
# single-instance lock (next scanstate then throws code 29). Every child we
# launch is tracked here; Stop-TrackedChildren force-kills any survivor and is
# called from each role's finally block and from the Ctrl+C / exit handlers.
# ==============================================================================

# Process names we own (no .exe) for stale detection and pre-flight cleanup.
$script:MigrationProcNames = @('scanstate', 'loadstate', 'localsend')

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
        Write-Warn "Killing stale migration process(es) before starting: $names"
    } else {
        Write-Warn "Found stale migration process(es) from a prior/cancelled run: $names"
        Write-Warn "Killing them so this run does not hit USMT lock (scanstate code 29)."
    }
    foreach ($p in $stale) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

# ==============================================================================
# USMT (reused from usmt_profile_migrate.ps1)
# ==============================================================================

function Get-UserProfiles {
    $RegKey = 'Registry::HKey_Local_Machine\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\*'
    $profiles = @()

    Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $SID  = New-Object System.Security.Principal.SecurityIdentifier($_.PSChildName)
            $User = $SID.Translate([System.Security.Principal.NTAccount]).Value

            if ($User -notlike 'NT AUTHORITY\*' -and $User -notlike 'NT SERVICE\*') {
                $profilePath = $_.ProfileImagePath
                $profileSize = Get-FolderSize -Path $profilePath

                $profiles += [PSCustomObject]@{
                    Account       = $User
                    Path          = $profilePath
                    Size          = $profileSize
                    SizeFormatted = Format-FileSize $profileSize
                    SID           = $_.PSChildName
                }
            }
        } catch { }
    }
    return $profiles
}

function Install-USMT {
    $OSArch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    if ($OSArch -match '64') {
        $Arch = 'amd64'
        $URL  = $USMTx64URL
    } else {
        $Arch = 'x86'
        $URL  = $USMTx86URL
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

function New-MigrationLocalUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName = '',
        [switch]$Admin
    )
    try {
        $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Info "User $Username already exists"
            return $true
        }

        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $params = @{
            Name                     = $Username
            Password                 = $securePassword
            PasswordNeverExpires     = $true
            UserMayNotChangePassword = $false
        }
        if (-not [string]::IsNullOrWhiteSpace($FullName)) { $params.FullName = $FullName }

        New-LocalUser @params | Out-Null
        Write-Success "Created local user: $Username"

        if ($Admin) {
            Add-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction SilentlyContinue
            Write-Info "Added $Username to Administrators group"
        }
        Write-Info "User must log in once to initialize profile before restore"
        return $true
    } catch {
        Write-Failure "Failed to create user: $($_.Exception.Message)"
        return $false
    }
}

# Build the shared scanstate argument list. When -EstimateOnly, adds /p:<file>
# and /nocompress so USMT only computes the space estimate (no store written).
function Get-ScanStateArgs {
    param(
        [string]$USMTPath,
        [string]$SourceAccount,
        [string]$StorePath,
        [string]$EncryptionKey,
        [switch]$IncludeLocalAppData,
        [switch]$EstimateOnly
    )

    $scanArgs = @(
        "`"$StorePath`""
        '/o'
        '/ue:*'
        "/ui:`"$SourceAccount`""
        "/l:`"$StorePath\scan.log`""
        "/progress:`"$StorePath\scan_progress.log`""
        '/v:5'
        '/c'
        '/vsc'
        '/efs:skip'
    )

    if ($EstimateOnly) {
        # Space estimate only: no store, no compression. /p:<file> writes the XML report.
        $scanArgs += '/nocompress'
        $scanArgs += "/p:`"$StorePath\space_estimate.xml`""
    } else {
        # Real run: compression is FORCED ON so the store is a single USMT.MIG.
        # (We intentionally do NOT pass /nocompress.)
        if (-not [string]::IsNullOrWhiteSpace($EncryptionKey)) {
            $scanArgs += '/encrypt'
            $scanArgs += "/key:`"$EncryptionKey`""
        }
    }

    $scanArgs += "/i:`"$USMTPath\MigUser.xml`""
    $scanArgs += "/i:`"$USMTPath\MigDocs.xml`""
    $scanArgs += "/i:`"$USMTPath\MigApp.xml`""

    # AppData\Local is off by default (it can be huge). When enabled we rely on
    # MigUser/MigApp defaults; the advanced toggle simply does not exclude it.
    if (-not $IncludeLocalAppData) {
        $scanArgs += '/ue:%CSIDL_LOCAL_APPDATA%\*'
    }

    return $scanArgs
}

function Start-ProfileScan {
    param(
        [string]$USMTPath,
        [string]$SourceAccount,
        [string]$StorePath,
        [string]$EncryptionKey,
        [switch]$IncludeLocalAppData
    )
    $ScanStateExe = Join-Path $USMTPath 'scanstate.exe'
    $scanArgs = Get-ScanStateArgs -USMTPath $USMTPath -SourceAccount $SourceAccount `
                                  -StorePath $StorePath -EncryptionKey $EncryptionKey `
                                  -IncludeLocalAppData:$IncludeLocalAppData
    $argString = $scanArgs -join ' '

    Write-Step "Running scanstate.exe (compression ON, single USMT.MIG)..."
    Write-Info "This may take several minutes depending on profile size."
    $process = Start-Tracked -FilePath $ScanStateExe -ArgumentList $argString -Wait
    return $process.ExitCode
}

function Get-SpaceEstimate {
    param(
        [string]$USMTPath,
        [string]$SourceAccount,
        [string]$StorePath,
        [switch]$IncludeLocalAppData
    )
    $ScanStateExe = Join-Path $USMTPath 'scanstate.exe'
    $estArgs = Get-ScanStateArgs -USMTPath $USMTPath -SourceAccount $SourceAccount `
                                 -StorePath $StorePath -EncryptionKey '' `
                                 -IncludeLocalAppData:$IncludeLocalAppData -EstimateOnly
    $argString = $estArgs -join ' '

    Write-Step "Estimating migration size (scanstate /p)..."
    $process = Start-Tracked -FilePath $ScanStateExe -ArgumentList $argString -Wait

    $estimateFile = Join-Path $StorePath 'space_estimate.xml'
    $bytes = 0
    if (Test-Path $estimateFile) {
        try {
            [xml]$xml = Get-Content $estimateFile -Raw
            # USMT space report: <PreGather> / store size node. Pull the largest
            # numeric "size" attribute/element we can find as a safe upper bound.
            $sizeNodes = $xml.SelectNodes('//*[@size]')
            foreach ($n in $sizeNodes) {
                $v = 0
                if ([long]::TryParse($n.size, [ref]$v) -and $v -gt $bytes) { $bytes = $v }
            }
        } catch { $bytes = 0 }
    }
    return @{ ExitCode = $process.ExitCode; Bytes = $bytes }
}

function Start-ProfileRestore {
    param(
        [string]$USMTPath,
        [string]$StorePath,
        [string]$SourceAccount,
        [string]$TargetAccount,
        [string]$EncryptionKey,
        [bool]$CreateAccountFlags = $false,
        [string]$NewAccountPassword = ''
    )
    $LoadStateExe = Join-Path $USMTPath 'loadstate.exe'

    $loadArgs = @(
        "`"$StorePath`""
        "/l:`"$StorePath\load.log`""
        "/progress:`"$StorePath\load_progress.log`""
        '/v:5'
        '/c'
        "/i:`"$USMTPath\MigUser.xml`""
        "/i:`"$USMTPath\MigDocs.xml`""
        "/i:`"$USMTPath\MigApp.xml`""
    )

    if ($SourceAccount -ne $TargetAccount -and -not [string]::IsNullOrWhiteSpace($TargetAccount)) {
        $loadArgs += "/mu:`"$SourceAccount`":`"$TargetAccount`""
        Write-Info "Merging: $SourceAccount -> $TargetAccount"
    }

    if (-not [string]::IsNullOrWhiteSpace($EncryptionKey)) {
        $loadArgs += '/decrypt'
        $loadArgs += "/key:`"$EncryptionKey`""
    }

    if ($CreateAccountFlags) {
        if (-not [string]::IsNullOrWhiteSpace($NewAccountPassword)) {
            $loadArgs += "/lac:`"$NewAccountPassword`""
        } else {
            $loadArgs += '/lac'
        }
        $loadArgs += '/lae'
    }

    $argString = $loadArgs -join ' '
    Write-Step "Running loadstate.exe..."
    Write-Info "This may take several minutes."
    $process = Start-Tracked -FilePath $LoadStateExe -ArgumentList $argString -Wait
    return $process.ExitCode
}

# ==============================================================================
# LOCALSEND CLI
#
# Source-verified syntax (github.com/0w0mewo/localsend-cli, release v0.0.7):
#   send : localsend send --ip <IP> -f <file> [-f <file2>] [-p <PIN>]
#   recv : localsend recv -d <dir> [-n <devname>] [-p <PIN>]  (daemon, auto-save)
#   scan : localsend scan -t <seconds>  ("Name: .., Address: IP:PORT, ..")
#   port : 53317 (TCP transfer + UDP mDNS)
# Confirmed against cmd/send/send.go, cmd/recv/recv.go, cmd/scan/scan.go and
# internal/localsend/localsend.go + recv/recv.go. The official localsend/localsend
# cli/README.md is a stub, so this Go CLI is the authoritative reference used.
# ==============================================================================

function Install-LocalSend {
    $exe = Join-Path $LocalSendBase 'localsend.exe'
    if (Test-Path $exe) {
        Write-Success "LocalSend CLI already present at $exe"
        return $exe
    }

    $OSArch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    $archTag = if ($OSArch -match 'ARM') { 'windows-arm64' } else { 'windows-amd64' }
    $asset   = "localsend-$LocalSendVersion-$archTag.zip"
    $url     = "https://github.com/0w0mewo/localsend-cli/releases/download/$LocalSendVersion/$asset"

    Write-Step "Downloading LocalSend CLI ($asset)..."
    try {
        if (-not (Test-Path $LocalSendBase)) {
            New-Item -Path $LocalSendBase -ItemType Directory -Force | Out-Null
        }
        $zipPath = Join-Path $LocalSendBase $asset
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $LocalSendBase -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # The archive may unpack the binary under a subfolder; locate it.
        if (-not (Test-Path $exe)) {
            $found = Get-ChildItem -Path $LocalSendBase -Filter 'localsend*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Copy-Item $found.FullName $exe -Force
            }
        }
        if (-not (Test-Path $exe)) { throw "localsend.exe not found after extraction" }

        Write-Success "LocalSend CLI installed"
        return $exe
    } catch {
        Write-Failure "Failed to install LocalSend CLI: $($_.Exception.Message)"
        return $null
    }
}

# Enumerate this machine's usable IPv4 addresses with their prefix lengths,
# excluding loopback (127.x) and APIPA (169.254.x). Returns objects with
# IPAddress + PrefixLength so callers can do real subnet math.
function Get-LocalIPv4 {
    $list = @()
    try {
        $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
        foreach ($a in $addrs) {
            $list += [PSCustomObject]@{
                IPAddress    = $a.IPAddress
                PrefixLength = [int]$a.PrefixLength
            }
        }
    } catch { }
    # Force array semantics so a single-NIC (one item) or zero-NIC ($null)
    # result still supports .Count / indexing under Set-StrictMode (WinPS 5.1
    # throws "property 'Count' cannot be found" on a bare scalar).
    return @($list)
}

# Convert a dotted IPv4 string to a UInt32 for bitmask subnet math.
# Arithmetic stays in [uint64] until the final cast so the high bit of values
# like 192.x doesn't overflow a signed [int] (which would throw on the cast).
function ConvertTo-UInt32Ip {
    param([string]$IpString)
    $bytes = $IpString.Split('.')
    if ($bytes.Count -ne 4) { return $null }
    [uint64]$val = 0
    foreach ($b in $bytes) {
        $n = 0
        if (-not [int]::TryParse($b, [ref]$n) -or $n -lt 0 -or $n -gt 255) { return $null }
        $val = ($val * 256) + [uint64]$n
    }
    return [uint32]$val
}

# True if TargetIp is in the same subnet as one of this machine's interfaces,
# computed from the interface IP + its prefix length (not a /24 assumption).
# Also returns, via -MatchedCidr, the local CIDR it matched (or the first local
# CIDR, for a helpful "you're on X, receiver is on Y" warning).
function Test-SameSubnet {
    param(
        [string]$TargetIp,
        [ref]$MatchedCidr
    )
    $target = ConvertTo-UInt32Ip -IpString $TargetIp
    if ($null -eq $target) {
        if ($MatchedCidr) { $MatchedCidr.Value = '' }
        return $false
    }

    [uint64]$target64 = [uint64]$target
    $firstCidr = ''
    foreach ($lip in (Get-LocalIPv4)) {
        $local = ConvertTo-UInt32Ip -IpString $lip.IPAddress
        if ($null -eq $local) { continue }
        $prefix = $lip.PrefixLength
        if ($prefix -lt 0 -or $prefix -gt 32) { continue }

        # Build the /prefix mask in [uint64] (0xFFFFFFFF is a signed int literal,
        # so keep all of this unsigned to avoid sign-extension on the shift).
        [uint64]$full = [uint64]4294967295   # 0xFFFFFFFF
        $mask = if ($prefix -eq 0) { [uint64]0 } else { ($full -shl (32 - $prefix)) -band $full }

        $cidr = "$($lip.IPAddress)/$prefix"
        if ($firstCidr -eq '') { $firstCidr = $cidr }
        if ((([uint64]$local) -band $mask) -eq ($target64 -band $mask)) {
            if ($MatchedCidr) { $MatchedCidr.Value = $cidr }
            return $true
        }
    }
    if ($MatchedCidr) { $MatchedCidr.Value = $firstCidr }
    return $false
}

# True if the candidate IP is one of THIS machine's own IPv4 addresses.
function Test-IsOwnIp {
    param([string]$CandidateIp)
    foreach ($lip in (Get-LocalIPv4)) {
        if ($lip.IPAddress -eq $CandidateIp) { return $true }
    }
    return $false
}

function Resolve-ReceiverIp {
    param([string]$NameOrIp)
    # Already an IPv4 literal?
    if ($NameOrIp -match '^\d{1,3}(\.\d{1,3}){3}$') { return $NameOrIp }
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($NameOrIp) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -First 1
        if ($resolved) { return $resolved.IPAddressToString }
    } catch { }
    return $null
}

# Discover LocalSend receivers on the LAN via the CLI's mDNS scan.
#
# Source-verified against 0w0mewo/localsend-cli cmd/scan/scan.go:
#   subcommand : scan   (flag -t/--timeout int seconds, default 4)
#   found      : prints "Found Devices:" then one line PER device, exact Go
#                format string "\tName: %s, Version: %s, Address: %s:%d, Protocol: %s"
#   none       : prints "No device found" to stderr
# So each device line looks like:
#   <TAB>Name: NEWLT-01, Version: 2.1, Address: 192.168.2.50:53317, Protocol: https
# Returns an array of @{ Name; IP; Port }.
function Find-Receivers {
    param([string]$LocalSendExe, [int]$ScanSeconds = 6)

    $devices = @()
    # The LocalSend CLI logs INFO lines to stderr (Go's default logger writes there).
    # Under Windows PowerShell 5.1 with $ErrorActionPreference='Stop', merging that
    # stderr via 2>&1 promotes the first log line ("INFO Start Scanning") to a
    # terminating NativeCommandError -- aborting the scan before any device line is
    # parsed, and orphaning the still-running localsend child. Neutralize EAP for
    # just this native call so stderr arrives as plain records the regex ignores.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $scanOut = & $LocalSendExe scan -t $ScanSeconds 2>&1
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    foreach ($line in $scanOut) {
        $text = "$line"
        $m = [regex]::Match($text, 'Name:\s*(?<name>.+?),\s*Version:\s*.+?,\s*Address:\s*(?<ip>\d{1,3}(?:\.\d{1,3}){3}):(?<port>\d+)')
        if ($m.Success) {
            $devices += [PSCustomObject]@{
                Name = $m.Groups['name'].Value.Trim()
                IP   = $m.Groups['ip'].Value
                Port = [int]$m.Groups['port'].Value
            }
        }
    }
    # Force array semantics for the 0/1-device cases (see Get-LocalIPv4).
    return @($devices)
}

function Test-TcpPort {
    param([string]$TargetIp, [int]$Port, [int]$TimeoutMs = 2000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($TargetIp, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# Fail-fast: wait for the NEW laptop's recv listener (TCP 53317) BEFORE we spend
# capture time. Returns the resolved receiver IP on success, $null on timeout.
function Wait-ForReceiver {
    param([string]$ReceiverName, [int]$TimeoutSeconds)

    $ip = Resolve-ReceiverIp -NameOrIp $ReceiverName
    if (-not $ip) {
        # Not resolvable yet (the receiver may not have advertised). Fall back to
        # the name; the poll below still works once DNS/mDNS catches up.
        $ip = $ReceiverName
    }

    Write-Step "Waiting for the NEW laptop to be ready in Receiver mode (${ip}:$LocalSendPort)..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        # Re-resolve each loop in case the name only becomes resolvable later.
        $candidate = Resolve-ReceiverIp -NameOrIp $ReceiverName
        if ($candidate) { $ip = $candidate }
        if (Test-TcpPort -TargetIp $ip -Port $LocalSendPort -TimeoutMs 2000) {
            Write-Success "Receiver is listening on ${ip}:$LocalSendPort"
            return $ip
        }
        Start-Sleep -Seconds 3
    }
    return $null
}

function Send-Store {
    param(
        [string]$Transport,
        [string]$StoreDir,         # folder holding USMT.MIG + backup_info.json
        [string]$ReceiverName      # localsend: hostname/IP ; path: destination dir
    )

    if ($Transport -eq 'path') {
        Write-Step "Copying store to path: $ReceiverName"
        if (-not (Test-Path $ReceiverName)) {
            New-Item -Path $ReceiverName -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $StoreDir '*') -Destination $ReceiverName -Recurse -Force
        Write-Success "Store written to $ReceiverName"
        return $true
    }

    # --- LocalSend backend ----------------------------------------------------
    $exe = Install-LocalSend
    if (-not $exe) { return $false }

    # The Sender role has already run network pre-flight (discovery / self-IP
    # reject / subnet check / readiness wait) and passes a validated IP here.
    # Resolve as a safety net in case a literal hostname slips through.
    $ip = Resolve-ReceiverIp -NameOrIp $ReceiverName
    if (-not $ip) { $ip = $ReceiverName }

    $migFile  = Join-Path $StoreDir 'USMT.MIG'
    $infoFile = Join-Path $StoreDir 'backup_info.json'

    Write-Step "Sending store to $ReceiverName (${ip}:$LocalSendPort) via LocalSend..."
    Write-Info "Large stores over WiFi are slow; use the 'path' transport (wired/USB/UNC) for very large profiles."

    # Source-verified flags: --ip <IP>, -f/--file <path> (repeatable).
    $sendArgs = @('send', '--ip', $ip, '-f', $migFile)
    if (Test-Path $infoFile) { $sendArgs += @('-f', $infoFile) }

    & $exe @sendArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "LocalSend send returned exit code $LASTEXITCODE"
        return $false
    }
    Write-Success "Store sent"
    return $true
}

function Receive-Store {
    param(
        [string]$Transport,
        [string]$StoreDir,         # localsend: staging dir ; path: source dir to read
        [int]$TimeoutSeconds = 1800
    )

    if ($Transport -eq 'path') {
        # Path backend: the store already lives at $StoreDir (UNC/SMB/USB). Nothing
        # to receive -- just confirm USMT.MIG is present.
        $mig = Join-Path $StoreDir 'USMT.MIG'
        if (Test-Path $mig) {
            Write-Success "Store found at $StoreDir"
            return $true
        }
        Write-Failure "No USMT.MIG found at $StoreDir"
        return $false
    }

    # --- LocalSend backend ----------------------------------------------------
    $exe = Install-LocalSend
    if (-not $exe) { return $false }

    if (-not (Test-Path $StoreDir)) {
        New-Item -Path $StoreDir -ItemType Directory -Force | Out-Null
    }

    $ruleAdded = $false
    try {
        # Temporary inbound firewall rule for the LocalSend port (TCP + UDP).
        Write-Step "Opening temporary firewall rule for LocalSend (port $LocalSendPort)..."
        New-NetFirewallRule -DisplayName $FirewallRuleName -Direction Inbound -Action Allow `
                            -Protocol TCP -LocalPort $LocalSendPort -ErrorAction Stop | Out-Null
        New-NetFirewallRule -DisplayName "$FirewallRuleName (UDP)" -Direction Inbound -Action Allow `
                            -Protocol UDP -LocalPort $LocalSendPort -ErrorAction Stop | Out-Null
        $ruleAdded = $true

        Write-Step "Starting LocalSend receiver (auto-save) into: $StoreDir"
        Write-Info "Waiting for the sender to push the store (up to $([int]($TimeoutSeconds/60)) min)..."

        # recv runs until killed; auto-saves into -d. Tracked so a cancel during
        # the poll loop force-kills it (via the role finally) instead of orphaning.
        Start-Tracked -FilePath $exe `
                      -ArgumentList @('recv', '-d', "`"$StoreDir`"", '-n', $env:COMPUTERNAME) | Out-Null

        $mig = Join-Path $StoreDir 'USMT.MIG'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $received = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-Path $mig) {
                # Wait for the file to settle (size stable across two polls).
                $s1 = (Get-Item $mig).Length
                Start-Sleep -Seconds 3
                $s2 = (Get-Item $mig).Length
                if ($s1 -eq $s2 -and $s1 -gt 0) { $received = $true; break }
            }
            Start-Sleep -Seconds 2
        }

        if ($received) {
            Write-Success "Store received into $StoreDir"
            return $true
        }
        Write-Failure "Timed out waiting for the store to arrive."
        return $false
    } catch {
        Write-Failure "Receive failed: $($_.Exception.Message)"
        return $false
    } finally {
        # Always stop the recv daemon (and any other tracked child) and pull the
        # temporary firewall rule -- on success, timeout, error, or cancel.
        Stop-TrackedChildren
        if ($ruleAdded) {
            Write-Step "Removing temporary firewall rule(s)..."
            Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "$FirewallRuleName (UDP)" -ErrorAction SilentlyContinue
        }
    }
}

# ==============================================================================
# ROLE FLOWS
# ==============================================================================

function Invoke-SenderRole {
    param([string]$Transport)

    try {
    Write-Header -Type run -Title 'USMT SETUP'
    $USMTPath = Install-USMT
    if (-not $USMTPath) { throw "Cannot proceed without USMT" }

    # --- Resolve source account (config or menu) ------------------------------
    $source = $SourceAccount
    if ([string]::IsNullOrWhiteSpace($source)) {
        Write-Step "Scanning for user profiles..."
        $profiles = @(Get-UserProfiles)
        if ($profiles.Count -eq 0) { throw "No user profiles found" }

        Write-Host ""
        Write-Host "  Available Profiles:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            $p = $profiles[$i]
            Write-Host "  $($i + 1). $($p.Account)  (~$($p.SizeFormatted))" -ForegroundColor White
        }
        Write-Host ""
        $selection = Read-Host "Select profile to migrate (1-$($profiles.Count))"
        $index = [int]$selection - 1
        if ($index -lt 0 -or $index -ge $profiles.Count) { throw "Invalid selection" }
        $source = $profiles[$index].Account
    }
    Write-Success "Source account : $source"

    # --- Resolve receiver target ----------------------------------------------
    $receiver = $ReceiverName
    if ($Transport -eq 'localsend') {
        # ---- Network pre-flight (order: own-IPs -> discover/manual ->
        #      self-IP reject -> subnet warn -> readiness wait) ----------------
        Write-Header -Type run -Title 'NETWORK PRE-FLIGHT'

        # Show this sender's own IPs so the operator can sanity-check the target.
        $ownIPs = @(Get-LocalIPv4)
        if ($ownIPs.Count -gt 0) {
            Write-Info "This machine (SENDER) IPv4: $(($ownIPs | ForEach-Object { $_.IPAddress }) -join ', ')"
        }

        $exe = Install-LocalSend
        if (-not $exe) { throw "Cannot proceed without the LocalSend CLI" }

        # 2. Auto-discovery via mDNS scan BEFORE manual entry.
        $chosenIp = ''
        if ([string]::IsNullOrWhiteSpace($receiver)) {
            Write-Step "Discovering LocalSend receivers on the LAN (mDNS scan)..."
            $found = @(Find-Receivers -LocalSendExe $exe -ScanSeconds 6)

            if ($found.Count -eq 1) {
                $d = $found[0]
                Write-Success "Found one receiver: $($d.Name) at $($d.IP)"
                $confirm = Read-Host "Use $($d.Name) ($($d.IP))? (Y/n)"
                if ($confirm -eq 'n' -or $confirm -eq 'N') {
                    $receiver = Read-Host "Enter the NEW laptop's IP or hostname"
                } else {
                    $chosenIp = $d.IP
                }
            } elseif ($found.Count -gt 1) {
                Write-Host ""
                Write-Host "  Discovered receivers:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $found.Count; $i++) {
                    Write-Host "  $($i + 1). $($found[$i].Name)  ($($found[$i].IP))" -ForegroundColor White
                }
                Write-Host "  $($found.Count + 1). Enter an IP/hostname manually" -ForegroundColor White
                Write-Host ""
                $pick = Read-Host "Select the NEW laptop (1-$($found.Count + 1))"
                $pIdx = [int]$pick - 1
                if ($pIdx -ge 0 -and $pIdx -lt $found.Count) {
                    $chosenIp = $found[$pIdx].IP
                } else {
                    $receiver = Read-Host "Enter the NEW laptop's IP or hostname"
                }
            } else {
                Write-Warn "No LocalSend receiver was discovered on this network."
                Write-Info "That usually means the NEW laptop is not in Receiver mode yet, or"
                Write-Info "the two machines are on different WiFi networks/subnets (e.g. a guest network)."
                $receiver = Read-Host "Enter the NEW laptop's IP or hostname (or fix the network and re-run)"
            }
        }

        # Resolve whatever target we have (manual entry or unused $chosenIp).
        if ([string]::IsNullOrWhiteSpace($chosenIp)) {
            if ([string]::IsNullOrWhiteSpace($receiver)) { throw "Receiver IP/hostname is required for LocalSend transport" }
            $chosenIp = Resolve-ReceiverIp -NameOrIp $receiver
            if (-not $chosenIp) { throw "Could not resolve '$receiver' to an IPv4 address." }
        }

        # 3. Self-IP rejection (the exact mistake from the live run).
        if (Test-IsOwnIp -CandidateIp $chosenIp) {
            throw "$chosenIp is this machine's own IP -- enter the NEW laptop's address."
        }

        # 4. Same-subnet check with a clear, actionable warning.
        $matchedCidr = ''
        if (-not (Test-SameSubnet -TargetIp $chosenIp -MatchedCidr ([ref]$matchedCidr))) {
            $here = if ($matchedCidr) { $matchedCidr } else { 'an unknown subnet' }
            Write-Warn "This machine is on $here; receiver $chosenIp is on a different network/WiFi -- they likely can't reach each other."
            Write-Warn "Make sure both laptops are on the same WiFi (not a guest network)."
            if (-not $Force) {
                $go = Read-Host "Continue anyway? (y/N)"
                if ($go -ne 'y' -and $go -ne 'Y') { throw "Aborted: receiver is on a different subnet." }
            } else {
                Write-Info "-Force set -- continuing despite the subnet mismatch."
            }
        } else {
            Write-Success "Receiver $chosenIp is on the same subnet ($matchedCidr)."
        }

        $receiver = $chosenIp
    } else {
        if ([string]::IsNullOrWhiteSpace($receiver)) {
            $receiver = Read-Host "Enter destination path for the store (UNC/SMB/USB)"
        }
        if ([string]::IsNullOrWhiteSpace($receiver)) { throw "Destination path is required for path transport" }
    }

    # --- Fail-fast receiver readiness (BEFORE the expensive capture) ----------
    Write-Header -Type run -Title 'RECEIVER READINESS'
    if ($Transport -eq 'localsend') {
        # 5. Final gate: wait for the recv listener on :53317.
        $readyIp = Wait-ForReceiver -ReceiverName $receiver -TimeoutSeconds $ReceiverWaitSeconds
        if (-not $readyIp) {
            throw "Receiver not reachable on ${receiver}:$LocalSendPort -- start the NEW laptop in Receiver mode first."
        }
    } else {
        # Path transport: verify the destination is reachable and writable now,
        # rather than discovering it after the whole capture.
        try {
            if (-not (Test-Path $receiver)) {
                New-Item -Path $receiver -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $probe = Join-Path $receiver ('.usmt_write_test_{0}' -f ([guid]::NewGuid().ToString('N')))
            Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
            Remove-Item $probe -Force -ErrorAction SilentlyContinue
            Write-Success "Destination path is reachable and writable: $receiver"
        } catch {
            throw "Destination path not reachable/writable: $receiver -- $($_.Exception.Message)"
        }
    }

    # --- Staging dir ----------------------------------------------------------
    $stagingBase = $StorePath
    if ([string]::IsNullOrWhiteSpace($stagingBase)) { $stagingBase = $DefaultStorePath }
    $dateStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $cleanUser = $source -replace '[\\/:*?"<>|]', '_'
    $storeDir  = Join-Path $stagingBase "${env:COMPUTERNAME}_${cleanUser}_${dateStamp}"
    New-Item -Path $storeDir -ItemType Directory -Force | Out-Null

    # --- Space estimate first -------------------------------------------------
    Write-Header -Type run -Title 'SPACE ESTIMATE'
    $est = Get-SpaceEstimate -USMTPath $USMTPath -SourceAccount $source -StorePath $storeDir -IncludeLocalAppData:$IncludeLocalAppData
    if ($est.Bytes -gt 0) {
        Write-Info "Estimated migration size : ~$(Format-FileSize $est.Bytes)"
        if ($est.Bytes -ge 20GB -and $Transport -eq 'localsend') {
            Write-Warn "Store is large (>20 GB). Wired or 'path' transport is strongly recommended over WiFi LocalSend."
        }
    } else {
        Write-Warn "Could not parse a space estimate; continuing."
    }

    # --- Backup (compression ON -> single USMT.MIG) ---------------------------
    Write-Header -Type run -Title 'PROFILE BACKUP'
    $scanExit = Start-ProfileScan -USMTPath $USMTPath -SourceAccount $source -StorePath $storeDir `
                                  -EncryptionKey $EncryptionKey -IncludeLocalAppData:$IncludeLocalAppData
    if ($scanExit -gt 1) {
        throw "scanstate failed (exit code $scanExit). See $storeDir\scan.log"
    }
    Write-Success "scanstate complete"

    # --- Metadata (never persist the key) -------------------------------------
    $metadata = @{
        SourceAccount  = $source
        SourceComputer = $env:COMPUTERNAME
        BackupDate     = (Get-Date).ToString('o')
        Encrypted      = (-not [string]::IsNullOrWhiteSpace($EncryptionKey))
        Transport      = $Transport
        EncryptionKey  = if (-not [string]::IsNullOrWhiteSpace($EncryptionKey)) { '[ENCRYPTED]' } else { '' }
    }
    $metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $storeDir 'backup_info.json') -Encoding UTF8

    $storeSize = Get-FolderSize -Path $storeDir
    Write-Info "Store size : $(Format-FileSize $storeSize)"

    # --- Transport ------------------------------------------------------------
    Write-Header -Type run -Title 'STORE TRANSPORT'
    Write-Info "Transport : $Transport"
    $sent = Send-Store -Transport $Transport -StoreDir $storeDir -ReceiverName $receiver
    if (-not $sent) { throw "Failed to move the migration store to the receiver" }

    Write-Header -Type ok -Title 'SENDER COMPLETE'
    Write-Info "Profile $source captured and sent. Run this script in Receiver role on the NEW laptop."
    }
    finally {
        # Never leave a scanstate/localsend child alive on exit or cancel.
        Stop-TrackedChildren
    }
}

function Invoke-ReceiverRole {
    param([string]$Transport)

    try {
    Write-Header -Type run -Title 'USMT SETUP'
    $USMTPath = Install-USMT
    if (-not $USMTPath) { throw "Cannot proceed without USMT" }

    # --- Staging / source dir -------------------------------------------------
    $stageDir = $StorePath
    if ([string]::IsNullOrWhiteSpace($stageDir)) {
        if ($Transport -eq 'path') {
            $stageDir = Read-Host "Enter the path to the migration store (UNC/SMB/USB)"
        } else {
            $stageDir = Join-Path $DefaultStorePath 'incoming'
        }
    }
    if ([string]::IsNullOrWhiteSpace($stageDir)) { throw "Store/staging path is required" }

    # --- Receive --------------------------------------------------------------
    Write-Header -Type run -Title 'STORE RECEIVE'
    Write-Info "Transport : $Transport"

    # Show this receiver's own LAN IP(s) prominently so the operator can tell the
    # SENDER exactly what to target -- removes the guess-the-IP problem.
    if ($Transport -eq 'localsend') {
        $ownIPs = @(Get-LocalIPv4)
        Write-Host ""
        if ($ownIPs.Count -gt 0) {
            Write-Host "[INFO] Tell the SENDER to target this machine at:" -ForegroundColor Cyan
            foreach ($lip in $ownIPs) {
                Write-Host "         $($lip.IPAddress)" -ForegroundColor White
            }
            if ($ownIPs.Count -gt 1) {
                Write-Info "(Multiple addresses shown -- use the one on the same WiFi as the OLD laptop.)"
            }
        } else {
            Write-Warn "Could not determine this machine's LAN IP -- check the network connection."
        }
        Write-Host ""
    }

    $got = Receive-Store -Transport $Transport -StoreDir $stageDir
    if (-not $got) { throw "Failed to receive the migration store" }

    # Read metadata for source account / encryption flag.
    $infoFile = Join-Path $stageDir 'backup_info.json'
    $sourceAcct = ''
    $encrypted  = $false
    if (Test-Path $infoFile) {
        try {
            $info = Get-Content $infoFile -Raw | ConvertFrom-Json
            if ($info.PSObject.Properties.Name -contains 'SourceAccount') { $sourceAcct = $info.SourceAccount }
            if ($info.PSObject.Properties.Name -contains 'Encrypted')     { $encrypted  = [bool]$info.Encrypted }
        } catch { }
    }

    # --- Resolve source account -----------------------------------------------
    if ([string]::IsNullOrWhiteSpace($sourceAcct)) {
        $sourceAcct = $SourceAccount
    }
    if ([string]::IsNullOrWhiteSpace($sourceAcct)) {
        $sourceAcct = Read-Host "Enter the SOURCE account name from the old machine (e.g. OLDLT\jdoe)"
    }
    if ([string]::IsNullOrWhiteSpace($sourceAcct)) { throw "Source account is required for /mu mapping" }

    # --- Optional account creation --------------------------------------------
    $target = $TargetAccount
    $createFlags = $false
    $newPw = ''

    if ($CreateAccount) {
        $userName = $NewUserName
        $newPw    = $NewPassword
        if ([string]::IsNullOrWhiteSpace($userName)) { $userName = Read-Host "Enter username for the new local account" }
        if ([string]::IsNullOrWhiteSpace($userName)) { throw "New account username is required" }
        if ([string]::IsNullOrWhiteSpace($newPw)) {
            $sec1 = Read-Host "Enter password for $userName" -AsSecureString
            $sec2 = Read-Host "Confirm password" -AsSecureString
            $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec1))
            $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2))
            if ($p1 -ne $p2) { throw "Passwords do not match" }
            $newPw = $p1
        }

        Write-Header -Type run -Title 'CREATE LOCAL ACCOUNT'
        $created = New-MigrationLocalUser -Username $userName -Password $newPw
        if (-not $created) { throw "Failed to create local account $userName" }
        $target      = "$env:COMPUTERNAME\$userName"
        $createFlags = $true
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = Read-Host "Enter the TARGET account on this machine (e.g. $env:COMPUTERNAME\jdoe)"
    }
    if ([string]::IsNullOrWhiteSpace($target)) { throw "Target account is required" }

    # --- Encryption key (if store is encrypted) -------------------------------
    $key = $EncryptionKey
    if ($encrypted -and [string]::IsNullOrWhiteSpace($key)) {
        $secKey = Read-Host "Store is encrypted. Enter the decryption key" -AsSecureString
        $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secKey))
    }

    # --- Destructive-action confirm (interactive) or -Force (unattended) ------
    Write-Header -Type warn -Title 'RESTORE CONFIRMATION'
    Write-Info "From : $sourceAcct"
    Write-Info "To   : $target  (this machine)"
    Write-Info "loadstate writes into the target profile and cannot be undone."
    if (-not $Force) {
        $confirm = Read-Host "Proceed with loadstate? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Warn "Restore cancelled by operator."
            return
        }
    } else {
        Write-Info "-Force / config flag set -- proceeding without prompt."
    }

    # --- Restore --------------------------------------------------------------
    Write-Header -Type run -Title 'PROFILE RESTORE'
    $loadExit = Start-ProfileRestore -USMTPath $USMTPath -StorePath $stageDir `
                                     -SourceAccount $sourceAcct -TargetAccount $target `
                                     -EncryptionKey $key -CreateAccountFlags $createFlags `
                                     -NewAccountPassword $newPw
    if ($loadExit -gt 1) {
        throw "loadstate failed (exit code $loadExit). See $stageDir\load.log"
    }

    Write-Header -Type ok -Title 'RECEIVER COMPLETE'
    Write-Info "Profile restored into $target."
    Write-Info "Have the user LOG OUT and LOG BACK IN for all settings to apply."
    }
    finally {
        # Never leave a loadstate/recv child alive on exit or cancel.
        Stop-TrackedChildren
    }
}

# ==============================================================================
# MAIN
# ==============================================================================

$exitCode = 0

# Route Ctrl+C / engine exit through the same child-process cleanup so a cancel
# never orphans scanstate/loadstate/localsend (which would hold USMT's lock and
# the console pipe). Best-effort: the engine event covers normal cancel/exit.
$null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
    if ($script:TrackedChildren) {
        foreach ($proc in $script:TrackedChildren) {
            try { if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
        }
    }
}

try {
    $script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')

    # --- INPUT VALIDATION -----------------------------------------------------
    Write-Header -Type info -Title 'INPUT VALIDATION'
    $errorOccurred = $false
    $errorText = ""

    $resolvedRole = $Role
    if ([string]::IsNullOrWhiteSpace($resolvedRole)) {
        Write-Host ""
        Write-Host "  This machine : $($env:COMPUTERNAME)  (Admin: $( if ($script:IsAdmin) { 'Yes' } else { 'No' } ))" -ForegroundColor Gray
        Write-Host "  Which laptop is this?" -ForegroundColor Yellow
        Write-Host "    1. OLD laptop  -- Sender (capture and send the profile)" -ForegroundColor White
        Write-Host "    2. NEW laptop  -- Receiver (receive and restore the profile)" -ForegroundColor White
        Write-Host ""
        $roleChoice = Read-Host "  Select (1-2)"
        switch ($roleChoice) {
            '1' { $resolvedRole = 'Sender' }
            '2' { $resolvedRole = 'Receiver' }
            default { $resolvedRole = '' }
        }
    }

    if ($resolvedRole -ne 'Sender' -and $resolvedRole -ne 'Receiver') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Role must be 'Sender' or 'Receiver'"
    }

    if ($Transport -ne 'localsend' -and $Transport -ne 'path') {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Transport must be 'localsend' or 'path'"
    }

    # Admin is required on the Receiver (loadstate / account creation / firewall).
    if ($resolvedRole -eq 'Receiver' -and -not $script:IsAdmin) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Receiver role requires Administrator privileges (loadstate, account creation, firewall rule). Re-run elevated."
    }
    # Sender also needs admin for scanstate /vsc.
    if ($resolvedRole -eq 'Sender' -and -not $script:IsAdmin) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Sender role requires Administrator privileges (scanstate). Re-run elevated."
    }

    if ($errorOccurred) {
        Write-Header -Type error -Title 'ERROR OCCURRED'
        Write-Host $errorText -ForegroundColor Red
        Write-Header -Type error -Title 'FINAL STATUS'
        Write-Failure "Input validation failed"
        exit 1
    }

    Write-Success "Inputs valid"

    # --- PRE-FLIGHT: clear stale migration processes --------------------------
    # A prior cancelled run can leave scanstate/loadstate/localsend alive, which
    # poisons a fresh run with USMT's single-instance lock (scanstate code 29).
    Write-Header -Type info -Title 'PRE-FLIGHT CLEANUP'
    Stop-StaleMigrationProcesses -Force:$Force
    Write-Success "No conflicting migration processes running"

    Write-Header -Type info -Title 'ROLE SELECTION'
    Write-Info "This machine : $($env:COMPUTERNAME)  (Admin: $( if ($script:IsAdmin) { 'Yes' } else { 'No' } ))"
    Write-Info "Role         : $resolvedRole"
    Write-Info "Transport    : $Transport"

    if ($resolvedRole -eq 'Sender') {
        Invoke-SenderRole -Transport $Transport
    } else {
        Invoke-ReceiverRole -Transport $Transport
    }

    Write-Header -Type ok -Title 'SCRIPT COMPLETED'
    Write-Success "Done"
}
catch {
    Write-Header -Type error -Title 'ERROR OCCURRED'
    Write-Failure $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Info $_.ScriptStackTrace }
    Write-Header -Type error -Title 'FINAL STATUS'
    Write-Failure "Migration failed"
    $exitCode = 1
}
finally {
    # Final backstop: kill any tracked child still alive and drop the exit handler.
    Stop-TrackedChildren
    Unregister-Event -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -ErrorAction SilentlyContinue
}

exit $exitCode
