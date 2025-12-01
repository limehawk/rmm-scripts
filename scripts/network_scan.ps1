$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Network IP Scanner                                             v1.0.0
FILE   : network_scan.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Scans a range of IP addresses using multi-threaded ping requests to discover
    active hosts on the network. Optionally resolves hostnames via DNS.

REQUIRED INPUTS:
    $startIP          : Starting IP address of the range to scan
    $endIP            : Ending IP address of the range to scan
    $disableDNS       : Skip DNS hostname resolution (faster)
    $threads          : Number of concurrent threads (default: 32)
    $pingAttempts     : Number of ping attempts per IP (default: 1)

BEHAVIOR:
    1. Validates IP address range
    2. Creates runspace pool for parallel execution
    3. Pings each IP in the range
    4. Optionally resolves hostnames for responding IPs
    5. Outputs results sorted by IP address

PREREQUISITES:
    - Windows PowerShell 5.1 or later
    - Network access to target IP range

SECURITY NOTES:
    - No secrets in logs
    - Only performs ICMP ping and DNS lookups

EXIT CODES:
    0 = Success
    1 = Failure (invalid IP range)

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    Start IP : 192.168.1.1
    End IP   : 192.168.1.254
    Threads  : 32

    [ SCANNING NETWORK ]
    --------------------------------------------------------------
    Scanning 254 IP addresses...

    [ RESULTS ]
    --------------------------------------------------------------
    IPv4Address    Status Hostname
    -----------    ------ --------
    192.168.1.1    Up     router.local
    192.168.1.10   Up     desktop-pc.local
    192.168.1.25   Up

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : 3 hosts found

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
$startIP = "192.168.1.1"
$endIP = "192.168.1.254"
$disableDNS = $false
$threads = 32
$pingAttempts = 1

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Convert-IPv4ToInt {
    param([string]$IPv4)
    ($IPv4.Split('.') | ForEach-Object { [int]$_ }) |
        ForEach-Object -Begin { $sum = 0 } -Process { $sum = ($sum * 256) + $_ } -End { $sum }
}

function Convert-IntToIPv4 {
    param([int]$Int)
    ($Int -shr 24), (($Int -shr 16) -band 255), (($Int -shr 8) -band 255), ($Int -band 255) -join '.'
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

# Validate IP addresses
$ipPattern = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
if ($startIP -notmatch $ipPattern) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Invalid start IP address format"
}

if ($endIP -notmatch $ipPattern) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Invalid end IP address format"
}

if (-not $errorOccurred) {
    $startInt = Convert-IPv4ToInt -IPv4 $startIP
    $endInt = Convert-IPv4ToInt -IPv4 $endIP

    if ($startInt -gt $endInt) {
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Start IP must be less than or equal to End IP"
    }
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Input validation failed:"
    Write-Host $errorText
    exit 1
}

Write-Host "Start IP    : $startIP"
Write-Host "End IP      : $endIP"
Write-Host "Threads     : $threads"
Write-Host "DNS Lookup  : $(if ($disableDNS) { 'Disabled' } else { 'Enabled' })"

$totalIPs = $endInt - $startInt + 1
Write-Host "IPs to Scan : $totalIPs"

# ============================================================================
# SCAN NETWORK
# ============================================================================
Write-Host ""
Write-Host "[ SCANNING NETWORK ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Scanning $totalIPs IP addresses..."

$scriptBlock = {
    param($IP, $DisableDNS, $Attempts)

    try {
        $ping = New-Object System.Net.NetworkInformation.Ping

        for ($i = 0; $i -lt $Attempts; $i++) {
            $reply = $ping.Send($IP, 1000)

            if ($reply.Status -eq "Success") {
                $hostname = ""
                if (-not $DisableDNS) {
                    try { $hostname = [System.Net.Dns]::GetHostEntry($IP).HostName } catch { }
                }

                return [pscustomobject]@{
                    IPv4Address = $IP
                    Status      = "Up"
                    Hostname    = $hostname
                }
            }
        }

        return [pscustomobject]@{
            IPv4Address = $IP
            Status      = "Down"
            Hostname    = ""
        }
    }
    catch {
        return [pscustomobject]@{
            IPv4Address = $IP
            Status      = "Down"
            Hostname    = ""
        }
    }
}

$runspacePool = [runspacefactory]::CreateRunspacePool(1, $threads)
$runspacePool.Open()

$jobs = @()

for ($i = $startInt; $i -le $endInt; $i++) {
    $IP = Convert-IntToIPv4 -Int $i
    $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($IP).AddArgument($disableDNS).AddArgument($pingAttempts)
    $powershell.RunspacePool = $runspacePool
    $jobs += [pscustomobject]@{
        Handle      = $powershell
        AsyncResult = $powershell.BeginInvoke()
    }
}

$results = [System.Collections.ArrayList]::new()

foreach ($job in $jobs) {
    $result = $job.Handle.EndInvoke($job.AsyncResult)
    $job.Handle.Dispose()
    if ($result.Status -eq "Up") {
        [void]$results.Add($result)
    }
}

$runspacePool.Close()
$runspacePool.Dispose()

# ============================================================================
# RESULTS
# ============================================================================
Write-Host ""
Write-Host "[ RESULTS ]"
Write-Host "--------------------------------------------------------------"

if ($results.Count -gt 0) {
    $results | Sort-Object { [version]$_.IPv4Address } | Format-Table -AutoSize
}
else {
    Write-Host "No hosts responded to ping"
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : $($results.Count) host(s) found"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
