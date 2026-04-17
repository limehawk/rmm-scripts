Import-Module $SuperOpsModule
$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rename to Snake Case                                        v1.1.2
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\files_rename_snake_case.ps1
================================================================================
 FILE     : files_rename_snake_case.ps1
 DESCRIPTION : Recursively renames files and folders to snake_case format
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Recursively renames all files and folders in a directory to snake_case format.
 Converts spaces, hyphens, and other non-alphanumeric characters to underscores
 and lowercases all characters.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (target directory path)

 REQUIRED INPUTS

 - TargetPath : Directory path to process (recursive)

 SETTINGS

 - Converts to lowercase
 - Replaces non-alphanumeric characters with underscores
 - Trims leading/trailing underscores
 - Processes child items first (bottom-up) to avoid path issues

 BEHAVIOR

 1. Validates target directory exists
 2. Gets all files and folders recursively
 3. Reverses list (process children before parents)
 4. Renames each item to snake_case if different
 5. Reports each rename operation

 PREREQUISITES

 - Windows 10/11
 - Write permissions to target directory

 SECURITY NOTES

 - No secrets in logs
 - Only renames files/folders, does not modify content
 - Cannot be undone - backup important directories first

 EXIT CODES

 - 0: Success
 - 1: Failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Target Path : C:\Users\Example\Documents\MyFolder

 [RUN] OPERATION
 ==============================================================
 Processing 15 items...
 Renamed "My File.txt" to "my_file.txt"
 Renamed "Another-File.pdf" to "another_file.pdf"
 Renamed "Sub Folder" to "sub_folder"

 [OK] RESULT
 ==============================================================
 Status  : Success
 Renamed : 12 items
 Skipped : 3 items (already snake_case)

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.2 Updated to two-line ASCII console output style
 2026-01-14 v1.1.1 Added Import-Module for SuperOps placeholder support
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-29 v1.0.0 Initial Style A implementation
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""
$renamedCount = 0
$skippedCount = 0

# ==== HARDCODED INPUTS ====
$TargetPath = "$YourTargetPathHere"

# ==== HELPER FUNCTIONS ====

Set-StrictMode -Version Latest

function Convert-ToSnakeCase {
    param([string]$Name)

    # Replace all non-alphanumeric characters with underscores and convert to lowercase
    $snakeCaseName = $Name -replace '\W+', '_'
    $snakeCaseName = $snakeCaseName.ToLower()

    # Trim any leading or trailing underscores
    $snakeCaseName = $snakeCaseName.Trim('_')

    return $snakeCaseName
}

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- TargetPath is required."
}

if (-not $errorOccurred -and -not (Test-Path -Path $TargetPath -PathType Container)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- TargetPath does not exist or is not a directory: $TargetPath"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Target Path : $TargetPath"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # Get all items in the directory recursively
    $items = Get-ChildItem -Path $TargetPath -Recurse -ErrorAction Stop

    if ($items.Count -eq 0) {
        Write-Host "No items found in directory"
    } else {
        Write-Host "Processing $($items.Count) items..."

        # Reverse the list to rename child items first (bottom-up)
        [array]::Reverse($items)

        foreach ($item in $items) {
            $newName = Convert-ToSnakeCase -Name $item.Name
            $newPath = Join-Path -Path $item.Directory.FullName -ChildPath $newName

            # Rename the item if the new name is different from the old name
            if ($newName -ne $item.Name) {
                Rename-Item -Path $item.FullName -NewName $newName -Force -ErrorAction Stop
                Write-Host "Renamed `"$($item.Name)`" to `"$newName`""
                $renamedCount++
            } else {
                $skippedCount++
            }
        }
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] OPERATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] RESULT"
} else {
    Write-Host "[OK] RESULT"
}
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Status : Failure"
} else {
    Write-Host "Status  : Success"
    Write-Host "Renamed : $renamedCount items"
    Write-Host "Skipped : $skippedCount items (already snake_case)"
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] FINAL STATUS"
} else {
    Write-Host "[OK] FINAL STATUS"
}
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Snake case rename failed. See error above."
} else {
    Write-Host "All items in $TargetPath processed."
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] SCRIPT COMPLETED"
} else {
    Write-Host "[OK] SCRIPT COMPLETED"
}
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
