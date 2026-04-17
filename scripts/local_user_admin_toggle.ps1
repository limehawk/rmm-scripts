$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Local Admin Toggle v1.2.2
 AUTHOR   : Limehawk.io
 DATE      : January 2026
 USAGE    : .\local_user_admin_toggle.ps1
================================================================================
 FILE     : local_user_admin_toggle.ps1
 DESCRIPTION : Adds or removes a local user from the Administrators group
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Adds or removes a local user from the Administrators group. Idempotent
 operation that ensures the user's group membership aligns with the
 requested action.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (username, action)

 REQUIRED INPUTS

 - Username : The local user account to manage (via SuperOps $TargetUsername)
 - Action   : "add" or "remove"

 SETTINGS

 - Operates on built-in Administrators group
 - Validates user exists before operation

 BEHAVIOR

 1. Validates user exists
 2. Checks current membership status
 3. Adds or removes from Administrators group
 4. Reports final status

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required
 - Target user must exist locally

 SECURITY NOTES

 - No secrets in logs
 - Modifies local group membership

 EXIT CODES

 - 0: Success
 - 1: Failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Username : john
 Action   : add

 [RUN] OPERATION
 ==============================================================
 User found: john
 Current membership: Not a member
 Adding to Administrators group...

 [OK] RESULT
 ==============================================================
 Status : Success
 Action : User added to Administrators

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.2.2 Updated to two-line ASCII console output style
 2025-12-23 v1.2.1 Updated to Limehawk Script Framework
 2025-12-03 v1.2.0 Use descriptive runtime variable name ($TargetUsername); 2025-12-03 v1.1.0 Add SuperOps runtime variable validation; 2025-11-29 v1.0.0 Initial Style A implementation
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""
$actionResult = ""

# ==== HARDCODED INPUTS ====
$Username = "$TargetUsername"
$Action = "add"  # "add" or "remove"

# ==== VALIDATION ====

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Username) -or $Username -eq '$' + 'TargetUsername') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Username is required (set via SuperOps runtime variable)."
}

if ($Action -ne "add" -and $Action -ne "remove") {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Action must be 'add' or 'remove'."
}

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Script must be run with administrator privileges."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Username : $Username"
Write-Host "Action   : $Action"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # Check if user exists
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        throw "User account '$Username' not found on this system."
    }
    Write-Host "User found: $Username"

    # Get Administrators group
    $adminGroup = Get-LocalGroup -Name "Administrators" -ErrorAction Stop

    # Check current membership
    $members = Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction SilentlyContinue
    $isMember = $false
    foreach ($member in $members) {
        if ($member.Name -like "*\$Username" -or $member.Name -eq $Username) {
            $isMember = $true
            break
        }
    }

    if ($isMember) {
        Write-Host "Current membership: Administrator"
    } else {
        Write-Host "Current membership: Not an administrator"
    }

    # Perform action
    switch ($Action) {
        "add" {
            if (-not $isMember) {
                Write-Host "Adding to Administrators group..."
                Add-LocalGroupMember -Group $adminGroup -Member $user -ErrorAction Stop
                $actionResult = "User added to Administrators"
            } else {
                $actionResult = "Already an administrator (no change)"
            }
        }
        "remove" {
            if ($isMember) {
                Write-Host "Removing from Administrators group..."
                Remove-LocalGroupMember -Group $adminGroup -Member $user -ErrorAction Stop
                $actionResult = "User removed from Administrators"
            } else {
                $actionResult = "Not an administrator (no change)"
            }
        }
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] OPERATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
}

Write-Host ""
Write-Host "[OK] RESULT"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Status : Failure"
} else {
    Write-Host "Status : Success"
    Write-Host "Action : $actionResult"
}

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Admin toggle operation failed. See error above."
} else {
    if ($Action -eq "add") {
        Write-Host "User '$Username' administrator status verified."
    } else {
        Write-Host "User '$Username' has been removed from administrators."
    }
}

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
