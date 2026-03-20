$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search                                                 v4.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\file_search_everything.ps1
================================================================================
 FILE     : file_search_everything.ps1
 DESCRIPTION : Searches all fixed drives for files matching a pattern via NTFS MFT
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Searches all fixed NTFS drives by reading the Master File Table directly
   via fsutil. Much faster than Get-ChildItem because it reads the MFT
   sequentially instead of walking the directory tree. No third-party tools.

 DATA SOURCES & PRIORITY

   1) NTFS Master File Table via fsutil usn enumdata

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $searchPattern : Wildcard pattern (e.g., *landtrust*, *.pdf)

 SETTINGS

   - Searches all fixed NTFS drives (DriveType 3)
   - Resolves full paths only for matches (not entire MFT)

 BEHAVIOR

   1. Validates search pattern
   2. Enumerates all fixed drives
   3. Streams MFT entries via fsutil usn enumdata per drive
   4. Filters filenames inline using wildcard match
   5. Resolves full paths for matches via fsutil file queryfilenamebyid
   6. Outputs results

 PREREQUISITES

   - Windows 10/11 with NTFS volumes
   - Administrator privileges (required for MFT access)
   - PowerShell 5.1 or later

 SECURITY NOTES

   - Read-only MFT scan, no file contents accessed
   - May show entries for recently deleted files (MFT not yet overwritten)

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Search Pattern : *landtrust*

   [RUN] MFT SEARCH
   ==============================================================
   Scanning drive : C:
   Scanning drive : D:

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
 2026-03-20 v4.0.0 Rewrite using NTFS MFT via fsutil for fast search
 2026-03-20 v3.0.0 Native PowerShell Get-ChildItem approach
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

function Search-MFT([string]$Volume, [string]$Pattern) {
    $hits = [System.Collections.Generic.List[string]]::new()
    $currentFileName = $null
    $currentParentRef = $null

    fsutil usn enumdata 0 0 1 $Volume | ForEach-Object {
        if ($_ -match '^\s*File Name\s+:\s+(.+)') {
            $currentFileName = $Matches[1].Trim()
        }
        elseif ($_ -match '^\s*Parent File Ref#\s+:\s+(.+)') {
            $currentParentRef = $Matches[1].Trim()
            if ($currentFileName -like $Pattern) {
                $fullPath = $null
                try {
                    $resolved = fsutil file queryfilenamebyid $Volume $currentParentRef 2>&1
                    if ($resolved -match '\\\\[?\\]+(.+)') {
                        $fullPath = Join-Path $Matches[1] $currentFileName
                    }
                } catch {}
                if (-not $fullPath) {
                    $fullPath = "$Volume\<unresolved>\$currentFileName"
                }
                $hits.Add($fullPath)
            }
            $currentFileName = $null
            $currentParentRef = $null
        }
    }

    return $hits
}

try {
    Write-Section 'info' 'INPUT VALIDATION'
    if ([string]::IsNullOrWhiteSpace($searchPattern)) {
        throw "Search pattern is required"
    }
    Write-Host "  Search Pattern : $searchPattern"

    Write-Section 'run' 'MFT SEARCH'
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    $allResults = [System.Collections.Generic.List[string]]::new()

    foreach ($drive in $drives) {
        Write-Host "  Scanning drive : $drive"
        $results = Search-MFT -Volume $drive -Pattern $searchPattern
        if ($results.Count -gt 0) {
            $allResults.AddRange($results)
        }
    }

    Write-Section 'info' 'SEARCH RESULTS'
    if ($allResults.Count -gt 0) {
        foreach ($path in $allResults) {
            Write-Host "  $path"
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
