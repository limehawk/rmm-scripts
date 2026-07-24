$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Windows LAPS Entra Configure                                 v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\windows_laps_entra_configure.ps1
================================================================================
 FILE     : windows_laps_entra_configure.ps1
 DESCRIPTION : Configures Windows LAPS to back up the local admin password to Entra ID
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

 Configures the built-in Windows LAPS client to rotate the local
 administrator password and escrow it to Microsoft Entra ID. Applies the
 LAPS policy via the registry, forces an immediate policy processing pass,
 and reports the result from the LAPS operational event log so the tech can
 see whether the Entra escrow succeeded or is pending. Works on Entra ID
 Free (Microsoft 365 Business Standard) - no Intune subscription required.

 IMPORTANT: The tenant-side setting "Enable Microsoft Entra Local
 Administrator Password Solution (LAPS)" must be set to Yes in the Entra
 admin center (Devices -> Device settings) for the password to actually
 escrow to Entra ID. Without it, the client applies the policy but the
 escrow stays pending and the operational log reports a failure until the
 tenant toggle is flipped.

 DATA SOURCES & PRIORITY

 1) Hardcoded values (defined within the script body)
 2) dsregcmd /status (Entra join state detection)
 3) Microsoft-Windows-LAPS/Operational event log (result reporting)

 REQUIRED INPUTS

 All inputs are hardcoded in the script body:
   - $BackupDirectory: Password backup target. 0 = disabled, 1 = Entra ID,
     2 = Active Directory. Default 1 (Entra ID).
   - $PasswordAgeDays: Maximum password age in days before rotation.
     Default 30.
   - $PasswordLength: Managed password length in characters (8-64).
     Default 20.
   - $PasswordComplexity: Character set. 1 = large letters, 2 = large +
     small letters, 3 = large + small + numbers, 4 = large + small +
     numbers + specials. Default 4.
   - $AdministratorAccountName: Account to manage. Empty string = the
     built-in Administrator (by well-known RID); a name = that account.
     Default '' (built-in Administrator).
   - $PasswordEncryptionEnabled: 1 = encrypt the escrowed password (Entra
     ID always encrypts). Default 1.

 SETTINGS

 - Registry policy path : HKLM\SOFTWARE\Microsoft\Policies\LAPS
 - BackupDirectory      : written as DWORD
 - PasswordAgeDays       : written as DWORD
 - PasswordLength        : written as DWORD
 - PasswordComplexity    : written as DWORD
 - PasswordEncryptionEnabled : written as DWORD
 - AdministratorAccountName  : written as String, ONLY when non-empty

 BEHAVIOR

 The script performs the following actions in order:
 1. Validates the hardcoded input values
 2. Confirms the Windows LAPS client is present
    (Invoke-LapsPolicyProcessing)
 3. Detects Entra join state via dsregcmd /status (warns if not joined)
 4. Writes the LAPS policy values to the registry
 5. Forces an immediate LAPS policy processing pass
 6. Reads the LAPS operational event log and surfaces the latest status

 PREREQUISITES

 - Windows 11, or Windows 10 patched with the April 2023 (or later)
   cumulative update that ships the Windows LAPS client
 - Administrator privileges (RMM runs as SYSTEM)
 - Device joined to Microsoft Entra ID
 - Tenant setting "Enable Microsoft Entra Local Administrator Password
   Solution (LAPS)" = Yes (Entra admin center -> Devices -> Device
   settings)

 SECURITY NOTES

 - No secrets in logs (the managed password is never read or printed)
 - Escrowed passwords are stored encrypted in Entra ID
 - Disabling or weakening the policy reduces local-account security

 ENDPOINTS

 - Not applicable (policy is applied locally; escrow traffic is handled by
   the Entra-joined device, not this script)

 EXIT CODES

 0 = Success
 1 = Failure (error occurred)

 EXAMPLE RUN

 [INFO] INPUT VALIDATION
 ==============================================================
 Backup Directory    : 1 (Entra ID)
 Password Age Days   : 30
 Password Length     : 20
 Password Complexity : 4
 Admin Account       : (built-in Administrator)
 Password Encryption : 1

 [INFO] PREFLIGHT
 ==============================================================
 Windows LAPS client : Present
 Entra Joined        : YES

 [RUN] APPLY POLICY
 ==============================================================
 Set BackupDirectory = 1
 Set PasswordAgeDays = 30
 Set PasswordLength = 20
 Set PasswordComplexity = 4
 Set PasswordEncryptionEnabled = 1

 [RUN] PROCESS POLICY
 ==============================================================
 Forcing LAPS policy processing...
 Policy processing invoked

 [INFO] RESULT
 ==============================================================
 Latest LAPS event : The password for the managed account was
 successfully updated in Microsoft Entra ID.

 [OK] FINAL STATUS
 ==============================================================
 Status : Success
 LAPS Entra configuration applied

 [OK] SCRIPT COMPLETED
 ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-23 v1.0.0 Initial release
================================================================================
#>

# ==== HARDCODED INPUTS ====
$BackupDirectory           = 1     # 0 = disabled, 1 = Entra ID, 2 = Active Directory
$PasswordAgeDays           = 30    # Max password age in days before rotation
$PasswordLength            = 20    # Managed password length (8-64)
$PasswordComplexity        = 4     # 1=upper, 2=+lower, 3=+numbers, 4=+specials
$AdministratorAccountName  = ''    # '' = built-in Administrator; a name = that account
$PasswordEncryptionEnabled = 1     # 1 = encrypt escrowed password (Entra always encrypts)

Set-StrictMode -Version Latest

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== ADMIN CHECK ====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[ERROR] PRIVILEGES REQUIRED"
    Write-Host "=============================================================="
    Write-Host "Script requires admin privileges."
    Write-Host "Please relaunch as Administrator."
    exit 1
}

# ==== INPUT VALIDATION ====
if ($BackupDirectory -notin @(0, 1, 2)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- BackupDirectory must be 0, 1, or 2"
}
if ($PasswordAgeDays -lt 1) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- PasswordAgeDays must be at least 1"
}
if ($PasswordLength -lt 8 -or $PasswordLength -gt 64) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- PasswordLength must be between 8 and 64"
}
if ($PasswordComplexity -notin @(1, 2, 3, 4)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- PasswordComplexity must be 1, 2, 3, or 4"
}
if ($PasswordEncryptionEnabled -notin @(0, 1)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- PasswordEncryptionEnabled must be 0 or 1"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status : Failure"
    exit 1
}

$backupLabel = switch ($BackupDirectory) {
    0 { "0 (Disabled)" }
    1 { "1 (Entra ID)" }
    2 { "2 (Active Directory)" }
}
$accountLabel = if ([string]::IsNullOrWhiteSpace($AdministratorAccountName)) {
    "(built-in Administrator)"
} else {
    $AdministratorAccountName
}

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Backup Directory    : $backupLabel"
Write-Host "Password Age Days   : $PasswordAgeDays"
Write-Host "Password Length     : $PasswordLength"
Write-Host "Password Complexity : $PasswordComplexity"
Write-Host "Admin Account       : $accountLabel"
Write-Host "Password Encryption : $PasswordEncryptionEnabled"

# ==== PREFLIGHT ====
Write-Host ""
Write-Host "[INFO] PREFLIGHT"
Write-Host "=============================================================="

# Windows LAPS client presence (built into Win11 / patched Win10)
$lapsCmd = Get-Command Invoke-LapsPolicyProcessing -ErrorAction SilentlyContinue
if (-not $lapsCmd) {
    Write-Host "Windows LAPS client : Not found"
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "The Windows LAPS client (Invoke-LapsPolicyProcessing) is not"
    Write-Host "available on this device. Windows LAPS ships with Windows 11 and"
    Write-Host "with Windows 10 patched to the April 2023 (or later) cumulative"
    Write-Host "update. Patch the device and retry."
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status : Failure"
    exit 1
}
Write-Host "Windows LAPS client : Present"

# Entra join state via dsregcmd /status (warn only - policy still applies)
$entraJoined = $false
try {
    $dsregOutput = dsregcmd /status 2>$null
    $azureAdLine = $dsregOutput | Select-String -Pattern 'AzureAdJoined\s*:\s*YES' -SimpleMatch:$false
    if ($azureAdLine) {
        $entraJoined = $true
    }
} catch {
    $entraJoined = $false
}

if ($entraJoined) {
    Write-Host "Entra Joined        : YES"
} else {
    Write-Host "Entra Joined        : NO"
    Write-Host "[WARN] Device is not joined to Microsoft Entra ID."
    Write-Host "[WARN] The local policy will be applied, but the password will"
    Write-Host "[WARN] NOT escrow to Entra ID until the device is Entra-joined."
}

# ==== APPLY POLICY ====
Write-Host ""
Write-Host "[RUN] APPLY POLICY"
Write-Host "=============================================================="

$lapsPolicyPath = "HKLM:\SOFTWARE\Microsoft\Policies\LAPS"

try {
    if (-not (Test-Path $lapsPolicyPath)) {
        New-Item -Path $lapsPolicyPath -Force | Out-Null
    }

    Set-ItemProperty -Path $lapsPolicyPath -Name "BackupDirectory" -Value $BackupDirectory -Type DWord -Force
    Write-Host "Set BackupDirectory = $BackupDirectory"

    Set-ItemProperty -Path $lapsPolicyPath -Name "PasswordAgeDays" -Value $PasswordAgeDays -Type DWord -Force
    Write-Host "Set PasswordAgeDays = $PasswordAgeDays"

    Set-ItemProperty -Path $lapsPolicyPath -Name "PasswordLength" -Value $PasswordLength -Type DWord -Force
    Write-Host "Set PasswordLength = $PasswordLength"

    Set-ItemProperty -Path $lapsPolicyPath -Name "PasswordComplexity" -Value $PasswordComplexity -Type DWord -Force
    Write-Host "Set PasswordComplexity = $PasswordComplexity"

    Set-ItemProperty -Path $lapsPolicyPath -Name "PasswordEncryptionEnabled" -Value $PasswordEncryptionEnabled -Type DWord -Force
    Write-Host "Set PasswordEncryptionEnabled = $PasswordEncryptionEnabled"

    if (-not [string]::IsNullOrWhiteSpace($AdministratorAccountName)) {
        Set-ItemProperty -Path $lapsPolicyPath -Name "AdministratorAccountName" -Value $AdministratorAccountName -Type String -Force
        Write-Host "Set AdministratorAccountName = $AdministratorAccountName"
    } else {
        Write-Host "AdministratorAccountName not set (managing built-in Administrator)"
    }
} catch {
    $errorOccurred = $true
    $errorText = "Failed to write LAPS policy: $($_.Exception.Message)"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status : Failure"
    exit 1
}

# ==== PROCESS POLICY ====
Write-Host ""
Write-Host "[RUN] PROCESS POLICY"
Write-Host "=============================================================="
Write-Host "Forcing LAPS policy processing..."

try {
    Invoke-LapsPolicyProcessing -ErrorAction Stop
    Write-Host "Policy processing invoked"
} catch {
    Write-Host "[WARN] LAPS policy processing reported an issue:"
    Write-Host "[WARN] $($_.Exception.Message)"
    Write-Host "[WARN] Check the RESULT section and the tenant-side setting."
}

# ==== RESULT ====
Write-Host ""
Write-Host "[INFO] RESULT"
Write-Host "=============================================================="

try {
    $lapsEvents = Get-WinEvent -LogName 'Microsoft-Windows-LAPS/Operational' -MaxEvents 5 -ErrorAction Stop
    if ($lapsEvents) {
        $latest = $lapsEvents | Select-Object -First 1
        Write-Host "Latest LAPS event : $($latest.Message)"
    } else {
        Write-Host "Latest LAPS event : (no events found in the LAPS operational log)"
    }
} catch {
    Write-Host "Latest LAPS event : (LAPS operational log not available yet)"
    Write-Host "The Microsoft-Windows-LAPS/Operational log may not populate until"
    Write-Host "the first processing pass completes. Re-run to read the result."
}

Write-Host ""
Write-Host "Reminder: the escrow only succeeds when the tenant setting"
Write-Host 'Enable Microsoft Entra Local Administrator Password Solution (LAPS)'
Write-Host "is set to Yes in the Entra admin center (Devices -> Device settings)."

# ==== FINAL STATUS ====
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status : Success"
Write-Host "LAPS Entra configuration applied"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
