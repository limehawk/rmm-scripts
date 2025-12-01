#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Streamer Install (macOS)                           v1.0.0
# FILE   : splashtop_streamer_install_macos.sh
# ==============================================================================
# PURPOSE:
#   Downloads and installs the Splashtop Streamer agent on macOS for remote
#   access capabilities.
#
# USAGE:
#   sudo ./splashtop_streamer_install_macos.sh
#
# PREREQUISITES:
#   - macOS
#   - Root/sudo privileges
#   - Internet connectivity
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -e

# Configuration
SPLASHTOP_URL="https://download.splashtop.com/csrs/Splashtop_Streamer_Mac_DEPLOY_INSTALLER_v3.7.0.0.dmg"
TEMP_DMG="/tmp/splashtop_streamer.dmg"
MOUNT_DIR="/Volumes/SplashtopStreamer"

echo ""
echo "[ SPLASHTOP STREAMER INSTALL - macOS ]"
echo "--------------------------------------------------------------"

# Download installer
echo "Downloading Splashtop Streamer..."
curl -L -o "$TEMP_DMG" "$SPLASHTOP_URL" || {
    echo "[ERROR] Failed to download installer"
    exit 1
}

# Mount DMG
echo "Mounting installer..."
hdiutil attach "$TEMP_DMG" -nobrowse -quiet || {
    echo "[ERROR] Failed to mount DMG"
    exit 1
}

# Install package
echo "Installing Splashtop Streamer..."
sudo installer -pkg "$MOUNT_DIR/.Splashtop Streamer.pkg" -target / || {
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null
    echo "[ERROR] Installation failed"
    exit 1
}

# Cleanup
echo "Cleaning up..."
hdiutil detach "$MOUNT_DIR" -quiet
rm -f "$TEMP_DMG"

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop Streamer installed successfully"
exit 0
