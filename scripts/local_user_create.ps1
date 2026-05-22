$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Local User Create v1.2.5
 AUTHOR   : Limehawk.io
 DATE      : May 2026
 USAGE    : .\local_user_create.ps1
================================================================================
 FILE     : local_user_create.ps1
 DESCRIPTION : Creates local user account with optional administrator privileges
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Creates a new local user account with specified username and password.
 Optionally adds the user to the Administrators group.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (username, password, admin flag)

 REQUIRED INPUTS

 - Username    : Username for the new account (via SuperOps $NewUsername)
 - Password    : Password for the account (via SuperOps $NewPassword)
 - AddToAdmin  : "Yes" or "No" (default: "No")

 SETTINGS

 - Creates standard local user account
 - Optional administrator privileges

 BEHAVIOR

 1. Validates inputs
 2. Creates local user account
 3. Optionally adds to Administrators group
 4. Reports final status

 PREREQUISITES

 - Windows 10/11
 - Admin privileges required
 - PowerShell 5.1+

 SECURITY NOTES

 - Password visible in script - use RMM variables for production
 - No secrets logged to output

 EXIT CODES

 - 0: Success
 - 1: Failure

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Username    : newuser
 Add to Admin: No

 [RUN] OPERATION
 ==============================================================
 Creating user account...
 User created successfully

 [OK] RESULT
 ==============================================================
 Status : Success
 User   : newuser
 Admin  : No

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-22 v1.2.5 Set account display name (FullName) to the username
 2026-05-22 v1.2.4 Enrich catch output with exception type and failing line
 2026-05-22 v1.2.3 Reject username matching the computer name (Windows error 2253)
 2026-01-19 v1.2.2 Updated to two-line ASCII console output style
 2025-12-23 v1.2.1 Updated to Limehawk Script Framework
 2025-12-03 v1.2.0 Use descriptive runtime variable names ($NewUsername, $NewPassword)
 2025-12-03 v1.1.0 Use SuperOps runtime variables for all inputs; 2025-11-29 v1.0.0 Initial Style A implementation
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== HARDCODED INPUTS ====
$Username = "$NewUsername"
$Password = "$NewPassword"
$AddToAdmin = "No"  # "Yes" or "No"

# ==== VALIDATION ====

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Username) -or $Username -eq '$' + 'NewUsername') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Username is required (set via SuperOps runtime variable)."
}

if ($Username -eq $env:COMPUTERNAME) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Username cannot match the computer name '$env:COMPUTERNAME' (Windows rejects this with error 2253)."
}

if ([string]::IsNullOrWhiteSpace($Password) -or $Password -eq '$' + 'NewPassword') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Password is required (set via SuperOps runtime variable)."
}

if ($AddToAdmin -ne "Yes" -and $AddToAdmin -ne "No") {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- AddToAdmin must be 'Yes' or 'No'."
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
Write-Host "Username     : $Username"
Write-Host "Add to Admin : $AddToAdmin"

Write-Host ""
Write-Host "[RUN] OPERATION"
Write-Host "=============================================================="

try {
    # Check if user already exists
    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($existingUser) {
        throw "User '$Username' already exists on this system."
    }

    # Create the user
    Write-Host "Creating user account..."
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $securePassword -FullName $Username -Description "User created via RMM" -ErrorAction Stop | Out-Null
    Write-Host "User created successfully"

    # Add to Administrators if requested
    if ($AddToAdmin -eq "Yes") {
        Write-Host "Adding to Administrators group..."
        Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
        Write-Host "Added to Administrators group"
    }

} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
    $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
    $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
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
    Write-Host "User   : $Username"
    Write-Host "Admin  : $AddToAdmin"
}

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "User creation failed. See error above."
} else {
    Write-Host "User '$Username' has been created successfully."
    if ($AddToAdmin -eq "Yes") {
        Write-Host "User has administrator privileges."
    } else {
        Write-Host "User is a standard user (no admin privileges)."
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
