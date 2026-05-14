$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : DNS Set Provider                                             v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : May 2026
 USAGE    : .\dns_set_provider.ps1
================================================================================
 FILE     : dns_set_provider.ps1
 DESCRIPTION : Sets IPv4 DNS servers on active adapters to a chosen provider
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Quickly switches all active physical IPv4 network adapters to a known
   public DNS provider chosen by number. Designed for SuperOps runtime
   replacement so a tech can pick the desired DNS from a numbered list
   without typing IP addresses or worrying about syntax.

 DATA SOURCES & PRIORITY

   1) SuperOps runtime variable (DnsProviderSelection)
   2) Hardcoded provider table (see PROVIDERS below)

 REQUIRED INPUTS

   - $DnsProviderSelection - SuperOps runtime replacement variable
                             holding the numeric provider selection
                             (1-14, see PROVIDERS table)

 PROVIDERS

    1  DHCP / Automatic        - clear static DNS, return to DHCP
    2  Cloudflare              - 1.1.1.1, 1.0.0.1
    3  Cloudflare Malware      - 1.1.1.2, 1.0.0.2  (block malware)
    4  Cloudflare Families     - 1.1.1.3, 1.0.0.3  (block malware + adult)
    5  Google                  - 8.8.8.8, 8.8.4.4
    6  OpenDNS                 - 208.67.222.222, 208.67.220.220
    7  OpenDNS FamilyShield    - 208.67.222.123, 208.67.220.123
    8  Quad9                   - 9.9.9.9, 149.112.112.112  (block malware)
    9  Quad9 Unsecured         - 9.9.9.10, 149.112.112.10  (no filtering)
   10  AdGuard                 - 94.140.14.14, 94.140.15.15  (block ads)
   11  AdGuard Family          - 94.140.14.15, 94.140.15.16  (block ads + adult)
   12  CleanBrowsing Security  - 185.228.168.9, 185.228.169.9
   13  CleanBrowsing Family    - 185.228.168.168, 185.228.169.168
   14  Control D Free          - 76.76.2.0, 76.76.10.0

 SETTINGS

   - Target adapters : all UP IPv4 adapters whose hardware
                       interface type is Ethernet (6) or 802.11 (71)
   - DNS family      : IPv4 only (IPv6 DNS untouched)
   - Cache flush     : ipconfig /flushdns after change

 BEHAVIOR

   1. Validates DnsProviderSelection is present and a number 1..14
   2. Resolves the selection to a provider name and DNS pair
   3. Enumerates active Ethernet / Wi-Fi adapters
   4. Applies the DNS servers to each adapter (or resets to DHCP if #1)
   5. Flushes the resolver cache
   6. Reports per-adapter status

 PREREQUISITES

   - Windows 10 1809+ / Windows Server 2019+
   - SYSTEM or Administrator privileges
   - At least one active Ethernet or Wi-Fi adapter

 EXIT CODES

   0 = Success - DNS applied to all targeted adapters
   1 = Failure - validation failed, or no adapters configured

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Selection       : 2
   Provider        : Cloudflare
   Primary DNS     : 1.1.1.1
   Secondary DNS   : 1.0.0.1
   Inputs validated

   [INFO] ENUMERATE ADAPTERS
   ==============================================================
   Found 1 active adapter(s)
    - Ethernet (Intel I219-V) [Up]

   [RUN] APPLY DNS
   ==============================================================
   Ethernet : applied 1.1.1.1, 1.0.0.1

   [RUN] FLUSH RESOLVER CACHE
   ==============================================================
   Cache flushed

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Provider        : Cloudflare
   Adapters set    : 1

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-05-14 v1.0.0 Initial release - numbered DNS provider selector
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS (SuperOps runtime replacement)
# ============================================================================

$DnsProviderSelection = "$DnsProviderSelection"   # SuperOps replaces $DnsProviderSelection

# Numbered provider table - keep in sync with the PROVIDERS section above
$ProviderTable = @{
    1  = @{ Name = "DHCP / Automatic";        Primary = $null;             Secondary = $null }
    2  = @{ Name = "Cloudflare";               Primary = "1.1.1.1";         Secondary = "1.0.0.1" }
    3  = @{ Name = "Cloudflare Malware";       Primary = "1.1.1.2";         Secondary = "1.0.0.2" }
    4  = @{ Name = "Cloudflare Families";      Primary = "1.1.1.3";         Secondary = "1.0.0.3" }
    5  = @{ Name = "Google";                   Primary = "8.8.8.8";         Secondary = "8.8.4.4" }
    6  = @{ Name = "OpenDNS";                  Primary = "208.67.222.222";  Secondary = "208.67.220.220" }
    7  = @{ Name = "OpenDNS FamilyShield";     Primary = "208.67.222.123";  Secondary = "208.67.220.123" }
    8  = @{ Name = "Quad9";                    Primary = "9.9.9.9";         Secondary = "149.112.112.112" }
    9  = @{ Name = "Quad9 Unsecured";          Primary = "9.9.9.10";        Secondary = "149.112.112.10" }
    10 = @{ Name = "AdGuard";                  Primary = "94.140.14.14";    Secondary = "94.140.15.15" }
    11 = @{ Name = "AdGuard Family";           Primary = "94.140.14.15";    Secondary = "94.140.15.16" }
    12 = @{ Name = "CleanBrowsing Security";   Primary = "185.228.168.9";   Secondary = "185.228.169.9" }
    13 = @{ Name = "CleanBrowsing Family";     Primary = "185.228.168.168"; Secondary = "185.228.169.168" }
    14 = @{ Name = "Control D Free";           Primary = "76.76.2.0";       Secondary = "76.76.10.0" }
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================

$errorOccurred = $false
$errorText = ""

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$selectionRaw = $DnsProviderSelection
if ([string]::IsNullOrWhiteSpace($selectionRaw) -or $selectionRaw -eq '$' + 'DnsProviderSelection') {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps runtime variable `$DnsProviderSelection was not replaced"
}

$selectionNum = 0
if (-not $errorOccurred) {
    if (-not [int]::TryParse($selectionRaw.Trim(), [ref]$selectionNum)) {
        $errorOccurred = $true
        $errorText += "- DnsProviderSelection must be a number (got: '$selectionRaw')"
    } elseif (-not $ProviderTable.ContainsKey($selectionNum)) {
        $errorOccurred = $true
        $errorText += "- DnsProviderSelection '$selectionNum' is not a valid choice (1..14)"
    }
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "Valid selections:"
    foreach ($k in ($ProviderTable.Keys | Sort-Object)) {
        $row = $ProviderTable[$k]
        if ($null -eq $row.Primary) {
            Write-Host ("  {0,2}  {1}" -f $k, $row.Name)
        } else {
            Write-Host ("  {0,2}  {1}  ({2}, {3})" -f $k, $row.Name, $row.Primary, $row.Secondary)
        }
    }
    Write-Host ""
    exit 1
}

$chosen = $ProviderTable[$selectionNum]
$providerName = $chosen.Name
$primaryDns   = $chosen.Primary
$secondaryDns = $chosen.Secondary
$isDhcp       = ($null -eq $primaryDns)

Write-Host "Selection       : $selectionNum"
Write-Host "Provider        : $providerName"
if ($isDhcp) {
    Write-Host "Mode            : Reset to DHCP (no static DNS)"
} else {
    Write-Host "Primary DNS     : $primaryDns"
    Write-Host "Secondary DNS   : $secondaryDns"
}
Write-Host "Inputs validated"

# ============================================================================
# ENUMERATE ADAPTERS
# ============================================================================

Write-Host ""
Write-Host "[INFO] ENUMERATE ADAPTERS"
Write-Host "=============================================================="

# InterfaceType 6 = Ethernet, 71 = 802.11 wireless
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceType -eq 6 -or $_.InterfaceType -eq 71) }

if (-not $adapters -or $adapters.Count -eq 0) {
    Write-Host ""
    Write-Host "[ERROR] NO ACTIVE ADAPTERS"
    Write-Host "=============================================================="
    Write-Host "No active Ethernet or Wi-Fi adapters found"
    Write-Host ""
    exit 1
}

Write-Host "Found $($adapters.Count) active adapter(s)"
foreach ($a in $adapters) {
    Write-Host " - $($a.Name) ($($a.InterfaceDescription)) [$($a.Status)]"
}

# ============================================================================
# APPLY DNS
# ============================================================================

Write-Host ""
Write-Host "[RUN] APPLY DNS"
Write-Host "=============================================================="

$successCount = 0
$failureCount = 0

foreach ($a in $adapters) {
    try {
        if ($isDhcp) {
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            Write-Host "$($a.Name) : reset to DHCP"
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @($primaryDns, $secondaryDns) -ErrorAction Stop
            Write-Host "$($a.Name) : applied $primaryDns, $secondaryDns"
        }
        $successCount++
    } catch {
        Write-Host "$($a.Name) : FAILED - $($_.Exception.Message)"
        $failureCount++
    }
}

if ($successCount -eq 0) {
    Write-Host ""
    Write-Host "[ERROR] NO ADAPTERS CONFIGURED"
    Write-Host "=============================================================="
    Write-Host "Failed to apply DNS to any adapter"
    Write-Host ""
    exit 1
}

# ============================================================================
# FLUSH RESOLVER CACHE
# ============================================================================

Write-Host ""
Write-Host "[RUN] FLUSH RESOLVER CACHE"
Write-Host "=============================================================="

try {
    & ipconfig.exe /flushdns | Out-Null
    Write-Host "Cache flushed"
} catch {
    Write-Host "Cache flush warning: $($_.Exception.Message)"
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status          : Success"
Write-Host "Provider        : $providerName"
Write-Host "Adapters set    : $successCount"
if ($failureCount -gt 0) {
    Write-Host "Adapters failed : $failureCount"
}
Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
exit 0
