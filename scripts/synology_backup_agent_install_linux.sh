#!/bin/bash
# ==============================================================================
# SCRIPT : Synology Active Backup Agent Install (Linux)                 v1.0.0
# FILE   : synology_backup_agent_install_linux.sh
# ==============================================================================
# PURPOSE:
#   Installs the Synology Active Backup for Business Agent on Linux systems.
#   Includes prerequisite checks for architecture, kernel headers, and tools.
#
# USAGE:
#   sudo ./synology_backup_agent_install_linux.sh
#
# PREREQUISITES:
#   - Debian 10/11/12 or Ubuntu 16.04-24.04 (x86_64 only)
#   - Root/sudo privileges
#   - linux-headers for current kernel
#   - make 4.1+, dkms 2.2.0.3+, gcc 4.8.2+
#   - unzip, curl or wget
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -euo pipefail

echo ""
echo "[ SYNOLOGY ACTIVE BACKUP AGENT INSTALL - Linux ]"
echo "--------------------------------------------------------------"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root."
    exit 1
fi

# ==============================================================================
# SYSTEM REQUIREMENT CHECKS
# ==============================================================================
echo ""
echo "[ SYSTEM CHECKS ]"
echo "--------------------------------------------------------------"

# Check architecture
ARCH=$(uname -m)
echo "Architecture : $ARCH"
if [ "$ARCH" != "x86_64" ]; then
    echo "[ERROR] Unsupported architecture. Only x86_64 is supported."
    exit 1
fi

# Check Linux headers
KERNEL_HEADERS_DIR="/usr/src/linux-headers-$(uname -r)"
echo "Kernel : $(uname -r)"
if [ ! -d "${KERNEL_HEADERS_DIR}" ]; then
    echo "[ERROR] Linux headers not found at ${KERNEL_HEADERS_DIR}"
    echo "Install with: apt install linux-headers-$(uname -r)"
    exit 1
fi
echo "Headers : Found"

# Check required commands
for cmd in make dkms gcc unzip; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "[ERROR] $cmd is not installed. Please install it."
        exit 1
    fi
done
echo "Tools : make, dkms, gcc, unzip - OK"

# Setup downloader
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl -L -o"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget -O"
else
    echo "[ERROR] Neither curl nor wget is installed."
    exit 1
fi

# Version check function
check_version() {
    local prog_name=$1
    local required_version=$2
    local current_version

    current_version=$($prog_name --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
    if [ -z "$current_version" ]; then
        echo "[WARNING] Could not determine version for $prog_name"
        return
    fi
    if dpkg --compare-versions "$current_version" "lt" "$required_version"; then
        echo "[ERROR] $prog_name version $current_version < required $required_version"
        exit 1
    fi
    echo "$prog_name : $current_version (>= $required_version required) - OK"
}

check_version make 4.1
check_version dkms 2.2.0.3
check_version gcc 4.8.2

# ==============================================================================
# DOWNLOAD
# ==============================================================================
echo ""
echo "[ DOWNLOAD ]"
echo "--------------------------------------------------------------"

FILE_URL="https://global.download.synology.com/download/Utility/ActiveBackupBusinessAgent/2.7.1-3235/Linux/x86_64/Synology%20Active%20Backup%20for%20Business%20Agent-2.7.1-3235-x64-deb.zip"
TEMP_DIR=$(mktemp -d -t synology_installer_XXXXXX)
ZIP_FILE="${TEMP_DIR}/agent.zip"

echo "Downloading Synology Active Backup Agent..."
if ! ${DOWNLOADER} "${ZIP_FILE}" "${FILE_URL}"; then
    echo "[ERROR] Failed to download the file."
    exit 1
fi
echo "Download completed"

# ==============================================================================
# EXTRACT
# ==============================================================================
echo ""
echo "[ EXTRACT ]"
echo "--------------------------------------------------------------"

echo "Extracting installer..."
if ! unzip "${ZIP_FILE}" -d "${TEMP_DIR}"; then
    echo "[ERROR] Failed to unzip the file."
    exit 1
fi
echo "Extraction completed"

# ==============================================================================
# INSTALL
# ==============================================================================
echo ""
echo "[ INSTALL ]"
echo "--------------------------------------------------------------"

INSTALL_RUN=$(find "${TEMP_DIR}" -type f -name "install.run" | head -n 1)
if [ -z "${INSTALL_RUN}" ]; then
    echo "[ERROR] install.run not found in the archive."
    exit 1
fi

echo "Running installer..."
chmod +x "${INSTALL_RUN}"
if ! "${INSTALL_RUN}"; then
    echo "[ERROR] Installation failed."
    exit 1
fi

# ==============================================================================
# CLEANUP
# ==============================================================================
echo ""
echo "[ CLEANUP ]"
echo "--------------------------------------------------------------"

echo "Removing temporary files..."
rm -rf "${TEMP_DIR}"
echo "Cleanup completed"

# ==============================================================================
# FINAL STATUS
# ==============================================================================
echo ""
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"
echo "Result : SUCCESS"
echo "Synology Active Backup Agent installed successfully"
echo ""
echo "To connect to your NAS: abb-cli -c"
echo "For help: abb-cli -h"

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
