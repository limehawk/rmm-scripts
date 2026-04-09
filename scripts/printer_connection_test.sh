#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Printer Connection Test                                      v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : ./printer_connection_test.sh
# ================================================================================
#  FILE     : printer_connection_test.sh
#  DESCRIPTION : Tests network printer connectivity via ping and IPP port check
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Tests network connectivity to configured printers by pinging their
#    hostnames/IPs. Reports success/failure for each printer and optionally
#    sends an email alert if any tests fail.
#
#  DATA SOURCES & PRIORITY
#
#    - Network ping: Tests ICMP connectivity to each printer
#    - DNS lookup: Additional diagnostics for failed connections
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - PRINTERS: Array of printer hostnames or IP addresses
#      - SEND_EMAIL: Enable/disable email notifications
#      - MAIL_TO: Recipient email address
#      - MAIL_FROM: Sender email address
#
#  SETTINGS
#
#    Default configuration:
#      - Ping count: 2 packets
#      - Ping timeout: 5 seconds
#      - Email alerts: Disabled by default
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Displays test configuration
#    2. Pings each configured printer
#    3. Records pass/fail status for each
#    4. Performs DNS lookup for failed printers
#    5. Sends email alert if configured and failures occurred
#    6. Reports final status with counts
#
#  PREREQUISITES
#
#    - macOS or Linux
#    - Network access to printer hosts
#    - (Optional) sendmail for email alerts
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Email credentials not stored in script
#    - Log files stored in /tmp (auto-cleaned)
#
#  ENDPOINTS
#
#    - Configured printer hostnames/IPs (ping targets)
#
#  EXIT CODES
#
#    0 = All printers reachable
#    1 = One or more printers unreachable
#
#  EXAMPLE RUN
#
#    [INFO] PRINTER CONNECTION TEST
#    ==============================================================
#    Hostname : workstation01
#    Date     : Mon Dec 23 10:00:00 PST 2024
#    Printers : 3
#
#    [RUN] TESTING CONNECTIVITY
#    ==============================================================
#    Testing printer1.example.com... OK
#    Testing printer2.example.com... FAILED
#    Testing 192.168.1.100... OK
#
#    [ERROR] FINAL STATUS
#    ==============================================================
#    Result : FAILURE
#    Failed : 1 printer(s) unreachable
#
#    [ERROR] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-01-01 v1.0.0 Initial release
# ================================================================================

set -euo pipefail

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Printer hostnames or IP addresses to test
PRINTERS=(
    "printer1.example.com"
    "printer2.example.com"
    "192.168.1.100"
)

# Email notification settings (leave empty to disable)
SEND_EMAIL="false"           # Set to "true" to enable email alerts
MAIL_TO=""                   # e.g., "admin@example.com"
MAIL_FROM=""                 # e.g., "noreply@example.com"
MAIL_SUBJECT="Printer Connectivity Alert - $(hostname)"
# ============================================================================

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[INFO] PRINTER CONNECTION TEST"
echo "=============================================================="
echo "Hostname : $(hostname)"
echo "Date     : $(date)"
echo "Printers : ${#PRINTERS[@]}"

# Initialize tracking
FAILED_COUNT=0
FAILED_PRINTERS=""
LOG_FILE="/tmp/printer_test_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo "[RUN] TESTING CONNECTIVITY"
echo "=============================================================="

for PRINTER in "${PRINTERS[@]}"; do
    echo -n "Testing $PRINTER... "

    if ping -c 2 -W 5 "$PRINTER" > /dev/null 2>&1; then
        echo "OK"
        echo "[PASS] $PRINTER" >> "$LOG_FILE"
    else
        echo "FAILED"
        echo "[FAIL] $PRINTER" >> "$LOG_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        if [ -n "$FAILED_PRINTERS" ]; then
            FAILED_PRINTERS="$FAILED_PRINTERS, $PRINTER"
        else
            FAILED_PRINTERS="$PRINTER"
        fi

        # Get additional diagnostic info
        echo "  DNS lookup:" >> "$LOG_FILE"
        host "$PRINTER" >> "$LOG_FILE" 2>&1 || echo "  DNS lookup failed" >> "$LOG_FILE"
    fi
done

echo ""

# ============================================================================
# SEND EMAIL ALERT IF CONFIGURED
# ============================================================================
if [ "$FAILED_COUNT" -gt 0 ] && [ "$SEND_EMAIL" = "true" ] && [ -n "$MAIL_TO" ]; then
    echo ""
    echo "[RUN] SENDING ALERT"
    echo "=============================================================="

    if command -v sendmail > /dev/null 2>&1; then
        {
            echo "Subject: $MAIL_SUBJECT"
            echo "From: $MAIL_FROM"
            echo "To: $MAIL_TO"
            echo ""
            echo "Printer connectivity test failed on $(hostname)"
            echo ""
            echo "Failed printers: $FAILED_PRINTERS"
            echo ""
            echo "Test log:"
            cat "$LOG_FILE"
        } | sendmail -t
        echo "Alert sent to $MAIL_TO"
    else
        echo "sendmail not available - skipping email alert"
    fi
    echo ""
fi

# ============================================================================
# FINAL STATUS
# ============================================================================
if [ "$FAILED_COUNT" -eq 0 ]; then
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Result : SUCCESS"
    echo "All ${#PRINTERS[@]} printer(s) are reachable"
    rm -f "$LOG_FILE"
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
else
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILURE"
    echo "Failed : $FAILED_COUNT printer(s) unreachable"
    echo "Failed : $FAILED_PRINTERS"
    echo "Log    : $LOG_FILE"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi
