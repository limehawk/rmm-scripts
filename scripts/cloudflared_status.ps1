$ErrorActionPreference = 'Continue'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Cloudflared Status                                           v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\cloudflared_status.ps1
================================================================================
 FILE     : cloudflared_status.ps1
 DESCRIPTION : Reports cloudflared binary, service, and tunnel connectivity state
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Field-triage view of a Windows endpoint's Cloudflare Tunnel connector.
   Reports the cloudflared binary version and install path, the
   Cloudflare Tunnel service Status and StartType, and a best-effort
   tunnel connectivity verdict pulled from the Windows Event Log with an
   outbound-socket fallback signal. Always exits 0 - absence of target
   is itself a valid status, not an error.

 DATA SOURCES & PRIORITY

   1) cloudflared.exe --version (binary)
   2) Get-Service "Cloudflare Tunnel" (service)
   3) Windows Application Event Log (primary connectivity signal)
   4) Get-NetTCPConnection / Get-NetUDPEndpoint on port 7844 (fallback)

 REQUIRED INPUTS

   None - all configuration is hardcoded

 SETTINGS

   - Service Name     : Cloudflare Tunnel
   - Event log window : last 15 minutes
   - Event log source : cloudflared (verify on a registered host with
                        Get-WinEvent -ListProvider *cloud* - source name
                        not empirically confirmed at scaffold time)
   - Connector port   : 7844 (TCP and UDP)

 BEHAVIOR

   1. Resolves cloudflared.exe; if absent reports Not installed and exits 0
   2. Reports binary version and install path
   3. Reports service Status and StartType
   4. Reads recent Application log entries for tunnel connector events
   5. If no event log signal, falls back to Get-NetTCPConnection /
      Get-NetUDPEndpoint on port 7844
   6. Always prints which signal was used so the field tech knows the basis

 PREREQUISITES

   - Windows 10 1809+ / Windows Server 2019+
   - Read access to the Application Event Log
   - PowerShell 5.1 or later

 SECURITY NOTES

   - No secrets in logs
   - Read-only - makes no system or service changes

 EXIT CODES

   0 = Always - status scripts report, they do not fail

 EXAMPLE RUN

   [INFO] BINARY
   ==============================================================
   Binary Present  : Yes
   Binary Path     : C:\Program Files (x86)\cloudflared\cloudflared.exe
   Version         : 2025.4.0

   [INFO] SERVICE
   ==============================================================
   Service Name    : Cloudflare Tunnel
   Status          : Running
   Start Type      : Automatic

   [INFO] TUNNEL CONNECTIVITY
   ==============================================================
   Signal Used     : Event Log
   Last Event      : 2026-05-12 10:15:22
   Verdict         : Healthy - Registered tunnel connection

   [OK] FINAL STATUS
   ==============================================================
   Status          : Reported

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-12 v1.0.0 Initial release - cloudflared health and connectivity status
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================

$ServiceName     = "Cloudflare Tunnel"
$FallbackBinary  = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$EventLogSource  = "cloudflared"   # Verify on registered host: Get-WinEvent -ListProvider *cloud*
$EventWindowMins = 15
$ConnectorPort   = 7844

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="
Write-Host "No runtime inputs required"

# ============================================================================
# BINARY
# ============================================================================

Write-Host ""
Write-Host "[INFO] BINARY"
Write-Host "=============================================================="

$cloudflaredExe = $null
$cloudflaredCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cloudflaredCmd) {
    $cloudflaredExe = $cloudflaredCmd.Source
} elseif (Test-Path $FallbackBinary) {
    $cloudflaredExe = $FallbackBinary
}

if (-not $cloudflaredExe) {
    Write-Host "Binary Present  : No"
    Write-Host "Version         : Not installed"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Status          : Reported (cloudflared not installed)"
    Write-Host ""
    Write-Host "[OK] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 0
}

$binaryVersion = "Unknown"
try {
    $versionOutput = & $cloudflaredExe --version 2>&1
    if ($versionOutput -match '([\d]+\.[\d]+\.[\d]+)') {
        $binaryVersion = $matches[1]
    } elseif ($versionOutput) {
        $binaryVersion = ($versionOutput | Select-Object -First 1).ToString()
    }
} catch {
    $binaryVersion = "Unknown"
}

Write-Host "Binary Present  : Yes"
Write-Host "Binary Path     : $cloudflaredExe"
Write-Host "Version         : $binaryVersion"

# ============================================================================
# SERVICE
# ============================================================================

Write-Host ""
Write-Host "[INFO] SERVICE"
Write-Host "=============================================================="

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceRegistered = [bool]$svc

Write-Host "Service Name    : $ServiceName"
if ($serviceRegistered) {
    Write-Host "Status          : $($svc.Status)"
    Write-Host "Start Type      : $($svc.StartType)"
} else {
    Write-Host "Status          : Not registered"
    Write-Host "Start Type      : n/a"
}

# ============================================================================
# TUNNEL CONNECTIVITY
# ============================================================================

Write-Host ""
Write-Host "[INFO] TUNNEL CONNECTIVITY"
Write-Host "=============================================================="

if (-not $serviceRegistered) {
    Write-Host "Signal Used     : None"
    Write-Host "Verdict         : Service not registered - no tunnel to check"
} else {
    $signalUsed = "None"
    $verdict = "Unknown"
    $eventTime = $null

    # Primary signal - Windows Event Log
    $sinceTime = (Get-Date).AddMinutes(-1 * $EventWindowMins)
    $logEntry = $null
    try {
        $filter = @{
            LogName      = 'Application'
            ProviderName = $EventLogSource
            StartTime    = $sinceTime
        }
        $logEntry = Get-WinEvent -FilterHashtable $filter -MaxEvents 50 -ErrorAction SilentlyContinue |
                    Sort-Object TimeCreated -Descending | Select-Object -First 1
    } catch {
        $logEntry = $null
    }

    if ($logEntry) {
        $signalUsed = "Event Log"
        $eventTime = $logEntry.TimeCreated
        $msg = $logEntry.Message
        if ($msg -match 'Registered tunnel connection') {
            $verdict = "Healthy - Registered tunnel connection"
        } elseif ($msg -match 'failed to connect to the edge|Unable to reach the origin|connection refused') {
            $verdict = "Unhealthy - $($matches[0])"
        } else {
            $verdict = "Activity present - $(($msg -split "`n")[0])"
        }
    } else {
        # Fallback signal - outbound socket on port 7844
        $signalUsed = "Outbound Socket"
        $cloudflaredProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
        $hasConnection = $false

        if ($cloudflaredProc) {
            try {
                $tcpConn = Get-NetTCPConnection -RemotePort $ConnectorPort -State Established -ErrorAction SilentlyContinue |
                           Where-Object { $cloudflaredProc.Id -contains $_.OwningProcess }
                if ($tcpConn) { $hasConnection = $true }
            } catch { }

            if (-not $hasConnection) {
                try {
                    $udpEnd = Get-NetUDPEndpoint -LocalPort $ConnectorPort -ErrorAction SilentlyContinue |
                              Where-Object { $cloudflaredProc.Id -contains $_.OwningProcess }
                    if (-not $udpEnd) {
                        # Some cloudflared builds use UDP outbound on the remote side
                        $udpEnd = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
                                  Where-Object { $cloudflaredProc.Id -contains $_.OwningProcess }
                    }
                    if ($udpEnd) { $hasConnection = $true }
                } catch { }
            }
        }

        if ($hasConnection) {
            $verdict = "Connector socket established (no recent event log activity)"
        } else {
            $verdict = "No connector socket - tunnel likely offline"
        }
    }

    Write-Host "Signal Used     : $signalUsed"
    if ($eventTime) {
        Write-Host "Last Event      : $($eventTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    } else {
        Write-Host "Last Event      : None in last $EventWindowMins min"
    }
    Write-Host "Verdict         : $verdict"
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status          : Reported"
Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
