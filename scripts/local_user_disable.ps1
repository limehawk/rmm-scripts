$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Local User Disable                                         v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\local_user_disable.ps1
================================================================================
 FILE     : local_user_disable.ps1
 DESCRIPTION : Disables a local user account without deleting profile data
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Disables a local user account so it cannot be used to log in. The user
   profile and all data are preserved on disk. Use this for offboarding
   when data retention is required.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime variables

 REQUIRED INPUTS

   - $UsernameToDisable : Local username to disable (SuperOps runtime variable)

 SETTINGS

   - Logs off active sessions for the target user after disabling
   - Preserves user profile and all files

 BEHAVIOR

   1. Validates username input
   2. Checks user exists and current enabled status
   3. Disables the local user account
   4. Logs off any active sessions for that user
   5. Reports final status

 PREREQUISITES

   - Windows 10/11
   - Admin privileges required
   - PowerShell 5.1+

 SECURITY NOTES

   - Non-destructive — profile data is preserved
   - Account can be re-enabled with Enable-LocalUser
   - No secrets in logs

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Username : jsmith

   [RUN] OPERATION
   ==============================================================
   User found: jsmith
   Current status: Enabled
   Disabling account...
   Account disabled
   Checking active sessions...
   Logged off session ID 2

   [OK] RESULT
   ==============================================================
   Status   : Success
   Account  : Disabled
   Profile  : Preserved

   [OK] SCRIPT COMPLETE
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-19 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title, [string]$status = "INFO")
    Write-Host ""
    Write-Host ("[$status] $title")
    Write-Host ("=" * 62)
}

function PrintKV($label, $value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# ==== STATE ====
$errorOccurred = $false
$errorText = ""
$wasDisabled = $false
$sessionsLogged = 0

# ==== SUPEROPS RUNTIME VARIABLES ====
$Username = "$UsernameToDisable"

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($Username) -or $Username -eq '$' + 'UsernameToDisable') {
    $errorOccurred = $true
    $errorText = "- UsernameToDisable is required. Set this variable in SuperOps."
}

if ($errorOccurred) {
    Write-Section "INPUT VALIDATION FAILED" "ERROR"
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Section "INPUT VALIDATION" "INFO"
PrintKV "Username" $Username

Write-Section "OPERATION" "RUN"

try {
    # Check if user exists
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        throw "User account '$Username' not found on this system."
    }

    PrintKV "User found" $Username

    if ($user.Enabled) {
        PrintKV "Current status" "Enabled"

        # Disable the account
        Write-Host " Disabling account..."
        Disable-LocalUser -Name $Username -ErrorAction Stop
        $wasDisabled = $true
        PrintKV "Account" "Disabled"
    } else {
        PrintKV "Current status" "Already disabled"
    }

    # Log off active sessions for this user
    Write-Host " Checking active sessions..."
    $sessions = query user 2>$null | Where-Object { $_ -match "\b$Username\b" }

    if ($sessions) {
        foreach ($session in $sessions) {
            if ($session -match '\s+(\d+)\s+') {
                $sessionId = $Matches[1]
                logoff $sessionId 2>$null
                PrintKV "Logged off session" $sessionId
                $sessionsLogged++
            }
        }
    } else {
        PrintKV "Active sessions" "None"
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Section "OPERATION FAILED" "ERROR"
    Write-Host $errorText
}

Write-Section "RESULT" "OK"
if ($errorOccurred) {
    PrintKV "Status" "Failure"
} else {
    PrintKV "Status" "Success"
    if ($wasDisabled) {
        PrintKV "Account" "Disabled"
    } else {
        PrintKV "Account" "Already disabled (no change)"
    }
    PrintKV "Profile" "Preserved"
    PrintKV "Sessions logged off" $sessionsLogged
}

Write-Section "SCRIPT COMPLETE" "OK"

if ($errorOccurred) { exit 1 } else { exit 0 }
