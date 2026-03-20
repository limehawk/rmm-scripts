$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search Everything Debug                                 v1.0.0
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

   Temporary diagnostic script. Reads the file_search_everything.ps1 file
   as deployed by SuperOps and reports encoding, line count, content around
   the error location (line 297), and brace balance. Remove after debugging.

 DATA SOURCES & PRIORITY

   1) Local filesystem - reads the deployed script file

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $targetScript : Path to the script to diagnose

 SETTINGS

   - Target : C:\ProgramData\Superops\Scripts\file_search_everything.ps1
   - Also checks for .ps1.ps1 double-extension variant

 BEHAVIOR

   1. Locates the target script file (checks both .ps1 and .ps1.ps1 paths)
   2. Reports file size, encoding, BOM, and line count
   3. Dumps lines around the error location (line 297)
   4. Counts open/close braces and reports balance
   5. Attempts to parse the file and reports any errors

 PREREQUISITES

   - PowerShell 5.1 or later
   - File must exist on the endpoint

 SECURITY NOTES

   - Read-only operations, no modifications
   - No secrets in output

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Diagnostic complete
   1 = Target file not found

 EXAMPLE RUN

   [INFO] FILE SEARCH EVERYTHING DEBUG
   ==============================================================
   (diagnostic output)

 CHANGELOG

   2026-03-20 v1.0.0 Initial release - temporary diagnostic
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

Write-Section 'info' 'FILE SEARCH EVERYTHING DEBUG'

# Check both possible paths
$scriptsDir = "C:\ProgramData\Superops\Scripts"
$candidates = @(
    Join-Path $scriptsDir "file_search_everything.ps1"
    Join-Path $scriptsDir "file_search_everything.ps1.ps1"
)

$targetScript = $null
foreach ($path in $candidates) {
    Write-Host "  Checking : $path"
    if (Test-Path $path) {
        Write-Host "  Found : YES"
        $targetScript = $path
        break
    } else {
        Write-Host "  Found : NO"
    }
}

# Also list all files in the scripts directory matching the name
Write-Host ""
Write-Host "  All matching files in $scriptsDir :"
$matchingFiles = Get-ChildItem -Path $scriptsDir -Filter "file_search*" -ErrorAction SilentlyContinue
if ($matchingFiles) {
    foreach ($f in $matchingFiles) {
        Write-Host "    $($f.Name)  ($($f.Length) bytes)"
    }
} else {
    Write-Host "    (none found)"
}

if (-not $targetScript) {
    Write-Section 'error' 'FILE NOT FOUND'
    Write-Host "  Neither .ps1 nor .ps1.ps1 variant found"
    exit 1
}

Write-Section 'run' 'FILE ANALYSIS'

# Read raw bytes for encoding detection
$rawBytes = [System.IO.File]::ReadAllBytes($targetScript)
Write-Host "  File Path : $targetScript"
Write-Host "  File Size : $($rawBytes.Length) bytes"

# Detect BOM
$bom = "No BOM (ASCII or UTF-8 without BOM)"
if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
    $bom = "UTF-8 BOM"
} elseif ($rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0xFF -and $rawBytes[1] -eq 0xFE) {
    $bom = "UTF-16 LE BOM"
} elseif ($rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0xFE -and $rawBytes[1] -eq 0xFF) {
    $bom = "UTF-16 BE BOM"
}
Write-Host "  BOM : $bom"

# Read content
$content = [System.IO.File]::ReadAllText($targetScript)
$lines = $content -split "`n"
Write-Host "  Line Count : $($lines.Count)"

# Check line endings
$crlfCount = ([regex]::Matches($content, "`r`n")).Count
$lfOnlyCount = ([regex]::Matches($content, "(?<!\r)`n")).Count
Write-Host "  CRLF Lines : $crlfCount"
Write-Host "  LF-Only : $lfOnlyCount"

# Brace counting (outside comment blocks)
Write-Section 'run' 'BRACE ANALYSIS'
$inComment = $false
$openBraces = 0
$closeBraces = 0
$braceStack = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].TrimEnd("`r")
    if ($line -match '^\s*<#') { $inComment = $true }
    if ($line -match '#>') { $inComment = $false; continue }
    if ($inComment) { continue }

    for ($j = 0; $j -lt $line.Length; $j++) {
        if ($line[$j] -eq '{') {
            $openBraces++
            $braceStack += ($i + 1)
        }
        if ($line[$j] -eq '}') {
            $closeBraces++
            if ($braceStack.Count -gt 0) {
                $braceStack = $braceStack[0..($braceStack.Count - 2)]
            } else {
                Write-Host "  UNMATCHED } at line $($i + 1): $line"
            }
        }
    }
}
Write-Host "  Open { : $openBraces"
Write-Host "  Close } : $closeBraces"
Write-Host "  Balanced : $(if ($openBraces -eq $closeBraces) { 'MATCHED' } else { 'UNBALANCED' })"
if ($braceStack.Count -gt 0) {
    Write-Host "  Unclosed { at lines: $($braceStack -join ', ')"
}

# Dump lines around error location
Write-Section 'run' 'CONTENT AROUND LINE 297'
$start = [Math]::Max(0, 290)
$end = [Math]::Min($lines.Count - 1, 305)
for ($i = $start; $i -le $end; $i++) {
    $lineContent = $lines[$i].TrimEnd("`r")
    # Show hex of first non-ASCII characters if any
    $hasNonAscii = $lineContent -match '[^\x00-\x7F]'
    $marker = if ($i -eq 296) { " <<<< ERROR LINE" } else { "" }
    Write-Host ("  {0,4}: {1}{2}" -f ($i + 1), $lineContent, $marker)
}

# Show first and last 5 lines
Write-Section 'run' 'FIRST 5 LINES'
for ($i = 0; $i -lt [Math]::Min(5, $lines.Count); $i++) {
    $lineContent = $lines[$i].TrimEnd("`r")
    Write-Host ("  {0,4}: {1}" -f ($i + 1), $lineContent)
}

Write-Section 'run' 'LAST 5 LINES'
$lastStart = [Math]::Max(0, $lines.Count - 5)
for ($i = $lastStart; $i -lt $lines.Count; $i++) {
    $lineContent = $lines[$i].TrimEnd("`r")
    Write-Host ("  {0,4}: {1}" -f ($i + 1), $lineContent)
}

# Attempt parse
Write-Section 'run' 'PARSE CHECK'
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($targetScript, [ref]$tokens, [ref]$errors)
if ($errors.Count -eq 0) {
    Write-Host "  Result : VALID (no errors)"
} else {
    Write-Host "  Result : ERRORS FOUND ($($errors.Count))"
    foreach ($err in $errors) {
        Write-Host "  Line $($err.Extent.StartLineNumber), Col $($err.Extent.StartColumnNumber): $($err.Message)"
    }
}

Write-Section 'ok' 'DEBUG COMPLETE'
exit 0
