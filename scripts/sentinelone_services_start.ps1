<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT    : SentinelOne Service Manager 1.1.1
 AUTHOR    : Limehawk.io
 DATE      : January 2026
 USAGE     : .\sentinelone_services_start.ps1
 FILE      : sentinelone_services_start.ps1
DESCRIPTION : Ensures all SentinelOne services are running on Windows
================================================================================
 README
--------------------------------------------------------------------------------

PURPOSE

Checks the status of all SentinelOne services on Windows systems and ensures
they are running. Enables disabled services and starts stopped services.
Useful for troubleshooting SentinelOne agent issues where services may have
been stopped or disabled.

DATA SOURCES & PRIORITY

1. Windows Service Control Manager - Query service status
2. WMI (Win32_Service) - Query service startup configuration

REQUIRED INPUTS

No inputs required. The script automatically checks these SentinelOne services:
- LogProcessorService
- SentinelAgent
- SentinelHelperService
- SentinelStaticEngine

SETTINGS

- Service startup type: Set to Automatic if currently Disabled
- Service action: Start service if currently Stopped
- No action taken if service is already Running

BEHAVIOR

1. Validates Administrator privileges
2. Checks status of each SentinelOne service
3. Displays current status and start type for each service
4. Enables service (sets to Automatic) if disabled
5. Starts service if stopped
6. Reports final status for all services

PREREQUISITES

- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges (required for service management)
- SentinelOne agent must be installed
- No modules required

SECURITY NOTES

- No secrets logged or displayed
- Requires elevation (will fail if not admin)
- Service changes are permanent until manually reversed

ENDPOINTS

- None (local system operations only)

EXIT CODES

- 0: Success - Services checked and started as needed
- 1: Failure - Error occurred or insufficient privileges

EXAMPLE RUN

PS> .\sentinelone_services_start.ps1

[INFO] SETUP
==============================================================
Script started : 2025-11-02 10:45:30
Administrator  : Yes

[RUN] SERVICE STATUS CHECK
==============================================================

Service : LogProcessorService
Display : SentinelOne Log Processor Service
Status  : Stopped
Startup : Automatic
Action  : Starting service...
Result  : Service started successfully

Service : SentinelAgent
Display : SentinelOne Endpoint Protection Agent
Status  : Running
Startup : Automatic
Action  : No action required

Service : SentinelHelperService
Display : SentinelOne Helper Service
Status  : Stopped
Startup : Disabled
Action  : Enabling service and starting...
Result  : Service enabled and started

Service : SentinelStaticEngine
Display : SentinelOne Static Engine
Status  : Running
Startup : Automatic
Action  : No action required

[OK] FINAL STATUS
==============================================================
Total services checked : 4
Services started       : 2
Services already running : 2
All services running   : Yes

[OK] SCRIPT COMPLETED
==============================================================
Script completed successfully
Exit code : 0
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-02 v1.0.0 Initial migration from SuperOps
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

# SentinelOne services to check and start
$servicesToCheck = @(
    "LogProcessorService",
    "SentinelAgent",
    "SentinelHelperService",
    "SentinelStaticEngine"
)

# ============================================================================
# SETUP
# ============================================================================

Write-Host ""
Write-Host "[INFO] SETUP"
Write-Host "=============================================================="

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[ERROR] ADMINISTRATOR REQUIRED"
    Write-Host "=============================================================="
    Write-Host "This script requires Administrator privileges"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Right-click PowerShell and select 'Run as Administrator'"
    Write-Host "- Or run from RMM platform with SYSTEM privileges"
    Write-Host ""
    exit 1
}

Write-Host "Script started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Administrator  : Yes"

# ============================================================================
# SERVICE STATUS CHECK
# ============================================================================

Write-Host ""
Write-Host "[RUN] SERVICE STATUS CHECK"
Write-Host "=============================================================="
Write-Host ""

$servicesChecked = 0
$servicesStarted = 0
$servicesAlreadyRunning = 0
$errorOccurred = $false

foreach ($serviceName in $servicesToCheck) {
    try {
        # Get service status
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if (-not $service) {
            Write-Host "Service : $serviceName"
            Write-Host "Status  : Not found (SentinelOne may not be installed)"
            Write-Host ""
            continue
        }

        # Get startup configuration
        $startupType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue).StartMode

        Write-Host "Service : $serviceName"
        Write-Host "Display : $($service.DisplayName)"
        Write-Host "Status  : $($service.Status)"
        Write-Host "Startup : $startupType"

        $servicesChecked++

        # Enable service if disabled
        if ($startupType -eq 'Disabled') {
            Write-Host "Action  : Service is disabled, enabling..."
            Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            Write-Host "Result  : Service enabled (set to Automatic)"
        }

        # Start service if stopped
        if ($service.Status -eq 'Stopped') {
            Write-Host "Action  : Service is stopped, starting..."
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-Host "Result  : Service started successfully"
            $servicesStarted++
        } else {
            Write-Host "Action  : No action required (already running)"
            $servicesAlreadyRunning++
        }

        Write-Host ""

    } catch {
        Write-Host "Error   : Failed to process service"
        Write-Host "Details : $($_.Exception.Message)"
        Write-Host ""
        $errorOccurred = $true
    }
}

# Check if any services were found
if ($servicesChecked -eq 0) {
    Write-Host ""
    Write-Host "[ERROR] NO SERVICES FOUND"
    Write-Host "=============================================================="
    Write-Host "No SentinelOne services found"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify SentinelOne agent is installed"
    Write-Host "- Check service names haven't changed in newer versions"
    Write-Host "- Run 'Get-Service | Where-Object { \$_.Name -like \"*Sentinel*\" }' to list services"
    Write-Host ""
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Total services checked   : $servicesChecked"
Write-Host "Services started         : $servicesStarted"
Write-Host "Services already running : $servicesAlreadyRunning"

if ($errorOccurred) {
    Write-Host "Errors encountered       : Yes"
    Write-Host "All services running     : Unknown"
} else {
    Write-Host "All services running     : Yes"
}

# ============================================================================
# SCRIPT COMPLETED
# ============================================================================

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

if ($errorOccurred) {
    Write-Host "Script completed with warnings"
    Write-Host "Exit code : 0 (check output for details)"
} else {
    Write-Host "Script completed successfully"
    Write-Host "Exit code : 0"
}

Write-Host ""

exit 0
