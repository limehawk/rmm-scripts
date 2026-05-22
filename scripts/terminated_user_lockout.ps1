$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Terminated User Lockout                                   v1.0.1
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\terminated_user_lockout.ps1
================================================================================
 FILE     : terminated_user_lockout.ps1
 DESCRIPTION : Immediately locks out a terminated user from the local workstation
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Performs a full local lockout for a terminated employee in a single pass.
   Locks the workstation, resets the local account password to a random value,
   disables the account, and forces logoff of all active sessions. Designed
   for immediate use during employee termination.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime variables

 REQUIRED INPUTS

   - $TerminatedUsername : Local username to lock out (SuperOps runtime variable)

 SETTINGS

   - Password is reset to a 32-character random string (unrecoverable)
   - Account is disabled after password reset
   - All active sessions are forcibly logged off
   - Workstation is locked if the user has an active console session
   - User profile and data are preserved on disk

 BEHAVIOR

   1. Validates username input
   2. Checks user exists on the local system
   3. Locks the workstation (if target user has active console session)
   4. Resets password to a random 32-character string
   5. Disables the local user account
   6. Logs off all active sessions for that user
   7. Reports final status

 PREREQUISITES

   - Windows 10/11
   - Admin privileges required
   - PowerShell 5.1+

 SECURITY NOTES

   - Non-destructive — profile data is preserved
   - Random password is never displayed or logged
   - Account can be re-enabled with Enable-LocalUser (new password required)

 ENDPOINTS

   Not applicable — local operations only

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Username : mkeeney

   [RUN] LOCKOUT
   ==============================================================
   User found               : mkeeney
   Current status           : Enabled
   Locking workstation...
   Workstation              : Locked
   Resetting password...
   Password                 : Reset (random)
   Disabling account...
   Account                  : Disabled
   Checking active sessions...
   Logged off session       : 2

   [OK] RESULT
   ==============================================================
   Status                   : Success
   Workstation              : Locked
   Password                 : Reset
   Account                  : Disabled
   Profile                  : Preserved
   Sessions logged off      : 1

   [OK] SCRIPT COMPLETE
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-22 v1.0.1 Enrich catch output; check logoff exit code
 2026-03-20 v1.0.0 Initial release
================================================================================
#>

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
$passwordReset = $false
$accountDisabled = $false
$workstationLocked = $false
$sessionsLogged = 0

# ==== SUPEROPS RUNTIME VARIABLES ====
$Username = "$TerminatedUsername"

# ==== VALIDATION ====

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Username) -or $Username -eq '$' + 'TerminatedUsername') {
    $errorOccurred = $true
    $errorText = "- TerminatedUsername is required. Set this variable in SuperOps."
}

if ($errorOccurred) {
    Write-Section "INPUT VALIDATION FAILED" "ERROR"
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Section "INPUT VALIDATION" "INFO"
PrintKV "Username" $Username

Write-Section "LOCKOUT" "RUN"

try {
    # Check if user exists
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        throw "User account '$Username' not found on this system."
    }

    PrintKV "User found" $Username
    PrintKV "Current status" $(if ($user.Enabled) { "Enabled" } else { "Already disabled" })

    # Lock workstation if the target user has an active console session
    $sessions = query user 2>$null | Where-Object { $_ -match "\b$Username\b" }
    if ($sessions) {
        Write-Host " Locking workstation..."
        rundll32.exe user32.dll,LockWorkStation
        $workstationLocked = $true
        PrintKV "Workstation" "Locked"
    }

    # Reset password to a random 32-character string
    Write-Host " Resetting password..."
    $randomChars = -join ((48..57) + (65..90) + (97..122) + (33, 35, 37, 42, 64) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    $securePassword = ConvertTo-SecureString -String $randomChars -AsPlainText -Force
    Set-LocalUser -Name $Username -Password $securePassword -ErrorAction Stop
    $passwordReset = $true
    PrintKV "Password" "Reset (random)"

    # Disable the account
    if ($user.Enabled) {
        Write-Host " Disabling account..."
        Disable-LocalUser -Name $Username -ErrorAction Stop
        $accountDisabled = $true
        PrintKV "Account" "Disabled"
    } else {
        PrintKV "Account" "Already disabled (no change)"
    }

    # Log off all active sessions
    Write-Host " Checking active sessions..."
    $sessions = query user 2>$null | Where-Object { $_ -match "\b$Username\b" }

    if ($sessions) {
        foreach ($session in $sessions) {
            if ($session -match '\s+(\d+)\s+') {
                $sessionId = $Matches[1]
                $logoffOutput = & logoff $sessionId 2>&1
                if ($LASTEXITCODE -eq 0) {
                    PrintKV "Logged off session" $sessionId
                    $sessionsLogged++
                } else {
                    PrintKV "[WARN] Logoff failed" "session $sessionId ($logoffOutput)"
                }
            }
        }
    } else {
        PrintKV "Active sessions" "None"
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
    $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
    $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
}

if ($errorOccurred) {
    Write-Section "LOCKOUT FAILED" "ERROR"
    Write-Host $errorText
}

Write-Section "RESULT" $(if ($errorOccurred) { "ERROR" } else { "OK" })
if ($errorOccurred) {
    PrintKV "Status" "Failure"
    PrintKV "Password reset" $(if ($passwordReset) { "Yes" } else { "No" })
    PrintKV "Account disabled" $(if ($accountDisabled) { "Yes" } else { "No" })
} else {
    PrintKV "Status" "Success"
    PrintKV "Workstation" $(if ($workstationLocked) { "Locked" } else { "No active console session" })
    PrintKV "Password" "Reset"
    PrintKV "Account" "Disabled"
    PrintKV "Profile" "Preserved"
    PrintKV "Sessions logged off" $sessionsLogged
}

Write-Section "SCRIPT COMPLETE" $(if ($errorOccurred) { "ERROR" } else { "OK" })

if ($errorOccurred) { exit 1 } else { exit 0 }
