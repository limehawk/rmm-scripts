$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : GCPW Install                                                    v1.0.0
FILE   : gcpw_install.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Downloads, installs, and configures Google Credential Provider for Windows
    (GCPW). Sets allowed domains and enrollment token in the system registry.

REQUIRED INPUTS:
    $domainsAllowedToLogin : Comma-separated list of allowed Google Workspace domains
    $enrollmentToken       : GCPW enrollment token from Google Admin Console

BEHAVIOR:
    1. Validates administrative privileges
    2. Downloads GCPW installer (32-bit or 64-bit based on OS)
    3. Installs GCPW silently
    4. Configures allowed domains in registry
    5. Configures enrollment token in registry

PREREQUISITES:
    - Windows 10/11 or Windows Server
    - Administrator privileges
    - Internet access
    - Valid Google Workspace enrollment token

SECURITY NOTES:
    - Enrollment token should be kept confidential
    - Only listed domains will be allowed to login
    - Requires elevated privileges

EXIT CODES:
    0 = Success
    1 = Failure
    5 = Configuration error (missing domains or not admin)

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Allowed Domains      : example.com,corp.example.com
    Enrollment Token     : ********-****-****-****-************

    [ DOWNLOADING GCPW ]
    --------------------------------------------------------------
    Architecture         : 64-bit
    Filename             : gcpwstandaloneenterprise64.msi
    Download             : SUCCESS

    [ INSTALLING GCPW ]
    --------------------------------------------------------------
    Installation         : SUCCESS

    [ CONFIGURING REGISTRY ]
    --------------------------------------------------------------
    Domains              : Configured
    Enrollment Token     : Configured

    [ FINAL STATUS ]
    --------------------------------------------------------------
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps (sanitized)
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# CONFIGURATION - EDIT THESE VALUES
# ============================================================================
# Comma-separated list of domains allowed to login with GCPW
$domainsAllowedToLogin = "yourdomain.com,anotherdomain.com"

# Enrollment token from Google Admin Console
# Generate at: Admin Console > Devices > Chrome > Settings > GCPW
$enrollmentToken = "00000000-0000-0000-0000-000000000000"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

function Get-MaskedToken {
    param([string]$token)
    if ($token.Length -gt 8) {
        return $token.Substring(0, 8) + "-****-****-****-" + $token.Substring($token.Length - 12)
    }
    return "********"
}

# ============================================================================
# PRIVILEGE CHECK
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Section "ERROR OCCURRED"
    Write-Host " This script requires administrative privileges to run."
    Write-Section "SCRIPT HALTED"
    exit 5
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Section "INPUT VALIDATION"

if ([string]::IsNullOrWhiteSpace($domainsAllowedToLogin) -or $domainsAllowedToLogin -eq "yourdomain.com,anotherdomain.com") {
    PrintKV "Error" "Domains not configured"
    Write-Host ""
    Write-Host " Please edit the script and set `$domainsAllowedToLogin"
    Write-Host " to your Google Workspace domain(s)."
    Write-Section "SCRIPT HALTED"
    exit 5
}

if ([string]::IsNullOrWhiteSpace($enrollmentToken) -or $enrollmentToken -eq "00000000-0000-0000-0000-000000000000") {
    PrintKV "Error" "Enrollment token not configured"
    Write-Host ""
    Write-Host " Please edit the script and set `$enrollmentToken"
    Write-Host " to your GCPW enrollment token from Google Admin Console."
    Write-Section "SCRIPT HALTED"
    exit 5
}

PrintKV "Allowed Domains" $domainsAllowedToLogin
PrintKV "Enrollment Token" (Get-MaskedToken $enrollmentToken)

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    # Determine architecture and download
    Write-Section "DOWNLOADING GCPW"

    $gcpwFileName = if ([Environment]::Is64BitOperatingSystem) {
        "gcpwstandaloneenterprise64.msi"
    } else {
        "gcpwstandaloneenterprise.msi"
    }

    $architecture = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
    PrintKV "Architecture" $architecture
    PrintKV "Filename" $gcpwFileName

    $gcpwUri = "https://dl.google.com/credentialprovider/$gcpwFileName"
    $downloadPath = Join-Path $env:TEMP $gcpwFileName

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $gcpwUri -OutFile $downloadPath -ErrorAction Stop
    PrintKV "Download" "SUCCESS"

    # Install GCPW
    Write-Section "INSTALLING GCPW"

    $arguments = "/i `"$downloadPath`" /q"
    $installProcess = Start-Process msiexec.exe -ArgumentList $arguments -PassThru -Wait -ErrorAction Stop

    if ($installProcess.ExitCode -ne 0) {
        PrintKV "Installation" "FAILED (exit code $($installProcess.ExitCode))"
        throw "MSI installation failed with exit code $($installProcess.ExitCode)"
    }

    PrintKV "Installation" "SUCCESS"

    # Configure Registry
    Write-Section "CONFIGURING REGISTRY"

    # Set allowed domains
    $gcpwPath = 'HKLM:\Software\Google\GCPW'
    if (-not (Test-Path $gcpwPath)) {
        New-Item -Path $gcpwPath -Force | Out-Null
    }
    Set-ItemProperty -Path $gcpwPath -Name 'domains_allowed_to_login' -Value $domainsAllowedToLogin
    PrintKV "Domains" "Configured"

    # Set enrollment token
    $cloudManagementPath = 'HKLM:\SOFTWARE\Policies\Google\CloudManagement'
    if (-not (Test-Path $cloudManagementPath)) {
        New-Item -Path $cloudManagementPath -Force | Out-Null
    }
    New-ItemProperty -Path $cloudManagementPath -Name 'EnrollmentToken' -Value $enrollmentToken -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    PrintKV "Enrollment Token" "Configured"

    # Cleanup
    if (Test-Path $downloadPath) {
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
    }

    # Final Status
    Write-Section "FINAL STATUS"
    Write-Host " SCRIPT SUCCEEDED"
    Write-Host ""
    Write-Host " GCPW has been installed and configured."
    Write-Host " Users can now sign in with their Google Workspace credentials."

    Write-Section "SCRIPT COMPLETED"
    exit 0
}
catch {
    Write-Section "ERROR OCCURRED"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Section "SCRIPT HALTED"
    exit 1
}
