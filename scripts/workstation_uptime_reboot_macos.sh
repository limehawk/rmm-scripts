#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Reboot on Uptime Threshold                                   v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./workstation_uptime_reboot_macos.sh
# ================================================================================
#  FILE     : workstation_uptime_reboot_macos.sh
#  DESCRIPTION : Reboots macOS when uptime exceeds configured threshold
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automatically reboots a macOS or Linux system if the uptime exceeds a
#    specified threshold (default: 14 days). Useful for ensuring systems are
#    restarted periodically to apply updates and clear memory.
#
#  DATA SOURCES & PRIORITY
#
#    - Linux: Reads from /proc/uptime
#    - macOS: Uses sysctl kern.boottime
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - max_uptime_days: Days of uptime before triggering reboot (default: 14)
#
#  SETTINGS
#
#    Default configuration:
#      - Maximum uptime: 14 days
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Detects operating system (Linux or macOS)
#    2. Gets current uptime in days
#    3. Compares against threshold
#    4. Reboots if threshold exceeded, otherwise exits cleanly
#
#  PREREQUISITES
#
#    - macOS or Linux with /proc/uptime (Linux) or sysctl (macOS)
#    - Root/sudo privileges for reboot
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Requires elevated privileges for reboot command
#
#  ENDPOINTS
#
#    Not applicable - local system operation only
#
#  EXIT CODES
#
#    0 = Success (reboot triggered or not needed)
#    1 = Failure (unable to determine uptime)
#
#  EXAMPLE RUN
#
#    [INFO] UPTIME CHECK
#    ==============================================================
#    Current Uptime : 21 days
#    Threshold      : 14 days
#
#    [RUN] FINAL STATUS
#    ==============================================================
#    Uptime exceeds threshold. Rebooting now...
#
#    [RUN] REBOOTING
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
max_uptime_days=14
# ============================================================================

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[INFO] UPTIME CHECK"
echo "=============================================================="

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
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Unable to determine uptime on this system"
    echo ""
    exit 1
fi

echo "Current Uptime : ${uptime_days} days"
echo "Threshold      : ${max_uptime_days} days"

if [[ "$uptime_days" -gt "$max_uptime_days" ]]; then
    echo ""
    echo "[RUN] FINAL STATUS"
    echo "=============================================================="
    echo "Uptime exceeds threshold. Rebooting now..."
    echo ""
    echo "[RUN] REBOOTING"
    echo "=============================================================="
    sudo reboot
else
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Uptime within acceptable range. No reboot needed."
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
fi

exit 0
