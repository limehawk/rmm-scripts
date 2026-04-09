#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Public IP to SuperOps                                        v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : March 2026
#  USAGE    : ./public_ip_export_superops_macos.sh
# ================================================================================
#  FILE     : public_ip_export_superops_macos.sh
#  DESCRIPTION : Fetches public IP info from wtfismyip.com and outputs formatted results
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Queries wtfismyip.com/json to retrieve public IP address, ISP, geolocation,
#    and hostname information. Formats the results into readable output. On macOS
#    and Linux, SuperOps does not provide a Send-CustomField equivalent, so
#    results are output to stdout for manual review or future automation.
#
#  DATA SOURCES & PRIORITY
#
#    - wtfismyip.com/json (primary) - public IP lookup API
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - API_URL : wtfismyip.com JSON endpoint (valid HTTPS URL)
#
#  SETTINGS
#
#    - API URL     : https://wtfismyip.com/json
#    - Output      : Formatted multiline text to stdout
#    - Timeout     : 30 seconds (curl)
#
#  BEHAVIOR
#
#    1. Validates curl is available
#    2. Queries wtfismyip.com/json for public IP information
#    3. Parses JSON response using python3 (macOS built-in)
#    4. Displays formatted results to stdout
#    5. Exits 0 on success, exits 1 on failure
#
#  PREREQUISITES
#
#    - curl (pre-installed on macOS and most Linux)
#    - python3 (pre-installed on macOS, common on Linux)
#    - Internet connectivity to reach wtfismyip.com
#    - No admin privileges required
#
#  SECURITY NOTES
#
#    - Public IP address is displayed in console output
#    - No secrets in logs
#    - All network operations use HTTPS
#
#  ENDPOINTS
#
#    - https://wtfismyip.com/json - Public IP lookup API
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    All required inputs are present
#
#    [RUN] PUBLIC IP LOOKUP
#    ==============================================================
#    Querying wtfismyip.com for public IP info
#    API response received successfully
#
#    [OK] RESULTS
#    ==============================================================
#    IP       : 73.XXX.XXX.XXX
#    Location : Nashville, TN, United States
#    Hostname : 73-XXX-XXX-XXX.example.net
#    ISP      : Comcast Cable
#    Country  : United States (US)
#    Tor Exit : No
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Status : Success
#    Public IP info captured
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-03-13 v1.0.0 Initial release
# ================================================================================

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
API_URL="https://wtfismyip.com/json"
# ============================================================================

# ============================================================================
# INPUT VALIDATION
# ============================================================================

echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="

ERROR_OCCURRED=false
ERROR_TEXT=""

if [[ -z "$API_URL" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- API URL is required"
fi

if ! command -v curl &> /dev/null; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- curl is not installed"
fi

if ! command -v python3 &> /dev/null; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- python3 is not installed"
fi

if [[ "$ERROR_OCCURRED" = true ]]; then
    echo ""
    echo "[ERROR] INPUT VALIDATION FAILED"
    echo "=============================================================="
    echo -e "$ERROR_TEXT"
    echo ""
    echo "Troubleshooting:"
    echo "- Ensure curl and python3 are installed"
    echo "- Check hardcoded variables in script body"
    exit 1
fi

echo "All required inputs are present"

# ============================================================================
# PUBLIC IP LOOKUP
# ============================================================================

echo ""
echo "[RUN] PUBLIC IP LOOKUP"
echo "=============================================================="

echo "Querying wtfismyip.com for public IP info"

RESPONSE=$(curl -s --max-time 30 "$API_URL" 2>&1)

if [[ $? -ne 0 ]] || [[ -z "$RESPONSE" ]]; then
    echo ""
    echo "[ERROR] PUBLIC IP LOOKUP FAILED"
    echo "=============================================================="
    echo "Error Message:"
    echo "$RESPONSE"
    echo ""
    echo "API URL:"
    echo "$API_URL"
    echo ""
    echo "Troubleshooting:"
    echo "- Verify internet connectivity"
    echo "- Check if wtfismyip.com is accessible from this network"
    echo "- Ensure no proxy or firewall is blocking the request"
    exit 1
fi

echo "API response received successfully"

# Parse JSON with python3
PARSED=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    ip = d.get('YourFuckingIPAddress', 'Unknown')
    loc = d.get('YourFuckingLocation', 'Unknown')
    host = d.get('YourFuckingHostname', 'Unknown')
    isp = d.get('YourFuckingISP', 'Unknown')
    country = d.get('YourFuckingCountry', 'Unknown')
    cc = d.get('YourFuckingCountryCode', 'Unknown')
    tor = 'Yes' if d.get('YourFuckingTorExit', False) else 'No'
    print(f'IP: {ip}')
    print(f'Location: {loc}')
    print(f'Hostname: {host}')
    print(f'ISP: {isp}')
    print(f'Country: {country} ({cc})')
    print(f'Tor Exit: {tor}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" <<< "$RESPONSE")

if [[ $? -ne 0 ]]; then
    echo ""
    echo "[ERROR] JSON PARSING FAILED"
    echo "=============================================================="
    echo "Error Message:"
    echo "$PARSED"
    echo ""
    echo "Raw Response:"
    echo "$RESPONSE"
    echo ""
    echo "Troubleshooting:"
    echo "- Verify python3 is working correctly"
    echo "- Check that wtfismyip.com returned valid JSON"
    exit 1
fi

# ============================================================================
# RESULTS
# ============================================================================

echo ""
echo "[OK] RESULTS"
echo "=============================================================="

# Display with KV alignment for console
IP_ADDR=$(echo "$PARSED" | grep "^IP:" | cut -d' ' -f2-)
LOCATION=$(echo "$PARSED" | grep "^Location:" | cut -d' ' -f2-)
HOSTNAME_VAL=$(echo "$PARSED" | grep "^Hostname:" | cut -d' ' -f2-)
ISP=$(echo "$PARSED" | grep "^ISP:" | cut -d' ' -f2-)
COUNTRY=$(echo "$PARSED" | grep "^Country:" | cut -d' ' -f2-)
TOR_EXIT=$(echo "$PARSED" | grep "^Tor Exit:" | cut -d' ' -f3-)

echo "IP       : $IP_ADDR"
echo "Location : $LOCATION"
echo "Hostname : $HOSTNAME_VAL"
echo "ISP      : $ISP"
echo "Country  : $COUNTRY"
echo "Tor Exit : $TOR_EXIT"

# ============================================================================
# FINAL STATUS
# ============================================================================

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Status : Success"
echo "Public IP info captured"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="

exit 0
