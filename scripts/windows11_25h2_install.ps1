$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows 11 25H2 Install                                      v1.1.1
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windows11_25h2_install.ps1
================================================================================
 FILE     : windows11_25h2_install.ps1
 DESCRIPTION : Path-aware silent upgrade to Windows 11 25H2 for Level RMM
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Detects the current Windows version and chooses a clean upgrade path to
   Windows 11, version 25H2 for Level RMM (run as System).

   Paths (Microsoft-aligned):
   - Already 25H2 → no-op success
   - Windows 11 24H2 (build 26100) + CU UBR 5074+ → enablement package KB5054156
     (24H2/25H2 share a core; eKB is a small "master switch" + one restart)
   - Windows 11 24H2 with UBR below 5074 → fail with clear CU prerequisite
   - Windows 10 or Windows 11 older than 24H2 → full feature upgrade via
     Windows Update (if offered) then Windows 11 Installation Assistant

   Sources: Microsoft KB5054156 (eKB applies to 24H2 only; prerequisite
   KB5064081 / 26100.5074+). Older releases need a full feature update / ISO /
   Installation Assistant — not the eKB.

 DATA SOURCES & PRIORITY

   - Registry HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion
   - Win32_OperatingSystem Caption
   - PROCESSOR_ARCHITECTURE / PROCESSOR_ARCHITEW6432
   - Microsoft Update COM (feature update search)
   - Microsoft catalog MSU URLs for KB5054156 (x64 + ARM64)
   - Windows 11 Installation Assistant (go.microsoft.com fwlink)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $downloadUrlX64 / $downloadUrlArm64 : KB5054156 MSU URLs
     - $minUbr / $requiredBuild            : eKB prereq (26100 / 5074)
     - $targetDisplayVersion               : 25H2
     - $sourceDisplayVersion               : 24H2 (eKB source)
     - $installationAssistantUrl           : IA download fwlink
     - $preferWindowsUpdate                : try WU feature update before IA
     - $rebootAfterInstall                 : schedule reboot after successful apply
                                           (default $true — upgrade incomplete without restart)

 SETTINGS

   - eKB method            : wusa.exe /quiet /norestart (then optional scheduled reboot)
   - Full upgrade fallback : Windows11InstallationAssistant.exe
                             /QuietInstall /SkipEULA /NoRestartUI
   - Reboot After Install  : true (default) — 60s delay via shutdown.exe after eKB
   - Level timeout         : 14400 seconds (4 hours) recommended
   - Level run context     : System

 BEHAVIOR

   1. Validate inputs
   2. Detect OS family, DisplayVersion, build, UBR, architecture
   3. Select upgrade path from source → target
   4. Execute path (eKB MSU, or WU feature update, or Installation Assistant)
   5. If $rebootAfterInstall, schedule reboot (eKB path); WU/IA may reboot themselves
   6. Report final status and reboot-pending note

 PREREQUISITES

   - Level agent; run as System
   - Internet access (MSU catalog and/or WU / Installation Assistant)
   - Admin / SYSTEM privileges
   - eKB path: Windows 11 24H2 build 26100 with UBR 5074+ (KB5064081 or later)
   - Full upgrade path: device must meet Windows 11 hardware requirements
   - Restart required to finish most upgrades (default schedules one after eKB)

 SECURITY NOTES

   - No secrets in logs
   - Downloads only from Microsoft delivery endpoints
   - Default reboots after success (set $rebootAfterInstall = $false for maintenance windows)
   - Full upgrade may reboot via Installation Assistant / WU even if flag is false

 ENDPOINTS

   - catalog.sf.dl.delivery.mp.microsoft.com (KB5054156 MSU x64/ARM64)
   - https://go.microsoft.com/fwlink/?linkid=2171764 (Installation Assistant)
   - Windows Update (device-configured)

 EXIT CODES

   0 = Success (already target, package applied, or upgrade started/completed)
   1 = Failure (unsupported OS, missing prereq, download/install error)

 EXAMPLE RUN (Win10 → full upgrade path)

   [INFO] OS DETECTION
   ==============================================================
     Product Name    : Windows 10 Pro
     Display Version : 22H2
     Build           : 19045
     Path            : full_feature_upgrade

   [RUN] WINDOWS UPDATE SEARCH
   ==============================================================
     No matching 25H2 feature update offered — using Installation Assistant

   [RUN] INSTALLATION ASSISTANT
   ==============================================================
     Quiet install started...

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-22 v1.1.1 Default $rebootAfterInstall = $true (upgrade incomplete without restart).
 2026-07-22 v1.1.0 Path-aware upgrades: eKB for 24H2; full feature upgrade
                   (WU then Installation Assistant) for Win10 / pre-24H2 Win11.
                   Level timeout guidance 14400s (4h).
 2026-07-22 v1.0.1 Level timeout 7200s (2h); Level unit is seconds.
 2026-07-22 v1.0.0 Initial release - silent eKB KB5054156 only (24H2→25H2)
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
$installationAssistantUrl = 'https://go.microsoft.com/fwlink/?linkid=2171764'
$preferWindowsUpdate = $true
$rebootAfterInstall = $true

Set-StrictMode -Version Latest

# ==============================================================================
# CONSTANTS
# ==============================================================================
$msuPath = Join-Path $env:TEMP 'windows11.0-kb5054156.msu'
$iaPath = Join-Path $env:TEMP 'Windows11InstallationAssistant.exe'
$ntCurrentVersionPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# wusa: 0 success, 3010 reboot required, 2359302 already installed
$wusaSuccessExitCodes = @(0, 3010, 2359302)

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

    $arch = $env:PROCESSOR_ARCHITECTURE
    if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        $arch = $env:PROCESSOR_ARCHITEW6432
    }
    if ([string]::IsNullOrWhiteSpace($arch)) {
        $arch = 'UNKNOWN'
    }

    $blob = ("$productName $caption").ToLowerInvariant()
    $family = 'Unknown'
    if ($blob -match 'windows 11') {
        $family = 'Windows11'
    } elseif ($blob -match 'windows 10') {
        $family = 'Windows10'
    }

    # Build-based fallback (ProductName can lag after upgrades)
    try {
        $buildNum = [int]$build
        if ($family -eq 'Unknown' -or $family -eq 'Windows10') {
            if ($buildNum -ge 22000) { $family = 'Windows11' }
            elseif ($buildNum -ge 10240) { $family = 'Windows10' }
        }
    } catch { }

    return @{
        DisplayVersion = $displayVersion
        Build          = $build
        Ubr            = $ubr
        ProductName    = $productName
        Caption        = $caption
        Architecture   = $arch.ToUpperInvariant()
        Family         = $family
    }
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

function Get-UpgradePath {
    param($OsInfo)

    if ($OsInfo.DisplayVersion -eq $targetDisplayVersion) {
        return @{
            Name   = 'already_target'
            Reason = "Already on Windows 11 $targetDisplayVersion"
        }
    }

    # eKB path: Windows 11 24H2 / build 26100 only (Microsoft KB5054156)
    $is24h2Core = ($OsInfo.Family -eq 'Windows11' -and (
            $OsInfo.DisplayVersion -eq $sourceDisplayVersion -or
            $OsInfo.Build -eq $requiredBuild
        ))

    if ($is24h2Core) {
        if ([int]$OsInfo.Ubr -lt [int]$minUbr) {
            return @{
                Name   = 'enablement_needs_cu'
                Reason = "Windows 11 $sourceDisplayVersion build $requiredBuild but UBR $($OsInfo.Ubr) < $minUbr (need KB5064081+ before eKB)"
            }
        }
        return @{
            Name   = 'enablement_ekb'
            Reason = "Windows 11 $sourceDisplayVersion ready for enablement package KB5054156"
        }
    }

    if ($OsInfo.Family -eq 'Windows10' -or $OsInfo.Family -eq 'Windows11') {
        return @{
            Name   = 'full_feature_upgrade'
            Reason = "$($OsInfo.Family) $($OsInfo.DisplayVersion) (build $($OsInfo.Build)) cannot use eKB — full feature upgrade required"
        }
    }

    return @{
        Name   = 'unsupported'
        Reason = "Unsupported OS family: $($OsInfo.Family) ($($OsInfo.ProductName))"
    }
}

function Install-EnablementPackage {
    param($OsInfo)

    Write-Section -Tag 'INFO' -Title 'ARCHITECTURE'
    $selectedUrl = ''
    $selectedArch = $OsInfo.Architecture

    if ($selectedArch -eq 'AMD64' -or $selectedArch -eq 'X64') {
        $selectedUrl = $downloadUrlX64
        $selectedArch = 'AMD64'
    } elseif ($selectedArch -eq 'ARM64') {
        if ([string]::IsNullOrWhiteSpace($downloadUrlArm64)) {
            Write-FailAndExit -Lines @(
                'ARM64 download URL is empty in hardcoded inputs'
                'Set $downloadUrlArm64 to the Microsoft catalog MSU for KB5054156 ARM64'
            )
        }
        $selectedUrl = $downloadUrlArm64
    } else {
        Write-FailAndExit -Lines @(
            "Unsupported processor architecture: $($OsInfo.Architecture)"
            'Supported architectures : AMD64, ARM64'
        )
    }

    Write-Host "  Architecture : $selectedArch"
    Write-Host "  Package URL  : $selectedUrl"

    Write-Section -Tag 'RUN' -Title 'DOWNLOAD'
    try {
        Write-Host "  Downloading KB5054156 enablement package..."
        Write-Host "  Destination : $msuPath"
        Invoke-WebRequest -Uri $selectedUrl -OutFile $msuPath -UseBasicParsing
        if (-not (Test-Path -Path $msuPath -PathType Leaf)) {
            throw 'MSU file was not downloaded'
        }
        $fileSizeMb = [math]::Round((Get-Item -Path $msuPath).Length / 1MB, 2)
        Write-Host "  File Size   : $fileSizeMb MB"
        Write-Host "  Download completed successfully"
    } catch {
        Write-FailAndExit -Lines @(
            'Failed to download KB5054156 enablement package'
            "URL   : $selectedUrl"
            "Error : $($_.Exception.Message)"
        )
    }

    Write-Section -Tag 'RUN' -Title 'INSTALLATION'
    $installExitCode = -1
    $rebootRequired = $false
    try {
        Write-Host "  Method     : wusa.exe /quiet /norestart"
        Write-Host "  Package    : $msuPath"
        $process = Start-Process -FilePath 'wusa.exe' -ArgumentList "`"$msuPath`"", '/quiet', '/norestart' -Wait -PassThru -NoNewWindow
        $installExitCode = $process.ExitCode
        Write-Host "  Installer exit code : $installExitCode"

        if ($wusaSuccessExitCodes -notcontains $installExitCode) {
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
            $rebootRequired = $true
        }
    } catch {
        if (Test-Path -Path $msuPath -PathType Leaf) {
            Remove-Item -Path $msuPath -Force -ErrorAction SilentlyContinue
        }
        Write-FailAndExit -Lines @(
            'Failed to install KB5054156 enablement package'
            "Exit Code : $installExitCode"
            "Error     : $($_.Exception.Message)"
            "Hint      : Confirm Windows 11 $sourceDisplayVersion build $requiredBuild UBR $minUbr+"
        )
    }

    Write-Section -Tag 'RUN' -Title 'CLEANUP'
    Remove-Item -Path $msuPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $msuPath -PathType Leaf) {
        Write-Host "  [WARN] Could not remove MSU file: $msuPath"
    } else {
        Write-Host "  Cleanup completed"
    }

    # Reboot is applied once in the main flow via $rebootAfterInstall
    return @{
        InstallExitCode = $installExitCode
        RebootRequired  = $rebootRequired
        Method          = 'enablement_ekb'
        SelectedArch    = $selectedArch
    }
}

function Install-FeatureUpdateViaWindowsUpdate {
    Write-Section -Tag 'RUN' -Title 'WINDOWS UPDATE SEARCH'
    Write-Host "  Searching for Windows 11 $targetDisplayVersion feature update..."

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # Broad software search; filter in PowerShell for feature update titles
        $result = $searcher.Search('IsInstalled=0 and Type=''Software''')
    } catch {
        Write-Host "  Windows Update search failed: $($_.Exception.Message)"
        return $false
    }

    $updateColl = New-Object -ComObject Microsoft.Update.UpdateColl
    $foundTitles = New-Object System.Collections.Generic.List[string]
    $updateCount = 0
    try {
        $updateCount = [int]$result.Updates.Count
    } catch {
        $updateCount = 0
    }

    for ($i = 0; $i -lt $updateCount; $i++) {
        $update = $result.Updates.Item($i)
        $title = [string]$update.Title
        $titleLower = $title.ToLowerInvariant()
        $isTargeted = ($titleLower -match '25h2') -or ($titleLower -match 'version 25h2')
        $isWin11Feature = (
            ($titleLower -match 'windows 11') -and
            (
                $isTargeted -or
                ($titleLower -match 'feature update')
            )
        )
        if (-not $isWin11Feature) { continue }

        # Prefer explicit 25H2 titles; accept first generic Win11 feature update only if none targeted yet
        if ($isTargeted -or $updateColl.Count -eq 0) {
            if ($isTargeted -and $updateColl.Count -gt 0 -and -not ($foundTitles[0] -match '25h2')) {
                # Rebuild coll with targeted update only
                $updateColl = New-Object -ComObject Microsoft.Update.UpdateColl
                $foundTitles.Clear()
            }
            if ($isTargeted -or $updateColl.Count -eq 0) {
                [void]$updateColl.Add($update)
                [void]$foundTitles.Add($title)
            }
        }
    }

    if ($updateColl.Count -eq 0) {
        Write-Host "  No matching Windows 11 $targetDisplayVersion feature update is currently offered by Windows Update"
        return $false
    }

    Write-Host "  Found $($updateColl.Count) update(s):"
    foreach ($t in $foundTitles) {
        Write-Host "    - $t"
    }

    Write-Section -Tag 'RUN' -Title 'WINDOWS UPDATE DOWNLOAD'
    try {
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updateColl
        $downloadResult = $downloader.Download()
        Write-Host "  Download result code : $($downloadResult.ResultCode)"
        # 2 = Succeeded (OperationResultCode)
        if ([int]$downloadResult.ResultCode -ne 2) {
            Write-Host "  Download did not fully succeed — falling back"
            return $false
        }
    } catch {
        Write-Host "  Download failed: $($_.Exception.Message)"
        return $false
    }

    Write-Section -Tag 'RUN' -Title 'WINDOWS UPDATE INSTALL'
    try {
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updateColl
        $installResult = $installer.Install()
        Write-Host "  Install result code  : $($installResult.ResultCode)"
        Write-Host "  Reboot required      : $($installResult.RebootRequired)"
        if ([int]$installResult.ResultCode -eq 2 -or [int]$installResult.ResultCode -eq 3) {
            # 2 Succeeded, 3 SucceededWithErrors
            return $true
        }
        Write-Host "  Install did not succeed — falling back"
        return $false
    } catch {
        Write-Host "  Install failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-ViaInstallationAssistant {
    Write-Section -Tag 'RUN' -Title 'INSTALLATION ASSISTANT'
    try {
        Write-Host "  Downloading Windows 11 Installation Assistant..."
        Write-Host "  URL         : $installationAssistantUrl"
        Write-Host "  Destination : $iaPath"
        Invoke-WebRequest -Uri $installationAssistantUrl -OutFile $iaPath -UseBasicParsing
        if (-not (Test-Path -Path $iaPath -PathType Leaf)) {
            throw 'Installation Assistant was not downloaded'
        }
        $fileSizeMb = [math]::Round((Get-Item -Path $iaPath).Length / 1MB, 2)
        Write-Host "  File Size   : $fileSizeMb MB"
        Write-Host "  Download completed"
    } catch {
        Write-FailAndExit -Lines @(
            'Failed to download Windows 11 Installation Assistant'
            "URL   : $installationAssistantUrl"
            "Error : $($_.Exception.Message)"
        )
    }

    try {
        # Community/Microsoft-assisted silent flags for unattended upgrade
        $iaArgs = @('/QuietInstall', '/SkipEULA', '/NoRestartUI')
        Write-Host "  Launching Installation Assistant silently..."
        Write-Host "  Args : $($iaArgs -join ' ')"
        Write-Host "  Note : Full upgrade can take a long time; device may reboot"
        $process = Start-Process -FilePath $iaPath -ArgumentList $iaArgs -Wait -PassThru -NoNewWindow
        Write-Host "  Exit code : $($process.ExitCode)"
        # IA often returns 0 on successful handoff/start; non-zero is failure
        if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
            throw "Installation Assistant failed with exit code $($process.ExitCode)"
        }
        Write-Host "  Installation Assistant completed (or handed off upgrade)"
    } catch {
        if (Test-Path -Path $iaPath -PathType Leaf) {
            Remove-Item -Path $iaPath -Force -ErrorAction SilentlyContinue
        }
        Write-FailAndExit -Lines @(
            'Windows 11 Installation Assistant failed'
            "Error : $($_.Exception.Message)"
            'Device must meet Windows 11 hardware requirements'
            'Check SetupDiag / Windows Update history if this persists'
        )
    }

    Write-Section -Tag 'RUN' -Title 'CLEANUP'
    Remove-Item -Path $iaPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $iaPath -PathType Leaf) {
        Write-Host "  [WARN] Could not remove IA binary: $iaPath"
    } else {
        Write-Host "  Cleanup completed"
    }

    return @{
        InstallExitCode = 0
        RebootRequired  = $true
        Method          = 'installation_assistant'
        SelectedArch    = ''
    }
}

function Install-FullFeatureUpgrade {
    if ($preferWindowsUpdate) {
        $wuOk = Install-FeatureUpdateViaWindowsUpdate
        if ($wuOk) {
            return @{
                InstallExitCode = 0
                RebootRequired  = $true
                Method          = 'windows_update_feature'
                SelectedArch    = ''
            }
        }
        Write-Host "  Falling back to Windows 11 Installation Assistant..."
    }

    return Install-ViaInstallationAssistant
}

function Invoke-ScheduledReboot {
    param(
        [string]$Message,
        [int]$DelaySeconds = 60
    )

    Write-Section -Tag 'RUN' -Title 'REBOOT'
    try {
        Write-Host "  Scheduling restart in $DelaySeconds seconds..."
        Write-Host "  Message : $Message"
        $shutdownProc = Start-Process -FilePath 'shutdown.exe' `
            -ArgumentList "/r /t $DelaySeconds /c `"$Message`" /d p:2:4" `
            -Wait -PassThru -NoNewWindow
        if ($null -ne $shutdownProc -and $shutdownProc.ExitCode -ne 0) {
            throw "shutdown.exe returned exit code $($shutdownProc.ExitCode)"
        }
        Write-Host "  Restart scheduled successfully"
        return $true
    } catch {
        Write-Host "  [WARN] Reboot scheduling failed: $($_.Exception.Message)"
        Write-Host "  Restart the device manually to finish the upgrade"
        return $false
    }
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'INPUT VALIDATION'

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($downloadUrlX64)) {
    $errorOccurred = $true
    $errorText += "- Download URL (x64) is required`n"
}
if ($minUbr -isnot [int] -and $minUbr -isnot [long]) {
    $errorOccurred = $true
    $errorText += "- Min UBR must be an integer`n"
} elseif ([int]$minUbr -lt 1) {
    $errorOccurred = $true
    $errorText += "- Min UBR must be a positive integer`n"
}
if ([string]::IsNullOrWhiteSpace($requiredBuild)) {
    $errorOccurred = $true
    $errorText += "- Required Build is required`n"
}
if ([string]::IsNullOrWhiteSpace($targetDisplayVersion)) {
    $errorOccurred = $true
    $errorText += "- Target Display Version is required`n"
}
if ([string]::IsNullOrWhiteSpace($sourceDisplayVersion)) {
    $errorOccurred = $true
    $errorText += "- Source Display Version is required`n"
}
if ([string]::IsNullOrWhiteSpace($installationAssistantUrl)) {
    $errorOccurred = $true
    $errorText += "- Installation Assistant URL is required`n"
}
if ($preferWindowsUpdate -isnot [bool]) {
    $errorOccurred = $true
    $errorText += "- Prefer Windows Update must be a boolean`n"
}
if ($rebootAfterInstall -isnot [bool]) {
    $errorOccurred = $true
    $errorText += "- Reboot After Install must be a boolean`n"
}

if ($errorOccurred) {
    Write-FailAndExit -Lines @($errorText.TrimEnd().Split("`n"))
}

$arm64Display = if ([string]::IsNullOrWhiteSpace($downloadUrlArm64)) { '(empty)' } else { $downloadUrlArm64 }
Write-Host "  Download URL (x64)   : $downloadUrlX64"
Write-Host "  Download URL (ARM64) : $arm64Display"
Write-Host "  Min UBR              : $minUbr"
Write-Host "  Required Build       : $requiredBuild"
Write-Host "  eKB Source Version   : $sourceDisplayVersion"
Write-Host "  Target Version       : $targetDisplayVersion"
Write-Host "  Prefer Windows Update: $preferWindowsUpdate"
Write-Host "  Installation Assistant: $installationAssistantUrl"
Write-Host "  Reboot After Install : $rebootAfterInstall"
Write-Host "  Inputs validated successfully"

# ==============================================================================
# OS DETECTION
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'OS DETECTION'

try {
    $osInfo = Get-WindowsVersionInfo
} catch {
    Write-FailAndExit -Lines @(
        'Failed to read Windows version information'
        "Path  : $ntCurrentVersionPath"
        "Error : $($_.Exception.Message)"
    )
}

Write-Host "  Product Name    : $($osInfo.ProductName)"
if (-not [string]::IsNullOrWhiteSpace($osInfo.Caption)) {
    Write-Host "  Caption         : $($osInfo.Caption)"
}
Write-Host "  Family          : $($osInfo.Family)"
Write-Host "  Display Version : $($osInfo.DisplayVersion)"
Write-Host "  Build           : $($osInfo.Build)"
Write-Host "  UBR             : $($osInfo.Ubr)"
Write-Host "  Architecture    : $($osInfo.Architecture)"

# ==============================================================================
# PATH SELECTION
# ==============================================================================

Write-Section -Tag 'INFO' -Title 'UPGRADE PATH'
$path = Get-UpgradePath -OsInfo $osInfo
Write-Host "  Selected Path   : $($path.Name)"
Write-Host "  Reason          : $($path.Reason)"
Write-Host "  Source → Target : $($osInfo.Family) $($osInfo.DisplayVersion) (build $($osInfo.Build).$($osInfo.Ubr)) → Windows 11 $targetDisplayVersion"

$result = $null

switch ($path.Name) {
    'already_target' {
        Write-Section -Tag 'OK' -Title 'FINAL STATUS'
        Write-Host "  Result           : SUCCESS"
        Write-Host "  Display Version  : $($osInfo.DisplayVersion)"
        Write-Host "  Build.UBR        : $($osInfo.Build).$($osInfo.Ubr)"
        Write-Host "  Note             : Already on Windows 11 $targetDisplayVersion — no action needed"
        Write-Section -Tag 'OK' -Title 'SCRIPT COMPLETED'
        exit 0
    }
    'enablement_needs_cu' {
        Write-FailAndExit -Lines @(
            'Enablement package prerequisite not met'
            "Required : Windows 11 $sourceDisplayVersion build $requiredBuild UBR $minUbr+ (KB5064081 or later CU)"
            "Current  : build $($osInfo.Build) UBR $($osInfo.Ubr)"
            'Install the latest Windows 11 cumulative update for 24H2, then re-run this script'
            'Microsoft: KB5054156 requires 24H2 + KB5064081 (26100.5074) or later'
        )
    }
    'unsupported' {
        Write-FailAndExit -Lines @(
            $path.Reason
            'This script supports Windows 10 and Windows 11 only'
        )
    }
    'enablement_ekb' {
        $result = Install-EnablementPackage -OsInfo $osInfo
    }
    'full_feature_upgrade' {
        $result = Install-FullFeatureUpgrade
    }
    default {
        Write-FailAndExit -Lines @("Unknown upgrade path: $($path.Name)")
    }
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

$rebootRequired = $false
if ($null -ne $result -and $result.ContainsKey('RebootRequired') -and $result.RebootRequired) {
    $rebootRequired = $true
}
if (-not $rebootRequired) {
    $rebootRequired = Test-RebootPending
}

# Default true: upgrade does not finish until restart (eKB activation; WU feature install)
if ($rebootAfterInstall -and $null -ne $result) {
    $rebootMsg = "Windows 11 $targetDisplayVersion upgrade applied (path: $($path.Name)). Restarting to complete."
    if (Invoke-ScheduledReboot -Message $rebootMsg -DelaySeconds 60) {
        $rebootRequired = $true
    } else {
        $rebootRequired = $true
    }
}

Write-Section -Tag 'OK' -Title 'FINAL STATUS'
Write-Host "  Result           : SUCCESS"
Write-Host "  Path             : $($path.Name)"
if ($null -ne $result -and $result.ContainsKey('Method') -and -not [string]::IsNullOrWhiteSpace([string]$result.Method)) {
    Write-Host "  Method           : $($result.Method)"
}
Write-Host "  Display Version  : $($finalInfo.DisplayVersion)"
Write-Host "  Build.UBR        : $($finalInfo.Build).$($finalInfo.Ubr)"
Write-Host "  Family           : $($finalInfo.Family)"
if ($null -ne $result -and $result.ContainsKey('InstallExitCode')) {
    Write-Host "  Install Exit     : $($result.InstallExitCode)"
}
Write-Host "  Reboot Pending   : $rebootRequired"
if ($finalInfo.DisplayVersion -ne $targetDisplayVersion) {
    Write-Host "  Note             : DisplayVersion may still show pre-upgrade until reboot / setup finishes"
    Write-Host "  Note             : Restart required to complete Windows 11 $targetDisplayVersion"
} else {
    Write-Host "  Note             : DisplayVersion already reports $targetDisplayVersion"
}

Write-Section -Tag 'OK' -Title 'SCRIPT COMPLETED'
exit 0
