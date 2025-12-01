#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Streamer Install (Debian AMD64)                    v1.0.0
# FILE   : splashtop_streamer_install_debian_amd64.sh
# ==============================================================================
# PURPOSE:
#   Downloads and installs the Splashtop Streamer agent on Debian/Ubuntu
#   systems running AMD64 architecture.
#
# USAGE:
#   sudo ./splashtop_streamer_install_debian_amd64.sh
#
# PREREQUISITES:
#   - Debian/Ubuntu Linux (AMD64)
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
URL="https://download.splashtop.com/linux/STB_CSRS_Ubuntu_v3.7.2.0_amd64.tar.gz"
TAR_FILE="splashtop_ubuntu_amd64.tar.gz"
INSTALL_DIR="/opt/splashtop"
DEB_PACKAGE="Splashtop_Streamer_Ubuntu_amd64.deb"

echo ""
echo "[ SPLASHTOP STREAMER INSTALL - Debian AMD64 ]"
echo "--------------------------------------------------------------"

# Update package list
echo "[1/5] Updating package list..."
sudo apt update

# Download package
echo "[2/5] Downloading Splashtop Streamer..."
wget -O "$TAR_FILE" "$URL" || {
    echo "[ERROR] Failed to download package"
    exit 1
}

# Create install directory and extract
echo "[3/5] Extracting package to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo tar -xzf "$TAR_FILE" -C "$INSTALL_DIR"

# Install deb package
echo "[4/5] Installing Splashtop Streamer..."
cd "$INSTALL_DIR"
sudo dpkg -i "$DEB_PACKAGE" || sudo apt install -f -y

# Cleanup
echo "[5/5] Cleaning up..."
rm -f "$TAR_FILE"

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop Streamer installed successfully"
exit 0
