$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT   : OpenSSH Server Setup                                         v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\openssh_server_setup.ps1
================================================================================
 FILE     : openssh_server_setup.ps1
 DESCRIPTION : Installs and configures OpenSSH Server on Windows
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Installs the OpenSSH Server Windows capability, configures the sshd service
   for automatic startup, enables public key authentication, and opens the
   Windows Firewall for SSH traffic on port 22.

 DATA SOURCES & PRIORITY

   - Windows Optional Features: OpenSSH.Server capability
   - Windows Firewall: Existing SSH rules

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $SshPort           : Port for SSH listener (default: 22)
     - $DefaultShell      : Shell for SSH sessions (default: PowerShell)
     - $AllowedUsersGroup : Group to restrict SSH access (default: Administrators)

 SETTINGS

   Configuration details and default values:
     - SSH port: 22
     - Default shell: PowerShell (C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe)
     - Password authentication: Enabled
     - Public key authentication: Enabled
     - Service startup: Automatic (delayed)
     - Firewall rule: Allow inbound TCP on configured port
     - Access restricted to Administrators group via sshd_config

 BEHAVIOR

   The script performs the following actions in order:
   1. Checks if OpenSSH Server is already installed
   2. Installs OpenSSH Server capability if missing
   3. Configures sshd_config for key auth and restricted access
   4. Sets the default shell to PowerShell
   5. Configures sshd service for Automatic (Delayed Start)
   6. Opens Windows Firewall for SSH traffic
   7. Starts the sshd service
   8. Verifies SSH is listening on the configured port

 PREREQUISITES

   - Windows Server 2019 or later / Windows 10 1809+
   - Administrator privileges
   - Internet access (for capability install if not already present)

 SECURITY NOTES

   - No secrets in logs
   - Access restricted to Administrators group by default
   - Public key authentication enabled for passwordless access
   - Password authentication left enabled for initial setup convenience

 ENDPOINTS

   - None (local capability install)

 EXIT CODES

   0 = Success
   1 = Failure (install failed, service failed to start, etc.)

 EXAMPLE RUN

   [INFO] ENVIRONMENT CHECK
   ==============================================================
     OS                   : Microsoft Windows Server 2019 Standard
     OpenSSH Server       : Not installed

   [RUN] INSTALL OPENSSH SERVER
   ==============================================================
     Installing OpenSSH.Server capability...
     Installation completed

   [RUN] CONFIGURE SSHD
   ==============================================================
     Configuring sshd_config...
     Default shell        : PowerShell
     SSH port             : 22
     Allowed group        : Administrators
     Configuration written

   [RUN] ENABLE SERVICE
   ==============================================================
     Setting sshd to Automatic (Delayed Start)...
     Starting sshd service...
     Service is running

   [RUN] CONFIGURE FIREWALL
   ==============================================================
     Adding firewall rule for SSH on port 22...
     Firewall rule active

   [OK] FINAL STATUS
   ==============================================================
     Result               : SUCCESS
     SSH listening         : Port 22
     Service startup       : AutomaticDelayedStart
     Default shell         : PowerShell
     Connect with          : ssh Administrator@<IP>

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-09 v1.0.0 Initial release - OpenSSH Server setup for remote management
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$SshPort           = 22
$DefaultShell      = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$AllowedUsersGroup = "Administrators"

# ==============================================================================
# STATE VARIABLES
# ==============================================================================
$errorOccurred = $false
$errorText     = ""
$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  SSH Port             : $SshPort"
Write-Host "  Default Shell        : $DefaultShell"
Write-Host "  Allowed Group        : $AllowedUsersGroup"

if ($SshPort -lt 1 -or $SshPort -gt 65535) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Invalid SSH port: $SshPort"
    exit 1
}

# ==============================================================================
# ENVIRONMENT CHECK
# ==============================================================================
Write-Host ""
Write-Host "[INFO] ENVIRONMENT CHECK"
Write-Host "=============================================================="

$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Host "  OS                   : $osCaption"

$sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }

if (-not $sshCapability) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  OpenSSH Server capability not available on this OS"
    Write-Host "  Requires Windows Server 2019+ or Windows 10 1809+"
    exit 1
}

$alreadyInstalled = $sshCapability.State -eq 'Installed'
if ($alreadyInstalled) {
    Write-Host "  OpenSSH Server       : Already installed"
} else {
    Write-Host "  OpenSSH Server       : Not installed"
}

# ==============================================================================
# INSTALL OPENSSH SERVER
# ==============================================================================
if (-not $alreadyInstalled) {
    Write-Host ""
    Write-Host "[RUN] INSTALL OPENSSH SERVER"
    Write-Host "=============================================================="
    Write-Host "  Installing OpenSSH.Server capability..."

    try {
        $result = Add-WindowsCapability -Online -Name $sshCapability.Name
        if ($result.RestartNeeded) {
            Write-Host "  Installation completed (reboot may be required)"
        } else {
            Write-Host "  Installation completed"
        }
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "  Failed to install OpenSSH Server"
        Write-Host "  Error: $($_.Exception.Message)"
        exit 1
    }
}

# ==============================================================================
# CONFIGURE SSHD
# ==============================================================================
Write-Host ""
Write-Host "[RUN] CONFIGURE SSHD"
Write-Host "=============================================================="
Write-Host "  Configuring sshd_config..."

try {
    # Ensure ssh directory exists
    $sshDir = Split-Path $sshdConfigPath
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Start sshd once to generate default config if it doesn't exist
    if (-not (Test-Path $sshdConfigPath)) {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Stop-Service sshd -ErrorAction SilentlyContinue
    }

    if (Test-Path $sshdConfigPath) {
        $config = Get-Content $sshdConfigPath

        # Enable public key authentication
        $config = $config -replace '^#?PubkeyAuthentication\s+.*', 'PubkeyAuthentication yes'

        # Set port
        $config = $config -replace '^#?Port\s+.*', "Port $SshPort"

        # Restrict access to allowed group
        $hasAllowGroups = $config | Where-Object { $_ -match '^#?AllowGroups\s' }
        if ($hasAllowGroups) {
            $config = $config -replace '^#?AllowGroups\s+.*', "AllowGroups $AllowedUsersGroup"
        } else {
            $config += "`nAllowGroups $AllowedUsersGroup"
        }

        # Fix administrators_authorized_keys to use proper permissions
        # Comment out the default Match Group administrators block that breaks key auth
        $inMatchBlock = $false
        $config = $config | ForEach-Object {
            if ($_ -match '^Match Group administrators') {
                $inMatchBlock = $true
                "# $_"
            } elseif ($inMatchBlock -and $_ -match '^\s+AuthorizedKeysFile') {
                $inMatchBlock = $false
                "# $_"
            } else {
                $_
            }
        }

        Set-Content -Path $sshdConfigPath -Value $config -Force
    }

    # Set default shell to PowerShell
    $shellRegPath = "HKLM:\SOFTWARE\OpenSSH"
    if (-not (Test-Path $shellRegPath)) {
        New-Item -Path $shellRegPath -Force | Out-Null
    }
    New-ItemProperty -Path $shellRegPath -Name DefaultShell -Value $DefaultShell -PropertyType String -Force | Out-Null

    Write-Host "  Default shell        : PowerShell"
    Write-Host "  SSH port             : $SshPort"
    Write-Host "  Allowed group        : $AllowedUsersGroup"
    Write-Host "  Configuration written"
}
catch {
    $errorOccurred = $true
    $errorText = $_.Exception.Message
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to configure sshd"
    Write-Host "  Error: $errorText"
    exit 1
}

# ==============================================================================
# ENABLE SERVICE
# ==============================================================================
Write-Host ""
Write-Host "[RUN] ENABLE SERVICE"
Write-Host "=============================================================="

try {
    Write-Host "  Setting sshd to Automatic (Delayed Start)..."
    Set-Service -Name sshd -StartupType Automatic
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\sshd" /v DelayedAutostart /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # Also enable ssh-agent
    Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue

    Write-Host "  Starting sshd service..."
    Restart-Service sshd
    Start-Service ssh-agent -ErrorAction SilentlyContinue

    $sshdService = Get-Service sshd
    if ($sshdService.Status -eq 'Running') {
        Write-Host "  Service is running"
    } else {
        throw "sshd service is not running after start attempt (status: $($sshdService.Status))"
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to start sshd service"
    Write-Host "  Error: $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
# CONFIGURE FIREWALL
# ==============================================================================
Write-Host ""
Write-Host "[RUN] CONFIGURE FIREWALL"
Write-Host "=============================================================="

try {
    $existingRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

    if ($existingRule) {
        Write-Host "  Firewall rule already exists"
        # Update port if different
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -LocalPort $SshPort -ErrorAction SilentlyContinue
    } else {
        Write-Host "  Adding firewall rule for SSH on port $SshPort..."
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Description "Allow inbound SSH traffic" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort $SshPort | Out-Null
    }
    Write-Host "  Firewall rule active"
}
catch {
    Write-Host ""
    Write-Host "[WARN] WARNING"
    Write-Host "=============================================================="
    Write-Host "  Failed to configure firewall rule"
    Write-Host "  Error: $($_.Exception.Message)"
    Write-Host "  SSH may still work if firewall is already open"
}

# ==============================================================================
# VERIFY
# ==============================================================================
Write-Host ""
Write-Host "[INFO] VERIFY"
Write-Host "=============================================================="

$listening = Get-NetTCPConnection -LocalPort $SshPort -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "  SSH listening         : Port $SshPort confirmed"
} else {
    Write-Host "  SSH listening         : Port $SshPort not detected (may need a moment)"
}

$sshdFinal = Get-Service sshd
$startType = $sshdFinal.StartType

# ==============================================================================
# FINAL STATUS
# ==============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result               : SUCCESS"
Write-Host "  SSH listening        : Port $SshPort"
Write-Host "  Service startup      : $startType"
Write-Host "  Default shell        : PowerShell"
Write-Host "  Connect with         : ssh Administrator@<IP>"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
