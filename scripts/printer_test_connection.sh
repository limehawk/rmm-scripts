#!/bin/bash
# ==============================================================================
# SCRIPT : Printer Connection Test                                      v1.0.0
# FILE   : printer_test_connection.sh
# ==============================================================================
# PURPOSE:
#   Tests network connectivity to configured printers by pinging their
#   hostnames/IPs. Reports success/failure for each printer and optionally
#   sends an email alert if any tests fail.
#
# CONFIGURATION:
#   Edit the PRINTERS array below with your printer hostnames or IPs.
#   Optionally configure email settings for failure notifications.
#
# USAGE:
#   ./printer_test_connection.sh
#
# PREREQUISITES:
#   - macOS or Linux
#   - Network access to printer hosts
#   - (Optional) sendmail for email alerts
#
# EXIT CODES:
#   0 = All printers reachable
#   1 = One or more printers unreachable
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION - EDIT THESE VALUES
# ==============================================================================
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

# ==============================================================================
# SCRIPT START
# ==============================================================================
echo ""
echo "[ PRINTER CONNECTION TEST ]"
echo "--------------------------------------------------------------"
echo "Hostname   : $(hostname)"
echo "Date       : $(date)"
echo "Printers   : ${#PRINTERS[@]}"
echo ""

# Initialize tracking
FAILED_COUNT=0
FAILED_PRINTERS=""
LOG_FILE="/tmp/printer_test_$(date +%Y%m%d_%H%M%S).log"

echo "[ TESTING CONNECTIVITY ]"
echo "--------------------------------------------------------------"

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

# ==============================================================================
# SEND EMAIL ALERT IF CONFIGURED
# ==============================================================================
if [ "$FAILED_COUNT" -gt 0 ] && [ "$SEND_EMAIL" = "true" ] && [ -n "$MAIL_TO" ]; then
    echo "[ SENDING ALERT ]"
    echo "--------------------------------------------------------------"

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

# ==============================================================================
# FINAL STATUS
# ==============================================================================
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "Result : SUCCESS"
    echo "All ${#PRINTERS[@]} printer(s) are reachable"
    rm -f "$LOG_FILE"
    exit 0
else
    echo "Result : FAILURE"
    echo "Failed : $FAILED_COUNT printer(s) unreachable"
    echo "Failed : $FAILED_PRINTERS"
    echo "Log    : $LOG_FILE"
    exit 1
fi

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"
