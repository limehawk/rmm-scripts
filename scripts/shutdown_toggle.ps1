$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Shutdown Toggle with Warning                                   v1.0.0
FILE   : shutdown_toggle.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Schedules a system shutdown with a warning message, or cancels an existing
    scheduled shutdown if one is already pending. Acts as a toggle - run once
    to schedule, run again to cancel.

REQUIRED INPUTS:
    $shutdownTime : Time in seconds before shutdown (default: 60)

BEHAVIOR:
    1. Checks if a shutdown is already scheduled
    2. If scheduled: Cancels the pending shutdown
    3. If not scheduled: Schedules a new shutdown with warning message
    4. User sees on-screen countdown before shutdown

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - shutdown.exe (standard Windows component)

SECURITY NOTES:
    - No secrets in logs
    - Shutdown can be canceled by running script again

EXIT CODES:
    0 = Success (shutdown scheduled or canceled)
    1 = Failure

EXAMPLE RUN (Scheduling):
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Shutdown Time : 60 seconds

    [ CHECKING SHUTDOWN STATUS ]
    --------------------------------------------------------------
    Pending Shutdown : None detected

    [ SCHEDULING SHUTDOWN ]
    --------------------------------------------------------------
    Command : shutdown /s /t 60
    Warning message displayed to user
    Shutdown scheduled in 60 seconds

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SHUTDOWN SCHEDULED
    Run this script again to cancel

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

EXAMPLE RUN (Canceling):
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Shutdown Time : 60 seconds

    [ CHECKING SHUTDOWN STATUS ]
    --------------------------------------------------------------
    Pending Shutdown : DETECTED

    [ CANCELING SHUTDOWN ]
    --------------------------------------------------------------
    Executing : shutdown /a
    Shutdown canceled successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SHUTDOWN CANCELED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$shutdownTime = 60  # Time in seconds before shutdown

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ($shutdownTime -lt 0 -or $shutdownTime -gt 315360000) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Shutdown time must be between 0 and 315360000 seconds"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ SCRIPT COMPLETED ]"
    Write-Host "--------------------------------------------------------------"
    exit 1
}

Write-Host "Shutdown Time : $shutdownTime seconds"

# ============================================================================
# CHECK FOR EXISTING SHUTDOWN
# ============================================================================
Write-Host ""
Write-Host "[ CHECKING SHUTDOWN STATUS ]"
Write-Host "--------------------------------------------------------------"

$existingShutdown = $false

try {
    # Try to abort any existing shutdown - if none exists, it will show a message
    $shutdownOutput = & shutdown /a 2>&1

    if ($shutdownOutput -match "No shutdown" -or $shutdownOutput -match "Unable to abort") {
        $existingShutdown = $false
        Write-Host "Pending Shutdown : None detected"
    }
    else {
        # If we successfully aborted, a shutdown was pending
        $existingShutdown = $true
        Write-Host "Pending Shutdown : DETECTED and CANCELED"
    }
}
catch {
    $existingShutdown = $false
    Write-Host "Pending Shutdown : None detected"
}

# ============================================================================
# TOGGLE SHUTDOWN
# ============================================================================
if ($existingShutdown) {
    # Shutdown was already canceled by the check above
    Write-Host ""
    Write-Host "[ SHUTDOWN CANCELED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Previous scheduled shutdown has been canceled"

    Write-Host ""
    Write-Host "[ FINAL STATUS ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Result : SHUTDOWN CANCELED"
}
else {
    # Schedule a new shutdown
    Write-Host ""
    Write-Host "[ SCHEDULING SHUTDOWN ]"
    Write-Host "--------------------------------------------------------------"

    try {
        $warningMessage = "System shutdown in $shutdownTime seconds. Run this script again to cancel."
        Write-Host "Command        : shutdown /s /t $shutdownTime"
        Write-Host "Warning        : $warningMessage"

        & shutdown /s /t $shutdownTime /c $warningMessage

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Shutdown scheduled successfully"
        }
        else {
            throw "shutdown command returned exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host ""
        Write-Host "[ ERROR OCCURRED ]"
        Write-Host "--------------------------------------------------------------"
        Write-Host "Failed to schedule shutdown"
        Write-Host "Error : $($_.Exception.Message)"
        exit 1
    }

    Write-Host ""
    Write-Host "[ FINAL STATUS ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Result : SHUTDOWN SCHEDULED"
    Write-Host "System will shutdown in $shutdownTime seconds"
    Write-Host "Run this script again to cancel"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
