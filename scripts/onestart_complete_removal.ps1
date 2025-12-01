$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT        : OneStart Complete Removal
VERSION       : 1.1.0
FILE          : onestart_complete_removal.ps1
--------------------------------------------------------------------------------
README
--------------------------------------------------------------
PURPOSE
Completely removes OneStart.ai browser/PUP from Windows systems. First attempts
a clean uninstall via NirSoft UninstallView, then performs manual cleanup of
any remaining processes, files, registry keys, and scheduled tasks.

--------------------------------------------------------------
DATA SOURCES & PRIORITY
1. NirSoft UninstallView for silent uninstall attempt
2. Windows Task Scheduler for scheduled task removal
3. File system for leftover folders
4. Windows Registry for leftover keys

--------------------------------------------------------------
REQUIRED INPUTS
- $appName : Application name for uninstall (default: OneStart)

--------------------------------------------------------------
SETTINGS
- Downloads NirSoft UninstallView if not present
- Attempts silent uninstall first
- Performs comprehensive manual cleanup after uninstall

--------------------------------------------------------------
BEHAVIOR
1. Downloads NirSoft UninstallView (architecture-appropriate)
2. Attempts silent uninstall of OneStart via UninstallView
3. Terminates any running OneStart/DBar processes
4. Removes scheduled tasks matching OneStart patterns
5. Removes leftover files and folders from AppData, ProgramData, Program Files
6. Backs up registry keys to $env:SystemDrive\limehawk\registry_backup before removal
7. Cleans up registry keys in HKCU and HKLM
8. Reports final cleanup status

--------------------------------------------------------------
PREREQUISITES
- Windows PowerShell 5.1+
- Administrative privileges required
- Internet access for UninstallView download

--------------------------------------------------------------
SECURITY NOTES
- No secrets in logs
- Only removes OneStart-related items using known paths/patterns
- Registry keys are backed up before removal for recovery if needed

--------------------------------------------------------------
ENDPOINTS
- https://www.nirsoft.net/utils/uninstallview-x64.zip
- https://www.nirsoft.net/utils/uninstallview.zip

--------------------------------------------------------------
EXIT CODES
- 0 : Success
- 1 : Failure

--------------------------------------------------------------
EXAMPLE RUN
[ INPUT VALIDATION ]
--------------------------------------------------------------
Application Name : OneStart

[ NIRSOFT UNINSTALLVIEW SETUP ]
--------------------------------------------------------------
Architecture : 64-bit
Download URL : https://www.nirsoft.net/utils/uninstallview-x64.zip
Downloading UninstallView...
Download complete
Extracting to C:\limehawk\nirsoft...
Extraction complete

[ UNINSTALL ATTEMPT ]
--------------------------------------------------------------
Searching for : OneStart
Attempting silent uninstall...
Uninstall command issued
Waiting 10 seconds for uninstall to complete...

[ PROCESS TERMINATION ]
--------------------------------------------------------------
Searching for OneStart/DBar processes...
Found process : OneStart (PID: 12345)
Terminated : OneStart
Process cleanup complete

[ SCHEDULED TASK REMOVAL ]
--------------------------------------------------------------
Searching for OneStart scheduled tasks...
Found : OneStartUpdaterTaskUser134.0.6
Removed : OneStartUpdaterTaskUser134.0.6
Removing task folders...
Task cleanup complete

[ FILE CLEANUP ]
--------------------------------------------------------------
Checking known OneStart locations...
Removed : C:\Users\User\AppData\Local\OneStart.ai
Removed : C:\Users\User\AppData\Roaming\OneStart
File cleanup complete

[ REGISTRY BACKUP ]
--------------------------------------------------------------
Creating registry backups before removal...
Backed up : HKCU:\Software\OneStart.ai
Backup location : <SystemDrive>\limehawk\registry_backup\onestart_20251201_120000
Registry backup complete

[ REGISTRY CLEANUP ]
--------------------------------------------------------------
Cleaning registry keys...
Removed : HKCU:\Software\OneStart.ai
Checking startup entries...
Registry cleanup complete

[ FINAL STATUS ]
--------------------------------------------------------------
Result : Success
Uninstall Attempted : Yes
Processes Terminated : 1
Tasks Removed : 1
Folders Removed : 2
Registry Keys Backed Up : 1
Registry Keys Removed : 1

[ SCRIPT COMPLETED ]

================================================================================
CHANGELOG
--------------------------------------------------------------
2025-12-01 v1.1.0 Add registry backup before removal to $env:SystemDrive\limehawk\registry_backup
2025-12-01 v1.0.0 Initial release - combines NirSoft uninstall with manual cleanup
================================================================================
#>

Set-StrictMode -Version Latest

# ==============================================================================
# INPUTS
# ==============================================================================

$appName = 'OneStart'

# ==============================================================================
# CONFIGURATION (internal - not user inputs)
# ==============================================================================

$destinationFolder = "$env:SystemDrive\limehawk\nirsoft"
$registryBackupFolder = "$env:SystemDrive\limehawk\registry_backup"

$processPatterns = @(
    'OneStart'
    'onestart'
    'onestartbar'
    'onestartupdate'
    'DBar'
)

$taskPathPatterns = @(
    '\OneStartUser\*'
    '\OneStart*'
)

$taskNamePatterns = @(
    'OneStart*'
    '*OneStart*'
)

$folderPaths = @(
    "$env:APPDATA\OneStart"
    "$env:APPDATA\OneStart.ai"
    "$env:LOCALAPPDATA\OneStart"
    "$env:LOCALAPPDATA\OneStart.ai"
    "$env:LOCALAPPDATA\OneStartBar"
    "$env:ProgramData\OneStart"
    "$env:ProgramData\OneStart.ai"
    "$env:ProgramFiles\OneStart"
    "$env:ProgramFiles\OneStart.ai"
    "${env:ProgramFiles(x86)}\OneStart"
    "${env:ProgramFiles(x86)}\OneStart.ai"
)

$registryPaths = @(
    'HKCU:\Software\OneStart.ai'
    'HKCU:\Software\OneStart'
    'HKCU:\Software\OneStartBar'
    'HKCU:\Software\DBar'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneStart.ai OneStart'
    'HKLM:\Software\OneStart.ai'
    'HKLM:\Software\OneStart'
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{31F4B209-D4E1-41E0-A34F-35EFF7117AE8}'
)

$runKeyPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
)

# ==============================================================================
# STATE TRACKING
# ==============================================================================

$uninstallAttempted   = $false
$processesTerminated  = 0
$tasksRemoved         = 0
$foldersRemoved       = 0
$registryKeysBackedUp = 0
$registryKeysRemoved  = 0

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText     = ""

if ([string]::IsNullOrWhiteSpace($appName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Application name is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    exit 1
}

Write-Host "Application Name : $appName"

# ==============================================================================
# NIRSOFT UNINSTALLVIEW SETUP
# ==============================================================================

Write-Host ""
Write-Host "[ NIRSOFT UNINSTALLVIEW SETUP ]"
Write-Host "--------------------------------------------------------------"

if ([Environment]::Is64BitOperatingSystem) {
    $downloadUrl = "https://www.nirsoft.net/utils/uninstallview-x64.zip"
    Write-Host "Architecture : 64-bit"
} else {
    $downloadUrl = "https://www.nirsoft.net/utils/uninstallview.zip"
    Write-Host "Architecture : 32-bit"
}

Write-Host "Download URL : $downloadUrl"

try {
    if (-not (Test-Path $destinationFolder)) {
        New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
        Write-Host "Created folder : $destinationFolder"
    }

    $zipFilePath = Join-Path $destinationFolder "UninstallView.zip"
    $uninstallViewPath = Join-Path $destinationFolder "UninstallView.exe"

    if (-not (Test-Path $uninstallViewPath)) {
        Write-Host "Downloading UninstallView..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing
        Write-Host "Download complete"

        Write-Host "Extracting to $destinationFolder..."
        Expand-Archive -Path $zipFilePath -DestinationPath $destinationFolder -Force
        Write-Host "Extraction complete"

        if (Test-Path $zipFilePath) {
            Remove-Item $zipFilePath -Force
        }
    } else {
        Write-Host "UninstallView already present"
    }
}
catch {
    Write-Host "Warning: Failed to setup UninstallView - $($_.Exception.Message)"
    Write-Host "Continuing with manual removal only..."
    $uninstallViewPath = $null
}

# ==============================================================================
# UNINSTALL ATTEMPT
# ==============================================================================

Write-Host ""
Write-Host "[ UNINSTALL ATTEMPT ]"
Write-Host "--------------------------------------------------------------"

if ($uninstallViewPath -and (Test-Path $uninstallViewPath)) {
    Write-Host "Searching for : $appName"
    Write-Host "Attempting silent uninstall..."

    try {
        $process = Start-Process -FilePath $uninstallViewPath `
            -ArgumentList "/quninstallwildcard `"$appName`" 5" `
            -PassThru -Wait -WindowStyle Hidden

        $uninstallAttempted = $true
        Write-Host "Uninstall command issued (exit code: $($process.ExitCode))"
        Write-Host "Waiting 10 seconds for uninstall to complete..."
        Start-Sleep -Seconds 10
    }
    catch {
        Write-Host "Warning: Uninstall attempt failed - $($_.Exception.Message)"
    }
} else {
    Write-Host "UninstallView not available, skipping automated uninstall"
}

# ==============================================================================
# PROCESS TERMINATION
# ==============================================================================

Write-Host ""
Write-Host "[ PROCESS TERMINATION ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Searching for OneStart/DBar processes..."

foreach ($pattern in $processPatterns) {
    try {
        $processes = Get-Process -Name "*$pattern*" -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            Write-Host "Found process : $($proc.ProcessName) (PID: $($proc.Id))"
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Host "Terminated : $($proc.ProcessName)"
                $processesTerminated++
            }
            catch {
                Write-Host "Failed to terminate : $($proc.ProcessName)"
            }
        }
    }
    catch {
        # No matching processes found
    }
}

if ($processesTerminated -eq 0) {
    Write-Host "No matching processes found"
}

Write-Host "Process cleanup complete"

# ==============================================================================
# SCHEDULED TASK REMOVAL
# ==============================================================================

Write-Host ""
Write-Host "[ SCHEDULED TASK REMOVAL ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Searching for OneStart scheduled tasks..."

foreach ($taskPath in $taskPathPatterns) {
    foreach ($taskName in $taskNamePatterns) {
        try {
            $tasks = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            foreach ($task in $tasks) {
                Write-Host "Found : $($task.TaskName)"
                try {
                    Unregister-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
                    Write-Host "Removed : $($task.TaskName)"
                    $tasksRemoved++
                }
                catch {
                    Write-Host "Failed to remove : $($task.TaskName)"
                }
            }
        }
        catch {
            # No matching tasks
        }
    }
}

# Also search root level
try {
    $rootTasks = Get-ScheduledTask -TaskName "*OneStart*" -ErrorAction SilentlyContinue
    foreach ($task in $rootTasks) {
        Write-Host "Found : $($task.TaskName)"
        try {
            Unregister-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "Removed : $($task.TaskName)"
            $tasksRemoved++
        }
        catch {
            Write-Host "Failed to remove : $($task.TaskName)"
        }
    }
}
catch {
    # No matching tasks
}

# Remove task folders
Write-Host "Removing task folders..."
$taskFoldersToRemove = @('\OneStartUser\OneStartUpdater\', '\OneStartUser\')

try {
    $scheduleService = New-Object -ComObject Schedule.Service
    $scheduleService.Connect()

    foreach ($folder in $taskFoldersToRemove) {
        try {
            $parentPath = Split-Path $folder.TrimEnd('\') -Parent
            $folderName = Split-Path $folder.TrimEnd('\') -Leaf
            if ([string]::IsNullOrWhiteSpace($parentPath)) { $parentPath = '\' }
            $parentFolder = $scheduleService.GetFolder($parentPath)
            $parentFolder.DeleteFolder($folderName, 0)
            Write-Host "Removed folder : $folder"
        }
        catch {
            # Folder may not exist or not empty
        }
    }
}
catch {
    Write-Host "Could not access Task Scheduler COM object"
}

if ($tasksRemoved -eq 0) {
    Write-Host "No matching tasks found"
}

Write-Host "Task cleanup complete"

# ==============================================================================
# FILE CLEANUP
# ==============================================================================

Write-Host ""
Write-Host "[ FILE CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Checking known OneStart locations..."

foreach ($folderPath in $folderPaths) {
    if (Test-Path $folderPath) {
        try {
            Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
            Write-Host "Removed : $folderPath"
            $foldersRemoved++
        }
        catch {
            Write-Host "Failed to remove : $folderPath - $($_.Exception.Message)"
        }
    }
}

# Check all user profiles
$userProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue
foreach ($profile in $userProfiles) {
    $userPaths = @(
        "$($profile.FullName)\AppData\Roaming\OneStart"
        "$($profile.FullName)\AppData\Roaming\OneStart.ai"
        "$($profile.FullName)\AppData\Local\OneStart"
        "$($profile.FullName)\AppData\Local\OneStart.ai"
        "$($profile.FullName)\AppData\Local\OneStartBar"
    )
    foreach ($userPath in $userPaths) {
        if (Test-Path $userPath) {
            try {
                Remove-Item -Path $userPath -Recurse -Force -ErrorAction Stop
                Write-Host "Removed : $userPath"
                $foldersRemoved++
            }
            catch {
                Write-Host "Failed to remove : $userPath"
            }
        }
    }
}

if ($foldersRemoved -eq 0) {
    Write-Host "No leftover folders found"
}

Write-Host "File cleanup complete"

# ==============================================================================
# REGISTRY BACKUP
# ==============================================================================

Write-Host ""
Write-Host "[ REGISTRY BACKUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Creating registry backups before removal..."

try {
    if (-not (Test-Path $registryBackupFolder)) {
        New-Item -ItemType Directory -Path $registryBackupFolder -Force | Out-Null
        Write-Host "Created backup folder : $registryBackupFolder"
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupSubFolder = Join-Path $registryBackupFolder "onestart_$timestamp"
    New-Item -ItemType Directory -Path $backupSubFolder -Force | Out-Null

    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                # Convert PowerShell path to reg.exe format
                $regExePath = $regPath -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
                $safeName = ($regPath -replace ':', '' -replace '\\', '_' -replace '\{', '' -replace '\}', '')
                $backupFile = Join-Path $backupSubFolder "$safeName.reg"

                $regExport = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$regExePath`" `"$backupFile`" /y" -Wait -PassThru -WindowStyle Hidden
                if ($regExport.ExitCode -eq 0) {
                    Write-Host "Backed up : $regPath"
                    $registryKeysBackedUp++
                } else {
                    Write-Host "Failed to backup : $regPath"
                }
            }
            catch {
                Write-Host "Failed to backup : $regPath - $($_.Exception.Message)"
            }
        }
    }

    # Backup Run key entries
    foreach ($runKey in $runKeyPaths) {
        if (Test-Path $runKey) {
            try {
                $props = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
                if ($props) {
                    $matchingProps = $props.PSObject.Properties | Where-Object { $_.Name -like "*OneStart*" -or $_.Name -like "*DBar*" }
                    if ($matchingProps) {
                        $regExePath = $runKey -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
                        $safeName = ($runKey -replace ':', '' -replace '\\', '_') + "_Run"
                        $backupFile = Join-Path $backupSubFolder "$safeName.reg"

                        $regExport = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$regExePath`" `"$backupFile`" /y" -Wait -PassThru -WindowStyle Hidden
                        if ($regExport.ExitCode -eq 0) {
                            Write-Host "Backed up Run key : $runKey"
                            $registryKeysBackedUp++
                        }
                    }
                }
            }
            catch {
                # Could not access run key
            }
        }
    }

    if ($registryKeysBackedUp -gt 0) {
        Write-Host "Backup location : $backupSubFolder"
    }
}
catch {
    Write-Host "Warning: Could not create backup folder - $($_.Exception.Message)"
}

if ($registryKeysBackedUp -eq 0) {
    Write-Host "No registry keys found to backup"
}

Write-Host "Registry backup complete"

# ==============================================================================
# REGISTRY CLEANUP
# ==============================================================================

Write-Host ""
Write-Host "[ REGISTRY CLEANUP ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Cleaning registry keys..."

foreach ($regPath in $registryPaths) {
    if (Test-Path $regPath) {
        try {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "Removed : $regPath"
            $registryKeysRemoved++
        }
        catch {
            Write-Host "Failed to remove : $regPath"
        }
    }
}

# Clean Run keys
Write-Host "Checking startup entries..."
foreach ($runKey in $runKeyPaths) {
    if (Test-Path $runKey) {
        try {
            $props = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -like "*OneStart*" -or $_.Name -like "*DBar*" } | ForEach-Object {
                    try {
                        Remove-ItemProperty -Path $runKey -Name $_.Name -Force -ErrorAction Stop
                        Write-Host "Removed startup entry : $($_.Name)"
                        $registryKeysRemoved++
                    }
                    catch {
                        Write-Host "Failed to remove startup entry : $($_.Name)"
                    }
                }
            }
        }
        catch {
            # Could not access run key
        }
    }
}

if ($registryKeysRemoved -eq 0) {
    Write-Host "No leftover registry keys found"
}

Write-Host "Registry cleanup complete"

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Result : Success"
Write-Host "Uninstall Attempted : $(if ($uninstallAttempted) { 'Yes' } else { 'No' })"
Write-Host "Processes Terminated : $processesTerminated"
Write-Host "Tasks Removed : $tasksRemoved"
Write-Host "Folders Removed : $foldersRemoved"
Write-Host "Registry Keys Backed Up : $registryKeysBackedUp"
Write-Host "Registry Keys Removed : $registryKeysRemoved"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
exit 0
