$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Remove Easy2Convert                                           v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : October 2026
 USAGE    : .\rem-easy2convert.ps1
================================================================================
 FILE     : rem-easy2convert.ps1
 DESCRIPTION : Removes Easy2Convert adware files, tasks, services and registry entries from the machine and every user profile
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Adware bundled with a file-converter installer. This script removes it from
   the machine and from every user profile, including users who are signed out.

 DATA SOURCES & PRIORITY

   - Hardcoded indicator lists in this script
   - ProfileList registry key for user profile folders and SIDs

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $ThreatName: Display name used in output. Default: Easy2Convert
     - $ProcessNames: Process names to stop, without .exe. * allowed
     - $ServiceNames: Service names to stop and delete. * allowed
     - $TaskNames: Scheduled task names to unregister, in any task folder. *
       allowed
     - $MachinePaths: Absolute files or folders to delete. * allowed
     - $MachineRegistryKeys: HKLM\SOFTWARE or HKLM\SYSTEM keys to delete. *
       allowed
     - $MachineRegistryValues: HKLM values to delete, written as Key|ValueName.
       * allowed in the value name
     - $UserPaths: Files or folders to delete, relative to each profile folder.
       * allowed
     - $UserDownloadPatterns: Installer file names to delete from each Downloads
       folder, searched recursively
     - $UserRegistryKeys: Keys to delete under each user hive, starting with
       Software\. * allowed
     - $UserRegistryValues: Values to delete under each user hive, written as
       Key|ValueName

 SETTINGS

   - Profiles: every S-1-5-21 profile listed under ProfileList
   - Signed-out users: NTUSER.DAT is loaded at HKU\Limehawk_<SID> and unloaded
     when done
   - Processes running from the Windows folder are never stopped
   - Each entry must keep 3 or more literal characters in its last segment, not
     counting the extension, so a stray * cannot widen a delete
   - Indicator counts: ProcessNames 1, ServiceNames 0, TaskNames 1, MachinePaths
     0, MachineRegistryKeys 0, MachineRegistryValues 0, UserPaths 1,
     UserDownloadPatterns 1, UserRegistryKeys 1, UserRegistryValues 0

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates every indicator entry and exits 1 if any is blank, too shallow
      or too broad
   2. Stops matching processes
   3. Stops and deletes matching services
   4. Unregisters matching scheduled tasks and deletes leftover task files
   5. Deletes machine-wide files, folders, registry keys and values
   6. For each user profile, deletes profile files, Downloads installers, user
      registry keys and values
   7. Confirms each file, registry and task delete and counts anything still
      present as a failure. Services count as removed when sc.exe reports
      success
   8. Exits 1 if anything could not be removed, otherwise exits 0

 PREREQUISITES

   - PowerShell 5.1 or later
   - Windows
   - Administrator privileges or SYSTEM

 SECURITY NOTES

   - No secrets in logs
   - Deletes files and registry entries without a backup
   - Matches processes, services and tasks by name only

 ENDPOINTS

   - Not applicable. This script performs local actions only.

 EXIT CODES

   0 = Success (removed, or nothing found)
   1 = Failure (input validation failed or an item could not be removed)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Threat : Easy2Convert
   Indicators : 5

   [RUN] STOP PROCESSES
   ==============================================================
   [OK] Stopped : Easy2Convert (4120)
   Stopped : 1

   [RUN] CLEAN USER PROFILES
   ==============================================================
   Profiles : 2
   Profile : C:\Users\jsmith
   [OK] Removed : Path C:\Users\jsmith\AppData\Local\Easy2Convert
   Profile : C:\Users\alee

   [INFO] RESULT
   ==============================================================
   Removed : 1
   Failed : 0
   Warnings : 0

   [OK] FINAL STATUS
   ==============================================================
   Easy2Convert removed

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-10-29 v1.0.0 Initial release
================================================================================
#>

# ==== HARDCODED INPUTS ====
$ThreatName            = 'Easy2Convert'
$ProcessNames          = @(
    'Easy2Convert'
)
$ServiceNames          = @()
$TaskNames             = @(
    '*Easy2ConvertTask*'
)
$MachinePaths          = @()
$MachineRegistryKeys   = @()
$MachineRegistryValues = @()
$UserPaths             = @(
    'AppData\Local\Easy2Convert'
)
$UserDownloadPatterns  = @(
    'Easy2Convert*.exe'
)
$UserRegistryKeys      = @(
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\Easy2Convert'
)
$UserRegistryValues    = @()

Set-StrictMode -Version Latest

function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info' = 'INFO'; 'run' = 'RUN'; 'ok' = 'OK'; 'warn' = 'WARN'; 'error' = 'ERROR' }
    $label = $indicators[$Type]
    Write-Host ''
    Write-Host "[$label] $Name"
    Write-Host ('=' * 62)
}

function Write-KV {
    param([string]$Label, [string]$Value)
    Write-Host ("{0} : {1}" -f $Label, $Value)
}

# Returns an error line when a pattern is too short or too broad to delete safely.
function Test-Pattern {
    param([string]$Kind, [string]$Pattern, [int]$MinSegments, [string]$RequiredPrefix)
    if ([string]::IsNullOrWhiteSpace($Pattern)) { return "- $Kind entry is blank" }
    if ($Pattern -match '\.\.') { return "- $Kind entry must not contain '..' : $Pattern" }
    if ($RequiredPrefix -and $Pattern -notmatch $RequiredPrefix) { return "- $Kind entry has the wrong root : $Pattern" }
    $segments = @($Pattern.TrimEnd('\') -split '\\' | Where-Object { $_ -ne '' })
    if ($segments.Count -lt $MinSegments) { return "- $Kind entry is too shallow : $Pattern" }
    # The file extension does not count, so *.exe is as broad as *.
    $leaf = ($segments[-1] -split '\|')[-1] -replace '\.[^.]*$', '' -replace '[\*\?]', ''
    if ($leaf.Length -lt 3) { return "- $Kind entry leaf needs 3 or more literal characters before any extension : $Pattern" }
    return ''
}

function Convert-RegistryPath {
    param([string]$Path)
    return 'Registry::' + ($Path -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKU\\', 'HKEY_USERS\')
}

# Deletes one resolved item and confirms it is gone.
function Remove-Target {
    param([string]$Label, [string]$LiteralPath, [string]$Display)
    try {
        Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host "[WARN] $($_.Exception.Message)"
    }
    if (Test-Path -LiteralPath $LiteralPath) {
        $script:failureCount++
        Write-Host "[ERROR] Not removed : $Label $Display"
    }
    else {
        $script:removedCount++
        Write-Host "[OK] Removed : $Label $Display"
    }
}

function Remove-PathPattern {
    param([string]$Label, [string]$Pattern)
    foreach ($item in @(Get-Item -Path $Pattern -Force -ErrorAction SilentlyContinue)) {
        Remove-Target -Label $Label -LiteralPath $item.PSPath -Display $item.FullName
    }
}

function Remove-RegistryKeyPattern {
    param([string]$Pattern)
    foreach ($key in @(Get-Item -Path $Pattern -Force -ErrorAction SilentlyContinue)) {
        Remove-Target -Label 'Key' -LiteralPath $key.PSPath -Display $key.Name
    }
}

# Entry format is 'Key|ValueName'. ValueName may use * wildcards.
function Remove-RegistryValuePattern {
    param([string]$Root, [string]$Entry)
    $keyPart, $valuePattern = $Entry -split '\|', 2
    $keyPath = Convert-RegistryPath -Path $(if ($Root) { "$Root\$keyPart" } else { $keyPart })
    foreach ($key in @(Get-Item -Path $keyPath -Force -ErrorAction SilentlyContinue)) {
        foreach ($valueName in @($key.GetValueNames() | Where-Object { $_ -like $valuePattern })) {
            try {
                Remove-ItemProperty -LiteralPath $key.PSPath -Name $valueName -Force -ErrorAction Stop
            }
            catch {
                Write-Host "[WARN] $($_.Exception.Message)"
            }
            if (@((Get-Item -LiteralPath $key.PSPath).GetValueNames()) -contains $valueName) {
                $script:failureCount++
                Write-Host "[ERROR] Not removed : Value $($key.Name)\$valueName"
            }
            else {
                $script:removedCount++
                Write-Host "[OK] Removed : Value $($key.Name)\$valueName"
            }
        }
    }
}

# Runs a console tool without letting its stderr trip ErrorActionPreference.
function Invoke-Tool {
    param([string]$FilePath, [string]$Arguments)
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}

$errorOccurred = $false
$errorText = ''
$removedCount = 0
$failureCount = 0
$warningCount = 0
$indicatorCount = $ProcessNames.Count + $ServiceNames.Count + $TaskNames.Count + $MachinePaths.Count +
    $MachineRegistryKeys.Count + $MachineRegistryValues.Count + $UserPaths.Count + $UserDownloadPatterns.Count +
    $UserRegistryKeys.Count + $UserRegistryValues.Count

if ([string]::IsNullOrWhiteSpace($ThreatName)) {
    $errorOccurred = $true
    $errorText += "- Threat name is required`n"
}
if ($indicatorCount -lt 1) {
    $errorOccurred = $true
    $errorText += "- At least one indicator is required`n"
}
function Add-ValidationError {
    param([string]$Line)
    if ($Line) {
        $script:errorOccurred = $true
        $script:errorText += "$Line`n"
    }
}

foreach ($p in $ProcessNames) { Add-ValidationError (Test-Pattern -Kind 'Process' -Pattern $p -MinSegments 1) }
foreach ($p in $ServiceNames) { Add-ValidationError (Test-Pattern -Kind 'Service' -Pattern $p -MinSegments 1) }
foreach ($p in $TaskNames) { Add-ValidationError (Test-Pattern -Kind 'Task' -Pattern $p -MinSegments 1) }
foreach ($p in $MachinePaths) {
    Add-ValidationError (Test-Pattern -Kind 'Machine path' -Pattern $p -MinSegments 3 -RequiredPrefix '^[A-Za-z]:\\')
    $depth = @($p -split '\\' | Where-Object { $_ -ne '' }).Count
    if (($p -match '^[A-Za-z]:\\Windows\\' -and $depth -lt 6) -or ($p -match '^[A-Za-z]:\\Users\\' -and $depth -lt 4)) {
        Add-ValidationError "- Machine path is too close to a system or profile folder : $p"
    }
}
foreach ($p in $MachineRegistryKeys) { Add-ValidationError (Test-Pattern -Kind 'Machine key' -Pattern $p -MinSegments 3 -RequiredPrefix '^HKLM\\(SOFTWARE|SYSTEM)\\') }
foreach ($p in $MachineRegistryValues) { Add-ValidationError (Test-Pattern -Kind 'Machine value' -Pattern $p -MinSegments 3 -RequiredPrefix '^HKLM\\SOFTWARE\\[^|]+\|.+') }
foreach ($p in $UserPaths) {
    Add-ValidationError (Test-Pattern -Kind 'User path' -Pattern $p -MinSegments 1 -RequiredPrefix '^[^\\:][^:]*$')
    if ($p.TrimEnd('\') -match '^(AppData(\\(Local|LocalLow|Roaming))?|Desktop|Documents|Downloads|Favorites|Music|Pictures|Videos|OneDrive[^\\]*|NTUSER\.DAT.*)$') {
        Add-ValidationError "- User path is a standard profile folder : $p"
    }
}
foreach ($p in $UserDownloadPatterns) { Add-ValidationError (Test-Pattern -Kind 'Download pattern' -Pattern $p -MinSegments 1 -RequiredPrefix '^[^\\:]+$') }
foreach ($p in $UserRegistryKeys) { Add-ValidationError (Test-Pattern -Kind 'User key' -Pattern $p -MinSegments 2 -RequiredPrefix '^Software\\') }
foreach ($p in $UserRegistryValues) { Add-ValidationError (Test-Pattern -Kind 'User value' -Pattern $p -MinSegments 2 -RequiredPrefix '^Software\\[^|]+\|.+') }

if ($errorOccurred) {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host $errorText.TrimEnd()
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host 'Input validation failed'
    Write-Section -Type 'error' -Name 'SCRIPT COMPLETED'
    exit 1
}

Write-Section -Type 'info' -Name 'INPUT VALIDATION'
Write-KV -Label 'Threat' -Value $ThreatName
Write-KV -Label 'Indicators' -Value ([string]$indicatorCount)

$step = 'Stop processes'
try {
    Write-Section -Type 'run' -Name 'STOP PROCESSES'
    $windowsDir = $env:SystemRoot.TrimEnd('\') + '\'
    $stopped = 0
    foreach ($name in $ProcessNames) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $processPath = ''
            try { $processPath = [string]$process.Path } catch { $processPath = '' }
            if ($processPath -and $processPath.StartsWith($windowsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $warningCount++
                Write-Host "[WARN] Skipped Windows process : $($process.ProcessName) ($processPath)"
                continue
            }
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $stopped++
                Write-Host "[OK] Stopped : $($process.ProcessName) ($($process.Id))"
            }
            catch {
                $warningCount++
                Write-Host "[WARN] Could not stop $($process.ProcessName) : $($_.Exception.Message)"
            }
        }
    }
    Write-KV -Label 'Stopped' -Value ([string]$stopped)
    if ($stopped -gt 0) { Start-Sleep -Seconds 2 }

    $step = 'Remove services'
    if ($ServiceNames.Count -gt 0) {
        Write-Section -Type 'run' -Name 'REMOVE SERVICES'
        foreach ($name in $ServiceNames) {
            foreach ($service in @(Get-Service -Name $name -ErrorAction SilentlyContinue)) {
                Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                $exitCode = Invoke-Tool -FilePath 'sc.exe' -Arguments "delete `"$($service.Name)`""
                # 1072 means the service is already marked for deletion at the next reboot.
                if ($exitCode -eq 0 -or $exitCode -eq 1072) {
                    $removedCount++
                    Write-Host "[OK] Removed : Service $($service.Name)"
                }
                else {
                    $failureCount++
                    Write-Host "[ERROR] Not removed : Service $($service.Name) (sc.exe exit $exitCode)"
                }
            }
        }
    }

    $step = 'Remove scheduled tasks'
    if ($TaskNames.Count -gt 0) {
        Write-Section -Type 'run' -Name 'REMOVE SCHEDULED TASKS'
        $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
        $taskFolder = Join-Path $env:SystemRoot 'System32\Tasks'
        foreach ($pattern in $TaskNames) {
            foreach ($task in @($allTasks | Where-Object { $_.TaskName -like $pattern })) {
                $display = "$($task.TaskPath)$($task.TaskName)"
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                }
                catch {
                    Write-Host "[WARN] $($_.Exception.Message)"
                }
                if (Get-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue) {
                    $failureCount++
                    Write-Host "[ERROR] Not removed : Task $display"
                }
                else {
                    $removedCount++
                    Write-Host "[OK] Removed : Task $display"
                }
            }
            # Task files left behind when an earlier cleanup deleted only the registry side.
            Remove-PathPattern -Label 'Task file' -Pattern (Join-Path $taskFolder $pattern)
        }
    }

    $step = 'Remove machine files'
    if ($MachinePaths.Count -gt 0) {
        Write-Section -Type 'run' -Name 'REMOVE MACHINE FILES'
        foreach ($pattern in $MachinePaths) {
            Remove-PathPattern -Label 'Path' -Pattern $pattern
        }
    }

    $step = 'Remove machine registry'
    if ($MachineRegistryKeys.Count + $MachineRegistryValues.Count -gt 0) {
        Write-Section -Type 'run' -Name 'REMOVE MACHINE REGISTRY'
        foreach ($pattern in $MachineRegistryKeys) {
            Remove-RegistryKeyPattern -Pattern (Convert-RegistryPath -Path $pattern)
        }
        foreach ($entry in $MachineRegistryValues) {
            Remove-RegistryValuePattern -Root '' -Entry $entry
        }
    }

    $step = 'Clean user profiles'
    $userWork = $UserPaths.Count + $UserDownloadPatterns.Count + $UserRegistryKeys.Count + $UserRegistryValues.Count
    if ($userWork -gt 0) {
        Write-Section -Type 'run' -Name 'CLEAN USER PROFILES'
        $profileList = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        # A .bak suffix marks a stale duplicate of a profile key, so match whole SIDs only.
        $profiles = @(Get-ChildItem -LiteralPath $profileList | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' })
        Write-KV -Label 'Profiles' -Value ([string]$profiles.Count)

        foreach ($profileKey in $profiles) {
            $sid = $profileKey.PSChildName
            $profileProps = Get-ItemProperty -LiteralPath $profileKey.PSPath
            if ($profileProps.PSObject.Properties.Name -notcontains 'ProfileImagePath') {
                continue
            }
            $profilePath = [Environment]::ExpandEnvironmentVariables([string]$profileProps.ProfileImagePath)
            if (-not $profilePath -or -not (Test-Path -LiteralPath $profilePath)) {
                continue
            }
            Write-KV -Label 'Profile' -Value $profilePath

            foreach ($relative in $UserPaths) {
                Remove-PathPattern -Label 'Path' -Pattern (Join-Path $profilePath $relative)
            }

            $downloads = Join-Path $profilePath 'Downloads'
            if ($UserDownloadPatterns.Count -gt 0 -and (Test-Path -LiteralPath $downloads)) {
                foreach ($pattern in $UserDownloadPatterns) {
                    foreach ($file in @(Get-ChildItem -LiteralPath $downloads -Filter $pattern -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                        Remove-Target -Label 'Download' -LiteralPath $file.FullName -Display $file.FullName
                    }
                }
            }

            if ($UserRegistryKeys.Count + $UserRegistryValues.Count -eq 0) {
                continue
            }

            # Signed-out users have no hive under HKU, so mount NTUSER.DAT while we work.
            $hiveRoot = "HKU\$sid"
            $mounted = $false
            if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid")) {
                $hiveFile = Join-Path $profilePath 'NTUSER.DAT'
                if (-not (Test-Path -LiteralPath $hiveFile)) {
                    continue
                }
                $hiveRoot = "HKU\Limehawk_$sid"
                $exitCode = Invoke-Tool -FilePath 'reg.exe' -Arguments "load `"$hiveRoot`" `"$hiveFile`""
                if ($exitCode -ne 0) {
                    $warningCount++
                    Write-Host "[WARN] Could not load hive : $hiveFile (reg.exe exit $exitCode)"
                    continue
                }
                $mounted = $true
            }

            try {
                foreach ($relative in $UserRegistryKeys) {
                    Remove-RegistryKeyPattern -Pattern (Convert-RegistryPath -Path "$hiveRoot\$relative")
                }
                foreach ($entry in $UserRegistryValues) {
                    Remove-RegistryValuePattern -Root $hiveRoot -Entry $entry
                }
            }
            finally {
                if ($mounted) {
                    [GC]::Collect()
                    [GC]::WaitForPendingFinalizers()
                    $exitCode = Invoke-Tool -FilePath 'reg.exe' -Arguments "unload `"$hiveRoot`""
                    if ($exitCode -ne 0) {
                        $warningCount++
                        Write-Host "[WARN] Could not unload hive : $hiveRoot (reg.exe exit $exitCode)"
                    }
                }
            }
        }
    }
}
catch {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-KV -Label 'Step' -Value $step
    Write-KV -Label 'Error Type' -Value $_.Exception.GetType().Name
    Write-KV -Label 'Error Message' -Value $_.Exception.Message
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "$ThreatName removal stopped before it finished"
    Write-Section -Type 'error' -Name 'SCRIPT COMPLETED'
    exit 1
}

Write-Section -Type 'info' -Name 'RESULT'
Write-KV -Label 'Removed' -Value ([string]$removedCount)
Write-KV -Label 'Failed' -Value ([string]$failureCount)
Write-KV -Label 'Warnings' -Value ([string]$warningCount)

if ($failureCount -gt 0) {
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "$failureCount $ThreatName item(s) could not be removed"
    Write-Section -Type 'error' -Name 'SCRIPT COMPLETED'
    exit 1
}

Write-Section -Type 'ok' -Name 'FINAL STATUS'
if ($removedCount -gt 0) {
    Write-Host "$ThreatName removed"
}
else {
    Write-Host "No $ThreatName indicators found"
}
Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
exit 0
