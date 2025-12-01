#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Business Install (macOS)                           v1.0.0
# FILE   : splashtop_business_install_macos.sh
# ==============================================================================
# PURPOSE:
#   Downloads and installs the Splashtop Business client application on macOS.
#
# USAGE:
#   sudo ./splashtop_business_install_macos.sh
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
SPLASHTOP_URL="https://download.splashtop.com/macclient/STB/Splashtop_Business_Mac_INSTALLER_v3.7.2.0.dmg"
SPLASHTOP_INSTALLER="Splashtop_Business_Mac_INSTALLER.dmg"
MOUNT_DIR="/Volumes/Splashtop Business"

# Error handler
handle_error() {
    echo "[ERROR] $1"
    exit 1
}

echo ""
echo "[ SPLASHTOP BUSINESS INSTALL - macOS ]"
echo "--------------------------------------------------------------"

# Download installer
echo "Downloading Splashtop Business installer..."
curl -L -o "$SPLASHTOP_INSTALLER" "$SPLASHTOP_URL" || handle_error "Failed to download installer"

if [ ! -f "$SPLASHTOP_INSTALLER" ]; then
    handle_error "Installer file not found after download"
fi
echo "Download completed"

# Mount DMG
echo "Mounting installer DMG..."
hdiutil attach "$SPLASHTOP_INSTALLER" -nobrowse || handle_error "Failed to mount DMG"

# Install package
PKG_PATH="$MOUNT_DIR/Splashtop Business.pkg"
if [ -e "$PKG_PATH" ]; then
    echo "Installing Splashtop Business..."
    sudo installer -pkg "$PKG_PATH" -target / || handle_error "Installation failed"
else
    hdiutil detach "$MOUNT_DIR" 2>/dev/null
    handle_error "Package not found in mounted DMG"
fi

# Cleanup
echo "Cleaning up..."
hdiutil detach "$MOUNT_DIR" || handle_error "Failed to unmount DMG"
rm -f "$SPLASHTOP_INSTALLER" || handle_error "Failed to remove installer"

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop Business installed successfully"
exit 0
