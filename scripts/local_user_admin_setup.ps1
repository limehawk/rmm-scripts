$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Local User Admin Setup                                      v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : April 2026
 USAGE    : .\local_user_admin_setup.ps1
================================================================================
 FILE     : local_user_admin_setup.ps1
 DESCRIPTION : Creates a new local administrator account for employee onboarding
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Creates a new local administrator account intended for employee onboarding.
 The account is created with a blank password and configured to force a
 password change at first interactive logon. The account is visible on the
 Windows login screen so the new employee can select it and set their own
 password immediately.

 DATA SOURCES & PRIORITY

 1) SuperOps runtime variables (username and display name)

 REQUIRED INPUTS

 - $username  : Account username (via SuperOps $NewAdminUsername)
 - $fullName  : Display name shown on login screen (via SuperOps $NewAdminFullName)

 SETTINGS

 - Password: blank (empty SecureString) by design
 - Password change forced at first logon via net user /logonpasswordchg:yes
 - Account added to local Administrators group

 BEHAVIOR

 1. Validates that username and display name are provided
 2. Checks if the account already exists and fails if so (setup only, not reset)
 3. Creates local user with blank password using New-LocalUser
 4. Adds the account to the local Administrators group
 5. Forces password change at next logon via net user /logonpasswordchg:yes

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required (runs as SYSTEM via RMM)
 - PowerShell 5.1+
 - LocalAccounts module (built-in on Windows 10/11)

 SECURITY NOTES

 - Blank password is intentional for onboarding workflow
 - Windows policy restricts blank password logon to the physical console only
 - Network logon with blank password is blocked by default
 - Employee must set a password at first interactive logon
 - No secrets in logs

 ENDPOINTS

 - Not applicable

 EXIT CODES

 0 = Success
 1 = Failure (validation error, account exists, or creation failed)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
   Username  : jsmith
   Full Name : John Smith

 [RUN] CREATE ACCOUNT
 ==============================================================
   Account does not exist, proceeding...
   Creating account with blank password...
   Account created successfully

 [RUN] CONFIGURE ACCOUNT
 ==============================================================
   Adding to Administrators group...
   Added to Administrators group
   Setting password change at next logon...
   Password change flag set

 [OK] RESULT
 ==============================================================
   Status    : Success
   Username  : jsmith
   Full Name : John Smith
   Password  : (blank - change required at first logon)

 [OK] SCRIPT COMPLETED
 ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-04-08 v1.0.0 Initial release
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== HARDCODED INPUTS ====
$username = "$NewAdminUsername"
$fullName = "$NewAdminFullName"

# ==== HELPER FUNCTIONS ====

Set-StrictMode -Version Latest

function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    $label = $indicators[$Type]
    Write-Host ""
    Write-Host "[$label] $Name"
    Write-Host "=============================================================="
}

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($username) -or $username -eq '$' + 'NewAdminUsername') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$NewAdminUsername was not replaced."
}

if ([string]::IsNullOrWhiteSpace($fullName) -or $fullName -eq '$' + 'NewAdminFullName') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$NewAdminFullName was not replaced."
}

if ($errorOccurred) {
    Write-Section -Type 'error' -Name 'INPUT VALIDATION FAILED'
    Write-Host $errorText
    exit 1
}

Write-Section -Type 'info' -Name 'INPUT VALIDATION'
Write-Host "  Username  : $username"
Write-Host "  Full Name : $fullName"

# ==== CHECK FOR EXISTING ACCOUNT ====
Write-Section -Type 'run' -Name 'CREATE ACCOUNT'

$existingAccount = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
if ($existingAccount) {
    Write-Host "  [ERROR] Account '$username' already exists."
    Write-Host "  This script is for initial setup only, not account reset."

    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "  Account already exists. Use a different script to reset."
    exit 1
}

Write-Host "  Account does not exist, proceeding..."

# ==== CREATE ACCOUNT ====
try {
    Write-Host "  Creating account with blank password..."
    $blankPassword = New-Object System.Security.SecureString
    New-LocalUser -Name $username -Password $blankPassword -FullName $fullName -ErrorAction Stop | Out-Null
    Write-Host "  Account created successfully"
} catch {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host "  Failed to create account: $($_.Exception.Message)"

    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "  Account creation failed. See error above."
    exit 1
}

# ==== CONFIGURE ACCOUNT ====
Write-Section -Type 'run' -Name 'CONFIGURE ACCOUNT'

try {
    Write-Host "  Adding to Administrators group..."
    Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction Stop
    Write-Host "  Added to Administrators group"

    Write-Host "  Setting password change at next logon..."
    $netResult = & net user $username /logonpasswordchg:yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "net user /logonpasswordchg:yes failed: $netResult"
    }
    Write-Host "  Password change flag set"
} catch {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host "  Failed to configure account: $($_.Exception.Message)"
    Write-Host "  Rolling back account creation..."
    try {
        Remove-LocalUser -Name $username -ErrorAction Stop
        Write-Host "  Account removed. Safe to re-run this script."
    } catch {
        Write-Host "  [WARN] Rollback failed: $($_.Exception.Message)"
        Write-Host "  Manually remove account '$username' before re-running."
    }

    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host "  Account configuration failed. Account has been rolled back."
    exit 1
}

# ==== RESULT ====
Write-Section -Type 'ok' -Name 'RESULT'
Write-Host "  Status    : Success"
Write-Host "  Username  : $username"
Write-Host "  Full Name : $fullName"
Write-Host "  Admin     : Yes"
Write-Host "  Password  : (blank - change required at first logon)"

Write-Section -Type 'ok' -Name 'FINAL STATUS'
Write-Host "  Account '$username' created and ready for onboarding."
Write-Host "  Employee will be prompted to set a password at first logon."

Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'

exit 0
