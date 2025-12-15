# Import-Module <RequiredModule>
$ErrorActionPreference = 'Stop' # Rule 1: Enable early error mode (fail on any non-terminating error)

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT    : invoke_reboot_on_uptime.ps1
 VERSION   : v7.2.0
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE
 This script forces a system reboot if the current uptime exceeds a specified
 threshold in days OR if Windows reboot-pending flags are detected. It is
 designed as a routine maintenance task to ensure system stability and that
 pending updates are applied.

 DATA SOURCES & PRIORITY
 1) RMM literal text replacement ($maxuptimedays)
 2) Environment variable (MAXUPTIMEDAYS)
 3) Default (7 days)

 REQUIRED INPUTS
 - Max Uptime Days:
   - RMM Name: '$maxuptimedays' (literal text placeholder)
   - Env Name: 'MAXUPTIMEDAYS'
   - Constraints: Integer (1 or greater)
   - Default: 7

 SETTINGS (hardcoded in script)
 - $DefaultMaxUptimeDays : Default uptime threshold if RMM/env not set (7)
 - $CheckCBSRebootPending : Check Component Based Servicing flag ($true)
 - $CheckWURebootRequired : Check Windows Update flag ($true)
 - $CheckPendingFileRename : Check Pending File Rename Operations ($true)

 BEHAVIOR
 - Retrieves the system's last boot time to calculate current uptime in days.
 - Checks Windows registry for reboot-pending flags:
   - Component Based Servicing (CBS) RebootPending
   - Windows Update RebootRequired
   - Pending File Rename Operations (Session Manager)
 - Compares the current uptime against the resolved $MaxUptimeDays threshold.
 - If uptime exceeds the threshold OR reboot flags are detected, a forceful
   reboot is initiated.
 - If neither condition is met, a successful, non-action taken status is logged.

 PREREQUISITES
 - PowerShell 5.1+
 - Must be run with local Administrator rights to query CIM and reboot.
 - The SuperOps module import is expected on line 1, though not used.

 SECURITY NOTES
 - The script does not handle secrets or API keys.
 - The reboot command is forceful (`Restart-Computer -Force`) and will not
   prompt users to save their work. This is by design for automated execution.

 ENDPOINTS
 - Not applicable. This script performs local actions only.

 EXIT CODES
 - 0 success (reboot not required or reboot initiated).
 - 1 failure (input validation failed or a command failed to execute).

 EXAMPLE RUN (Style A) - Reboot triggered by pending flags
 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 Max Uptime Days          : 14
 Check CBS Pending        : Yes
 Check WU Required        : Yes
 Check File Rename        : Yes

 [ REBOOT FLAG CHECK ]
 --------------------------------------------------------------
 CBS RebootPending        : No
 WU RebootRequired        : Yes
 PendingFileRename        : No
 Reboot Flags Detected    : Yes

 [ UPTIME CHECK ]
 --------------------------------------------------------------
 Last Boot Time           : 2025-12-10T08:00:00
 Current Uptime (Days)    : 5
 Threshold (Days)         : 14
 Uptime Exceeded          : No

 [ REBOOT ACTION ]
 --------------------------------------------------------------
 Trigger                  : Reboot flags detected
 Result                   : INITIATING REBOOT

 [ FINAL STATUS ]
 --------------------------------------------------------------
 OPERATION COMPLETED SUCCESSFULLY (REBOOT INITIATED)

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2025-12-15  v7.2.0  Simplified configuration section to follow style guidelines.
                     Added toggle settings for each reboot flag check.
 2025-12-15  v7.0.0  Added reboot flag detection - script now reboots if uptime
                     threshold exceeded OR if Windows reboot-pending flags are
                     detected (CBS, Windows Update, PendingFileRenameOperations).
 2025-09-25  v6.0.0  FINAL FIX: Reverted conditional logic to robust IF/ELSEIF/ELSE structure
                     to ensure compatibility with PowerShell 5.1 and earlier, fixing the '?' operator error.
 2025-09-25  v5.0.1  Revised input resolution to assume RMM performs LITERAL TEXT REPLACEMENT,
                     simplifying the check for the $maxuptimedays variable.
 2025-09-25  v5.0.0  Code simplification using smarter ternary-like assignment and [WMI] accelerator.
 2025-09-25  v4.0.0  FINAL FIX: Eliminated the 'param()' keyword entirely to satisfy the highly constrained
                     RMM environment; input is now resolved RMM -> ENV -> Default.
 2025-09-25  v3.0.0  Massive simplification: Removed complex helper functions and implemented input resolution
                     using direct variable assignment priority chain.
 2025-09-25  v2.0.3  Encapsulated main logic in a function to isolate param() from large header block.
 2025-09-25  v2.0.2  Corrected $env:$EnvName syntax to use ${env:Name} for dynamic variable access.
 2025-09-25  v2.0.1  Fixed 'param' positioning for PowerShell parser compatibility.
 2025-09-25  v2.0.0  Adopted Limehawk Style A, implemented RMM-aware input resolution.
 2025-09-05  v1.0.1  Added ASCII block to highlight config options.
 2025-09-05  v1.0.0  Initial script creation.
================================================================================
#>

Set-StrictMode -Version Latest

# ==== HARDCODED INPUTS ====
$DefaultMaxUptimeDays   = 7
$CheckCBSRebootPending  = $true
$CheckWURebootRequired  = $true
$CheckPendingFileRename = $true
$RMMValue               = "`$maxuptimedays"

# ==== HELPER FUNCTIONS (Output Compliance) ====
function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62) # Rule 4: Exactly 62 hyphens
}
function PrintKV([string]$label, [string]$value) {
    # Rule 5: Fixed label padding to 24 characters with ' : ' separator.
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ==== INPUT RESOLUTION (RMM -> ENV -> Default) ====
# Priority: RMM variable > Environment variable > Default from CONFIGURATION section

$ResolvedInput = $null

# Check if the RMM value is usable (not null, not empty, and not the literal placeholder itself)
$isRMMValueUsable = -not [string]::IsNullOrWhiteSpace($RMMValue) -and ($RMMValue -notmatch '^\$\w+$')

if ($isRMMValueUsable) {
    # 1. RMM Variable (Highest Priority)
    $ResolvedInput = $RMMValue
}
elseif (-not [string]::IsNullOrWhiteSpace($env:MAXUPTIMEDAYS)) {
    # 2. Environment Variable
    $ResolvedInput = $env:MAXUPTIMEDAYS
}
else {
    # 3. Default from CONFIGURATION section
    $ResolvedInput = $DefaultMaxUptimeDays
}

# ==== VALIDATE AND CAST ====
$errors = @()
if (-not ([int]::TryParse($ResolvedInput, [ref]$null) -and [int]$ResolvedInput -ge 1)) {
    $errors += "MaxUptimeDays must be an integer of 1 or greater. Value provided: '$ResolvedInput'."
}
# Final cast to [int] for use in main logic
$MaxUptimeDays = [int]$ResolvedInput

# Handle validation failure
if ($errors.Count -gt 0) {
    Write-Section "ERROR OCCURRED"
    foreach ($e in $errors) { PrintKV "Message" $e }
    Write-Section "FINAL STATUS"
    Write-Host " INPUT VALIDATION FAILED"
    Write-Section "SCRIPT COMPLETED"
    exit 1
}

# --- Validation Success Output ---
Write-Section "INPUT VALIDATION"
PrintKV "Max Uptime Days" $MaxUptimeDays
PrintKV "Check CBS Pending"      $(if ($CheckCBSRebootPending) { "Yes" } else { "No" })
PrintKV "Check WU Required"      $(if ($CheckWURebootRequired) { "Yes" } else { "No" })
PrintKV "Check File Rename"      $(if ($CheckPendingFileRename) { "Yes" } else { "No" })

# ==== MAIN OPERATION ====
try {
    # --- Reboot Flag Detection ---
    Write-Section "REBOOT FLAG CHECK"

    # Check Component Based Servicing (CBS) RebootPending
    $cbsRebootPending = $false
    if ($CheckCBSRebootPending) {
        $cbsRebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    }

    # Check Windows Update RebootRequired
    $wuRebootRequired = $false
    if ($CheckWURebootRequired) {
        $wuRebootRequired = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    }

    # Check Pending File Rename Operations (non-empty value indicates pending reboot)
    $pendingFileRename = $false
    if ($CheckPendingFileRename) {
        $sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        if (Test-Path $sessionManagerPath) {
            $pendingOps = Get-ItemProperty -Path $sessionManagerPath -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
            if ($pendingOps -and $pendingOps.PendingFileRenameOperations) {
                $pendingFileRename = $true
            }
        }
    }

    # Determine if any reboot flags are set
    $rebootFlagsDetected = $cbsRebootPending -or $wuRebootRequired -or $pendingFileRename

    PrintKV "CBS RebootPending"      $(if (-not $CheckCBSRebootPending) { "Skipped" } elseif ($cbsRebootPending) { "Yes" } else { "No" })
    PrintKV "WU RebootRequired"      $(if (-not $CheckWURebootRequired) { "Skipped" } elseif ($wuRebootRequired) { "Yes" } else { "No" })
    PrintKV "PendingFileRename"      $(if (-not $CheckPendingFileRename) { "Skipped" } elseif ($pendingFileRename) { "Yes" } else { "No" })
    PrintKV "Reboot Flags Detected"  $(if ($rebootFlagsDetected) { "Yes" } else { "No" })

    # --- Uptime Check ---
    Write-Section "UPTIME CHECK"

    # Uptime Check: Using [WMI] type accelerator and direct property access.
    $bootObject = [WMI]'Win32_OperatingSystem= @'
    $bootTime   = $bootObject.ConvertToDateTime($bootObject.LastBootUpTime)
    $uptimeDays = ((Get-Date) - $bootTime).Days
    $bootTimeString = $bootTime.ToString('yyyy-MM-ddTHH:mm:ss')

    PrintKV "Last Boot Time"         $bootTimeString
    PrintKV "Current Uptime (Days)"  $uptimeDays
    PrintKV "Threshold (Days)"       $MaxUptimeDays

    $uptimeExceeded = $uptimeDays -gt $MaxUptimeDays
    PrintKV "Uptime Exceeded"        $(if ($uptimeExceeded) { "Yes" } else { "No" })

    # --- Reboot Decision ---
    if ($rebootFlagsDetected -or $uptimeExceeded) {
        Write-Section "REBOOT ACTION"

        # Determine trigger reason for logging
        if ($rebootFlagsDetected -and $uptimeExceeded) {
            PrintKV "Trigger" "Both: Reboot flags AND uptime exceeded"
        }
        elseif ($rebootFlagsDetected) {
            PrintKV "Trigger" "Reboot flags detected"
        }
        else {
            PrintKV "Trigger" "Uptime exceeds threshold"
        }

        PrintKV "Result" "INITIATING REBOOT"

        # Execute forceful reboot
        Restart-Computer -Force -ErrorAction Stop

        Write-Section "FINAL STATUS"
        Write-Host " OPERATION COMPLETED SUCCESSFULLY (REBOOT INITIATED)"
    }
    else {
        Write-Section "FINAL STATUS"
        Write-Host " NO REBOOT REQUIRED. Uptime within threshold and no pending flags."
    }

    Write-Section "SCRIPT COMPLETED"
    exit 0
}
catch {
    # ==== ERROR HANDLING ====
    Write-Section "ERROR OCCURRED"
    PrintKV "Step"          "Main Operation"
    PrintKV "Error Type"    $_.Exception.GetType().Name
    PrintKV "Error Message" $_.Exception.Message

    Write-Section "FINAL STATUS"
    Write-Host " OPERATION FAILED"

    Write-Section "SCRIPT COMPLETED"
    exit 1
}