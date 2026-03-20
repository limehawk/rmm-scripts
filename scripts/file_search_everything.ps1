$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search                                                 v3.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\file_search_everything.ps1
================================================================================
 FILE     : file_search_everything.ps1
 DESCRIPTION : Searches all fixed drives for files matching a pattern
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Searches all fixed local drives for files matching a wildcard pattern.
   Returns full paths of all matches. No third-party tools required.

 DATA SOURCES & PRIORITY

   1) Local filesystem via Get-ChildItem

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $searchPattern : Wildcard pattern (e.g., *landtrust*, *.pdf)

 SETTINGS

   - Searches all fixed drives (DriveType 3)
   - Skips inaccessible directories silently

 BEHAVIOR

   1. Validates search pattern
   2. Enumerates all fixed drives
   3. Recursively searches each drive for matching files
   4. Outputs full paths and total count

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges recommended for full access

 SECURITY NOTES

   - Read-only file system scan
   - No file contents are read or transmitted

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Search Pattern : *landtrust*

   [RUN] FILE SEARCH
   ==============================================================
   Scanning drive : C:\
   Scanning drive : D:\

   [INFO] SEARCH RESULTS
   ==============================================================
   C:\Users\jsmith\Documents\landtrust_agreement.pdf
   C:\Users\jsmith\Desktop\landtrust_docs\deed.pdf
   --------------------------------------------------------------
   Total Matches : 2

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-20 v3.0.0 Rewrite using native PowerShell - no third-party tools
 2026-03-20 v2.0.0 Simplified Everything-based version
 2026-03-20 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

$searchPattern = '*landtrust*'

function Write-Section([string]$Type, [string]$Name) {
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    Write-Host ""
    Write-Host "[$($indicators[$Type])] $Name"
    Write-Host "=============================================================="
}

try {
    Write-Section 'info' 'INPUT VALIDATION'
    if ([string]::IsNullOrWhiteSpace($searchPattern)) {
        throw "Search pattern is required"
    }
    Write-Host "  Search Pattern : $searchPattern"

    Write-Section 'run' 'FILE SEARCH'
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    $allResults = @()

    foreach ($drive in $drives) {
        $root = "$drive\"
        Write-Host "  Scanning drive : $root"
        $found = Get-ChildItem -Path $root -Filter $searchPattern -Recurse -File -ErrorAction SilentlyContinue
        if ($found) {
            $allResults += $found
        }
    }

    Write-Section 'info' 'SEARCH RESULTS'
    if ($allResults.Count -gt 0) {
        foreach ($file in $allResults) {
            Write-Host "  $($file.FullName)"
        }
        Write-Host "  --------------------------------------------------------------"
        Write-Host "  Total Matches : $($allResults.Count)"
    } else {
        Write-Host "  No files found matching : $searchPattern"
    }

    Write-Section 'ok' 'SCRIPT COMPLETED'
    exit 0
}
catch {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  $($_.Exception.Message)"
    exit 1
}
