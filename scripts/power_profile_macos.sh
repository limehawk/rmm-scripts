#!/bin/bash
# ==============================================================================
# SCRIPT : Power Profile Always-On (macOS)                              v1.0.0
# FILE   : power_profile_macos.sh
# ==============================================================================
# PURPOSE:
#   Configures an "always-on" power profile for macOS laptops and desktops.
#   Sets display sleep, disk sleep, system sleep, and hibernation settings
#   based on whether the device has a battery.
#
# USAGE:
#   sudo ./power_profile_macos.sh
#
# PREREQUISITES:
#   - macOS 10.12 or later
#   - Root/sudo privileges
#   - pmset utility (standard macOS component)
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -euo pipefail

echo ""
echo "[ POWER PROFILE ALWAYS-ON - macOS ]"
echo "--------------------------------------------------------------"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (sudo)."
    exit 1
fi

# ==============================================================================
# DETECT BATTERY PRESENCE
# ==============================================================================
echo ""
echo "[ SYSTEM CHECK ]"
echo "--------------------------------------------------------------"

has_battery=$(pmset -g batt | grep -c 'Battery Power' || true)

if [ "$has_battery" -eq 0 ]; then
    echo "Battery Status : NOT DETECTED (Desktop)"
else
    echo "Battery Status : DETECTED (Laptop)"
fi

# ==============================================================================
# CONFIGURE POWER SETTINGS
# ==============================================================================
echo ""
echo "[ APPLYING POWER SETTINGS ]"
echo "--------------------------------------------------------------"

# Set display sleep to 30 minutes when on AC
echo "Display Sleep (AC)    : 30 minutes"
if ! sudo pmset -a displaysleep 30; then
    echo "[ERROR] Failed to set display sleep (AC)"
    exit 1
fi

# Set display sleep to 10 minutes when on battery
echo "Display Sleep (DC)    : 10 minutes"
if ! sudo pmset -b displaysleep 10; then
    echo "[ERROR] Failed to set display sleep (DC)"
    exit 1
fi

# Set hard drive sleep to 60 minutes when on AC
echo "Disk Sleep (AC)       : 60 minutes"
if ! sudo pmset -a disksleep 60; then
    echo "[ERROR] Failed to set disk sleep (AC)"
    exit 1
fi

# Set hard drive sleep to 30 minutes when on battery
echo "Disk Sleep (DC)       : 30 minutes"
if ! sudo pmset -b disksleep 30; then
    echo "[ERROR] Failed to set disk sleep (DC)"
    exit 1
fi

# Set Sleep based on battery presence
if [ "$has_battery" -eq 0 ]; then
    # Desktop: Set Sleep to never when on AC (no battery)
    echo "System Sleep (AC)     : Never (0)"
    if ! sudo pmset -a sleep 0; then
        echo "[ERROR] Failed to set system sleep (AC)"
        exit 1
    fi
else
    # Laptop: Set Sleep to 20 minutes when on battery
    echo "System Sleep (DC)     : 20 minutes"
    if ! sudo pmset -b sleep 20; then
        echo "[ERROR] Failed to set system sleep (DC)"
        exit 1
    fi
fi

# ==============================================================================
# CONFIGURE HIBERNATION
# ==============================================================================
echo ""
echo "[ CONFIGURING HIBERNATION ]"
echo "--------------------------------------------------------------"

if [ "$has_battery" -eq 0 ]; then
    echo "Hibernation           : DISABLED (Desktop)"
    if ! sudo pmset -a hibernatemode 0; then
        echo "[ERROR] Failed to disable hibernation"
        exit 1
    fi
else
    echo "Hibernation           : Enabled (Laptop default)"
fi

# ==============================================================================
# FINAL STATUS
# ==============================================================================
echo ""
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"
echo "Result : SUCCESS"
echo "Power settings configured successfully"

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
