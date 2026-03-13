Import-Module $SuperOpsModule
$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Public IP to SuperOps                                         v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\public_ip_to_superops.ps1
================================================================================
 FILE     : public_ip_to_superops.ps1
DESCRIPTION : Fetches public IP info from wtfismyip.com and syncs to SuperOps
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

Queries wtfismyip.com/json to retrieve public IP address, ISP, geolocation,
and hostname information. Formats the results into a readable multiline string
and sends it to a SuperOps custom field for network visibility and auditing.

DATA SOURCES & PRIORITY

1. wtfismyip.com/json (primary) - public IP lookup API
2. SuperOps custom field (output) - multiline text field for formatted results

REQUIRED INPUTS

All inputs are hardcoded in the script body:
  - $apiUrl             : wtfismyip.com JSON endpoint (valid HTTPS URL)
  - $customFieldName    : SuperOps custom field name (must exist in tenant)

SuperOps Custom Fields (must exist in tenant):
  - "Public IP"         : Multiline Text field for formatted IP info

SETTINGS

  - API URL         : https://wtfismyip.com/json
  - Field Name      : Public IP
  - Output Format   : Formatted multiline text (IP, Location, ISP, etc.)
  - Timeout         : PowerShell defaults (Invoke-RestMethod)

BEHAVIOR

1. Validates all hardcoded input values are present
2. Queries wtfismyip.com/json for public IP information
3. Parses JSON response and formats into readable multiline text
4. Sends formatted text to SuperOps "Public IP" custom field
5. Reports results to console
6. Exits 0 on success, exits 1 if any critical step fails

PREREQUISITES

  - SuperOps PowerShell module must be available and authenticated
  - Internet connectivity to reach wtfismyip.com
  - Windows OS with PowerShell 5.1+ or PowerShell 7+
  - No admin privileges required

SECURITY NOTES

  - Public IP address is displayed in console output and sent to SuperOps
  - No secrets are printed to console output or logs
  - All network operations use HTTPS

ENDPOINTS

  - https://wtfismyip.com/json - Public IP lookup API

EXIT CODES

  0 = Success - IP info retrieved and sent to SuperOps
  1 = Failure - input validation, API call, or sync failed

EXAMPLE RUN

  [INFO] INPUT VALIDATION
  ==============================================================
  All required inputs are present

  [RUN] PUBLIC IP LOOKUP
  ==============================================================
  Querying wtfismyip.com for public IP info
  API response received successfully

  [OK] RESULTS
  ==============================================================
  IP       : 73.XXX.XXX.XXX
  Location : Nashville, TN, United States
  Hostname : 73-XXX-XXX-XXX.example.net
  ISP      : Comcast Cable
  Country  : United States (US)
  Tor Exit : No

  [RUN] SUPEROPS SYNC
  ==============================================================
  Sent Public IP info to SuperOps
  Custom field synchronized successfully

  [OK] FINAL STATUS
  ==============================================================
  Status : Success
  Public IP info captured and synchronized to SuperOps

  [OK] SCRIPT COMPLETED
  ==============================================================
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-13 v1.0.0 Initial release
================================================================================
#>

Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================

$apiUrl          = 'https://wtfismyip.com/json'
$customFieldName = 'Public IP'

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText     = ""

if ([string]::IsNullOrWhiteSpace($superOpsModule)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- SuperOps module variable is not set"
}

if ([string]::IsNullOrWhiteSpace($apiUrl)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- API URL is required"
}

if ([string]::IsNullOrWhiteSpace($customFieldName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Custom field name is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify SuperOps module is configured in RMM environment"
    Write-Host "- Check hardcoded variables in script body"
    exit 1
}

Write-Host "All required inputs are present"

# ============================================================================
# PUBLIC IP LOOKUP
# ============================================================================

Write-Host ""
Write-Host "[RUN] PUBLIC IP LOOKUP"
Write-Host "=============================================================="

try {
    Write-Host "Querying wtfismyip.com for public IP info"
    $ipData = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    Write-Host "API response received successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] PUBLIC IP LOOKUP FAILED"
    Write-Host "=============================================================="
    Write-Host "Error Message:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "API URL:"
    Write-Host $apiUrl
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify internet connectivity"
    Write-Host "- Check if wtfismyip.com is accessible from this network"
    Write-Host "- Ensure no proxy or firewall is blocking the request"
    exit 1
}

# ============================================================================
# RESULTS
# ============================================================================

Write-Host ""
Write-Host "[OK] RESULTS"
Write-Host "=============================================================="

$ipAddress = $ipData.YourFuckingIPAddress
$location  = $ipData.YourFuckingLocation
$hostname  = $ipData.YourFuckingHostname
$isp       = $ipData.YourFuckingISP
$torExit   = if ($ipData.YourFuckingTorExit) { 'Yes' } else { 'No' }
$city      = $ipData.YourFuckingCity
$country   = $ipData.YourFuckingCountry
$countryCode = $ipData.YourFuckingCountryCode

Write-Host "IP       : $ipAddress"
Write-Host "Location : $location"
Write-Host "Hostname : $hostname"
Write-Host "ISP      : $isp"
Write-Host "Country  : $country ($countryCode)"
Write-Host "Tor Exit : $torExit"

# Format multiline text for custom field
$fieldValue = @"
IP: $ipAddress
Location: $location
Hostname: $hostname
ISP: $isp
Country: $country ($countryCode)
Tor Exit: $torExit
"@

# ============================================================================
# SUPEROPS SYNC
# ============================================================================

Write-Host ""
Write-Host "[RUN] SUPEROPS SYNC"
Write-Host "=============================================================="

try {
    Send-CustomField -CustomFieldName $customFieldName -Value $fieldValue -ErrorAction Stop
    Write-Host "Sent Public IP info to SuperOps"
    Write-Host "Custom field synchronized successfully"
} catch {
    Write-Host ""
    Write-Host "[ERROR] SUPEROPS SYNC FAILED"
    Write-Host "=============================================================="
    Write-Host "Error Message:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify custom field 'Public IP' exists in SuperOps tenant"
    Write-Host "- Check field name matches exactly (case-sensitive)"
    Write-Host "- Ensure field type is Multiline Text"
    Write-Host "- Verify SuperOps authentication is still valid"
    exit 1
}

# ============================================================================
# FINAL STATUS
# ============================================================================

Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Status : Success"
Write-Host "Public IP info captured and synchronized to SuperOps"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
