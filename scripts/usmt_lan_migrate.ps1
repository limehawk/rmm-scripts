$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : USMT LAN Migration Tool                                      v1.0.0
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
     - $IncludeLocalAppData : $false (advanced; AppData\Local can be very large)

 SETTINGS

   - Compression is FORCED ON so the store is a single USMT.MIG file (clean
     LocalSend send). This is intentional and not configurable.
   - LocalSend default port : 53317 (TCP for transfer, UDP for mDNS discovery).
     A temporary inbound firewall rule is opened on the Receiver for the
     duration of the receive and removed afterward.
   - Default staging / store path : C:\MigrationStore
   - USMT is auto-downloaded if absent (x64/x86 zip from the SuperGrate mirror).
   - LocalSend CLI is auto-downloaded if absent (0w0mewo/localsend-cli release).

 BEHAVIOR

   Sender (OLD laptop):
   1. Verify admin, install USMT, install LocalSend CLI (if transport=localsend)
   2. Pick the source profile (menu or from CONFIG)
   3. Run scanstate /p first for a space estimate, then scanstate with
      compression to produce USMT.MIG + backup_info.json
   4. Move the store to the Receiver via LocalSend (--ip) or write to a path

   Receiver (NEW laptop):
   1. Verify admin, install USMT, install LocalSend CLI (if transport=localsend)
   2. Open a temporary inbound firewall rule, run LocalSend recv into staging
      (auto-saves; no interactive accept), then remove the firewall rule -- OR
      read the store from a path
   3. Optionally create + initialize the target local account
   4. Confirm (or -Force), run loadstate with /mu source:target mapping
   5. Tell the user to log out and back in

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
    $process = Start-Process -FilePath $ScanStateExe -ArgumentList $argString -Wait -PassThru -NoNewWindow
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
    $process = Start-Process -FilePath $ScanStateExe -ArgumentList $argString -Wait -PassThru -NoNewWindow

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
    $process = Start-Process -FilePath $LoadStateExe -ArgumentList $argString -Wait -PassThru -NoNewWindow
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

function Test-SameSubnet {
    param([string]$TargetIp)
    # mDNS discovery requires the same subnet. If we can resolve the target to an
    # IPv4 on one of our local /24-ish interfaces, warn when prefixes differ.
    try {
        $localIPs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
        foreach ($lip in $localIPs) {
            $localPrefix  = ($lip.IPAddress -split '\.')[0..2] -join '.'
            $targetPrefix = ($TargetIp -split '\.')[0..2] -join '.'
            if ($localPrefix -eq $targetPrefix) { return $true }
        }
        return $false
    } catch {
        return $true  # don't block on detection failure; just proceed
    }
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

    $ip = Resolve-ReceiverIp -NameOrIp $ReceiverName
    if (-not $ip) {
        Write-Step "Could not resolve '$ReceiverName' directly; scanning the LAN..."
        # localsend scan prints: "Name: <alias>, Version: .., Address: IP:PORT, .."
        $scanOut = & $exe scan -t 6 2>&1
        $match = $scanOut | Select-String -Pattern ("Name:\s*{0}.*Address:\s*([0-9.]+):" -f [regex]::Escape($ReceiverName))
        if ($match -and $match.Matches.Count -gt 0) {
            $ip = $match.Matches[0].Groups[1].Value
        }
    }
    if (-not $ip) {
        Write-Failure "Could not find receiver '$ReceiverName' on the LAN."
        Write-Info "Confirm the receiver is running this script in Receiver role and is on the same subnet."
        return $false
    }

    if (-not (Test-SameSubnet -TargetIp $ip)) {
        Write-Warn "Receiver $ip does not appear to be on this machine's subnet -- LocalSend mDNS may fail."
    }

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

        # recv runs until killed; auto-saves into -d. We run it as a child process
        # and stop it once USMT.MIG lands (or we time out).
        $recv = Start-Process -FilePath $exe `
                              -ArgumentList @('recv', '-d', "`"$StoreDir`"", '-n', $env:COMPUTERNAME) `
                              -PassThru -NoNewWindow

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
            if ($recv.HasExited) { break }
            Start-Sleep -Seconds 2
        }

        if (-not $recv.HasExited) {
            Stop-Process -Id $recv.Id -Force -ErrorAction SilentlyContinue
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

    Write-Header -Type run -Title 'USMT SETUP'
    $USMTPath = Install-USMT
    if (-not $USMTPath) { throw "Cannot proceed without USMT" }

    # --- Resolve source account (config or menu) ------------------------------
    $source = $SourceAccount
    if ([string]::IsNullOrWhiteSpace($source)) {
        Write-Step "Scanning for user profiles..."
        $profiles = Get-UserProfiles
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
        if ([string]::IsNullOrWhiteSpace($receiver)) {
            $receiver = Read-Host "Enter the NEW laptop's hostname or IP"
        }
        if ([string]::IsNullOrWhiteSpace($receiver)) { throw "Receiver hostname/IP is required for LocalSend transport" }
    } else {
        if ([string]::IsNullOrWhiteSpace($receiver)) {
            $receiver = Read-Host "Enter destination path for the store (UNC/SMB/USB)"
        }
        if ([string]::IsNullOrWhiteSpace($receiver)) { throw "Destination path is required for path transport" }
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

function Invoke-ReceiverRole {
    param([string]$Transport)

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

# ==============================================================================
# MAIN
# ==============================================================================

$exitCode = 0
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

exit $exitCode
