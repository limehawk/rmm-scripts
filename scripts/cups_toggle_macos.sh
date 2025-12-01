#!/bin/bash
set -euo pipefail
# ==============================================================================
# SCRIPT : Toggle CUPS Web Interface                                     v1.0.0
# FILE   : cups_toggle_macos.sh
# ==============================================================================
# PURPOSE:
#   Toggles the CUPS (Common Unix Printing System) web interface on or off.
#   If currently enabled, disables it. If disabled, enables it.
#
# PREREQUISITES:
#   - macOS or Linux with CUPS installed
#   - cupsctl command available
#   - Administrator/root privileges
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

echo ""
echo "[ CUPS WEB INTERFACE TOGGLE ]"
echo "--------------------------------------------------------------"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Check current status
web_interface_status=$(cupsctl | grep 'WebInterface=no' || true)

if [[ -n "$web_interface_status" ]]; then
    # Web interface is disabled, enable it
    echo "Current Status     : Disabled"
    echo "Action             : Enabling"
    cupsctl WebInterface=yes
    echo "Result             : ENABLED"
    echo ""
    echo "CUPS Web Interface URL: http://localhost:631"
else
    # Web interface is enabled, disable it
    echo "Current Status     : Enabled"
    echo "Action             : Disabling"
    cupsctl WebInterface=no
    echo "Result             : DISABLED"
fi

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
