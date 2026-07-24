$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows 11 25H2 ISO Upgrade                                  v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windows11_iso_upgrade.ps1
================================================================================
 FILE     : windows11_iso_upgrade.ps1
 DESCRIPTION : ISO-based silent upgrade to Windows 11 25H2 for Level RMM
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   ISO-based silent in-place upgrade to Windows 11, version 25H2, for Level RMM
   (run as System). This is the fallback path when the enablement package /
   Windows Update / Installation Assistant routes are unsuitable: it fetches a
   fresh consumer (Home/Pro/Edu) ISO via Fido, gates on hardware eligibility
   before any download, then drives setup.exe for an authoritative compat scan
   and the upgrade itself. Already-25H2 devices are a no-op success. The fleet is
   Home/Pro only, so the consumer multi-edition ISO is sufficient (the business
   editions ISO is not obtainable unauthenticated).

 DATA SOURCES & PRIORITY

   - Registry HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion (DisplayVersion)
   - Win32_Processor / Win32_ComputerSystem (CPU, RAM)
   - Get-Disk / Get-Partition (system disk size), Get-PSDrive (free space)
   - Win32_Tpm (root\cimv2\security\microsofttpm) SpecVersion, Get-Tpm fallback
   - Confirm-SecureBootUEFI (UEFI / Secure Boot capability)
   - Fido.ps1 v1.70 -> Microsoft software-download ISO URL (expires ~24h)
   - setup.exe /compat scanonly result code (authoritative compat gate)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $targetDisplayVersion : 25H2 (registry DisplayVersion that means "done")
     - $fidoUrl              : Fido.ps1 raw URL, pinned to release tag v1.70
     - $fidoWin              : Fido -Win value (11)
     - $fidoRel              : Fido -Rel value (25H2)
     - $fidoEd               : Fido -Ed value (Pro)
     - $fidoLang             : Fido -Lang value (English (United States))
     - $fidoArch             : Fido -Arch value (x64)
     - $workDir              : working directory for Fido + ISO
     - $requiredFreeGB       : minimum free space on the system drive (35)
     - $rebootAfterInstall   : schedule reboot after a successful upgrade (true)

 SETTINGS

   - Fido pin            : v1.70 (SYSTEM fleet-wide, so no floating tag)
   - Fido command        : -Win 11 -Rel 25H2 -Ed Pro
                           -Lang "English (United States)" -Arch x64 -GetUrl
   - ISO download        : curl.exe --location --silent --show-error --fail
   - Compat scan         : setup.exe /auto upgrade /quiet /noreboot
                           /compat scanonly /eula accept
   - Upgrade             : setup.exe /auto upgrade /quiet /eula accept
                           /dynamicupdate enable /noreboot
   - Reboot After Install : true (default) - 60s delay via shutdown.exe
   - Level timeout       : 14400 seconds (4 hours) recommended
   - Level run context   : System

 BEHAVIOR

   The script performs the following actions in order:
   1. Validate hardcoded inputs
   2. No-op success if registry DisplayVersion already reports 25H2
   3. Hardware compat gate (before any download): AMD64, CPU >=2 cores >=1GHz,
      RAM >=4GB, system disk >=64GB, free space >=35GB, TPM 2.0, UEFI + Secure
      Boot capable. Collect ALL blockers, print a report, exit 1 if any.
   4. Download Fido.ps1 (pinned v1.70), run it, take the last https:// stdout
      line as the ISO URL
   5. Download the ISO with curl.exe; sanity-check size >= 3GB (an ISO retained
      by a previous failed upgrade attempt is reused instead of re-downloaded)
   6. Mount the ISO, resolve the drive letter, verify setup.exe exists
   7. Compat scan (setup.exe /compat scanonly); only 0xC1900210 proceeds
   8. Upgrade (setup.exe /auto upgrade); success = exit 0 or 0xC1900210
   9. On success: dismount ISO, delete ISO + Fido, then optionally schedule reboot

 PREREQUISITES

   - PowerShell 5.1 or later
   - Level agent; run as System (SYSTEM privileges)
   - Internet access (raw.githubusercontent.com + Microsoft download endpoints)
   - Device must meet Windows 11 hardware requirements (gated inline)
   - Consumer edition only (Home / Pro / Edu) - no Enterprise
   - Restart required to complete the upgrade (default schedules one)

 SECURITY NOTES

   - No secrets in logs
   - Fido pinned to release tag v1.70 (no floating branch fetched as SYSTEM)
   - Downloads only from raw.githubusercontent.com and Microsoft endpoints
   - Microsoft ISO URLs expire ~24h; fetched and consumed in a single run
   - Default reboots after success (set $rebootAfterInstall = $false for
     maintenance windows)
   - ISO + Fido.ps1 are deleted from the work dir after a successful upgrade

 ENDPOINTS

   - https://raw.githubusercontent.com/pbatard/Fido/v1.70/Fido.ps1 (Fido script)
   - https://software-download.microsoft.com / *.microsoft.com (ISO, Fido-issued)

 EXIT CODES

   0 = Success (already 25H2, or upgrade staged and reboot scheduled)
   1 = Failure (input invalid, hardware blocker, download/mount/compat/upgrade)

 EXAMPLE RUN (eligible device -> upgrade staged)

   [INFO] INPUT VALIDATION
   ==============================================================
     Inputs validated successfully

   [INFO] TARGET VERSION CHECK
   ==============================================================
     Current DisplayVersion : 24H2
     Target DisplayVersion  : 25H2
     Not yet on target - continuing

   [INFO] HARDWARE COMPATIBILITY
   ==============================================================
     Architecture   : AMD64 (OK)
     CPU            : 8 cores @ 2900 MHz (OK)
     RAM            : 16 GB (OK)
     System Disk    : 476 GB (OK)
     Free Space     : 210 GB (OK)
     TPM            : SpecVersion 2.0 (OK)
     Firmware       : UEFI (SecureBoot enabled: True) (OK)
     Result         : All hardware checks passed

   [RUN] FETCH ISO URL
   ==============================================================
     Fido returned ISO URL

   [RUN] DOWNLOAD ISO
   ==============================================================
     File Size : 6.8 GB

   [RUN] MOUNT ISO
   ==============================================================
     Drive : E: (setup.exe found)

   [RUN] COMPATIBILITY SCAN
   ==============================================================
     Exit : 0xC1900210 (no compatibility issues)

   [RUN] UPGRADE
   ==============================================================
     Exit : 0xC1900210 (upgrade staged)

   [OK] FINAL STATUS
   ==============================================================
     Result : SUCCESS - reboot scheduled to complete 25H2

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-24 v1.0.0 Initial release - ISO-based silent upgrade to Windows 11 25H2
                   (Fido v1.70 URL fetch, inline hardware gate, setup.exe compat
                   scan + upgrade, cleanup and optional reboot).
================================================================================
#>

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$targetDisplayVersion = '25H2'
$fidoUrl = 'https://raw.githubusercontent.com/pbatard/Fido/v1.70/Fido.ps1'
$fidoWin = '11'
$fidoRel = '25H2'
$fidoEd = 'Pro'
$fidoLang = 'English (United States)'
$fidoArch = 'x64'
$workDir = 'C:\ProgramData\Limehawk\windows11_iso_upgrade'
$requiredFreeGB = 35
$rebootAfterInstall = $true

Set-StrictMode -Version Latest

# ==============================================================================
# CONSTANTS
# ==============================================================================
$ntCurrentVersionPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$fidoScriptPath = Join-Path $workDir 'Fido.ps1'
$isoPath = Join-Path $workDir 'Windows11_25H2.iso'
# Minimum hardware thresholds (Windows 11 requirements)
$minCpuCores = 2
$minCpuMhz = 1000
$minRamGB = 4
$minSystemDiskGB = 64
$minIsoSizeGB = 3
# setup.exe result codes (formatted as 0x{X8} from the signed Int32 exit code)
$codeNoIssues = '0xC1900210'   # MOSETUP_E_COMPAT_SCANONLY - no issues
$codeAppBlock = '0xC1900208'   # incompatible app compat block
$codeEditionMismatch = '0xC1900204' # migration choice unavailable (edition mismatch)
$codeNotEligible = '0xC1900200' # not eligible (hardware requirements)
$codeDiskSpace = '0xC190020E'   # insufficient disk space

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================
# HELPERS
# ==============================================================================

function Write-Section {
    param([string]$Tag, [string]$Title)
    Write-Host ""
    Write-Host "[$Tag] $Title"
    Write-Host "=============================================================="
}

function Write-FailAndExit {
    param([string[]]$Lines)
    Write-Section -Tag 'ERROR' -Title 'ERROR OCCURRED'
    foreach ($line in $Lines) {
        Write-Host "  $line"
    }
    Write-Section -Tag 'ERROR' -Title 'SCRIPT COMPLETED'
    exit 1
}

function ConvertTo-ExitHex {
    param([int]$Code)
    return ('0x{0:X8}' -f $Code)
}

function Get-ExitCodeMeaning {
    param([string]$HexCode)
    switch ($HexCode) {
        $codeNoIssues { return 'no compatibility issues' }
        $codeAppBlock { return 'application compatibility block (incompatible app)' }
        $codeEditionMismatch { return 'migration choice unavailable (edition mismatch)' }
        $codeNotEligible { return 'device not eligible (hardware requirements not met)' }
        $codeDiskSpace { return 'insufficient disk space' }
        '0x00000000' { return 'success' }
        default { return 'unknown / unmapped setup result code' }
    }
}

function Dismount-IsoQuiet {
    try {
        if (Test-Path -LiteralPath $isoPath) {
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
}

function Remove-IsoAndFido {
    Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fidoScriptPath -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'INPUT VALIDATION'

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($targetDisplayVersion)) {
    $errorOccurred = $true
    $errorText += "- Target Display Version is required`n"
}
if ([string]::IsNullOrWhiteSpace($fidoUrl) -or $fidoUrl -notmatch '^https://') {
    $errorOccurred = $true
    $errorText += "- Fido URL is required and must start with https://`n"
}
if ([string]::IsNullOrWhiteSpace($fidoWin)) {
    $errorOccurred = $true
    $errorText += "- Fido -Win value is required`n"
}
if ([string]::IsNullOrWhiteSpace($fidoRel)) {
    $errorOccurred = $true
    $errorText += "- Fido -Rel value is required`n"
}
if ([string]::IsNullOrWhiteSpace($fidoEd)) {
    $errorOccurred = $true
    $errorText += "- Fido -Ed value is required`n"
}
if ([string]::IsNullOrWhiteSpace($fidoLang)) {
    $errorOccurred = $true
    $errorText += "- Fido -Lang value is required`n"
}
if ([string]::IsNullOrWhiteSpace($fidoArch)) {
    $errorOccurred = $true
    $errorText += "- Fido -Arch value is required`n"
}
if ([string]::IsNullOrWhiteSpace($workDir)) {
    $errorOccurred = $true
    $errorText += "- Work directory is required`n"
}
if ($requiredFreeGB -isnot [int] -and $requiredFreeGB -isnot [long]) {
    $errorOccurred = $true
    $errorText += "- requiredFreeGB must be an integer`n"
} elseif ([int]$requiredFreeGB -lt 1) {
    $errorOccurred = $true
    $errorText += "- requiredFreeGB must be a positive integer`n"
}
if ($rebootAfterInstall -isnot [bool]) {
    $errorOccurred = $true
    $errorText += "- Reboot After Install must be a boolean`n"
}

if ($errorOccurred) {
    Write-FailAndExit -Lines @($errorText.TrimEnd().Split("`n"))
}

Write-Host "  Target Version       : $targetDisplayVersion"
Write-Host "  Fido URL             : $fidoUrl"
Write-Host "  Fido Selection       : -Win $fidoWin -Rel $fidoRel -Ed $fidoEd -Lang `"$fidoLang`" -Arch $fidoArch"
Write-Host "  Work Directory       : $workDir"
Write-Host "  Required Free Space  : $requiredFreeGB GB"
Write-Host "  Reboot After Install : $rebootAfterInstall"
Write-Host "  Inputs validated successfully"

# ==============================================================================
# TARGET VERSION CHECK (no-op gate)
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'TARGET VERSION CHECK'

$currentDisplayVersion = ''
try {
    $props = Get-ItemProperty -Path $ntCurrentVersionPath -ErrorAction Stop
    if ($props.PSObject.Properties.Name -contains 'DisplayVersion' -and -not [string]::IsNullOrWhiteSpace($props.DisplayVersion)) {
        $currentDisplayVersion = [string]$props.DisplayVersion
    }
} catch {
    Write-FailAndExit -Lines @(
        'Failed to read Windows DisplayVersion from the registry'
        "Path  : $ntCurrentVersionPath"
        "Error : $($_.Exception.Message)"
    )
}

Write-Host "  Current DisplayVersion : $currentDisplayVersion"
Write-Host "  Target DisplayVersion  : $targetDisplayVersion"

if ($currentDisplayVersion -eq $targetDisplayVersion) {
    Write-Host "  Already on target - no action needed"
    Write-Section -Tag 'OK' -Title 'FINAL STATUS'
    Write-Host "  Result : SUCCESS"
    Write-Host "  Note   : Device already reports Windows 11 $targetDisplayVersion"
    Write-Section -Tag 'OK' -Title 'SCRIPT COMPLETED'
    exit 0
}

Write-Host "  Not yet on target - continuing"

# ==============================================================================
# HARDWARE COMPATIBILITY (gate before any download)
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'HARDWARE COMPATIBILITY'

$hwBlocked = $false
$hwBlockers = ""

# --- Architecture (AMD64) ---
$arch = $env:PROCESSOR_ARCHITECTURE
if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
    $arch = $env:PROCESSOR_ARCHITEW6432
}
if ([string]::IsNullOrWhiteSpace($arch)) { $arch = 'UNKNOWN' }
$arch = $arch.ToUpperInvariant()
if ($arch -eq 'AMD64') {
    Write-Host "  Architecture   : $arch (OK)"
} else {
    Write-Host "  Architecture   : $arch (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- Architecture $arch is not supported (requires AMD64/x64)`n"
}

# --- CPU (>=2 cores, >=1GHz) ---
try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $cpuCores = [int]$cpu.NumberOfCores
    $cpuMhz = [int]$cpu.MaxClockSpeed
    if ($cpuCores -ge $minCpuCores -and $cpuMhz -ge $minCpuMhz) {
        Write-Host "  CPU            : $cpuCores cores @ $cpuMhz MHz (OK)"
    } else {
        Write-Host "  CPU            : $cpuCores cores @ $cpuMhz MHz (BLOCKER)"
        $hwBlocked = $true
        $hwBlockers += "- CPU must have >=$minCpuCores cores and >=$minCpuMhz MHz (found $cpuCores cores @ $cpuMhz MHz)`n"
    }
} catch {
    Write-Host "  CPU            : query failed (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- Could not query CPU (Win32_Processor): $($_.Exception.Message)`n"
}

# --- RAM (>=4GB) ---
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $ramGB = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 1)
    if ($ramGB -ge $minRamGB) {
        Write-Host "  RAM            : $ramGB GB (OK)"
    } else {
        Write-Host "  RAM            : $ramGB GB (BLOCKER)"
        $hwBlocked = $true
        $hwBlockers += "- RAM must be >=$minRamGB GB (found $ramGB GB)`n"
    }
} catch {
    Write-Host "  RAM            : query failed (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- Could not query RAM (Win32_ComputerSystem): $($_.Exception.Message)`n"
}

# --- System disk size (>=64GB) ---
$systemDriveLetter = ($env:SystemDrive).TrimEnd(':')
$diskSizeGB = 0
try {
    $osPartition = Get-Partition -DriveLetter $systemDriveLetter -ErrorAction Stop
    $osDisk = Get-Disk -Number $osPartition.DiskNumber -ErrorAction Stop
    $diskSizeGB = [math]::Round([double]$osDisk.Size / 1GB, 1)
} catch {
    try {
        $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $diskSizeGB = [math]::Round([double]$ld.Size / 1GB, 1)
    } catch {
        $diskSizeGB = 0
    }
}
if ($diskSizeGB -ge $minSystemDiskGB) {
    Write-Host "  System Disk    : $diskSizeGB GB (OK)"
} else {
    Write-Host "  System Disk    : $diskSizeGB GB (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- System disk must be >=$minSystemDiskGB GB (found $diskSizeGB GB)`n"
}

# --- Free space (>= requiredFreeGB on system drive) ---
$freeGB = 0
try {
    $psDrive = Get-PSDrive -Name $systemDriveLetter -ErrorAction Stop
    $freeGB = [math]::Round([double]$psDrive.Free / 1GB, 1)
} catch {
    try {
        $ld2 = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $freeGB = [math]::Round([double]$ld2.FreeSpace / 1GB, 1)
    } catch {
        $freeGB = 0
    }
}
if ($freeGB -ge [int]$requiredFreeGB) {
    Write-Host "  Free Space     : $freeGB GB (OK)"
} else {
    Write-Host "  Free Space     : $freeGB GB (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- Free space on $($env:SystemDrive) must be >=$requiredFreeGB GB (found $freeGB GB)`n"
}

# --- TPM (present, SpecVersion contains 2.0) ---
$tpmOk = $false
$tpmDetail = 'not detected'
try {
    $tpmC = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction Stop | Select-Object -First 1
    if ($null -ne $tpmC -and -not [string]::IsNullOrWhiteSpace([string]$tpmC.SpecVersion)) {
        $tpmDetail = "SpecVersion $([string]$tpmC.SpecVersion)"
        if ([string]$tpmC.SpecVersion -match '2\.0') { $tpmOk = $true }
    }
} catch {
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm.TpmPresent) {
            $tpmDetail = 'present but SpecVersion could not be confirmed as 2.0'
        }
    } catch {
        $tpmDetail = 'not detected'
    }
}
if ($tpmOk) {
    Write-Host "  TPM            : $tpmDetail (OK)"
} else {
    Write-Host "  TPM            : $tpmDetail (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- TPM 2.0 required ($tpmDetail)`n"
}

# --- Firmware (UEFI + Secure Boot capable) ---
$fwOk = $false
$fwDetail = ''
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction Stop
    # $true = Secure Boot on; $false = off but UEFI/capable. Both mean UEFI.
    $fwOk = $true
    $fwDetail = "UEFI (SecureBoot enabled: $sb)"
} catch {
    # "Cmdlet not supported on this platform" => legacy BIOS
    $fwOk = $false
    $fwDetail = 'Legacy BIOS or Secure Boot not supported (Confirm-SecureBootUEFI threw)'
}
if ($fwOk) {
    Write-Host "  Firmware       : $fwDetail (OK)"
} else {
    Write-Host "  Firmware       : $fwDetail (BLOCKER)"
    $hwBlocked = $true
    $hwBlockers += "- UEFI firmware with Secure Boot capability required ($fwDetail)`n"
}

if ($hwBlocked) {
    Write-Host "  Result         : One or more hardware checks failed"
    Write-FailAndExit -Lines (@(
        'Device does not meet Windows 11 hardware requirements - nothing downloaded'
    ) + $hwBlockers.TrimEnd().Split("`n"))
}

Write-Host "  Result         : All hardware checks passed"

# ==============================================================================
# WORK DIRECTORY
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'WORK DIRECTORY'
try {
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    Write-Host "  Work directory ready : $workDir"
} catch {
    Write-FailAndExit -Lines @(
        'Failed to create the work directory'
        "Path  : $workDir"
        "Error : $($_.Exception.Message)"
    )
}

# ==============================================================================
# FETCH ISO URL (Fido)
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'FETCH ISO URL'

try {
    Write-Host "  Downloading Fido.ps1 (pinned v1.70)..."
    Write-Host "  URL         : $fidoUrl"
    Write-Host "  Destination : $fidoScriptPath"
    Invoke-WebRequest -Uri $fidoUrl -OutFile $fidoScriptPath -UseBasicParsing
    if (-not (Test-Path -LiteralPath $fidoScriptPath -PathType Leaf)) {
        throw 'Fido.ps1 was not downloaded'
    }
} catch {
    Write-FailAndExit -Lines @(
        'Failed to download Fido.ps1'
        "URL   : $fidoUrl"
        "Error : $($_.Exception.Message)"
    )
}

Write-Host "  Running Fido to resolve the ISO URL..."
# PS 5.1: redirected native stderr throws under $ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$fidoOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fidoScriptPath `
    -Win $fidoWin -Rel $fidoRel -Ed $fidoEd -Lang $fidoLang -Arch $fidoArch -GetUrl 2>&1
$fidoExit = $LASTEXITCODE
$ErrorActionPreference = $prevEap

$fidoLines = @()
foreach ($item in $fidoOutput) { $fidoLines += [string]$item }
$fidoText = $fidoLines -join "`n"

$isoUrl = ($fidoLines | Where-Object { $_ -match '^https://' } | Select-Object -Last 1)

if ($fidoExit -ne 0 -or [string]::IsNullOrWhiteSpace($isoUrl)) {
    Remove-Item -LiteralPath $fidoScriptPath -Force -ErrorAction SilentlyContinue
    Write-FailAndExit -Lines (@(
        'Fido did not return a Windows 11 25H2 ISO URL'
        "Fido exit code : $fidoExit"
        'Fido output    :'
    ) + $fidoLines)
}

Write-Host "  Fido exit code : $fidoExit"
Write-Host "  ISO URL resolved successfully"

# ==============================================================================
# DOWNLOAD ISO
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'DOWNLOAD ISO'

# Reuse an ISO retained from a failed upgrade attempt (saves a ~7GB re-download)
$reuseIso = $false
if (Test-Path -LiteralPath $isoPath -PathType Leaf) {
    if ((Get-Item -LiteralPath $isoPath).Length -ge ($minIsoSizeGB * 1GB)) {
        $reuseIso = $true
        Write-Host "  Existing ISO found from a previous run - reusing it"
    } else {
        Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $reuseIso) {
    try {
        Write-Host "  Downloading ISO with curl.exe..."
        Write-Host "  Destination : $isoPath"
        # House rule: curl stderr kills PowerShell under Stop; use --silent --show-error --fail
        & curl.exe --location --silent --show-error --fail --output $isoPath $isoUrl
        $curlExit = $LASTEXITCODE
        if ($curlExit -ne 0) {
            throw "curl.exe exited with code $curlExit"
        }
        if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
            throw 'ISO file was not downloaded'
        }
    } catch {
        Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
        Write-FailAndExit -Lines @(
            'Failed to download the Windows 11 25H2 ISO'
            "Error : $($_.Exception.Message)"
            'Microsoft ISO URLs expire ~24h; re-run to fetch a fresh URL'
        )
    }
}

$isoSizeBytes = (Get-Item -LiteralPath $isoPath).Length
$isoSizeGB = [math]::Round([double]$isoSizeBytes / 1GB, 2)
if ($isoSizeBytes -lt ($minIsoSizeGB * 1GB)) {
    Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
    Write-FailAndExit -Lines @(
        'Downloaded ISO failed the size sanity check'
        "Size     : $isoSizeGB GB"
        "Minimum  : $minIsoSizeGB GB"
        'The download is likely truncated or an error page - re-run'
    )
}
Write-Host "  File Size : $isoSizeGB GB"
Write-Host "  Download completed successfully"

# ==============================================================================
# MOUNT ISO
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'MOUNT ISO'

$driveLetter = ''
try {
    $mount = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 2
    $volume = $mount | Get-Volume -ErrorAction Stop
    $driveLetter = [string]$volume.DriveLetter
    if ([string]::IsNullOrWhiteSpace($driveLetter)) {
        throw 'Could not resolve a drive letter for the mounted ISO'
    }
} catch {
    Dismount-IsoQuiet
    Remove-IsoAndFido
    Write-FailAndExit -Lines @(
        'Failed to mount the Windows 11 25H2 ISO'
        "Error : $($_.Exception.Message)"
    )
}

$setupPath = "${driveLetter}:\setup.exe"
if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
    Dismount-IsoQuiet
    Remove-IsoAndFido
    Write-FailAndExit -Lines @(
        'setup.exe was not found on the mounted ISO'
        "Expected : $setupPath"
    )
}
Write-Host "  Drive : ${driveLetter}: (setup.exe found)"

# ==============================================================================
# COMPATIBILITY SCAN
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'COMPATIBILITY SCAN'

try {
    Write-Host "  Running setup.exe /compat scanonly..."
    $scanProc = Start-Process -FilePath $setupPath `
        -ArgumentList '/auto', 'upgrade', '/quiet', '/noreboot', '/compat', 'scanonly', '/eula', 'accept' `
        -Wait -PassThru
    $scanExit = [int]$scanProc.ExitCode
} catch {
    Dismount-IsoQuiet
    Remove-IsoAndFido
    Write-FailAndExit -Lines @(
        'Failed to run the setup.exe compatibility scan'
        "Error : $($_.Exception.Message)"
    )
}

$scanHex = ConvertTo-ExitHex -Code $scanExit
$scanMeaning = Get-ExitCodeMeaning -HexCode $scanHex
Write-Host "  Exit : $scanHex ($scanMeaning)"

if ($scanHex -ne $codeNoIssues) {
    Dismount-IsoQuiet
    Remove-IsoAndFido
    Write-FailAndExit -Lines @(
        'Compatibility scan reported a blocking condition - upgrade aborted'
        "Result : $scanHex ($scanMeaning)"
        'ISO dismounted and removed; resolve the blocker then re-run'
    )
}

# ==============================================================================
# UPGRADE
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'UPGRADE'

try {
    Write-Host "  Running setup.exe /auto upgrade (this can take a long time)..."
    $upgradeProc = Start-Process -FilePath $setupPath `
        -ArgumentList '/auto', 'upgrade', '/quiet', '/eula', 'accept', '/dynamicupdate', 'enable', '/noreboot' `
        -Wait -PassThru
    $upgradeExit = [int]$upgradeProc.ExitCode
} catch {
    Dismount-IsoQuiet
    # Keep ISO for retry on unexpected launch failure
    Write-FailAndExit -Lines @(
        'Failed to launch the setup.exe upgrade'
        "Error : $($_.Exception.Message)"
        'ISO retained for retry'
    )
}

$upgradeHex = ConvertTo-ExitHex -Code $upgradeExit
$upgradeMeaning = Get-ExitCodeMeaning -HexCode $upgradeHex
Write-Host "  Exit : $upgradeHex ($upgradeMeaning)"

if ($upgradeHex -ne '0x00000000' -and $upgradeHex -ne $codeNoIssues) {
    Dismount-IsoQuiet
    # Keep ISO for retry; setup logs remain for diagnosis
    Write-FailAndExit -Lines @(
        'Windows 11 25H2 upgrade did not complete successfully'
        "Result : $upgradeHex ($upgradeMeaning)"
        'ISO retained for retry (Fido.ps1 removed)'
        'Diagnose with SetupDiag and C:\$WINDOWS.~BT\Sources\Panther logs'
    )
}

# Fido no longer needed once the upgrade staged successfully
Remove-Item -LiteralPath $fidoScriptPath -Force -ErrorAction SilentlyContinue

# ==============================================================================
# CLEANUP
# ==============================================================================

Write-Section -Tag 'RUN' -Title 'CLEANUP'
Dismount-IsoQuiet
Write-Host "  ISO dismounted"
Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $isoPath) {
    Write-Host "  [WARN] Could not remove ISO: $isoPath"
} else {
    Write-Host "  ISO removed : $isoPath"
}
if (-not (Test-Path -LiteralPath $fidoScriptPath)) {
    Write-Host "  Fido.ps1 removed"
}

# ==============================================================================
# REBOOT
# ==============================================================================

$rebootScheduled = $false
if ($rebootAfterInstall) {
    Write-Section -Tag 'RUN' -Title 'REBOOT'
    $rebootMsg = "The Windows 11 $targetDisplayVersion upgrade will complete after this restart. Please save your work."
    try {
        Write-Host "  Scheduling restart in 60 seconds..."
        Write-Host "  Message : $rebootMsg"
        $shutdownProc = Start-Process -FilePath 'shutdown.exe' `
            -ArgumentList "/r /t 60 /c `"$rebootMsg`" /d p:2:4" -Wait -PassThru -NoNewWindow
        if ($null -ne $shutdownProc -and $shutdownProc.ExitCode -ne 0) {
            throw "shutdown.exe returned exit code $($shutdownProc.ExitCode)"
        }
        $rebootScheduled = $true
        Write-Host "  Restart scheduled successfully"
    } catch {
        Write-Host "  [WARN] Reboot scheduling failed: $($_.Exception.Message)"
        Write-Host "  Restart the device manually to finish the upgrade"
    }
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Section -Tag 'OK' -Title 'FINAL STATUS'
Write-Host "  Result           : SUCCESS"
Write-Host "  Upgrade Exit     : $upgradeHex ($upgradeMeaning)"
Write-Host "  ISO Size         : $isoSizeGB GB"
if ($rebootAfterInstall) {
    if ($rebootScheduled) {
        Write-Host "  Reboot           : scheduled (60s) to complete Windows 11 $targetDisplayVersion"
    } else {
        Write-Host "  Reboot           : scheduling failed - restart manually to complete upgrade"
    }
} else {
    Write-Host "  Reboot           : not scheduled (rebootAfterInstall is false) - restart to complete"
}
Write-Host "  Note             : DisplayVersion reports $targetDisplayVersion after the restart finishes setup"

Write-Section -Tag 'OK' -Title 'SCRIPT COMPLETED'
exit 0
