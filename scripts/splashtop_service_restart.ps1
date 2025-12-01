$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Splashtop Service Restart                                      v1.0.0
FILE   : splashtop_service_restart.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Restarts the Splashtop Remote Service to resolve connectivity or
    performance issues with Splashtop remote access.

REQUIRED INPUTS:
    $serviceName : Name of the Splashtop service to restart

BEHAVIOR:
    1. Validates service name input
    2. Checks if service exists
    3. Restarts the service
    4. Reports final status

PREREQUISITES:
    - Windows OS
    - Administrator privileges
    - Splashtop Streamer installed

SECURITY NOTES:
    - No secrets in logs

EXIT CODES:
    0 = Success
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Service Name : SplashtopRemoteService
    Inputs validated successfully

    [ SERVICE RESTART ]
    --------------------------------------------------------------
    Restarting SplashtopRemoteService...
    Service restarted successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    Service Name : SplashtopRemoteService
    Status : Running

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$serviceName = 'SplashtopRemoteService'

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($serviceName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Service name is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host "Service Name : $serviceName"
Write-Host "Inputs validated successfully"

# ============================================================================
# SERVICE RESTART
# ============================================================================
Write-Host ""
Write-Host "[ SERVICE RESTART ]"
Write-Host "--------------------------------------------------------------"

try {
    $service = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Restarting $serviceName..."
    Restart-Service -InputObject $service -Force
    Start-Sleep -Seconds 3
    Write-Host "Service restarted successfully"
}
catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Service $serviceName could not be found"
    Write-Host "Ensure Splashtop Streamer is installed"
    exit 1
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to restart service"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

$finalService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($finalService -and $finalService.Status -eq 'Running') {
    Write-Host "Result : SUCCESS"
    Write-Host "Service Name : $serviceName"
    Write-Host "Status : $($finalService.Status)"
} else {
    Write-Host "Result : WARNING"
    Write-Host "Service may not be running properly"
    Write-Host "Status : $($finalService.Status)"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
