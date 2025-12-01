#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Streamer Install (Debian ARM64)                    v1.0.0
# FILE   : splashtop_streamer_install_debian_arm64.sh
# ==============================================================================
# PURPOSE:
#   Downloads and installs the Splashtop Streamer agent on Debian systems
#   running ARM64 architecture (e.g., Raspberry Pi, ARM servers).
#
# USAGE:
#   sudo ./splashtop_streamer_install_debian_arm64.sh
#
# PREREQUISITES:
#   - Debian Linux (ARM64)
#   - Root/sudo privileges
#   - Internet connectivity
#   - wget and tar packages
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -e

# Configuration
URL="https://download.splashtop.com/linux/STB_CSRS_Debian_v3.7.2.0_arm64.tar.gz"
TAR_FILE="splashtop_debian_arm64.tar.gz"
INSTALL_DIR="/opt/splashtop"
DEB_PACKAGE="Splashtop_Streamer_Debian_arm64.deb"

echo ""
echo "[ SPLASHTOP STREAMER INSTALL - Debian ARM64 ]"
echo "--------------------------------------------------------------"

# Update package list
echo "[1/6] Updating APT..."
sudo apt update

# Install prerequisites
echo "[2/6] Installing prerequisites..."
sudo apt install -y wget tar

# Download package
echo "[3/6] Downloading Splashtop Streamer v3.7.2.0..."
wget -O "$TAR_FILE" "$URL" || {
    echo "[ERROR] Failed to download package"
    exit 1
}

# Extract package
echo "[4/6] Extracting to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo tar -xzf "$TAR_FILE" -C "$INSTALL_DIR"

# Install deb package
echo "[5/6] Installing package and fixing dependencies..."
cd "$INSTALL_DIR"
sudo dpkg -i "$DEB_PACKAGE" || sudo apt install -f -y

# Enable and start service
echo "[6/6] Enabling and starting service..."
sudo systemctl enable --now splashtop-streamer.service

# Cleanup
rm -f "$TAR_FILE"

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop Streamer v3.7.2.0 installed and running"
exit 0
