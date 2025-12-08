$ErrorActionPreference = 'Stop'
<#
================================================================================
   SCRIPT: secure_delete_with_certificate.ps1                        v1.0.0
================================================================================

██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

--------------------------------------------------------------------------------
   FILE: secure_delete_with_certificate.ps1
--------------------------------------------------------------------------------
   README
--------------------------------------------------------------------------------

PURPOSE:
    Securely deletes files using Microsoft SDelete with DoD 5220.22-M compliant
    overwriting, generating comprehensive documentation suitable for legal
    proceedings. Creates a detailed certificate of destruction with file hashes,
    metadata, system information, and timestamped audit trail.

DATA SOURCES & PRIORITY:
    1. Target path specified in REQUIRED INPUTS
    2. System information from WMI/CIM
    3. SDelete output capture

REQUIRED INPUTS:
    $targetPath       - File or folder path to securely delete
    $outputDirectory  - Where to save the certificate (default: Desktop)
    $overwritePasses  - Number of overwrite passes (default: 3)
    $operatorName     - Name of person executing the deletion
    $caseReference    - Legal case reference number (optional)
    $witnessName      - Name of witness if present (optional)
    $notes            - Additional notes for the certificate (optional)

SETTINGS:
    $dryRun           - Test mode: performs all steps except actual deletion ($true/$false)
    $recursive        - Process subfolders if target is directory ($true/$false)
    $generateHtml     - Generate HTML certificate in addition to text ($true/$false)
    $autoInstallSDelete - Auto-install SDelete via winget if not found ($true/$false)

BEHAVIOR:
    1. Validates target path exists and SDelete is available
    2. Generates unique session ID for audit trail
    3. Captures complete system information (hardware, OS, user, network)
    4. Enumerates all target files with full metadata
    5. Calculates SHA-256 and MD5 hashes for each file (dual hash for verification)
    6. Records file attributes, timestamps, size, and NTFS alternate data streams
    7. Executes SDelete with specified passes, capturing all output
    8. Verifies each file no longer exists post-deletion
    9. Generates comprehensive certificate with all collected data
    10. Outputs certificate to specified directory with timestamp

PREREQUISITES:
    - Microsoft SDelete (auto-installed via winget if $autoInstallSDelete = $true)
    - PowerShell 5.1 or later
    - Administrator rights recommended for complete metadata access

SECURITY NOTES:
    - No secrets in logs
    - Certificate contains file paths and hashes which may be sensitive
    - Store certificates securely according to legal requirements

EXIT CODES:
    0 - All files successfully deleted and verified
    1 - Validation failed or deletion errors occurred

EXAMPLE RUN (DRY RUN MODE):
    --------------------------------------------------------------
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Target Path      : C:\Sensitive\Documents
    Operator         : John Smith
    Case Reference   : CASE-2025-001
    Overwrite Passes : 3
    Output Directory : C:\Users\john\Desktop
    Recursive        : True
    Dry Run          : True

    *** DRY RUN MODE - NO FILES WILL BE DELETED ***

    Validation passed

    [ SESSION INITIALIZATION ]
    --------------------------------------------------------------
    Session ID : 20251208-143022-A7B3C9D1
    Started    : 2025-12-08 14:30:22.123 -05:00

    [ SYSTEM INFORMATION ]
    --------------------------------------------------------------
    Collecting system information...
    Computer   : WORKSTATION-01
    User       : CONTOSO\jsmith
    OS         : Microsoft Windows 11 Pro
    SDelete    : v2.05
    Drive      : C: (NTFS)

    [ FILE ENUMERATION ]
    --------------------------------------------------------------
    Target is a directory (recursive: True)
    Files found : 3

    [ PRE-DELETION HASHING ]
    --------------------------------------------------------------
    Calculating hashes for all files...
    This may take a while for large files.

    Processing : document1.pdf
      SHA-256  : A1B2C3D4E5F6...
      Size     : 1,234,567 bytes

    Processing : spreadsheet.xlsx
      SHA-256  : 9F8E7D6C5B4A...
      Size     : 45,678 bytes

    Processing : notes.txt
      SHA-256  : 1A2B3C4D5E6F...
      Size     : 1,234 bytes

    Hashing complete for 3 files

    [ CONFIRMATION ]
    --------------------------------------------------------------
    *** DRY RUN MODE ***

    The following files WOULD be destroyed (but won't be in dry run):

      - C:\Sensitive\Documents\document1.pdf
      - C:\Sensitive\Documents\spreadsheet.xlsx
      - C:\Sensitive\Documents\notes.txt

    Proceeding with dry run - no files will be modified.

    [ SECURE DELETION ]
    --------------------------------------------------------------
    *** DRY RUN MODE - SKIPPING ACTUAL DELETION ***

    Would execute: sdelete -accepteula -p 3 -nobanner <file>
    Files that would be deleted: 3

      [WOULD DELETE] document1.pdf
      [WOULD DELETE] spreadsheet.xlsx
      [WOULD DELETE] notes.txt

    [ POST-DELETION VERIFICATION ]
    --------------------------------------------------------------
    *** DRY RUN MODE - FILES STILL EXIST ***

    EXISTS   : document1.pdf (dry run - not deleted)
    EXISTS   : spreadsheet.xlsx (dry run - not deleted)
    EXISTS   : notes.txt (dry run - not deleted)

    Dry run verification complete
    All files remain intact

    [ CERTIFICATE GENERATION ]
    --------------------------------------------------------------
    Text certificate : C:\Users\john\Desktop\SecureDeletion_DRYRUN_20251208-143022.txt
    HTML certificate : C:\Users\john\Desktop\SecureDeletion_DRYRUN_20251208-143022.html

    [ FINAL STATUS ]
    --------------------------------------------------------------
    *** DRY RUN COMPLETE - NO FILES WERE DELETED ***

    Session ID          : 20251208-143022-A7B3C9D1
    Files Processed     : 3
    Files Inventoried   : 3
    Files Deleted       : 0 (Dry Run)
    Certificate (Text)  : C:\Users\john\Desktop\SecureDeletion_DRYRUN_20251208-143022.txt
    Certificate (HTML)  : C:\Users\john\Desktop\SecureDeletion_DRYRUN_20251208-143022.html

    To perform actual deletion, set $dryRun = $false and run again.

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

--------------------------------------------------------------------------------
   CHANGELOG
--------------------------------------------------------------------------------
   2025-12-08 v1.0.0 Initial release - comprehensive secure deletion with
                     certificate generation for legal documentation
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# REQUIRED INPUTS - MODIFY THESE VALUES
# ==============================================================================

# Target file or folder to securely delete
$targetPath = 'C:\Path\To\File\Or\Folder'

# Output directory for certificates (leave empty for Desktop)
$outputDirectory = ''

# Number of overwrite passes (DoD standard is 3, higher = more secure but slower)
$overwritePasses = 3

# Operator information (person executing the deletion)
$operatorName = 'Your Name Here'

# Legal case reference (optional - leave empty if not applicable)
$caseReference = ''

# Witness name (optional - leave empty if no witness)
$witnessName = ''

# Additional notes for the certificate (optional)
$notes = ''

# ==============================================================================
# SETTINGS
# ==============================================================================

# DRY RUN MODE - Set to $true to test without deleting anything
# Performs all steps (enumeration, hashing, system info) but skips actual deletion
$dryRun = $true

# Process subfolders if target is a directory
$recursive = $true

# Generate HTML certificate in addition to plain text
$generateHtml = $true

# Auto-install SDelete via winget if not found
$autoInstallSDelete = $true

# ==============================================================================
# STATE VARIABLES
# ==============================================================================

$script:sessionId = ''
$script:startTime = $null
$script:endTime = $null
$script:systemInfo = @{}
$script:fileInventory = @()
$script:deletionLog = @()
$script:verificationResults = @()
$script:sdeleteOutput = ''
$script:errorOccurred = $false
$script:errorMessages = @()

# ==============================================================================
# FUNCTIONS
# ==============================================================================

function Write-Section {
    param([string]$Name)
    Write-Host ""
    Write-Host "[ $Name ]"
    Write-Host "--------------------------------------------------------------"
}

function Get-FormattedTimestamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff K')
}

function Get-SessionId {
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $random = -join ((65..90) + (48..57) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    return "$timestamp-$random"
}

function Get-SystemInformation {
    $info = @{}

    # Timestamps
    $info['SessionStart'] = Get-FormattedTimestamp
    $info['SessionId'] = $script:sessionId

    # Computer identity
    $info['ComputerName'] = $env:COMPUTERNAME
    $info['Domain'] = $env:USERDOMAIN
    $info['Username'] = $env:USERNAME
    $info['UserDomainFull'] = "$env:USERDOMAIN\$env:USERNAME"

    # Operating system
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $info['OSName'] = $os.Caption
        $info['OSVersion'] = $os.Version
        $info['OSBuild'] = $os.BuildNumber
        $info['OSArchitecture'] = $os.OSArchitecture
        $info['InstallDate'] = $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss')
        $info['LastBootTime'] = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
    } catch {
        $info['OSError'] = "Unable to retrieve OS info: $_"
    }

    # Hardware
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $info['Manufacturer'] = $cs.Manufacturer
        $info['Model'] = $cs.Model
        $info['SystemType'] = $cs.SystemType
        $info['TotalPhysicalMemoryGB'] = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    } catch {
        $info['HardwareError'] = "Unable to retrieve hardware info: $_"
    }

    # BIOS/Serial
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS
        $info['BIOSVersion'] = $bios.SMBIOSBIOSVersion
        $info['SerialNumber'] = $bios.SerialNumber
    } catch {
        $info['BIOSError'] = "Unable to retrieve BIOS info: $_"
    }

    # Processor
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        $info['Processor'] = $cpu.Name
        $info['ProcessorId'] = $cpu.ProcessorId
    } catch {
        $info['CPUError'] = "Unable to retrieve CPU info: $_"
    }

    # Network (for identification, not connectivity)
    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration |
            Where-Object { $_.IPEnabled -eq $true }
        $info['IPAddresses'] = ($adapters.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
        $info['MACAddresses'] = ($adapters.MACAddress) -join ', '
    } catch {
        $info['NetworkError'] = "Unable to retrieve network info: $_"
    }

    # Target drive information
    try {
        $targetRoot = [System.IO.Path]::GetPathRoot($targetPath)
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk |
            Where-Object { $_.DeviceID -eq $targetRoot.TrimEnd('\') }
        if ($drive) {
            $info['TargetDrive'] = $drive.DeviceID
            $info['TargetDriveFileSystem'] = $drive.FileSystem
            $info['TargetDriveSerial'] = $drive.VolumeSerialNumber
            $info['TargetDriveSizeGB'] = [math]::Round($drive.Size / 1GB, 2)
        }

        # Physical disk info
        $partition = Get-CimInstance -ClassName Win32_LogicalDiskToPartition |
            Where-Object { $_.Dependent -like "*$($targetRoot.TrimEnd('\'))*" }
        if ($partition) {
            $diskIndex = ($partition.Antecedent -replace '.*Disk #(\d+).*', '$1')
            $physDisk = Get-CimInstance -ClassName Win32_DiskDrive |
                Where-Object { $_.Index -eq $diskIndex }
            if ($physDisk) {
                $info['PhysicalDiskModel'] = $physDisk.Model
                $info['PhysicalDiskSerial'] = $physDisk.SerialNumber
                $info['PhysicalDiskInterface'] = $physDisk.InterfaceType
                $info['PhysicalDiskMediaType'] = $physDisk.MediaType
            }
        }
    } catch {
        $info['DriveInfoError'] = "Unable to retrieve drive info: $_"
    }

    # SDelete version
    try {
        $sdeleteVersion = & sdelete -nobanner 2>&1 | Select-String -Pattern 'v\d+\.\d+' |
            ForEach-Object { $_.Matches.Value } | Select-Object -First 1
        $info['SDeleteVersion'] = $sdeleteVersion
        $sdeleteLocation = (Get-Command sdelete -ErrorAction SilentlyContinue).Source
        $info['SDeletePath'] = $sdeleteLocation
    } catch {
        $info['SDeleteVersion'] = 'Unable to determine'
    }

    # PowerShell version
    $info['PowerShellVersion'] = $PSVersionTable.PSVersion.ToString()

    return $info
}

function Get-FileDetails {
    param([string]$FilePath)

    $details = @{
        FullPath = $FilePath
        Name = [System.IO.Path]::GetFileName($FilePath)
        Directory = [System.IO.Path]::GetDirectoryName($FilePath)
        Extension = [System.IO.Path]::GetExtension($FilePath)
        EnumeratedAt = Get-FormattedTimestamp
    }

    try {
        $file = Get-Item -LiteralPath $FilePath -Force

        $details['SizeBytes'] = $file.Length
        $details['SizeFormatted'] = '{0:N0}' -f $file.Length
        $details['CreationTime'] = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss.fff K')
        $details['CreationTimeUtc'] = $file.CreationTimeUtc.ToString('yyyy-MM-dd HH:mm:ss.fff') + ' UTC'
        $details['LastWriteTime'] = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff K')
        $details['LastWriteTimeUtc'] = $file.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss.fff') + ' UTC'
        $details['LastAccessTime'] = $file.LastAccessTime.ToString('yyyy-MM-dd HH:mm:ss.fff K')
        $details['LastAccessTimeUtc'] = $file.LastAccessTimeUtc.ToString('yyyy-MM-dd HH:mm:ss.fff') + ' UTC'
        $details['Attributes'] = $file.Attributes.ToString()
        $details['IsReadOnly'] = $file.IsReadOnly
        $details['IsHidden'] = ($file.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0
        $details['IsSystem'] = ($file.Attributes -band [System.IO.FileAttributes]::System) -ne 0

        # NTFS Alternate Data Streams
        try {
            $streams = Get-Item -LiteralPath $FilePath -Stream * -ErrorAction SilentlyContinue
            $altStreams = $streams | Where-Object { $_.Stream -ne ':$DATA' }
            if ($altStreams) {
                $details['AlternateDataStreams'] = ($altStreams | ForEach-Object {
                    "$($_.Stream) ($($_.Length) bytes)"
                }) -join '; '
            } else {
                $details['AlternateDataStreams'] = 'None'
            }
        } catch {
            $details['AlternateDataStreams'] = 'Unable to enumerate'
        }

        # File hashes
        $details['HashingStarted'] = Get-FormattedTimestamp

        try {
            $sha256 = Get-FileHash -LiteralPath $FilePath -Algorithm SHA256
            $details['SHA256'] = $sha256.Hash
        } catch {
            $details['SHA256'] = "ERROR: $_"
        }

        try {
            $md5 = Get-FileHash -LiteralPath $FilePath -Algorithm MD5
            $details['MD5'] = $md5.Hash
        } catch {
            $details['MD5'] = "ERROR: $_"
        }

        try {
            $sha1 = Get-FileHash -LiteralPath $FilePath -Algorithm SHA1
            $details['SHA1'] = $sha1.Hash
        } catch {
            $details['SHA1'] = "ERROR: $_"
        }

        $details['HashingCompleted'] = Get-FormattedTimestamp
        $details['Status'] = 'Inventoried'

    } catch {
        $details['Status'] = 'Error'
        $details['Error'] = $_.Exception.Message
    }

    return $details
}

function Invoke-SecureDeletion {
    param([string[]]$FilePaths)

    $results = @{
        StartTime = Get-FormattedTimestamp
        FilesAttempted = $FilePaths.Count
        Command = "sdelete -accepteula -p $overwritePasses -nobanner"
        Output = ''
        ExitCode = $null
        EndTime = $null
    }

    $allOutput = New-Object System.Text.StringBuilder

    foreach ($filePath in $FilePaths) {
        $fileResult = @{
            Path = $filePath
            StartTime = Get-FormattedTimestamp
            Output = ''
            ExitCode = $null
            Success = $false
        }

        try {
            # Remove read-only attribute if present
            $file = Get-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
            if ($file -and $file.IsReadOnly) {
                $file.IsReadOnly = $false
                [void]$allOutput.AppendLine("Removed read-only attribute from: $filePath")
            }

            # Execute SDelete
            $output = & sdelete -accepteula -p $overwritePasses -nobanner "$filePath" 2>&1
            $fileResult['ExitCode'] = $LASTEXITCODE
            $fileResult['Output'] = $output -join "`n"
            $fileResult['Success'] = ($LASTEXITCODE -eq 0)

            [void]$allOutput.AppendLine("--- $filePath ---")
            [void]$allOutput.AppendLine($fileResult['Output'])
            [void]$allOutput.AppendLine("")

        } catch {
            $fileResult['Output'] = "EXCEPTION: $_"
            $fileResult['Success'] = $false
            [void]$allOutput.AppendLine("EXCEPTION processing $filePath : $_")
        }

        $fileResult['EndTime'] = Get-FormattedTimestamp
        $script:deletionLog += [PSCustomObject]$fileResult
    }

    $results['Output'] = $allOutput.ToString()
    $results['EndTime'] = Get-FormattedTimestamp

    return $results
}

function Test-FileDeleted {
    param([string]$FilePath)

    $result = @{
        Path = $FilePath
        VerifiedAt = Get-FormattedTimestamp
        Exists = $null
        Verified = $false
        Details = ''
    }

    try {
        $exists = Test-Path -LiteralPath $FilePath
        $result['Exists'] = $exists

        if (-not $exists) {
            $result['Verified'] = $true
            $result['Details'] = 'File confirmed deleted - path no longer exists'
        } else {
            $result['Verified'] = $false
            $result['Details'] = 'WARNING: File still exists after deletion attempt'
        }

        # Also check if parent directory still exists (for context)
        $parentDir = [System.IO.Path]::GetDirectoryName($FilePath)
        $result['ParentDirectoryExists'] = Test-Path -LiteralPath $parentDir

    } catch {
        $result['Details'] = "Verification error: $_"
    }

    return $result
}

function New-Certificate {
    param(
        [hashtable]$SystemInfo,
        [array]$FileInventory,
        [array]$DeletionLog,
        [array]$VerificationResults,
        [string]$SDeleteOutput
    )

    $cert = New-Object System.Text.StringBuilder

    # Header
    [void]$cert.AppendLine("================================================================================")
    if ($dryRun) {
        [void]$cert.AppendLine("              *** DRY RUN *** CERTIFICATE PREVIEW *** DRY RUN ***")
        [void]$cert.AppendLine("                         NO FILES WERE ACTUALLY DELETED")
    } else {
        [void]$cert.AppendLine("                    CERTIFICATE OF SECURE DATA DESTRUCTION")
    }
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine("Session ID        : $($SystemInfo['SessionId'])")
    [void]$cert.AppendLine("Generated         : $(Get-FormattedTimestamp)")
    if ($dryRun) {
        [void]$cert.AppendLine("Mode              : DRY RUN (Preview Only)")
    }
    [void]$cert.AppendLine("")

    # Case Information
    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    [void]$cert.AppendLine("CASE INFORMATION")
    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    [void]$cert.AppendLine("Operator Name     : $operatorName")
    if ($caseReference) {
        [void]$cert.AppendLine("Case Reference    : $caseReference")
    }
    if ($witnessName) {
        [void]$cert.AppendLine("Witness Name      : $witnessName")
    }
    [void]$cert.AppendLine("Target Path       : $targetPath")
    [void]$cert.AppendLine("Overwrite Passes  : $overwritePasses")
    [void]$cert.AppendLine("Method            : DoD 5220.22-M (via Microsoft SDelete)")
    [void]$cert.AppendLine("")

    # Summary
    $successCount = @($VerificationResults | Where-Object { $_.Verified -eq $true }).Count
    $failCount = @($VerificationResults | Where-Object { $_.Verified -ne $true }).Count

    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    if ($dryRun) {
        [void]$cert.AppendLine("DRY RUN SUMMARY (NO FILES DELETED)")
    } else {
        [void]$cert.AppendLine("DESTRUCTION SUMMARY")
    }
    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    [void]$cert.AppendLine("Session Start     : $($SystemInfo['SessionStart'])")
    [void]$cert.AppendLine("Session End       : $script:endTime")
    [void]$cert.AppendLine("Files Processed   : $($FileInventory.Count)")
    if ($dryRun) {
        [void]$cert.AppendLine("Files Inventoried : $($FileInventory.Count)")
        [void]$cert.AppendLine("Files Deleted     : 0 (Dry Run)")
        [void]$cert.AppendLine("Overall Status    : DRY RUN - PREVIEW ONLY")
    } else {
        [void]$cert.AppendLine("Files Destroyed   : $successCount")
        [void]$cert.AppendLine("Files Failed      : $failCount")
        [void]$cert.AppendLine("Overall Status    : $(if ($failCount -eq 0 -and $successCount -gt 0) { 'SUCCESSFUL' } else { 'INCOMPLETE - REVIEW REQUIRED' })")
    }
    [void]$cert.AppendLine("")

    # System Information
    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    [void]$cert.AppendLine("SYSTEM INFORMATION")
    [void]$cert.AppendLine("--------------------------------------------------------------------------------")
    [void]$cert.AppendLine("Computer Name     : $($SystemInfo['ComputerName'])")
    [void]$cert.AppendLine("Domain            : $($SystemInfo['Domain'])")
    [void]$cert.AppendLine("Executing User    : $($SystemInfo['UserDomainFull'])")
    [void]$cert.AppendLine("Operating System  : $($SystemInfo['OSName'])")
    [void]$cert.AppendLine("OS Version        : $($SystemInfo['OSVersion']) (Build $($SystemInfo['OSBuild']))")
    [void]$cert.AppendLine("OS Architecture   : $($SystemInfo['OSArchitecture'])")
    [void]$cert.AppendLine("Manufacturer      : $($SystemInfo['Manufacturer'])")
    [void]$cert.AppendLine("Model             : $($SystemInfo['Model'])")
    [void]$cert.AppendLine("Serial Number     : $($SystemInfo['SerialNumber'])")
    [void]$cert.AppendLine("Processor         : $($SystemInfo['Processor'])")
    [void]$cert.AppendLine("IP Address(es)    : $($SystemInfo['IPAddresses'])")
    [void]$cert.AppendLine("MAC Address(es)   : $($SystemInfo['MACAddresses'])")
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine("Target Drive      : $($SystemInfo['TargetDrive'])")
    [void]$cert.AppendLine("File System       : $($SystemInfo['TargetDriveFileSystem'])")
    [void]$cert.AppendLine("Volume Serial     : $($SystemInfo['TargetDriveSerial'])")
    [void]$cert.AppendLine("Physical Disk     : $($SystemInfo['PhysicalDiskModel'])")
    [void]$cert.AppendLine("Disk Serial       : $($SystemInfo['PhysicalDiskSerial'])")
    [void]$cert.AppendLine("Disk Interface    : $($SystemInfo['PhysicalDiskInterface'])")
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine("SDelete Version   : $($SystemInfo['SDeleteVersion'])")
    [void]$cert.AppendLine("SDelete Path      : $($SystemInfo['SDeletePath'])")
    [void]$cert.AppendLine("PowerShell Ver    : $($SystemInfo['PowerShellVersion'])")
    [void]$cert.AppendLine("")

    # File Inventory (Pre-Deletion)
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("FILE INVENTORY (PRE-DELETION)")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")

    $fileNum = 1
    foreach ($file in $FileInventory) {
        [void]$cert.AppendLine("--- FILE $fileNum of $($FileInventory.Count) ---")
        [void]$cert.AppendLine("Full Path         : $($file.FullPath)")
        [void]$cert.AppendLine("File Name         : $($file.Name)")
        [void]$cert.AppendLine("Directory         : $($file.Directory)")
        [void]$cert.AppendLine("Size (bytes)      : $($file.SizeFormatted)")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("SHA-256           : $($file.SHA256)")
        [void]$cert.AppendLine("SHA-1             : $($file.SHA1)")
        [void]$cert.AppendLine("MD5               : $($file.MD5)")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("Created           : $($file.CreationTime)")
        [void]$cert.AppendLine("Modified          : $($file.LastWriteTime)")
        [void]$cert.AppendLine("Accessed          : $($file.LastAccessTime)")
        [void]$cert.AppendLine("Attributes        : $($file.Attributes)")
        [void]$cert.AppendLine("Alt Data Streams  : $($file.AlternateDataStreams)")
        [void]$cert.AppendLine("Enumerated At     : $($file.EnumeratedAt)")
        [void]$cert.AppendLine("Hashing Completed : $($file.HashingCompleted)")
        [void]$cert.AppendLine("")
        $fileNum++
    }

    # Deletion Log
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("DELETION EXECUTION LOG")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine("Deletion Method   : Microsoft SDelete")
    [void]$cert.AppendLine("Overwrite Passes  : $overwritePasses")
    [void]$cert.AppendLine("Command Template  : sdelete -accepteula -p $overwritePasses -nobanner <filepath>")
    [void]$cert.AppendLine("")

    foreach ($entry in $DeletionLog) {
        [void]$cert.AppendLine("File: $($entry.Path)")
        [void]$cert.AppendLine("  Start Time  : $($entry.StartTime)")
        [void]$cert.AppendLine("  End Time    : $($entry.EndTime)")
        [void]$cert.AppendLine("  Exit Code   : $($entry.ExitCode)")
        [void]$cert.AppendLine("  Success     : $($entry.Success)")
        [void]$cert.AppendLine("")
    }

    # Verification Results
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("POST-DELETION VERIFICATION")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")

    foreach ($result in $VerificationResults) {
        [void]$cert.AppendLine("File: $($result.Path)")
        [void]$cert.AppendLine("  Verified At : $($result.VerifiedAt)")
        [void]$cert.AppendLine("  File Exists : $($result.Exists)")
        [void]$cert.AppendLine("  Verified    : $($result.Verified)")
        [void]$cert.AppendLine("  Details     : $($result.Details)")
        [void]$cert.AppendLine("")
    }

    # Raw SDelete Output
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("RAW SDELETE OUTPUT")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine($SDeleteOutput)
    [void]$cert.AppendLine("")

    # Notes
    if ($notes) {
        [void]$cert.AppendLine("================================================================================")
        [void]$cert.AppendLine("ADDITIONAL NOTES")
        [void]$cert.AppendLine("================================================================================")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine($notes)
        [void]$cert.AppendLine("")
    }

    # Attestation
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("ATTESTATION")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("")
    if ($dryRun) {
        [void]$cert.AppendLine("*** DRY RUN - NO SIGNATURE REQUIRED ***")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("This is a preview certificate generated in dry run mode.")
        [void]$cert.AppendLine("No files were actually deleted during this session.")
        [void]$cert.AppendLine("Run the script with `$dryRun = `$false to perform actual deletion.")
    } else {
        [void]$cert.AppendLine("I, the undersigned operator, attest that the above files were securely")
        [void]$cert.AppendLine("destroyed using the method and parameters specified in this certificate.")
        [void]$cert.AppendLine("The file hashes recorded above represent the exact content of each file")
        [void]$cert.AppendLine("immediately prior to destruction.")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("Operator Signature: _________________________________  Date: _______________")
        [void]$cert.AppendLine("")
        [void]$cert.AppendLine("Operator Name (Print): $operatorName")
        [void]$cert.AppendLine("")
        if ($witnessName) {
            [void]$cert.AppendLine("")
            [void]$cert.AppendLine("Witness Signature:  _________________________________  Date: _______________")
            [void]$cert.AppendLine("")
            [void]$cert.AppendLine("Witness Name (Print): $witnessName")
            [void]$cert.AppendLine("")
        }
    }
    [void]$cert.AppendLine("")
    [void]$cert.AppendLine("================================================================================")
    [void]$cert.AppendLine("                           END OF CERTIFICATE")
    [void]$cert.AppendLine("             Session ID: $($SystemInfo['SessionId'])")
    [void]$cert.AppendLine("================================================================================")

    return $cert.ToString()
}

function New-HtmlCertificate {
    param(
        [hashtable]$SystemInfo,
        [array]$FileInventory,
        [array]$DeletionLog,
        [array]$VerificationResults,
        [string]$SDeleteOutput
    )

    $successCount = @($VerificationResults | Where-Object { $_.Verified -eq $true }).Count
    $failCount = @($VerificationResults | Where-Object { $_.Verified -ne $true }).Count
    $overallStatus = if ($failCount -eq 0 -and $successCount -gt 0) { 'SUCCESSFUL' } else { 'INCOMPLETE - REVIEW REQUIRED' }
    $statusClass = if ($failCount -eq 0 -and $successCount -gt 0) { 'success' } else { 'warning' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$(if ($dryRun) { 'DRY RUN - ' })Certificate of Secure Data Destruction - $($SystemInfo['SessionId'])</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; max-width: 1000px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
        .certificate { background: white; border: 3px solid #1a365d; padding: 40px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 2px solid #1a365d; padding-bottom: 20px; margin-bottom: 30px; }
        .header h1 { color: #1a365d; font-size: 24px; margin-bottom: 10px; }
        .header .session-id { font-family: monospace; color: #666; font-size: 14px; }
        .dry-run-banner { background: #fef3c7; border: 2px solid #f59e0b; color: #92400e; padding: 15px; text-align: center; font-weight: bold; margin-bottom: 20px; font-size: 18px; }
        .section { margin-bottom: 30px; }
        .section h2 { background: #1a365d; color: white; padding: 10px 15px; font-size: 16px; margin-bottom: 15px; }
        .section h3 { color: #1a365d; border-bottom: 1px solid #ddd; padding-bottom: 5px; margin: 20px 0 10px 0; font-size: 14px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 15px; font-size: 13px; }
        th, td { padding: 8px 12px; text-align: left; border: 1px solid #ddd; }
        th { background: #f0f4f8; font-weight: 600; width: 200px; }
        td { font-family: monospace; word-break: break-all; }
        .hash { font-size: 11px; }
        .status-success { color: #166534; font-weight: bold; }
        .status-warning { color: #b45309; font-weight: bold; }
        .status-fail { color: #dc2626; font-weight: bold; }
        .status-dryrun { color: #6366f1; font-weight: bold; }
        .summary-box { background: #f0f4f8; padding: 20px; border-left: 4px solid #1a365d; margin-bottom: 20px; }
        .summary-box.success { border-left-color: #166534; }
        .summary-box.warning { border-left-color: #b45309; }
        .summary-box.dryrun { border-left-color: #6366f1; background: #eef2ff; }
        .file-block { border: 1px solid #ddd; margin-bottom: 20px; }
        .file-block .file-header { background: #f0f4f8; padding: 10px 15px; font-weight: bold; border-bottom: 1px solid #ddd; }
        .file-block .file-content { padding: 15px; }
        pre { background: #f8f9fa; padding: 15px; overflow-x: auto; font-size: 11px; border: 1px solid #ddd; white-space: pre-wrap; word-wrap: break-word; }
        .attestation { border: 2px solid #1a365d; padding: 30px; margin-top: 40px; }
        .attestation p { margin-bottom: 15px; }
        .signature-line { border-bottom: 1px solid #333; width: 300px; display: inline-block; margin: 0 10px; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 2px solid #1a365d; color: #666; font-size: 12px; }
        @media print { body { background: white; } .certificate { border: none; box-shadow: none; } }
    </style>
</head>
<body>
    <div class="certificate">
        $(if ($dryRun) { '<div class="dry-run-banner">*** DRY RUN - PREVIEW ONLY - NO FILES WERE DELETED ***</div>' })
        <div class="header">
            <h1>$(if ($dryRun) { 'DRY RUN PREVIEW: ' })CERTIFICATE OF SECURE DATA DESTRUCTION</h1>
            <div class="session-id">Session ID: $($SystemInfo['SessionId'])</div>
            <div>Generated: $(Get-FormattedTimestamp)</div>
            $(if ($dryRun) { '<div style="color: #6366f1; font-weight: bold; margin-top: 10px;">Mode: DRY RUN (Preview Only)</div>' })
        </div>

        <div class="summary-box $(if ($dryRun) { 'dryrun' } else { $statusClass })">
            <table>
                <tr><th>Overall Status</th><td class="$(if ($dryRun) { 'status-dryrun' } else { "status-$statusClass" })">$(if ($dryRun) { 'DRY RUN - PREVIEW ONLY' } else { $overallStatus })</td></tr>
                <tr><th>Files Processed</th><td>$($FileInventory.Count)</td></tr>
                <tr><th>$(if ($dryRun) { 'Files Inventoried' } else { 'Files Destroyed' })</th><td>$(if ($dryRun) { $FileInventory.Count } else { $successCount })</td></tr>
                $(if (-not $dryRun) { "<tr><th>Files Failed</th><td>$failCount</td></tr>" })
                <tr><th>Session Duration</th><td>$($SystemInfo['SessionStart']) to $script:endTime</td></tr>
            </table>
        </div>

        <div class="section">
            <h2>CASE INFORMATION</h2>
            <table>
                <tr><th>Operator Name</th><td>$operatorName</td></tr>
                $(if ($caseReference) { "<tr><th>Case Reference</th><td>$caseReference</td></tr>" })
                $(if ($witnessName) { "<tr><th>Witness Name</th><td>$witnessName</td></tr>" })
                <tr><th>Target Path</th><td>$targetPath</td></tr>
                <tr><th>Destruction Method</th><td>DoD 5220.22-M (via Microsoft SDelete)</td></tr>
                <tr><th>Overwrite Passes</th><td>$overwritePasses</td></tr>
            </table>
        </div>

        <div class="section">
            <h2>SYSTEM INFORMATION</h2>
            <h3>Computer Identity</h3>
            <table>
                <tr><th>Computer Name</th><td>$($SystemInfo['ComputerName'])</td></tr>
                <tr><th>Domain</th><td>$($SystemInfo['Domain'])</td></tr>
                <tr><th>Executing User</th><td>$($SystemInfo['UserDomainFull'])</td></tr>
                <tr><th>Serial Number</th><td>$($SystemInfo['SerialNumber'])</td></tr>
            </table>

            <h3>Operating System</h3>
            <table>
                <tr><th>OS Name</th><td>$($SystemInfo['OSName'])</td></tr>
                <tr><th>Version</th><td>$($SystemInfo['OSVersion']) (Build $($SystemInfo['OSBuild']))</td></tr>
                <tr><th>Architecture</th><td>$($SystemInfo['OSArchitecture'])</td></tr>
            </table>

            <h3>Hardware</h3>
            <table>
                <tr><th>Manufacturer</th><td>$($SystemInfo['Manufacturer'])</td></tr>
                <tr><th>Model</th><td>$($SystemInfo['Model'])</td></tr>
                <tr><th>Processor</th><td>$($SystemInfo['Processor'])</td></tr>
            </table>

            <h3>Network Identity</h3>
            <table>
                <tr><th>IP Address(es)</th><td>$($SystemInfo['IPAddresses'])</td></tr>
                <tr><th>MAC Address(es)</th><td>$($SystemInfo['MACAddresses'])</td></tr>
            </table>

            <h3>Target Storage</h3>
            <table>
                <tr><th>Target Drive</th><td>$($SystemInfo['TargetDrive'])</td></tr>
                <tr><th>File System</th><td>$($SystemInfo['TargetDriveFileSystem'])</td></tr>
                <tr><th>Volume Serial</th><td>$($SystemInfo['TargetDriveSerial'])</td></tr>
                <tr><th>Physical Disk</th><td>$($SystemInfo['PhysicalDiskModel'])</td></tr>
                <tr><th>Disk Serial</th><td>$($SystemInfo['PhysicalDiskSerial'])</td></tr>
                <tr><th>Disk Interface</th><td>$($SystemInfo['PhysicalDiskInterface'])</td></tr>
            </table>

            <h3>Deletion Tool</h3>
            <table>
                <tr><th>SDelete Version</th><td>$($SystemInfo['SDeleteVersion'])</td></tr>
                <tr><th>SDelete Path</th><td>$($SystemInfo['SDeletePath'])</td></tr>
                <tr><th>PowerShell Version</th><td>$($SystemInfo['PowerShellVersion'])</td></tr>
            </table>
        </div>

        <div class="section">
            <h2>FILE INVENTORY (PRE-DELETION)</h2>
"@

    $fileNum = 1
    foreach ($file in $FileInventory) {
        $verification = $VerificationResults | Where-Object { $_.Path -eq $file.FullPath }
        if ($dryRun) {
            $verifiedClass = 'dryrun'
            $verifiedText = 'WOULD DELETE'
        } else {
            $verifiedClass = if ($verification.Verified) { 'success' } else { 'fail' }
            $verifiedText = if ($verification.Verified) { 'DESTROYED' } else { 'FAILED' }
        }

        $html += @"
            <div class="file-block">
                <div class="file-header">File $fileNum of $($FileInventory.Count): $($file.Name) <span class="status-$verifiedClass">[$verifiedText]</span></div>
                <div class="file-content">
                    <table>
                        <tr><th>Full Path</th><td>$($file.FullPath)</td></tr>
                        <tr><th>Size</th><td>$($file.SizeFormatted) bytes</td></tr>
                        <tr><th>SHA-256</th><td class="hash">$($file.SHA256)</td></tr>
                        <tr><th>SHA-1</th><td class="hash">$($file.SHA1)</td></tr>
                        <tr><th>MD5</th><td class="hash">$($file.MD5)</td></tr>
                        <tr><th>Created</th><td>$($file.CreationTime)</td></tr>
                        <tr><th>Modified</th><td>$($file.LastWriteTime)</td></tr>
                        <tr><th>Accessed</th><td>$($file.LastAccessTime)</td></tr>
                        <tr><th>Attributes</th><td>$($file.Attributes)</td></tr>
                        <tr><th>Alternate Data Streams</th><td>$($file.AlternateDataStreams)</td></tr>
                        <tr><th>Enumerated At</th><td>$($file.EnumeratedAt)</td></tr>
                        <tr><th>Hashing Completed</th><td>$($file.HashingCompleted)</td></tr>
                        <tr><th>$(if ($dryRun) { 'Status' } else { 'Deletion Verified' })</th><td>$(if ($dryRun) { 'Dry Run - Not Deleted' } else { $verification.VerifiedAt })</td></tr>
                    </table>
                </div>
            </div>
"@
        $fileNum++
    }

    $escapedOutput = [System.Web.HttpUtility]::HtmlEncode($SDeleteOutput)

    $html += @"
        </div>

        <div class="section">
            <h2>RAW SDELETE OUTPUT</h2>
            <pre>$escapedOutput</pre>
        </div>
"@

    if ($notes) {
        $escapedNotes = [System.Web.HttpUtility]::HtmlEncode($notes)
        $html += @"
        <div class="section">
            <h2>ADDITIONAL NOTES</h2>
            <p>$escapedNotes</p>
        </div>
"@
    }

    $html += @"
        <div class="attestation">
            <h2 style="margin-bottom: 20px;">ATTESTATION</h2>
"@

    if ($dryRun) {
        $html += @"
            <p style="color: #6366f1; font-weight: bold; font-size: 16px;">*** DRY RUN - NO SIGNATURE REQUIRED ***</p>
            <p>This is a preview certificate generated in dry run mode. No files were actually deleted during this session.</p>
            <p>Run the script with <code>`$dryRun = `$false</code> to perform actual deletion and generate a valid certificate.</p>
"@
    } else {
        $html += @"
            <p>I, the undersigned operator, attest that the above files were securely destroyed using the method and parameters specified in this certificate. The file hashes recorded above represent the exact content of each file immediately prior to destruction.</p>

            <p style="margin-top: 40px;">
                Operator Signature: <span class="signature-line"></span> Date: <span class="signature-line" style="width: 150px;"></span>
            </p>
            <p>Operator Name (Print): <strong>$operatorName</strong></p>
"@

        if ($witnessName) {
            $html += @"
            <p style="margin-top: 30px;">
                Witness Signature: <span class="signature-line"></span> Date: <span class="signature-line" style="width: 150px;"></span>
            </p>
            <p>Witness Name (Print): <strong>$witnessName</strong></p>
"@
        }
    }

    $html += @"
        </div>

        <div class="footer">
            <strong>END OF CERTIFICATE$(if ($dryRun) { ' (DRY RUN PREVIEW)' })</strong><br>
            Session ID: $($SystemInfo['SessionId'])<br>
            Generated by Limehawk Secure Deletion Script v1.0.0
        </div>
    </div>
</body>
</html>
"@

    return $html
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Section "INPUT VALIDATION"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($targetPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Target path is required"
}

if ([string]::IsNullOrWhiteSpace($operatorName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Operator name is required for legal documentation"
}

if ($overwritePasses -lt 1 -or $overwritePasses -gt 35) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Overwrite passes must be between 1 and 35"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

# Check if target exists
if (-not (Test-Path -LiteralPath $targetPath)) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Target path does not exist: $targetPath"
    Write-Host ""
    Write-Host "Please verify the path and try again."
    exit 1
}

# Check if SDelete is available
$sdeleteAvailable = $null -ne (Get-Command sdelete -ErrorAction SilentlyContinue)

# If not in PATH, search common installation locations
if (-not $sdeleteAvailable) {
    $searchPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        "$env:ProgramFiles\SysinternalsSuite"
        "${env:ProgramFiles(x86)}\SysinternalsSuite"
    )

    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $found = Get-ChildItem -Path $searchPath -Filter 'sdelete.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $sdeleteDir = $found.DirectoryName
                $env:Path = "$sdeleteDir;$env:Path"
                Write-Host "Found SDelete at: $sdeleteDir"
                $sdeleteAvailable = $true
                break
            }
        }
    }
}

if (-not $sdeleteAvailable) {
    if ($autoInstallSDelete) {
        Write-Host "SDelete not found. Installing via winget..."

        # Check if winget is available
        $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        if (-not $wingetAvailable) {
            Write-Host ""
            Write-Host "[ ERROR OCCURRED ]"
            Write-Host "--------------------------------------------------------------"
            Write-Host "Winget is not available on this system."
            Write-Host "Please install SDelete manually from:"
            Write-Host "https://learn.microsoft.com/en-us/sysinternals/downloads/sdelete"
            exit 1
        }

        try {
            $installResult = winget install Microsoft.Sysinternals.SDelete --accept-source-agreements --accept-package-agreements 2>&1
            Write-Host $installResult

            # Refresh PATH and verify installation
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $sdeleteAvailable = $null -ne (Get-Command sdelete -ErrorAction SilentlyContinue)

            # If not in PATH, search common winget installation locations
            if (-not $sdeleteAvailable) {
                $searchPaths = @(
                    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
                    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
                    "$env:ProgramFiles\SysinternalsSuite"
                    "${env:ProgramFiles(x86)}\SysinternalsSuite"
                )

                foreach ($searchPath in $searchPaths) {
                    if (Test-Path $searchPath) {
                        $found = Get-ChildItem -Path $searchPath -Filter 'sdelete.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) {
                            $sdeleteDir = $found.DirectoryName
                            $env:Path = "$sdeleteDir;$env:Path"
                            Write-Host "Found SDelete at: $sdeleteDir"
                            $sdeleteAvailable = $true
                            break
                        }
                    }
                }
            }

            if (-not $sdeleteAvailable) {
                Write-Host ""
                Write-Host "[ ERROR OCCURRED ]"
                Write-Host "--------------------------------------------------------------"
                Write-Host "SDelete installation completed but sdelete.exe not found."
                Write-Host "Please install manually or add SDelete location to PATH."
                exit 1
            }

            Write-Host "SDelete installed successfully"
            Write-Host ""
        } catch {
            Write-Host ""
            Write-Host "[ ERROR OCCURRED ]"
            Write-Host "--------------------------------------------------------------"
            Write-Host "Failed to install SDelete: $_"
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Microsoft SDelete is not installed or not in PATH."
        Write-Host ""
        Write-Host "Install with: winget install Microsoft.Sysinternals.SDelete"
        Write-Host ""
        Write-Host "Or set `$autoInstallSDelete = `$true to install automatically."
        exit 1
    }
}

# Set default output directory
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    $outputDirectory = [Environment]::GetFolderPath('Desktop')
}

Write-Host "Target Path      : $targetPath"
Write-Host "Operator         : $operatorName"
if ($caseReference) { Write-Host "Case Reference   : $caseReference" }
if ($witnessName) { Write-Host "Witness          : $witnessName" }
Write-Host "Overwrite Passes : $overwritePasses"
Write-Host "Output Directory : $outputDirectory"
Write-Host "Recursive        : $recursive"
Write-Host "Dry Run          : $dryRun"
if ($dryRun) {
    Write-Host ""
    Write-Host "*** DRY RUN MODE - NO FILES WILL BE DELETED ***"
}
Write-Host ""
Write-Host "Validation passed"

# ==============================================================================
# INITIALIZE SESSION
# ==============================================================================

Write-Section "SESSION INITIALIZATION"

$script:sessionId = Get-SessionId
$script:startTime = Get-FormattedTimestamp

Write-Host "Session ID : $script:sessionId"
Write-Host "Started    : $script:startTime"

# ==============================================================================
# SYSTEM INFORMATION
# ==============================================================================

Write-Section "SYSTEM INFORMATION"

Write-Host "Collecting system information..."
$script:systemInfo = Get-SystemInformation

Write-Host "Computer   : $($script:systemInfo['ComputerName'])"
Write-Host "User       : $($script:systemInfo['UserDomainFull'])"
Write-Host "OS         : $($script:systemInfo['OSName'])"
Write-Host "SDelete    : $($script:systemInfo['SDeleteVersion'])"
Write-Host "Drive      : $($script:systemInfo['TargetDrive']) ($($script:systemInfo['TargetDriveFileSystem']))"

# ==============================================================================
# FILE ENUMERATION
# ==============================================================================

Write-Section "FILE ENUMERATION"

$filesToProcess = @()

if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    # Single file
    $filesToProcess += $targetPath
    Write-Host "Target is a single file"
} else {
    # Directory
    if ($recursive) {
        $filesToProcess = Get-ChildItem -LiteralPath $targetPath -File -Recurse -Force |
            Select-Object -ExpandProperty FullName
    } else {
        $filesToProcess = Get-ChildItem -LiteralPath $targetPath -File -Force |
            Select-Object -ExpandProperty FullName
    }
    Write-Host "Target is a directory (recursive: $recursive)"
}

Write-Host "Files found : $($filesToProcess.Count)"

if ($filesToProcess.Count -eq 0) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "No files found at target path."
    exit 1
}

# ==============================================================================
# PRE-DELETION HASHING
# ==============================================================================

Write-Section "PRE-DELETION HASHING"

Write-Host "Calculating hashes for all files..."
Write-Host "This may take a while for large files."
Write-Host ""

foreach ($filePath in $filesToProcess) {
    $fileName = [System.IO.Path]::GetFileName($filePath)
    Write-Host "Processing : $fileName"

    $fileDetails = Get-FileDetails -FilePath $filePath
    $script:fileInventory += [PSCustomObject]$fileDetails

    Write-Host "  SHA-256  : $($fileDetails.SHA256)"
    Write-Host "  Size     : $($fileDetails.SizeFormatted) bytes"
    Write-Host ""
}

Write-Host "Hashing complete for $($script:fileInventory.Count) files"

# ==============================================================================
# CONFIRMATION PROMPT
# ==============================================================================

Write-Section "CONFIRMATION"

if ($dryRun) {
    Write-Host "*** DRY RUN MODE ***"
    Write-Host ""
    Write-Host "The following files WOULD be destroyed (but won't be in dry run):"
    Write-Host ""
    foreach ($file in $script:fileInventory) {
        Write-Host "  - $($file.FullPath)"
    }
    Write-Host ""
    Write-Host "Proceeding with dry run - no files will be modified."
} else {
    Write-Host "WARNING: You are about to PERMANENTLY DESTROY the following files:"
    Write-Host ""
    foreach ($file in $script:fileInventory) {
        Write-Host "  - $($file.FullPath)"
    }
    Write-Host ""
    Write-Host "This action CANNOT be undone. The files will be overwritten"
    Write-Host "$overwritePasses times using the DoD 5220.22-M standard."
    Write-Host ""
    Write-Host "Type 'DELETE' to confirm and proceed, or anything else to abort:"
    Write-Host ""

    $confirmation = Read-Host "Confirmation"

    if ($confirmation -ne 'DELETE') {
        Write-Host ""
        Write-Host "[ ABORTED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Deletion cancelled by user."
        Write-Host "No files were modified."
        exit 0
    }
}

# ==============================================================================
# SECURE DELETION
# ==============================================================================

Write-Section "SECURE DELETION"

if ($dryRun) {
    Write-Host "*** DRY RUN MODE - SKIPPING ACTUAL DELETION ***"
    Write-Host ""
    Write-Host "Would execute: sdelete -accepteula -p $overwritePasses -nobanner <file>"
    Write-Host "Files that would be deleted: $($filesToProcess.Count)"
    Write-Host ""
    foreach ($filePath in $filesToProcess) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        Write-Host "  [WOULD DELETE] $fileName"

        # Create simulated deletion log entry
        $script:deletionLog += [PSCustomObject]@{
            Path = $filePath
            StartTime = Get-FormattedTimestamp
            EndTime = Get-FormattedTimestamp
            Output = 'DRY RUN - Deletion not performed'
            ExitCode = 0
            Success = $true
        }
    }
    $script:sdeleteOutput = "*** DRY RUN MODE ***`n`nNo files were actually deleted.`nSDelete was not executed.`n`nCommand that would have been used:`nsdelete -accepteula -p $overwritePasses -nobanner <filepath>"
} else {
    Write-Host "Executing SDelete with $overwritePasses passes..."
    Write-Host "Command : sdelete -accepteula -p $overwritePasses -nobanner <file>"
    Write-Host ""

    $deletionResults = Invoke-SecureDeletion -FilePaths $filesToProcess
    $script:sdeleteOutput = $deletionResults.Output

    Write-Host "SDelete execution completed"
    Write-Host "Files attempted : $($deletionResults.FilesAttempted)"
}

# ==============================================================================
# POST-DELETION VERIFICATION
# ==============================================================================

Write-Section "POST-DELETION VERIFICATION"

if ($dryRun) {
    Write-Host "*** DRY RUN MODE - FILES STILL EXIST ***"
    Write-Host ""

    foreach ($filePath in $filesToProcess) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $exists = Test-Path -LiteralPath $filePath

        $script:verificationResults += [PSCustomObject]@{
            Path = $filePath
            VerifiedAt = Get-FormattedTimestamp
            Exists = $exists
            Verified = $true  # In dry run, we mark as "verified" since no deletion was expected
            Details = 'DRY RUN - File intentionally not deleted'
            ParentDirectoryExists = $true
        }

        Write-Host "EXISTS   : $fileName (dry run - not deleted)"
    }

    Write-Host ""
    Write-Host "Dry run verification complete"
    Write-Host "All files remain intact"

    $successCount = $filesToProcess.Count
    $failCount = 0
} else {
    Write-Host "Verifying files have been deleted..."
    Write-Host ""

    foreach ($filePath in $filesToProcess) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $verification = Test-FileDeleted -FilePath $filePath
        $script:verificationResults += [PSCustomObject]$verification

        if ($verification.Verified) {
            Write-Host "VERIFIED : $fileName - DELETED"
        } else {
            Write-Host "FAILED   : $fileName - STILL EXISTS"
            $script:errorOccurred = $true
        }
    }

    Write-Host ""

    $successCount = @($script:verificationResults | Where-Object { $_.Verified -eq $true }).Count
    $failCount = @($script:verificationResults | Where-Object { $_.Verified -ne $true }).Count

    Write-Host "Verification complete"
    Write-Host "Successfully deleted : $successCount"
    Write-Host "Failed               : $failCount"
}

# ==============================================================================
# CERTIFICATE GENERATION
# ==============================================================================

Write-Section "CERTIFICATE GENERATION"

$script:endTime = Get-FormattedTimestamp

# Generate text certificate
$textCertificate = New-Certificate `
    -SystemInfo $script:systemInfo `
    -FileInventory $script:fileInventory `
    -DeletionLog $script:deletionLog `
    -VerificationResults $script:verificationResults `
    -SDeleteOutput $script:sdeleteOutput

$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$filePrefix = if ($dryRun) { 'SecureDeletion_DRYRUN' } else { 'SecureDeletion' }
$textCertPath = Join-Path $outputDirectory "${filePrefix}_$timestamp.txt"

$textCertificate | Out-File -FilePath $textCertPath -Encoding UTF8
Write-Host "Text certificate : $textCertPath"

# Generate HTML certificate if enabled
if ($generateHtml) {
    Add-Type -AssemblyName System.Web

    $htmlCertificate = New-HtmlCertificate `
        -SystemInfo $script:systemInfo `
        -FileInventory $script:fileInventory `
        -DeletionLog $script:deletionLog `
        -VerificationResults $script:verificationResults `
        -SDeleteOutput $script:sdeleteOutput

    $htmlCertPath = Join-Path $outputDirectory "${filePrefix}_$timestamp.html"
    $htmlCertificate | Out-File -FilePath $htmlCertPath -Encoding UTF8
    Write-Host "HTML certificate : $htmlCertPath"
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Section "FINAL STATUS"

if ($dryRun) {
    Write-Host "*** DRY RUN COMPLETE - NO FILES WERE DELETED ***"
    Write-Host ""
}

Write-Host "Session ID          : $script:sessionId"
Write-Host "Files Processed     : $($script:fileInventory.Count)"
if ($dryRun) {
    Write-Host "Files Inventoried   : $($script:fileInventory.Count)"
    Write-Host "Files Deleted       : 0 (Dry Run)"
} else {
    Write-Host "Files Deleted       : $successCount"
    Write-Host "Files Failed        : $failCount"
}
Write-Host "Certificate (Text)  : $textCertPath"
if ($generateHtml) {
    Write-Host "Certificate (HTML)  : $htmlCertPath"
}
Write-Host ""

if ($dryRun) {
    Write-Host "To perform actual deletion, set `$dryRun = `$false and run again."
} elseif ($failCount -gt 0) {
    Write-Host "WARNING: Some files could not be verified as deleted."
    Write-Host "Review the certificate for details."
}

Write-Section "SCRIPT COMPLETED"

if (-not $dryRun -and ($script:errorOccurred -or $failCount -gt 0)) {
    exit 1
} else {
    exit 0
}
