$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search Everything Debug                                v1.0.1
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\file_search_everything_debug.ps1
================================================================================
 FILE     : file_search_everything_debug.ps1
 DESCRIPTION : Diagnoses parse error in file_search_everything.ps1 on SuperOps endpoints
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Temporary diagnostic script. Analyzes how SuperOps delivers script content
   to endpoints. Reads its own file to understand encoding and delivery, then
   searches all temp/script locations for the target script.

 DATA SOURCES & PRIORITY

   1) Own script file via $MyInvocation
   2) SuperOps scripts directory scan
   3) Temp directories scan

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - No configurable inputs required

 SETTINGS

   - Scans C:\ProgramData\Superops and common temp paths
   - Analyzes own file as a delivery reference

 BEHAVIOR

   1. Reports PowerShell version and execution context
   2. Reads and analyzes its own file (encoding, BOM, line count)
   3. Searches all likely locations for the target script
   4. Reports findings

 PREREQUISITES

   - PowerShell 5.1 or later

 SECURITY NOTES

   - Read-only operations, no modifications
   - No secrets in output

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Diagnostic complete

 EXAMPLE RUN

   [INFO] SUPEROPS SCRIPT DELIVERY DEBUG
   ==============================================================
   (diagnostic output)

 CHANGELOG

   2026-03-20 v1.0.1 Rewrite to analyze own file and search all paths
   2026-03-20 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

function Write-Section([string]$Type, [string]$Name) {
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

Write-Section 'info' 'SUPEROPS SCRIPT DELIVERY DEBUG'

# Execution context
Write-Host "  PowerShell : $($PSVersionTable.PSVersion)"
Write-Host "  User : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "  PID : $PID"

# What does PowerShell think this script is?
Write-Section 'run' 'SCRIPT IDENTITY'
Write-Host "  MyInvocation.MyCommand.Path : $($MyInvocation.MyCommand.Path)"
Write-Host "  MyInvocation.MyCommand.Definition : $($MyInvocation.MyCommand.Definition)"
Write-Host "  MyInvocation.MyCommand.Name : $($MyInvocation.MyCommand.Name)"
Write-Host "  MyInvocation.ScriptName : $($MyInvocation.ScriptName)"
Write-Host "  PSCommandPath : $PSCommandPath"
Write-Host "  PSScriptRoot : $PSScriptRoot"

# Try to read our own file
Write-Section 'run' 'SELF ANALYSIS'
$selfPath = $MyInvocation.MyCommand.Path
if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Definition }

if ($selfPath -and (Test-Path $selfPath)) {
    $rawBytes = [System.IO.File]::ReadAllBytes($selfPath)
    Write-Host "  Self Path : $selfPath"
    Write-Host "  File Size : $($rawBytes.Length) bytes"

    $bom = "No BOM"
    if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
        $bom = "UTF-8 BOM"
    } elseif ($rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0xFF -and $rawBytes[1] -eq 0xFE) {
        $bom = "UTF-16 LE BOM"
    } elseif ($rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0xFE -and $rawBytes[1] -eq 0xFF) {
        $bom = "UTF-16 BE BOM"
    }
    Write-Host "  BOM : $bom"
    Write-Host "  First 4 bytes (hex) : $(($rawBytes[0..3] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"

    $content = [System.IO.File]::ReadAllText($selfPath)
    $lineCount = ($content -split "`n").Count
    Write-Host "  Line Count : $lineCount"

    $crlfCount = ([regex]::Matches($content, "`r`n")).Count
    Write-Host "  CRLF Lines : $crlfCount"
} else {
    Write-Host "  Self Path : NOT AVAILABLE (script may be streamed, not file-based)"
    Write-Host "  This means SuperOps pipes content to PowerShell without writing a file"
}

# Search for any file_search_everything files anywhere in SuperOps paths
Write-Section 'run' 'FILE SEARCH ACROSS ALL PATHS'

$searchPaths = @(
    "C:\ProgramData\Superops"
    "C:\ProgramData\Superops\Scripts"
    $env:TEMP
    "$env:SystemRoot\Temp"
    "C:\Windows\Temp"
)

foreach ($searchPath in $searchPaths) {
    if (Test-Path $searchPath) {
        Write-Host ""
        Write-Host "  Scanning : $searchPath"
        $found = Get-ChildItem -Path $searchPath -Filter "file_search*" -Recurse -ErrorAction SilentlyContinue
        if ($found) {
            foreach ($f in $found) {
                Write-Host "    $($f.FullName) ($($f.Length) bytes, $($f.LastWriteTime))"
            }
        } else {
            Write-Host "    (none)"
        }
    }
}

# List ALL files in the SuperOps Scripts directory
Write-Section 'run' 'ALL FILES IN SUPEROPS SCRIPTS DIR'
$scriptsDir = "C:\ProgramData\Superops\Scripts"
if (Test-Path $scriptsDir) {
    $allFiles = Get-ChildItem -Path $scriptsDir -ErrorAction SilentlyContinue
    if ($allFiles) {
        foreach ($f in $allFiles) {
            Write-Host "  $($f.Name) ($($f.Length) bytes)"
        }
        Write-Host ""
        Write-Host "  Total : $($allFiles.Count) files"
    } else {
        Write-Host "  (empty directory)"
    }
} else {
    Write-Host "  Directory does not exist"
}

# List SuperOps processes
Write-Section 'run' 'SUPEROPS PROCESSES'
$soProcs = Get-Process -Name "*superops*","*rmm*" -ErrorAction SilentlyContinue
if ($soProcs) {
    foreach ($p in $soProcs) {
        Write-Host "  $($p.ProcessName) (PID $($p.Id)) : $($p.Path)"
    }
} else {
    Write-Host "  No SuperOps processes found"
}

# Check if PowerShell was invoked with -Command or -File
Write-Section 'run' 'POWERSHELL INVOCATION'
$parentProc = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue
if ($parentProc) {
    Write-Host "  CommandLine : $($parentProc.CommandLine)"
    $parentPid = $parentProc.ParentProcessId
    $parentParent = Get-CimInstance Win32_Process -Filter "ProcessId = $parentPid" -ErrorAction SilentlyContinue
    if ($parentParent) {
        Write-Host "  Parent Process : $($parentParent.Name) (PID $parentPid)"
        Write-Host "  Parent Command : $($parentParent.CommandLine)"
    }
}

Write-Section 'ok' 'DEBUG COMPLETE'
Write-Host "  Paste this entire output back to diagnose the issue"
exit 0
