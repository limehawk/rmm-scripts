#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Power Profile Always-On (macOS)                              v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./power_profile_set_macos.sh
# ================================================================================
#  FILE     : power_profile_set_macos.sh
#  DESCRIPTION : Configures always-on power settings for macOS systems
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Configures an "always-on" power profile for macOS laptops and desktops.
#    Sets display sleep, disk sleep, system sleep, and hibernation settings
#    based on whether the device has a battery (laptop vs desktop).
#
#  DATA SOURCES & PRIORITY
#
#    - pmset: Queries battery status and configures power settings
#
#  REQUIRED INPUTS
#
#    No hardcoded inputs required - auto-detects battery presence.
#
#  SETTINGS
#
#    Desktop (no battery):
#      - Display Sleep (AC): 30 minutes
#      - Disk Sleep (AC): 60 minutes
#      - System Sleep (AC): Never
#      - Hibernation: Disabled
#
#    Laptop (with battery):
#      - Display Sleep (AC): 30 minutes
#      - Display Sleep (DC): 10 minutes
#      - Disk Sleep (AC): 60 minutes
#      - Disk Sleep (DC): 30 minutes
#      - System Sleep (DC): 20 minutes
#      - Hibernation: Enabled (default)
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Verifies root/sudo privileges
#    2. Detects battery presence to identify laptop vs desktop
#    3. Configures display sleep timeouts
#    4. Configures disk sleep timeouts
#    5. Configures system sleep (never for desktops)
#    6. Configures hibernation mode
#    7. Reports final status
#
#  PREREQUISITES
#
#    - macOS 10.12 or later
#    - Root/sudo privileges
#    - pmset utility (standard macOS component)
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Requires elevated privileges to modify system settings
#
#  ENDPOINTS
#
#    Not applicable - local system configuration only
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure (not root or pmset error)
#
#  EXAMPLE RUN
#
#    [RUN] POWER PROFILE ALWAYS-ON - macOS
#    ==============================================================
#
#    [INFO] SYSTEM CHECK
#    ==============================================================
#    Battery Status : NOT DETECTED (Desktop)
#
#    [RUN] APPLYING POWER SETTINGS
#    ==============================================================
#    Display Sleep (AC) : 30 minutes
#    Display Sleep (DC) : 10 minutes
#    Disk Sleep (AC)    : 60 minutes
#    Disk Sleep (DC)    : 30 minutes
#    System Sleep (AC)  : Never (0)
#
#    [RUN] CONFIGURING HIBERNATION
#    ==============================================================
#    Hibernation        : DISABLED (Desktop)
#
#    [INFO] RESULT
#    ==============================================================
#    Result : SUCCESS
#
#    [OK] SCRIPT COMPLETED
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
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[RUN] POWER PROFILE ALWAYS-ON - macOS"
echo "=============================================================="

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "This script must be run as root (sudo)"
    echo ""
    exit 1
fi

# ============================================================================
# DETECT BATTERY PRESENCE
# ============================================================================
echo ""
echo "[INFO] SYSTEM CHECK"
echo "=============================================================="

has_battery=$(pmset -g batt | grep -c 'Battery Power' || true)

if [ "$has_battery" -eq 0 ]; then
    echo "Battery Status : NOT DETECTED (Desktop)"
else
    echo "Battery Status : DETECTED (Laptop)"
fi

# ============================================================================
# CONFIGURE POWER SETTINGS
# ============================================================================
echo ""
echo "[RUN] APPLYING POWER SETTINGS"
echo "=============================================================="

# Set display sleep to 30 minutes when on AC
echo "Display Sleep (AC) : 30 minutes"
if ! sudo pmset -a displaysleep 30; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Failed to set display sleep (AC)"
    exit 1
fi

# Set display sleep to 10 minutes when on battery
echo "Display Sleep (DC) : 10 minutes"
if ! sudo pmset -b displaysleep 10; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Failed to set display sleep (DC)"
    exit 1
fi

# Set hard drive sleep to 60 minutes when on AC
echo "Disk Sleep (AC)    : 60 minutes"
if ! sudo pmset -a disksleep 60; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Failed to set disk sleep (AC)"
    exit 1
fi

# Set hard drive sleep to 30 minutes when on battery
echo "Disk Sleep (DC)    : 30 minutes"
if ! sudo pmset -b disksleep 30; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Failed to set disk sleep (DC)"
    exit 1
fi

# Set Sleep based on battery presence
if [ "$has_battery" -eq 0 ]; then
    # Desktop: Set Sleep to never when on AC (no battery)
    echo "System Sleep (AC)  : Never (0)"
    if ! sudo pmset -a sleep 0; then
        echo ""
        echo "[ERROR] ERROR OCCURRED"
        echo "=============================================================="
        echo "Failed to set system sleep (AC)"
        exit 1
    fi
else
    # Laptop: Set Sleep to 20 minutes when on battery
    echo "System Sleep (DC)  : 20 minutes"
    if ! sudo pmset -b sleep 20; then
        echo ""
        echo "[ERROR] ERROR OCCURRED"
        echo "=============================================================="
        echo "Failed to set system sleep (DC)"
        exit 1
    fi
fi

# ============================================================================
# CONFIGURE HIBERNATION
# ============================================================================
echo ""
echo "[RUN] CONFIGURING HIBERNATION"
echo "=============================================================="

if [ "$has_battery" -eq 0 ]; then
    echo "Hibernation        : DISABLED (Desktop)"
    if ! sudo pmset -a hibernatemode 0; then
        echo ""
        echo "[ERROR] ERROR OCCURRED"
        echo "=============================================================="
        echo "Failed to disable hibernation"
        exit 1
    fi
else
    echo "Hibernation        : Enabled (Laptop default)"
fi

# ============================================================================
# FINAL STATUS
# ============================================================================
echo ""
echo "[INFO] RESULT"
echo "=============================================================="
echo "Result : SUCCESS"
echo "Power settings configured successfully"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
