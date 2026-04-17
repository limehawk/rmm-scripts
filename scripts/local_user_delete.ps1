$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Local User Delete v1.3.2
 AUTHOR   : Limehawk.io
 DATE      : January 2026
 USAGE    : .\local_user_delete.ps1
================================================================================
 FILE     : local_user_delete.ps1
 DESCRIPTION : Deletes local user account and associated profile directory
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Deletes a local user account and its associated profile directory.
 Completely removes the user from the system including their files.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (username)
 2) WMI/CIM for profile removal

 REQUIRED INPUTS

 - Username : Username of the account to delete (via SuperOps $UsernameToDelete)
              Set to "listusers" to only list current users

 SETTINGS

 - Removes user profile via CIM (preferred method)
 - Falls back to direct filesystem removal if CIM fails
 - Lists users if no username provided or "listusers" specified

 BEHAVIOR

 1. If "listusers" mode: lists all local users and exits
 2. Validates user exists
 3. Removes user profile (CIM then filesystem fallback)
 4. Removes local user account
 5. Reports final status

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required
 - PowerShell 5.1+

 SECURITY NOTES

 - DESTRUCTIVE OPERATION - data cannot be recovered
 - No secrets in logs
 - Backup important data before running

 EXIT CODES

 - 0: Success
 - 1: Failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Username : tempuser

 [RUN] OPERATION
 ==============================================================
 Found user: tempuser
 Removing user profile...
 Profile removed via CIM
 Removing user account...
 User account removed

 [OK] RESULT
 ==============================================================
 Status : Success
 User   : tempuser (deleted)

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.3.2 Updated to two-line ASCII console output style
 2025-12-23 v1.3.1 Updated to Limehawk Script Framework
 2025-12-03 v1.3.0 Use descriptive runtime variable name ($UsernameToDelete)
 2025-12-03 v1.2.0 Standardize variable names ($Username instead of $UserToDelete); 2025-12-03 v1.1.0 Delete orphaned profiles even if user account doesn't exist; 2025-11-29 v1.0.0 Initial Style A implementation
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""
$profileRemoved = $false
$userRemoved = $false
$userExists = $false

# ==== HARDCODED INPUTS ====
$Username = "$UsernameToDelete"  # Set to "listusers" to list all users

# ==== HELPER FUNCTIONS ====

Set-StrictMode -Version Latest

function Show-LocalUsers {
    Write-Host ""
    Write-Host "[INFO] CURRENT LOCAL USERS"
    Write-Host "=============================================================="
    Get-LocalUser | ForEach-Object {
        $status = if ($_.Enabled) { "Enabled" } else { "Disabled" }
        Write-Host " $($_.Name.PadRight(20)) : $status"
    }
    Write-Host "=============================================================="
}

# ==== LIST USERS MODE ====
if ([string]::IsNullOrWhiteSpace($Username) -or $Username -eq "listusers" -or $Username -eq '$' + 'UsernameToDelete') {
    Show-LocalUsers
    Write-Host ""
    Write-Host "[OK] RESULT"
    Write-Host "=============================================================="
    Write-Host "Status : Listed users only"
    Write-Host "Action : Set Username variable to delete a user"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Username : $Username"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # Check if user exists
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "User account '$Username' not found (will still check for orphaned profile)"
        $userExists = $false
    } else {
        Write-Host "Found user: $Username"
        $userExists = $true
    }

    # Step 1: Remove user profile (even if user account doesn't exist)
    Write-Host "Checking for user profile..."

    # Try CIM method first (cleaner)
    $profile = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -like "*\$Username" }

    if ($profile) {
        try {
            Write-Host "Found profile via CIM, removing..."
            Remove-CimInstance $profile -ErrorAction Stop
            Write-Host "Profile removed via CIM"
            $profileRemoved = $true
        } catch {
            Write-Host "CIM removal failed, trying filesystem..."
        }
    }

    # Fallback: Direct filesystem removal
    if (-not $profileRemoved) {
        $profilePath = "$env:SystemDrive\Users\$Username"
        if (Test-Path $profilePath) {
            Write-Host "Found profile folder: $profilePath"
            Remove-Item -Path $profilePath -Recurse -Force -ErrorAction Stop
            Write-Host "Profile folder removed via filesystem"
            $profileRemoved = $true
        } else {
            Write-Host "No profile folder found"
        }
    }

    # Step 2: Remove user account (only if it exists)
    if ($userExists) {
        Write-Host "Removing user account..."
        Remove-LocalUser -Name $Username -ErrorAction Stop
        Write-Host "User account removed"
        $userRemoved = $true
    } else {
        Write-Host "Skipping user account removal (account doesn't exist)"
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
    Show-LocalUsers
}

Write-Host ""
Write-Host "[OK] RESULT"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Status  : Failure"
} elseif (-not $userExists -and -not $profileRemoved) {
    Write-Host "Status  : Nothing to delete"
    Write-Host "User    : Not found"
    Write-Host "Profile : Not found"
} else {
    Write-Host "Status  : Success"
    Write-Host "User    : $(if ($userRemoved) { 'Deleted' } else { 'Not found' })"
    Write-Host "Profile : $(if ($profileRemoved) { 'Removed' } else { 'Not found' })"
}

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "Deletion failed. See error above."
} elseif (-not $userExists -and -not $profileRemoved) {
    Write-Host "Nothing found for '$Username'."
} else {
    Write-Host "Cleanup complete for '$Username'."
    Write-Host "WARNING: This action cannot be undone."
}

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
