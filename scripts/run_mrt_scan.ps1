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
 SCRIPT   : Windows Malicious Software Removal Tool (MRT) Scanner v1.1.0
 VERSION  : v1.1.0
================================================================================
 FILE     : run_mrt_scan.ps1
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Executes the built-in Windows Malicious Software Removal Tool (MRT.exe) with
 configurable scan mode. Designed for RMM deployment via SuperOps, allowing
 administrators to trigger Quick or Full silent scans on target endpoints.
 Displays scan status and log preview upon completion.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (scan mode defined within script body)
 2) MRT executable from Windows System32 directory
 3) MRT log file at %WINDIR%\debug\mrt.log

 REQUIRED INPUTS

 - $SuperOpsModule : Path to SuperOps module (injected by RMM; non-empty string)
 - $ScanMode       : Scan type - must be 'Quick' or 'Full' (case-insensitive)

 SUPEROPS SETTINGS

 This script uses RMM variable injection for the scan mode. Configure SuperOps
 to replace the $ScanMode value at runtime. No hardcoded subdomain or API keys.

 BEHAVIOR

 1. Validates administrative privileges are present
 2. Validates scan mode is 'Quick' or 'Full'
 3. Locates MRT.exe in system path
 4. Executes MRT with appropriate arguments (/Q for Quick, /F /Q for Full)
 5. Waits for scan completion (may take minutes to hours depending on mode)
 6. Displays last 50 lines of MRT log file for review
 7. Reports success or failure with detailed diagnostics

 PREREQUISITES

 - PowerShell 5.1 or later
 - Administrator privileges required
 - Windows OS with MRT.exe available (included in Windows by default)
 - SuperOps module available via $SuperOpsModule variable

 SECURITY NOTES

 - No secrets (API keys, passwords) are used or logged
 - Executes only signed Microsoft utility (MRT.exe)
 - Log output limited to last 50 lines to control data exposure
 - No network calls beyond what MRT.exe performs internally

 ENDPOINTS

 - N/A (MRT.exe handles its own update/reporting endpoints)

 EXIT CODES

 - 0 : Success - scan completed and log displayed
 - 1 : Failure - validation error, missing privileges, or execution failure

 EXAMPLE RUN

 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 SuperOpsModule   : C:\Program Files\SuperOps\Modules\SuperOps.psm1
 ScanMode         : Quick
 Admin Privileges : Confirmed

 [ SYSTEM INFO ]
 --------------------------------------------------------------
 Computer Name    : WKSTN-FIN-01
 MRT Path         : C:\WINDOWS\system32\MRT.exe
 MRT Version      : 5.129.22621.4602

 [ SCAN EXECUTION ]
 --------------------------------------------------------------
 Scan Type        : Quick
 Arguments        : /Q
 Status           : Running silent scan...
 Note             : This may take several minutes

 [ SCAN COMPLETE ]
 --------------------------------------------------------------
 Duration         : Scan process completed
 Exit Code        : 0

 [ LOG PREVIEW ]
 --------------------------------------------------------------
 Log Path         : C:\WINDOWS\debug\mrt.log
 Showing          : Last 50 lines
 -------------------------------------------------->
 Microsoft Windows Malicious Software Removal Tool v5.129
 Started On Fri Sep 12 10:24:17 2025

 Results Summary:
 ----------------
 No malicious software was detected.
 Finished On Fri Sep 12 10:28:45 2025
 <--------------------------------------------------

 [ FINAL STATUS ]
 --------------------------------------------------------------
 Result           : SUCCESS
 MRT scan completed successfully

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2025-11-29 v1.1.0 Refactored to Limehawk Style A with improved validation,
                   MRT version detection, process exit code capture, and
                   enhanced error handling.
 2025-09-12 v1.0.0 Initial release with Quick/Full scan modes.
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# STATE VARIABLES
# ============================================================================

$errorOccurred = $false
$errorText     = ""

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

# RMM Variable Injection: SuperOps replaces $QuickOrFull with 'Quick' or 'Full'
$ScanMode = $QuickOrFull

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

# Validate SuperOps module
if ([string]::IsNullOrWhiteSpace($SuperOpsModule)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOpsModule path is required (injected by RMM)"
}

# Validate scan mode
if ([string]::IsNullOrWhiteSpace($ScanMode)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- ScanMode is required (must be 'Quick' or 'Full')"
} elseif ($ScanMode -notmatch '^(Quick|Full)$') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- ScanMode must be 'Quick' or 'Full' (received: '$ScanMode')"
}

# Validate admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Script must be run with Administrator privileges"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure SuperOps module is configured in RMM environment"
    Write-Host "- Verify ScanMode variable is set to 'Quick' or 'Full'"
    Write-Host "- Run script with Administrator privileges"
    exit 1
}

Write-Host "SuperOpsModule   : $SuperOpsModule"
Write-Host "ScanMode         : $ScanMode"
Write-Host "Admin Privileges : Confirmed"

# ============================================================================
# SYSTEM INFO
# ============================================================================

Write-Host ""
Write-Host "[ SYSTEM INFO ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Computer Name    : $env:COMPUTERNAME"

# Locate MRT.exe
try {
    $mrtCommand = Get-Command mrt.exe -ErrorAction Stop
    $mrtPath = $mrtCommand.Source
    Write-Host "MRT Path         : $mrtPath"
} catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to locate MRT.exe"
    Write-Host ""
    Write-Host "Error Message:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- MRT.exe should be in C:\Windows\System32"
    Write-Host "- Verify Windows installation is not corrupted"
    Write-Host "- Run 'sfc /scannow' to repair system files"
    exit 1
}

# Get MRT version
try {
    $mrtVersion = (Get-Item $mrtPath).VersionInfo.ProductVersion
    if ($mrtVersion) {
        Write-Host "MRT Version      : $mrtVersion"
    }
} catch {
    Write-Host "MRT Version      : Unable to determine"
}

# ============================================================================
# SCAN EXECUTION
# ============================================================================

Write-Host ""
Write-Host "[ SCAN EXECUTION ]"
Write-Host "--------------------------------------------------------------"

# Build arguments based on scan mode
if ($ScanMode -eq 'Full') {
    $mrtArguments = '/F', '/Q'
    $scanNote = "This can take SEVERAL HOURS depending on disk size"
} else {
    $mrtArguments = '/Q'
    $scanNote = "This may take several minutes"
}

Write-Host "Scan Type        : $ScanMode"
Write-Host "Arguments        : $($mrtArguments -join ' ')"
Write-Host "Status           : Running silent scan..."
Write-Host "Note             : $scanNote"

try {
    $mrtProcess = Start-Process -FilePath $mrtPath -ArgumentList $mrtArguments -Wait -PassThru -ErrorAction Stop
    $mrtExitCode = $mrtProcess.ExitCode
} catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to execute MRT.exe"
    Write-Host ""
    Write-Host "Error Message:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "MRT Path:"
    Write-Host $mrtPath
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host ($mrtArguments -join ' ')
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify MRT.exe is not corrupted"
    Write-Host "- Check if another instance is already running"
    Write-Host "- Ensure sufficient system resources are available"
    exit 1
}

# ============================================================================
# SCAN COMPLETE
# ============================================================================

Write-Host ""
Write-Host "[ SCAN COMPLETE ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Duration         : Scan process completed"
Write-Host "Exit Code        : $mrtExitCode"

# MRT exit codes: 0 = no infection, other values may indicate issues
if ($mrtExitCode -ne 0) {
    Write-Host "Warning          : Non-zero exit code may indicate findings or errors"
}

# ============================================================================
# LOG PREVIEW
# ============================================================================

Write-Host ""
Write-Host "[ LOG PREVIEW ]"
Write-Host "--------------------------------------------------------------"

$logFilePath = "$env:windir\debug\mrt.log"
Write-Host "Log Path         : $logFilePath"

if (Test-Path $logFilePath) {
    Write-Host "Showing          : Last 50 lines"
    Write-Host " -------------------------------------------------->"
    try {
        $logContent = Get-Content $logFilePath -Tail 50 -ErrorAction Stop
        foreach ($line in $logContent) {
            Write-Host "  $line"
        }
    } catch {
        Write-Host "  (Unable to read log file: $($_.Exception.Message))"
    }
    Write-Host " <--------------------------------------------------"
} else {
    Write-Host "Status           : Log file not found"
    Write-Host ""
    Write-Host "Note: Log file may not exist if this is the first MRT run"
    Write-Host "or if MRT encountered an early error."
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Result           : SUCCESS"
Write-Host "MRT $ScanMode scan completed successfully"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
