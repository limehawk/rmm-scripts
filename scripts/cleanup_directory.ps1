<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : cleanup_directory.ps1
 VERSION  : 1.0.0
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE
 Cleans up files and directories older than a specified number of days.
 Logs deleted items to a file.

 REQUIRED INPUTS
 - $folderPath: The path to the folder to clean up.
 - $days: The number of days old a file must be to be deleted.

================================================================================
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Define variables
$folderPath = "$runtime_folderPath"  # The path to the folder you want to clean up
$days = $runtime_days                # The number of days old a file must be to be deleted
$logFilePath = Join-Path -Path $folderPath -ChildPath "deleted_files.log"  # Log file path

# Initialize log file with a header for this run
Add-Content -Path $logFilePath -Value "Cleanup Log - $(Get-Date)" -Force
Add-Content -Path $logFilePath -Value "-----------------------------------"

# Get all files in the specified folder and subfolders
$filesToDelete = Get-ChildItem -Path $folderPath -File -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$days) }

# Log and delete files
foreach ($file in $filesToDelete) {
    Add-Content -Path $logFilePath -Value "Deleted: $($file.FullName) - Last Modified: $($file.LastWriteTime)"
    Remove-Item -Path $file.FullName -Force
}

# Get all directories in the specified folder and subfolders
$dirsToDelete = Get-ChildItem -Path $folderPath -Directory -Recurse

# Remove empty directories
foreach ($dir in $dirsToDelete) {
    if (-Not (Get-ChildItem -Path $dir.FullName -Recurse)) {
        Add-Content -Path $logFilePath -Value "Deleted Directory: $($dir.FullName)"
        Remove-Item -Path $dir.FullName -Force
    }
}

# Log completion
Add-Content -Path $logFilePath -Value "Cleanup completed. Files and directories older than $days days have been removed from $folderPath."
Add-Content -Path $logFilePath -Value ""  # Add an empty line for readability