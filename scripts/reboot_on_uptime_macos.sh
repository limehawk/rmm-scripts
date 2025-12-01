#!/bin/bash
set -euo pipefail
# ==============================================================================
# SCRIPT : Reboot on Uptime Threshold (macOS/Linux)                      v1.0.0
# FILE   : reboot_on_uptime_macos.sh
# ==============================================================================
# PURPOSE:
#   Automatically reboots a macOS or Linux system if the uptime exceeds a
#   specified threshold (default: 14 days).
#
# CONFIGURATION:
#   max_uptime_days : Days of uptime before triggering reboot (default: 14)
#
# PREREQUISITES:
#   - macOS or Linux with /proc/uptime (Linux) or uptime command (macOS)
#   - Root/sudo privileges
#
# EXIT CODES:
#   0 = Success (reboot triggered or not needed)
#   1 = Failure
# ==============================================================================

# Configuration
max_uptime_days=14

echo ""
echo "[ UPTIME CHECK ]"
echo "--------------------------------------------------------------"

# Get uptime in days based on OS
if [[ -f /proc/uptime ]]; then
    # Linux: Read from /proc/uptime
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    uptime_days=$((uptime_seconds / 86400))
elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS: Parse uptime command or use sysctl
    boot_time=$(sysctl -n kern.boottime | awk -F'[= ,]' '{print $4}')
    current_time=$(date +%s)
    uptime_seconds=$((current_time - boot_time))
    uptime_days=$((uptime_seconds / 86400))
else
    echo "ERROR: Unable to determine uptime on this system"
    exit 1
fi

echo " Current Uptime      : ${uptime_days} days"
echo " Threshold           : ${max_uptime_days} days"

echo ""
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"

if [[ "$uptime_days" -gt "$max_uptime_days" ]]; then
    echo " Uptime exceeds threshold. Rebooting now..."
    sudo reboot
else
    echo " Uptime within acceptable range. No reboot needed."
fi

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
