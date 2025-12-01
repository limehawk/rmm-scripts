$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : WinRE Partition Resize                                          v1.0.0
FILE   : winre_partition_resize.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Extends the Windows Recovery Environment (WinRE) partition by 250MB to
    resolve issues with Windows updates requiring more recovery partition space.
    This is commonly needed for KB5034441 and similar updates.

REQUIRED INPUTS:
    $BackupFolder : Path to backup WinRE partition contents (default: C:\winre_backup)

BEHAVIOR:
    1. Examines current disk layout and WinRE status
    2. Validates requirements (WinRE enabled, sufficient space)
    3. Backs up existing WinRE partition content
    4. Disables WinRE temporarily
    5. Shrinks OS partition by 250MB (if needed)
    6. Extends or recreates WinRE partition
    7. Re-enables WinRE
    8. Verifies new configuration

PREREQUISITES:
    - Windows 10/11
    - Administrator privileges
    - Sufficient free space on OS partition
    - Reboot recommended before running

SECURITY NOTES:
    - No secrets in logs
    - Creates backup of WinRE content
    - Modifies disk partitions (use with caution)

EXIT CODES:
    0 = Success (or no changes needed)
    1 = Failure

EXAMPLE RUN:
    [ EXAMINING SYSTEM ]
    --------------------------------------------------------------
    OS Disk              : 0
    OS Partition         : 3
    WinRE Partition      : 4
    Disk Type            : GPT

    [ CURRENT STATUS ]
    --------------------------------------------------------------
    WinRE Status         : Enabled
    WinRE Partition Size : 523190272
    WinRE Free Space     : 52428800

    [ PROPOSED CHANGES ]
    --------------------------------------------------------------
    Action               : Extend WinRE by 250MB
    Shrink OS By         : 250MB
    New WinRE Size       : 785285120

    [ EXECUTING CHANGES ]
    --------------------------------------------------------------
    Disabling WinRE...   : Done
    Shrinking OS...      : Done
    Extending WinRE...   : Done
    Enabling WinRE...    : Done

    [ FINAL STATUS ]
    --------------------------------------------------------------
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# CONFIGURATION
# ============================================================================
$BackupFolder = "C:\winre_backup"
$SkipConfirmation = $true

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

function ExtractNumbers([string]$str) {
    $cleanString = $str -replace "[^0-9]"
    return [long]$cleanString
}

function DisplayPartitionInfo([string[]]$partitionPath) {
    $volume = Get-WmiObject -Class Win32_Volume | Where-Object { $partitionPath -contains $_.DeviceID }
    return $volume.Capacity, $volume.FreeSpace
}

function DisplayWinREStatus {
    $WinREInfo = Reagentc /info
    $Status = $false
    $Location = ""

    foreach ($line in $WinREInfo) {
        $params = $line.Split(':')
        if ($params.Count -lt 2) { continue }

        if (($params[1].Trim() -ieq "Enabled") -Or ($params[1].Trim() -ieq "Disabled")) {
            $Status = $params[1].Trim() -ieq "Enabled"
        }
        if ($params[1].Trim() -like "\\?\GLOBALROOT*") {
            $Location = $params[1].Trim()
        }
    }

    return $Status, $Location
}

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Section "ERROR OCCURRED"
    Write-Host " This script requires administrative privileges to run."
    Write-Section "SCRIPT HALTED"
    exit 1
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    # Create backup folder if needed
    if (-not (Test-Path -Path $BackupFolder)) {
        New-Item -Path $BackupFolder -ItemType Directory | Out-Null
        PrintKV "Backup Directory" "Created at $BackupFolder"
    }

    Write-Section "EXAMINING SYSTEM"

    $NeedShrink = $true
    $NeedCreateNew = $false
    $NeedBackup = $false

    # Get WinRE status
    $InitialWinREStatus = DisplayWinREStatus
    $WinREStatus = $InitialWinREStatus[0]
    $WinRELocation = $InitialWinREStatus[1]

    if (-not $WinREStatus) {
        PrintKV "WinRE Status" "Disabled"
        Write-Host ""
        Write-Host " ERROR: WinRE is disabled. Cannot proceed."
        Write-Section "SCRIPT HALTED"
        exit 1
    }

    # Get system info
    $system32Path = [System.Environment]::SystemDirectory
    $ReAgentXmlPath = Join-Path -Path $system32Path -ChildPath "\Recovery\ReAgent.xml"

    if (-not (Test-Path $ReAgentXmlPath)) {
        Write-Host " ERROR: ReAgent.xml not found"
        Write-Section "SCRIPT HALTED"
        exit 1
    }

    # Get OS partition
    $OSDrive = $system32Path.Substring(0,1)
    $OSPartition = Get-Partition -DriveLetter $OSDrive

    # Get WinRE partition info
    $WinRELocationItems = $WinRELocation.Split('\\')
    foreach ($item in $WinRELocationItems) {
        if ($item -like "harddisk*") {
            $OSDiskIndex = ExtractNumbers($item)
        }
        if ($item -like "partition*") {
            $WinREPartitionIndex = ExtractNumbers($item)
        }
    }

    PrintKV "OS Disk" $OSDiskIndex
    PrintKV "OS Partition" $OSPartition.PartitionNumber
    PrintKV "WinRE Partition" $WinREPartitionIndex

    $WinREPartition = Get-Partition -DiskNumber $OSDiskIndex -PartitionNumber $WinREPartitionIndex
    $diskInfo = Get-Disk -Number $OSDiskIndex
    $diskType = $diskInfo.PartitionStyle

    PrintKV "Disk Type" $diskType

    # Get WinRE partition size
    Write-Section "CURRENT STATUS"

    $WinREPartitionSizeInfo = DisplayPartitionInfo($WinREPartition.AccessPaths)
    PrintKV "WinRE Status" "Enabled"
    PrintKV "WinRE Partition Size" $WinREPartitionSizeInfo[0]
    PrintKV "WinRE Free Space" $WinREPartitionSizeInfo[1]

    # Check if extension is needed
    if ($WinREPartitionSizeInfo[1] -ge 250MB) {
        Write-Host ""
        Write-Host " WinRE partition has sufficient free space (>= 250MB)."
        Write-Host " No changes needed."
        Write-Section "SCRIPT COMPLETED"
        exit 0
    }

    # Check partition layout
    $WinREIsOnSystemPartition = $false
    if ($diskType -ieq "MBR") {
        if ($WinREPartition.IsActive) { $WinREIsOnSystemPartition = $true }
    }
    if ($diskType -ieq "GPT") {
        if ($WinREPartition.Type -ieq "System") { $WinREIsOnSystemPartition = $true }
    }

    $OSPartitionEnds = $OSPartition.Offset + $OSPartition.Size

    if ($WinREPartition.Offset -lt $OSPartitionEnds) {
        $NeedCreateNew = $true
        $targetWinREPartitionSize = $WinREPartitionSizeInfo[0] + 250MB
        $shrinkSize = [Math]::Ceiling($targetWinREPartitionSize / 1MB) * 1MB
    } else {
        $shrinkSize = 250MB
        $UnallocatedSpace = $WinREPartition.Offset - $OSPartitionEnds

        if ($UnallocatedSpace -ge 250MB) {
            $NeedShrink = $false
        } else {
            $shrinkSize = [Math]::Ceiling((250MB - $UnallocatedSpace) / 1MB) * 1MB
            if ($shrinkSize -gt 250MB) { $shrinkSize = 250MB }
        }
    }

    $targetWinREPartitionSize = $WinREPartitionSizeInfo[0] + 250MB
    $targetOSPartitionSize = $OSPartition.Size - $shrinkSize

    # Validate shrink is possible
    $supportedSize = Get-PartitionSupportedSize -DriveLetter $OSDrive
    if ($NeedShrink -and $targetOSPartitionSize -lt $supportedSize.SizeMin) {
        Write-Host " ERROR: Cannot shrink OS partition enough. Insufficient free space."
        Write-Section "SCRIPT HALTED"
        exit 1
    }

    # Display proposed changes
    Write-Section "PROPOSED CHANGES"

    if ($NeedCreateNew) {
        PrintKV "Action" "Create new WinRE partition"
    } else {
        PrintKV "Action" "Extend existing WinRE partition"
    }

    if ($NeedShrink) {
        PrintKV "Shrink OS By" ("{0:N0} MB" -f ($shrinkSize / 1MB))
    } else {
        PrintKV "Shrink OS" "Not needed (using unallocated space)"
    }

    PrintKV "New WinRE Size" ("{0:N0} MB" -f ($targetWinREPartitionSize / 1MB))

    if (-not $WinREIsOnSystemPartition) {
        $NeedBackup = $true
    }

    # Execute changes
    Write-Section "EXECUTING CHANGES"

    # Clear stage location in ReAgent.xml
    $xml = [xml](Get-Content -Path $ReAgentXmlPath)
    $node = $xml.WindowsRE.ImageLocation
    if (-not (($node.path -eq "") -And ($node.guid -eq "{00000000-0000-0000-0000-000000000000}"))) {
        $node.path = ""
        $node.offset = "0"
        $node.guid = "{00000000-0000-0000-0000-000000000000}"
        $node.id = "0"
        $xml.Save($ReAgentXmlPath)
        PrintKV "ReAgent.xml" "Stage location cleared"
    }

    # Disable WinRE
    Write-Host " Disabling WinRE..."
    reagentc /disable | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to disable WinRE"
    }
    PrintKV "WinRE" "Disabled"

    # Verify WinRE.wim exists
    $disableWinREPath = Join-Path -Path $system32Path -ChildPath "\Recovery\WinRE.wim"
    if (-not (Test-Path $disableWinREPath)) {
        reagentc /enable | Out-Null
        throw "WinRE.wim not found after disabling"
    }

    # Shrink OS partition if needed
    if ($NeedShrink) {
        Write-Host " Shrinking OS partition..."
        Resize-Partition -DriveLetter $OSDrive -Size $targetOSPartitionSize
        PrintKV "OS Partition" "Shrunk"
    }

    # Backup and delete old WinRE partition (if not system partition)
    if (-not $WinREIsOnSystemPartition) {
        if ($NeedBackup) {
            $sourcePath = $WinREPartition.AccessPaths[0]
            Write-Host " Backing up WinRE content..."
            $items = Get-ChildItem -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.Name -ieq "System Volume Information") { continue }
                $sourceItemPath = Join-Path -Path $sourcePath -ChildPath $item.Name
                $destItemPath = Join-Path -Path $BackupFolder -ChildPath $item.Name
                Copy-Item -LiteralPath $sourceItemPath -Destination $destItemPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            PrintKV "Backup" "Completed to $BackupFolder"
        }

        Write-Host " Deleting old WinRE partition..."
        Remove-Partition -DiskNumber $OSDiskIndex -PartitionNumber $WinREPartitionIndex -Confirm:$false
        PrintKV "Old WinRE Partition" "Deleted"
    }

    Start-Sleep -Seconds 5

    # Create new WinRE partition
    Write-Host " Creating new WinRE partition..."

    if ($diskType -ieq "GPT") {
        $partition = New-Partition -DiskNumber $OSDiskIndex -Size $targetWinREPartitionSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
        $newPartitionIndex = $partition.PartitionNumber
        Start-Sleep -Seconds 2
        Format-Volume -Partition $partition -FileSystem NTFS -Confirm:$false | Out-Null
    } else {
        # MBR disk - use diskpart
        $targetWinREPartitionSizeInMb = [int]($targetWinREPartitionSize / 1MB)
        $diskpartScript = @"
select disk $OSDiskIndex
create partition primary size=$targetWinREPartitionSizeInMb id=27
format quick fs=ntfs label="Recovery"
set id=27
"@
        $diskpartSciptFile = Join-Path -Path $env:Temp -ChildPath "ExtendWinRE_Script.txt"
        $diskpartScript | Out-File -FilePath $diskpartSciptFile -Encoding ascii
        diskpart /s $diskpartSciptFile | Out-Null
        Remove-Item $diskpartSciptFile -Force

        $vol = Get-Volume -FileSystemLabel "Recovery"
        $newPartitionIndex = (Get-Partition | Where-Object { $_.AccessPaths -contains $vol.Path }).PartitionNumber
    }

    PrintKV "New WinRE Partition" "Created (Partition $newPartitionIndex)"

    # Re-enable WinRE
    Write-Host " Enabling WinRE..."
    reagentc /enable | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to re-enable WinRE"
    }
    PrintKV "WinRE" "Enabled"

    # Final verification
    Write-Section "VERIFICATION"

    $FinalWinREStatus = DisplayWinREStatus
    PrintKV "WinRE Status" $(if ($FinalWinREStatus[0]) { "Enabled" } else { "Disabled" })

    $newWinREPartition = Get-Partition -DiskNumber $OSDiskIndex -PartitionNumber $newPartitionIndex
    $newWinREPartitionSizeInfo = DisplayPartitionInfo($newWinREPartition.AccessPaths)
    PrintKV "New WinRE Size" ("{0:N0} MB" -f ($newWinREPartitionSizeInfo[0] / 1MB))
    PrintKV "New WinRE Free" ("{0:N0} MB" -f ($newWinREPartitionSizeInfo[1] / 1MB))

    Write-Section "FINAL STATUS"
    Write-Host " SCRIPT SUCCEEDED"
    Write-Host ""
    Write-Host " WinRE partition has been extended by 250MB."
    if ($NeedBackup) {
        Write-Host " Old content backed up to: $BackupFolder"
    }

    Write-Section "SCRIPT COMPLETED"
    exit 0
}
catch {
    Write-Section "ERROR OCCURRED"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName

    # Try to re-enable WinRE on error
    Write-Host ""
    Write-Host " Attempting to re-enable WinRE..."
    reagentc /enable 2>&1 | Out-Null

    Write-Section "SCRIPT HALTED"
    exit 1
}
