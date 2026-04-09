#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Reset NVRAM and Reboot (macOS)                               v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./nvram_reset_reboot_macos.sh
# ================================================================================
#  FILE     : nvram_reset_reboot_macos.sh
#  DESCRIPTION : Resets NVRAM and schedules immediate macOS reboot
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Schedules an NVRAM reset on the next reboot and immediately reboots the Mac.
#    NVRAM (Non-Volatile Random-Access Memory) stores system settings that macOS
#    accesses quickly, including:
#      - Startup disk selection
#      - Display resolution
#      - Speaker volume
#      - Time zone information
#      - Recent kernel panic information
#
#    Useful for troubleshooting:
#      - Boot issues
#      - Display problems
#      - Audio issues
#      - Startup disk not found errors
#      - Time/date problems
#
#  DATA SOURCES & PRIORITY
#
#    - nvram: macOS NVRAM utility
#    - sysctl: System information
#
#  REQUIRED INPUTS
#
#    No hardcoded inputs required.
#
#  SETTINGS
#
#    No configuration required.
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Checks for root privileges
#    2. Detects Mac architecture (Intel vs Apple Silicon)
#    3. Displays current NVRAM values (subset)
#    4. Sets NVRAM variable to trigger reset on next boot
#    5. Immediately reboots the system
#
#  PREREQUISITES
#
#    - Root/sudo access required
#    - macOS 10.14 or later
#    - Intel-based Mac (Apple Silicon uses different reset method)
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Runs with elevated privileges (sudo required)
#    - WILL IMMEDIATELY REBOOT THE SYSTEM
#    - User data is not affected (only system settings reset)
#
#  ENDPOINTS
#
#    Not applicable - local system operation only
#
#  EXIT CODES
#
#    0 = Success (reboot initiated)
#    1 = Failure (permission denied)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#     Running as root          : Yes
#
#    [INFO] SYSTEM DETECTION
#    ==============================================================
#     Architecture             : x86_64
#     Mac Model                : MacBookPro15,1
#
#    [INFO] CURRENT NVRAM
#    ==============================================================
#    Current NVRAM values (subset):
#      SystemAudioVolume       50
#
#    [RUN] OPERATION
#    ==============================================================
#    Setting NVRAM reset flag...
#     NVRAM Reset Flag         : Set
#     Action                   : Initiating reboot
#
#    *** SYSTEM WILL REBOOT NOW ***
#
#    [RUN] REBOOTING
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-01 v1.0.0 Initial release
# ================================================================================

set -e

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_section() {
    local status="$1"
    local title="$2"
    echo ""
    echo "[$status] $title"
    echo "=============================================================="
}

print_kv() {
    printf " %-24s : %s\n" "$1" "$2"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_section "INFO" "INPUT VALIDATION"

# Check for root privileges
if [ "$(id -u)" != "0" ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "This script must be run with root privileges (sudo)"
    echo ""
    exit 1
fi
print_kv "Running as root" "Yes"

print_section "INFO" "SYSTEM DETECTION"

# Detect architecture
ARCH=$(uname -m)
print_kv "Architecture" "$ARCH"

# Get Mac model
MAC_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
print_kv "Mac Model" "$MAC_MODEL"

# Check for Apple Silicon
if [ "$ARCH" = "arm64" ]; then
    echo ""
    echo "WARNING: Apple Silicon Macs (M1/M2/M3) handle NVRAM differently."
    echo "         NVRAM is automatically managed and this reset may have"
    echo "         limited effect. Consider using Recovery Mode for a full"
    echo "         NVRAM reset on Apple Silicon Macs."
    echo ""
    print_kv "Proceeding" "Yes (with warning)"
fi

print_section "INFO" "CURRENT NVRAM"

# Show some current NVRAM values (non-sensitive)
echo "Current NVRAM values (subset):"
nvram -p 2>/dev/null | grep -E "^(SystemAudioVolume|boot-args|csr-active-config)" | while read -r line; do
    echo "  $line"
done || echo "  (unable to read NVRAM)"

print_section "RUN" "OPERATION"

echo "Setting NVRAM reset flag..."
nvram ResetNVRam=1

print_kv "NVRAM Reset Flag" "Set"
print_kv "Action" "Initiating reboot"

echo ""
echo "*** SYSTEM WILL REBOOT NOW ***"

print_section "RUN" "REBOOTING"

# Initiate reboot
reboot

# Script will not reach here
exit 0
