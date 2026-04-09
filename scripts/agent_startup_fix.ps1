$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
 SCRIPT   : Fix RMM Agent Startup                                        v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\agent_startup_fix.ps1
================================================================================
 FILE     : agent_startup_fix.ps1
 DESCRIPTION : Fixes RMM agent service startup with recovery options and delayed start
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Configures the RMM agent service with proper recovery options and delayed
   automatic start to prevent startup failures on slow or overloaded machines.
   Detects the agent service by searching for common RMM agent patterns.

 DATA SOURCES & PRIORITY

   - Windows Services: Service name, display name, binary path
   - Windows Event Log: Service Control Manager crash events

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $ServiceName       : RMM agent service name (default: limehawk)
     - $RestartDelay1     : First failure restart delay in ms (default: 60000)
     - $RestartDelay2     : Second failure restart delay in ms (default: 60000)
     - $RestartDelay3     : Third failure restart delay in ms (default: 120000)
     - $ResetPeriod       : Reset failure count after seconds (default: 86400)
     - $EventLogDays      : Days of crash events to show (default: 3)

 SETTINGS

   Configuration details and default values:
     - Service name: limehawk
     - Recovery: Restart after 60s, 60s, then 120s
     - Reset failure count: Every 24 hours
     - Startup type: Automatic (Delayed Start) via registry
     - Event log lookback: 3 days

 BEHAVIOR

   The script performs the following actions in order:
   1. Locates the RMM agent service by name
   2. Reports current service status and startup type
   3. Sets service recovery options (restart on failure)
   4. Sets service to Automatic (Delayed Start) via registry
   5. Reports recent crash events from Event Viewer

 PREREQUISITES

   - Windows OS
   - Administrator privileges
   - RMM agent installed

 SECURITY NOTES

   - No secrets in logs
   - Service binary path is displayed for verification

 ENDPOINTS

   - None (local operations only)

 EXIT CODES

   0 = Success
   1 = Failure (service not found)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Service Name         : limehawk
     Restart Delay 1      : 60000 ms
     Restart Delay 2      : 60000 ms
     Restart Delay 3      : 120000 ms
     Reset Period         : 86400 s

   [INFO] SERVICE DETECTION
   ==============================================================
     Service Name         : limehawk
     Display Name         : limehawk
     Status               : Running
     Start Type           : Automatic
     Binary Path          : "C:\Program Files\limehawkrmm\bin\superops.exe" ...

   [RUN] SET RECOVERY OPTIONS
   ==============================================================
     Configuring restart on failure...
     Recovery options set

   [RUN] SET DELAYED START
   ==============================================================
     Setting Automatic (Delayed Start) via registry...
     Delayed start configured

   [INFO] RECENT CRASH EVENTS
   ==============================================================
     2026-03-09 The limehawk Updater service terminated unexpectedly.

   [OK] FINAL STATUS
   ==============================================================
     Result               : SUCCESS
     Recovery options     : Configured
     Startup type         : Automatic (Delayed Start)

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-09 v1.0.0 Initial release - RMM agent startup fix with recovery and delayed start
================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================
$ServiceName   = "limehawk"
$RestartDelay1 = 60000
$RestartDelay2 = 60000
$RestartDelay3 = 120000
$ResetPeriod   = 86400
$EventLogDays  = 3

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "  Service Name         : $ServiceName"
Write-Host "  Restart Delay 1      : $RestartDelay1 ms"
Write-Host "  Restart Delay 2      : $RestartDelay2 ms"
Write-Host "  Restart Delay 3      : $RestartDelay3 ms"
Write-Host "  Reset Period         : $ResetPeriod s"

# ==============================================================================
# SERVICE DETECTION
# ==============================================================================
Write-Host ""
Write-Host "[INFO] SERVICE DETECTION"
Write-Host "=============================================================="

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Service '$ServiceName' not found"
    Write-Host "  Verify the service name and try again"
    exit 1
}

$wmi = Get-WmiObject Win32_Service -Filter "Name='$ServiceName'"

Write-Host "  Service Name         : $($svc.Name)"
Write-Host "  Display Name         : $($svc.DisplayName)"
Write-Host "  Status               : $($svc.Status)"
Write-Host "  Start Type           : $($svc.StartType)"
Write-Host "  Binary Path          : $($wmi.PathName)"

# ==============================================================================
# SET RECOVERY OPTIONS
# ==============================================================================
Write-Host ""
Write-Host "[RUN] SET RECOVERY OPTIONS"
Write-Host "=============================================================="
Write-Host "  Configuring restart on failure..."

$scResult = sc.exe failure $ServiceName reset= $ResetPeriod actions= restart/$RestartDelay1/restart/$RestartDelay2/restart/$RestartDelay3 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "  Failed to set recovery options"
    Write-Host "  sc.exe output: $scResult"
    exit 1
}

Write-Host "  Recovery options set"

# Verify
sc.exe qfailure $ServiceName 2>&1 | ForEach-Object {
    $line = $_.ToString().Trim()
    if ($line -and $line -notmatch '^\[SC\]') {
        Write-Host "  $line"
    }
}

# ==============================================================================
# SET DELAYED START
# ==============================================================================
Write-Host ""
Write-Host "[RUN] SET DELAYED START"
Write-Host "=============================================================="
Write-Host "  Setting Automatic (Delayed Start) via registry..."

# Set to Automatic first
Set-Service -Name $ServiceName -StartupType Automatic

# Add delayed start via registry (compatible with Server 2019 PowerShell)
$regPath = "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName"
reg add $regPath /v DelayedAutostart /t REG_DWORD /d 1 /f 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Delayed start configured"
} else {
    Write-Host ""
    Write-Host "[WARN] WARNING"
    Write-Host "=============================================================="
    Write-Host "  Failed to set delayed start via registry"
    Write-Host "  Service is set to Automatic but not Delayed"
}

# ==============================================================================
# RECENT CRASH EVENTS
# ==============================================================================
Write-Host ""
Write-Host "[INFO] RECENT CRASH EVENTS"
Write-Host "=============================================================="

$startDate = (Get-Date).AddDays(-$EventLogDays)
$events = Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    ProviderName = 'Service Control Manager'
    Level        = 2
    StartTime    = $startDate
} -ErrorAction SilentlyContinue | Where-Object {
    $_.Message -like "*$ServiceName*"
}

if ($events) {
    foreach ($evt in $events) {
        $msg = $evt.Message
        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) + "..." }
        Write-Host "  $($evt.TimeCreated.ToString('yyyy-MM-dd HH:mm')) $msg"
    }
    Write-Host "  Total crash events   : $($events.Count)"
} else {
    Write-Host "  No crash events found in last $EventLogDays days"
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================
$svc = Get-Service -Name $ServiceName
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "  Result               : SUCCESS"
Write-Host "  Recovery options     : Configured"
Write-Host "  Startup type         : Automatic (Delayed Start)"
Write-Host "  Current status       : $($svc.Status)"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
