$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Workstation OOBE Seal                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : June 2026
 USAGE    : .\workstation_oobe_seal.ps1
================================================================================
 FILE     : workstation_oobe_seal.ps1
 DESCRIPTION : Seals a configured Win11 image to a silent OOBE via sysprep
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Finishes provisioning an OEM Windows 11 machine that has been configured in
   audit mode. It removes any stale local admin account left over from a prior
   run, writes a sysprep answer file that auto-creates a local administrator and
   silently skips the out-of-box setup screens, then runs sysprep to generalize
   the image to OOBE and power the machine off. The next power-on runs a silent
   OOBE that creates the admin account, logs in once, and lands on the desktop.

 DATA SOURCES & PRIORITY

   1. Hardcoded CONFIG values (admin account name, password, timezone)
   2. Embedded answer-file template (oobeSystem pass)

 WORKFLOW (operator context)

   1. At the OEM machine's OOBE screen, press Ctrl+Shift+F3. Windows reboots
      into audit mode and auto-logs into the built-in Administrator.
   2. Cancel the Sysprep dialog that appears. Install software / configure the
      machine as needed.
   3. From an elevated PowerShell, run:
        powershell -ExecutionPolicy Bypass -File workstation_oobe_seal.ps1
   4. The machine powers off. Next power-on: silent OOBE creates the local
      admin and auto-logs in once.

   NOTE: the OOBE-skip works ONLY because sysprep ACTIVELY applies this answer
   file (/oobe /unattend). Dropping unattend.xml into C:\Windows\Panther or
   setting the ChildCompletion registry flag does NOT work on modern Windows 11
   (verified dead ends against Microsoft Learn). Do not substitute those methods.

 REQUIRED INPUTS

   All inputs are hardcoded in the CONFIG block in the script body:
     - $adminName     : Local admin account name created at OOBE
     - $adminPassword : Local admin password. SHIPPED AS A PLACEHOLDER. The
                        operator MUST change "CHANGE_ME_BEFORE_USE" to a real
                        password before running, or the script aborts.
     - $timeZone      : Windows time zone ID applied during OOBE

 SETTINGS

   - Answer file path  : C:\Windows\Temp\unattend.xml (written, then consumed)
   - Sysprep mode      : /oobe /shutdown /unattend:<file> (generalize + power off)
   - OOBE screens      : EULA, OEM registration, online account, local account,
                         and wireless setup are all hidden/skipped
   - AutoLogon         : enabled once (LogonCount = 1) for the new admin

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates the CONFIG values (rejects the placeholder password)
   2. Removes a stale local admin account (and its profile) if present
   3. Writes the embedded answer file to C:\Windows\Temp\unattend.xml
   4. Runs sysprep /oobe /shutdown /unattend:<file>
   5. The machine POWERS OFF as part of sysprep (no further output expected)

 PREREQUISITES

   - Windows 11 (OEM image), sitting in audit mode
   - Running interactively as the built-in Administrator (audit-mode desktop)
   - PowerShell 5.1+ with an elevated session
   - NOT pushed by an RMM agent. This is a hands-on USB/interactive workflow.
     The closest RMM runAs enum is SYSTEM_USER; the real context is the
     built-in Administrator in audit mode.

 SECURITY NOTES

   - The admin password is written in PLAIN TEXT into the answer file (a
     sysprep requirement). Sysprep deletes C:\Windows\Temp\unattend.xml on
     successful generalize, but treat the configured password as sensitive.
   - No working password ships with this script. The default is an obvious
     placeholder that the operator must replace; the script refuses to run
     until it is changed.
   - Change the OOBE-created admin password (or rotate it) after first logon
     per your provisioning policy.

 ENDPOINTS

   - Not applicable (no network calls)

 EXIT CODES

   0 = Success (sysprep invoked; machine powering off)
   1 = Failure (validation error or sysprep/account operation failed)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Admin Name   : limehawk
   Time Zone    : Eastern Standard Time
   Answer File  : C:\Windows\Temp\unattend.xml

   [RUN] STALE ACCOUNT CLEANUP
   ==============================================================
   Stale account not present - ok

   [RUN] WRITE ANSWER FILE
   ==============================================================
   Answer file written

   [RUN] SYSPREP SEAL
   ==============================================================
   Invoking sysprep /oobe /shutdown - machine will power off

   [OK] FINAL STATUS
   ==============================================================
   Seal initiated. The machine is powering off.

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-06-16 v1.0.0 Initial Limehawk Script Framework version of the audit-mode
                   sysprep-seal provisioning script
================================================================================
#>

# ==== STATE ====
$errorOccurred = $false
$errorText = ""

# ==== HARDCODED INPUTS (CONFIG) ====
# Operator: edit these before running.
$adminName = "limehawk"

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! CHANGE THIS PASSWORD BEFORE USE. The script will REFUSE to run until you  !!
# !! replace the placeholder below with a real password. This value is written !!
# !! in plain text into the sysprep answer file (a sysprep requirement).       !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
$adminPassword = "CHANGE_ME_BEFORE_USE"

# Windows time zone ID. Run "tzutil /l" to list valid IDs for your region.
$timeZone = "Eastern Standard Time"

$unattendPath = "C:\Windows\Temp\unattend.xml"

Set-StrictMode -Version Latest

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($adminName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Admin account name is required."
}

if ([string]::IsNullOrWhiteSpace($adminPassword) -or $adminPassword -eq 'CHANGE_ME_BEFORE_USE') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Admin password is still the placeholder. Edit `$adminPassword in the CONFIG block before running."
}

if ([string]::IsNullOrWhiteSpace($timeZone)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Time zone is required (e.g. 'Eastern Standard Time')."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

# ==== ANSWER FILE (built from CONFIG) ====
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>0409:00000409</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$adminName</Name>
            <Group>Administrators</Group>
            <DisplayName>Limehawk Admin</DisplayName>
            <Password>
              <Value>$adminPassword</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>$adminName</Username>
        <LogonCount>1</LogonCount>
        <Password>
          <Value>$adminPassword</Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>
      <TimeZone>$timeZone</TimeZone>
    </component>
  </settings>
</unattend>
"@

# ==== RUNTIME OUTPUT ====
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "Admin Name   : $adminName"
Write-Host "Time Zone    : $timeZone"
Write-Host "Answer File  : $unattendPath"

Write-Host ""
Write-Host "[RUN] STALE ACCOUNT CLEANUP"
Write-Host "=============================================================="
try {
    $existing = Get-LocalUser -Name $adminName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-LocalUser -Name $adminName
        $profilePath = "C:\Users\$adminName"
        if (Test-Path $profilePath) {
            Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Removed stale account '$adminName'"
    } else {
        Write-Host "Stale account not present - ok"
    }
} catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
    $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
    $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
}

if (-not $errorOccurred) {
    Write-Host ""
    Write-Host "[RUN] WRITE ANSWER FILE"
    Write-Host "=============================================================="
    try {
        Set-Content -Path $unattendPath -Value $xml -Encoding UTF8
        Write-Host "Answer file written"
    } catch {
        $errorOccurred = $true
        $errorText = $_.Exception.Message
        $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
        $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
    }
}

if (-not $errorOccurred) {
    Write-Host ""
    Write-Host "[RUN] SYSPREP SEAL"
    Write-Host "=============================================================="
    Write-Host "Invoking sysprep /oobe /shutdown - machine will power off"
    try {
        & "C:\Windows\System32\Sysprep\sysprep.exe" /oobe /shutdown "/unattend:$unattendPath"
    } catch {
        $errorOccurred = $true
        $errorText = $_.Exception.Message
        $errorText += "`n  Type  : $($_.Exception.GetType().Name)"
        $errorText += "`n  Where : line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
    }
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] OPERATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Seal did not complete. See error above. Machine NOT sealed."
    exit 1
}

# Note: on success sysprep powers the machine off, so this rarely prints.
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Seal initiated. The machine is powering off."

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
