$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : NinjaOne Uninstall                                             v1.0.0
FILE   : ninjaone_uninstall.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Completely removes NinjaOne RMM agent and Ninja Remote from a Windows
    system. Includes disabling uninstall prevention, removing services,
    cleaning up registry entries, and removing the virtual display driver.

REQUIRED INPUTS:
    None - script auto-detects NinjaOne installation

BEHAVIOR:
    1. Checks for administrator privileges
    2. Locates NinjaOne installation path
    3. Disables uninstall prevention
    4. Runs MSI uninstaller silently
    5. Stops and removes NinjaOne services
    6. Kills running processes
    7. Removes installation directories
    8. Cleans up registry entries
    9. Removes Ninja Remote components
    10. Removes virtual display driver

PREREQUISITES:
    - Windows OS
    - Administrator privileges

SECURITY NOTES:
    - No secrets in logs
    - Creates transcript log in Windows\temp

EXIT CODES:
    0 = Success (or partial success with warnings)
    1 = Failure (requires admin privileges)

EXAMPLE RUN:
    [ SETUP ]
    --------------------------------------------------------------
    Transcript logging started
    Log Path : C:\Windows\temp\NinjaRemoval_01-12-2024_143022.txt

    [ LOCATE INSTALLATION ]
    --------------------------------------------------------------
    Registry Path : HKLM:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent
    Install Location : C:\Program Files\NinjaRMMAgent

    [ UNINSTALL AGENT ]
    --------------------------------------------------------------
    Disabling uninstall prevention...
    Running MSI uninstaller...
    Finished running uninstaller

    [ STOP SERVICES ]
    --------------------------------------------------------------
    Stopping NinjaRMMAgent service...
    Stopping nmsmanager service...
    Removing services...

    [ CLEANUP FILES ]
    --------------------------------------------------------------
    Removing installation directory...
    Removing data directory...

    [ CLEANUP REGISTRY ]
    --------------------------------------------------------------
    Removing registry entries...

    [ REMOVE NINJA REMOTE ]
    --------------------------------------------------------------
    Stopping Ninja Remote process...
    Removing Ninja Remote service...
    Removing virtual display driver...
    Removing Ninja Remote directory...

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    NinjaOne removal completed

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# ADMIN CHECK
# ============================================================================
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not ($currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "This script must be run with administrator privileges"
    exit 1
}

# ============================================================================
# SETUP
# ============================================================================
Write-Host ""
Write-Host "[ SETUP ]"
Write-Host "--------------------------------------------------------------"

$now = Get-Date -Format 'dd-MM-yyyy_HHmmss'
$logPath = "$env:windir\temp\NinjaRemoval_$now.txt"
Start-Transcript -Path $logPath -Force | Out-Null

Write-Host "Transcript logging started"
Write-Host "Log Path : $logPath"

$ErrorActionPreference = 'SilentlyContinue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Uninstall-NinjaMSI {
    param([string]$UninstallString, [string]$InstallLocation)

    $arguments = @(
        "/x$UninstallString"
        '/quiet'
        '/L*V'
        'C:\windows\temp\NinjaRMMAgent_uninstall.log'
        "WRAPPED_ARGUMENTS=`"--mode unattended`""
    )

    Write-Host "Disabling uninstall prevention..."
    Start-Process "$InstallLocation\NinjaRMMAgent.exe" -ArgumentList "-disableUninstallPrevention NOUI" -Wait -ErrorAction SilentlyContinue
    Start-Sleep 10

    Write-Host "Running MSI uninstaller..."
    Start-Process "msiexec.exe" -ArgumentList $arguments -Wait -NoNewWindow -ErrorAction SilentlyContinue
    Write-Host "Finished running uninstaller"
    Start-Sleep 30
}

# ============================================================================
# LOCATE INSTALLATION
# ============================================================================
Write-Host ""
Write-Host "[ LOCATE INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

$ninjaRegPath = 'HKLM:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent'
$ninjaDataDirectory = "$env:ProgramData\NinjaRMMAgent"
$uninstallRegPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'

if (-not ([System.Environment]::Is64BitOperatingSystem)) {
    $ninjaRegPath = 'HKLM:\SOFTWARE\NinjaRMM LLC\NinjaRMMAgent'
    $uninstallRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
}

Write-Host "Registry Path : $ninjaRegPath"

$ninjaInstallLocation = $null
try {
    $ninjaInstallLocation = (Get-ItemPropertyValue $ninjaRegPath -Name Location -ErrorAction Stop).Replace('/', '\')
} catch {
    $ninjaServicePath = ((Get-Service | Where-Object { $_.Name -eq 'NinjaRMMAgent' }).BinaryPathName).Trim('"')
    if (Test-Path $ninjaServicePath) {
        $ninjaInstallLocation = $ninjaServicePath | Split-Path
    }
}

if ($ninjaInstallLocation) {
    Write-Host "Install Location : $ninjaInstallLocation"
} else {
    Write-Host "Unable to locate Ninja installation path"
}

# ============================================================================
# UNINSTALL AGENT
# ============================================================================
Write-Host ""
Write-Host "[ UNINSTALL AGENT ]"
Write-Host "--------------------------------------------------------------"

$uninstallString = (Get-ItemProperty $uninstallRegPath -ErrorAction SilentlyContinue | Where-Object { ($_.DisplayName -eq 'NinjaRMMAgent') -and ($_.UninstallString -match 'msiexec') }).UninstallString

if ($uninstallString -and $ninjaInstallLocation) {
    $uninstallString = $uninstallString.Split('X')[1]
    Uninstall-NinjaMSI -UninstallString $uninstallString -InstallLocation $ninjaInstallLocation
} else {
    Write-Host "Unable to determine uninstall string, continuing with cleanup..."
}

# ============================================================================
# STOP SERVICES AND PROCESSES
# ============================================================================
Write-Host ""
Write-Host "[ STOP SERVICES ]"
Write-Host "--------------------------------------------------------------"

$ninjaServices = @('NinjaRMMAgent', 'nmsmanager', 'lockhart')
$processes = @("NinjaRMMAgent", "NinjaRMMAgentPatcher", "njbar", "NinjaRMMProxyProcess64")

foreach ($process in $processes) {
    $proc = Get-Process $process -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Stopping process: $process"
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

foreach ($svc in $ninjaServices) {
    $service = Get-Service $svc -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Removing service: $svc"
        & sc.exe DELETE $svc 2>&1 | Out-Null
        Start-Sleep 2
    }
}

# ============================================================================
# CLEANUP FILES
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP FILES ]"
Write-Host "--------------------------------------------------------------"

if ($ninjaInstallLocation -and (Test-Path $ninjaInstallLocation)) {
    Write-Host "Removing installation directory..."
    Remove-Item $ninjaInstallLocation -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $ninjaDataDirectory) {
    Write-Host "Removing data directory..."
    Remove-Item $ninjaDataDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# CLEANUP REGISTRY
# ============================================================================
Write-Host ""
Write-Host "[ CLEANUP REGISTRY ]"
Write-Host "--------------------------------------------------------------"

$msiWrapperReg = 'HKLM:\SOFTWARE\WOW6432Node\EXEMSI.COM\MSI Wrapper\Installed'
$productInstallerReg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products'
$hkcrInstallerReg = 'Registry::\HKEY_CLASSES_ROOT\Installer\Products'

$regKeysToRemove = [System.Collections.Generic.List[object]]::New()

(Get-ItemProperty $uninstallRegPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'NinjaRMMAgent' }).PSPath | ForEach-Object { if ($_) { $regKeysToRemove.Add($_) } }

if (Test-Path $msiWrapperReg) {
    (Get-ChildItem $msiWrapperReg -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NinjaRMMAgent' }).PSPath | ForEach-Object { if ($_) { $regKeysToRemove.Add($_) } }
}

Write-Host "Removing registry entries..."
foreach ($regKey in $regKeysToRemove) {
    if (-not [string]::IsNullOrEmpty($regKey)) {
        Remove-Item $regKey -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $ninjaRegPath) {
    Get-Item ($ninjaRegPath | Split-Path) -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# REMOVE NINJA REMOTE
# ============================================================================
Write-Host ""
Write-Host "[ REMOVE NINJA REMOTE ]"
Write-Host "--------------------------------------------------------------"

$nrProcess = 'ncstreamer'
$nrProc = Get-Process $nrProcess -ErrorAction SilentlyContinue
if ($nrProc) {
    Write-Host "Stopping Ninja Remote process..."
    $nrProc | Stop-Process -Force -ErrorAction SilentlyContinue
}

$nrService = Get-Service $nrProcess -ErrorAction SilentlyContinue
if ($nrService) {
    Write-Host "Removing Ninja Remote service..."
    Stop-Service $nrProcess -Force -ErrorAction SilentlyContinue
    & sc.exe DELETE $nrProcess 2>&1 | Out-Null
    Start-Sleep 5
}

# Remove virtual display driver
$nrDriver = 'nrvirtualdisplay.inf'
$driverCheck = pnputil /enum-drivers 2>&1 | Where-Object { $_ -match $nrDriver }
if ($driverCheck) {
    Write-Host "Removing virtual display driver..."
    $driverBreakdown = pnputil /enum-drivers | Where-Object { $_ -ne 'Microsoft PnP Utility' }

    $driversArray = [System.Collections.Generic.List[object]]::New()
    $currentDriver = @{}

    foreach ($line in $driverBreakdown) {
        if ($line -ne "") {
            $parts = $line.Split(':')
            if ($parts.Count -ge 2) {
                $objectName = $parts[0].Trim()
                $objectValue = $parts[1].Trim()
                $currentDriver[$objectName] = $objectValue
            }
        } else {
            if ($currentDriver.Count -gt 0) {
                $driversArray.Add([PSCustomObject]$currentDriver)
                $currentDriver = @{}
            }
        }
    }

    $driverToRemove = ($driversArray | Where-Object { $_.'Provider Name' -eq 'NinjaOne' }).'Published Name'
    if ($driverToRemove) {
        pnputil /delete-driver "$driverToRemove" /force 2>&1 | Out-Null
    }
}

$nrDirectory = "$env:ProgramFiles\NinjaRemote"
if (Test-Path $nrDirectory) {
    Write-Host "Removing Ninja Remote directory..."
    Remove-Item $nrDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

# Remove Ninja Remote printer
$nrPrinter = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'NinjaRemote' }
if ($nrPrinter) {
    Write-Host "Removing Ninja Remote printer..."
    Remove-Printer -InputObject $nrPrinter -ErrorAction SilentlyContinue
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "NinjaOne removal completed"
Write-Host "Review log for any warnings : $logPath"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

Stop-Transcript | Out-Null

exit 0
