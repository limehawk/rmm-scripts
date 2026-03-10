$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT   : OpenSSH Server Remove                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\openssh_server_remove.ps1
================================================================================
 FILE     : openssh_server_remove.ps1
 DESCRIPTION : Removes OpenSSH Server, firewall rule, and cleans up config
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Stops and removes the OpenSSH Server from Windows. Removes the firewall
   rule, uninstalls the Windows capability, and optionally cleans up the
   sshd configuration directory.

 DATA SOURCES & PRIORITY

   - Windows Services: sshd and ssh-agent service state
   - Windows Optional Features: OpenSSH.Server capability
   - Windows Firewall: SSH firewall rule

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $RemoveConfig : Whether to delete the sshd config directory (default: true)
     - $RemoveHostKeys : Whether to delete host keys with config (default: true)

 SETTINGS

   Configuration details and default values:
     - Remove config: true (deletes C:\ProgramData\ssh)
     - Remove host keys: true (included in config directory)
     - Removes firewall rule: OpenSSH-Server-In-TCP
     - Removes default shell registry key

 BEHAVIOR

   The script performs the following actions in order:
   1. Stops the sshd and ssh-agent services
   2. Removes the Windows Firewall rule for SSH
   3. Removes the default shell registry key
   4. Uninstalls the OpenSSH.Server Windows capability
   5. Removes sshd config directory if configured
   6. Verifies removal

 PREREQUISITES

   - Windows Server 2019 or later / Windows 10 1809+
   - Administrator privileges

 SECURITY NOTES

   - No secrets in logs
   - Host keys are deleted by default to prevent reuse
   - Config removal ensures no stale authorized_keys remain

 ENDPOINTS

   - None (local operations only)

 EXIT CODES

   0 = Success
   1 = Failure (removal failed)

 EXAMPLE RUN

   [INFO] ENVIRONMENT CHECK
   ==============================================================
     OpenSSH Server       : Installed
     sshd service         : Running

   [RUN] STOP SERVICES
   ==============================================================
     Stopping sshd...
     Stopping ssh-agent...
     Services stopped

   [RUN] REMOVE FIREWALL RULE
   ==============================================================
     Removing OpenSSH-Server-In-TCP rule...
     Firewall rule removed

   [RUN] REMOVE OPENSSH SERVER
   ==============================================================
     Uninstalling OpenSSH.Server capability...
     Capability removed

   [RUN] CLEAN UP CONFIG
   ==============================================================
     Removing C:\ProgramData\ssh...
     Config directory removed
     Registry key removed

   [OK] FINAL STATUS
   ==============================================================
     Result               : SUCCESS
     OpenSSH Server       : Removed
     Firewall rule        : Removed
     Config cleaned       : Yes

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-09 v1.0.0 Initial release - OpenSSH Server removal and cleanup
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$RemoveConfig   = $true
$RemoveHostKeys = $true

# ==============================================================================
# STATE VARIABLES
# ==============================================================================
$sshdConfigDir = "$env:ProgramData\ssh"

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  Remove config        : $RemoveConfig"
Write-Host "  Remove host keys     : $RemoveHostKeys"

# ==============================================================================
# ENVIRONMENT CHECK
# ==============================================================================
Write-Host ""
Write-Host "[INFO] ENVIRONMENT CHECK"
Write-Host "=============================================================="

$sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
$isInstalled = $sshCapability -and $sshCapability.State -eq 'Installed'

if (-not $isInstalled) {
    Write-Host "  OpenSSH Server       : Not installed"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "  Result               : SUCCESS"
    Write-Host "  OpenSSH Server       : Already not installed"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

Write-Host "  OpenSSH Server       : Installed"

$sshdService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshdService) {
    Write-Host "  sshd service         : $($sshdService.Status)"
} else {
    Write-Host "  sshd service         : Not found"
}

# ==============================================================================
# STOP SERVICES
# ==============================================================================
Write-Host ""
Write-Host "[RUN] STOP SERVICES"
Write-Host "=============================================================="

try {
    $sshdService = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshdService -and $sshdService.Status -eq 'Running') {
        Write-Host "  Stopping sshd..."
        Stop-Service sshd -Force
    } else {
        Write-Host "  sshd already stopped"
    }

    $agentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agentService -and $agentService.Status -eq 'Running') {
        Write-Host "  Stopping ssh-agent..."
        Stop-Service ssh-agent -Force
    } else {
        Write-Host "  ssh-agent already stopped"
    }

    Write-Host "  Services stopped"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to stop SSH services"
    Write-Host "  Error: $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# REMOVE FIREWALL RULE
# ==============================================================================
Write-Host ""
Write-Host "[RUN] REMOVE FIREWALL RULE"
Write-Host "=============================================================="

try {
    $rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($rule) {
        Write-Host "  Removing OpenSSH-Server-In-TCP rule..."
        Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
        Write-Host "  Firewall rule removed"
    } else {
        Write-Host "  No firewall rule found"
    }
}
catch {
    Write-Host ""
    Write-Host "[WARN] WARNING"
    Write-Host "=============================================================="
    Write-Host "  Failed to remove firewall rule"
    Write-Host "  Error: $($_.Exception.Message)"
}

# ==============================================================================
# REMOVE OPENSSH SERVER
# ==============================================================================
Write-Host ""
Write-Host "[RUN] REMOVE OPENSSH SERVER"
Write-Host "=============================================================="

try {
    Write-Host "  Uninstalling OpenSSH.Server capability..."
    Remove-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
    Write-Host "  Capability removed"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to remove OpenSSH Server capability"
    Write-Host "  Error: $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# CLEAN UP CONFIG
# ==============================================================================
Write-Host ""
Write-Host "[RUN] CLEAN UP CONFIG"
Write-Host "=============================================================="

$configCleaned = $false

if ($RemoveConfig -and (Test-Path $sshdConfigDir)) {
    try {
        Write-Host "  Removing $sshdConfigDir..."
        Remove-Item -Path $sshdConfigDir -Recurse -Force
        Write-Host "  Config directory removed"
        $configCleaned = $true
    }
    catch {
        Write-Host ""
        Write-Host "[WARN] WARNING"
        Write-Host "=============================================================="
        Write-Host "  Failed to remove config directory"
        Write-Host "  Error: $($_.Exception.Message)"
    }
} elseif (-not $RemoveConfig) {
    Write-Host "  Config removal skipped (RemoveConfig = false)"
} else {
    Write-Host "  Config directory not found"
    $configCleaned = $true
}

# Remove default shell registry key
$shellRegPath = "HKLM:\SOFTWARE\OpenSSH"
if (Test-Path $shellRegPath) {
    try {
        Remove-Item -Path $shellRegPath -Recurse -Force
        Write-Host "  Registry key removed"
    }
    catch {
        Write-Host ""
        Write-Host "[WARN] WARNING"
        Write-Host "=============================================================="
        Write-Host "  Failed to remove registry key"
        Write-Host "  Error: $($_.Exception.Message)"
    }
}

# Remove delayed start registry key
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\sshd" /v DelayedAutostart /f 2>&1 | Out-Null

# ==============================================================================
# FINAL STATUS
# ==============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result               : SUCCESS"
Write-Host "  OpenSSH Server       : Removed"
Write-Host "  Firewall rule        : Removed"
Write-Host "  Config cleaned       : $configCleaned"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
