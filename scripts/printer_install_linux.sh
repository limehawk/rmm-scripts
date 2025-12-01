#!/bin/bash
# ==============================================================================
# SCRIPT : Network Printer Install (Linux)                              v1.0.0
# FILE   : printer_install_linux.sh
# ==============================================================================
# PURPOSE:
#   Installs network printers on Linux using CUPS/lpadmin. Supports PPD files
#   for driver functionality. Automatically installs CUPS and required packages.
#
# CONFIGURATION:
#   Edit the variables below to configure:
#   - PRINTERS array: hostname|location|printername for each printer
#   - PPD_PATH: Path to the PPD file (must be installed first)
#   - PROTOCOL: lpd, ipp, or socket
#
# USAGE:
#   sudo ./printer_install_linux.sh
#
# PREREQUISITES:
#   - Debian/Ubuntu or compatible Linux
#   - Root/sudo privileges
#   - Internet access for package installation
#   - PPD file for the printer model
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION - EDIT THESE VALUES
# ==============================================================================

# Printer definitions: "hostname|location|display_name"
PRINTERS=(
    "printer1.example.com|Main Office|Office Printer"
    "printer2.example.com|Sales Dept|Sales Printer"
)

# Protocol: lpd, ipp, or socket
PROTOCOL="lpd"

# Path to PPD file (must exist on the system)
# Common locations:
#   /usr/share/cups/model/
#   /usr/share/ppd/
#   /etc/cups/ppd/
PPD_PATH="/usr/share/cups/model/YourPrinter.ppd"

# Install CUPS and dependencies if missing
AUTO_INSTALL_CUPS="true"

# ==============================================================================
# SCRIPT START
# ==============================================================================

echo ""
echo "[ NETWORK PRINTER INSTALL - Linux ]"
echo "--------------------------------------------------------------"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (sudo)."
    exit 1
fi

# Detect OS
OS_TYPE=$(uname)
if [ "$OS_TYPE" != "Linux" ]; then
    echo "[ERROR] This script is designed for Linux systems."
    exit 1
fi

echo "Protocol   : $PROTOCOL"
echo "PPD Path   : $PPD_PATH"
echo "Printers   : ${#PRINTERS[@]}"

# ==============================================================================
# INSTALL CUPS IF NEEDED
# ==============================================================================
if [ "$AUTO_INSTALL_CUPS" = "true" ]; then
    echo ""
    echo "[ CHECKING CUPS ]"
    echo "--------------------------------------------------------------"

    if ! command -v lpadmin > /dev/null 2>&1; then
        echo "CUPS not found, installing..."

        if command -v apt-get > /dev/null 2>&1; then
            apt-get update -qq
            apt-get install -y -qq cups cups-client printer-driver-all
        elif command -v yum > /dev/null 2>&1; then
            yum install -y cups
        elif command -v dnf > /dev/null 2>&1; then
            dnf install -y cups
        else
            echo "[ERROR] Unable to install CUPS - unsupported package manager"
            exit 1
        fi

        echo "CUPS installed"
    else
        echo "CUPS is already installed"
    fi

    # Ensure CUPS is running
    if command -v systemctl > /dev/null 2>&1; then
        systemctl enable cups > /dev/null 2>&1 || true
        systemctl restart cups
        echo "CUPS service started"
    fi
fi

# ==============================================================================
# VERIFY PPD FILE
# ==============================================================================
echo ""
echo "[ VERIFYING PPD ]"
echo "--------------------------------------------------------------"

if [ ! -f "$PPD_PATH" ]; then
    echo "[WARNING] PPD file not found: $PPD_PATH"
    echo "Attempting to use generic driver..."

    # Try to find a generic PPD
    GENERIC_PPD=$(find /usr/share/cups/model /usr/share/ppd -name "*.ppd*" 2>/dev/null | head -1 || echo "")

    if [ -n "$GENERIC_PPD" ]; then
        PPD_PATH="$GENERIC_PPD"
        echo "Using generic PPD: $PPD_PATH"
    else
        echo "[ERROR] No PPD files found. Please install printer drivers."
        echo "Try: apt-get install printer-driver-all"
        exit 1
    fi
else
    echo "PPD file verified: $PPD_PATH"
fi

# ==============================================================================
# INSTALL PRINTERS
# ==============================================================================
echo ""
echo "[ INSTALLING PRINTERS ]"
echo "--------------------------------------------------------------"

INSTALLED=0
FAILED=0

for PRINTER_ENTRY in "${PRINTERS[@]}"; do
    IFS="|" read -r HOSTNAME LOCATION DISPLAY_NAME <<< "$PRINTER_ENTRY"

    # Use hostname if no display name provided
    if [ -z "$DISPLAY_NAME" ]; then
        DISPLAY_NAME="$HOSTNAME"
    fi

    # Create a clean printer name (no spaces)
    PRINTER_NAME=$(echo "$DISPLAY_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    echo "Installing: $DISPLAY_NAME"
    echo "  Hostname : $HOSTNAME"
    echo "  Location : $LOCATION"
    echo "  Name     : $PRINTER_NAME"

    # Remove existing printer if present
    if lpstat -p "$PRINTER_NAME" > /dev/null 2>&1; then
        echo "  Removing existing printer..."
        lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
    fi

    # Build URI based on protocol
    case "$PROTOCOL" in
        lpd)    URI="lpd://${HOSTNAME}/" ;;
        ipp)    URI="ipp://${HOSTNAME}/ipp/print" ;;
        socket) URI="socket://${HOSTNAME}:9100" ;;
        *)      URI="${PROTOCOL}://${HOSTNAME}/" ;;
    esac

    # Install printer
    if lpadmin -p "$PRINTER_NAME" \
        -L "$LOCATION" \
        -D "$DISPLAY_NAME" \
        -v "$URI" \
        -P "$PPD_PATH" \
        -E; then

        # Enable and accept jobs
        cupsaccept "$PRINTER_NAME" 2>/dev/null || true
        cupsenable "$PRINTER_NAME" 2>/dev/null || true

        # Verify installation
        if lpstat -p "$PRINTER_NAME" > /dev/null 2>&1; then
            echo "  Status   : SUCCESS"
            INSTALLED=$((INSTALLED + 1))
        else
            echo "  Status   : FAILED (verification)"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "  Status   : FAILED (lpadmin)"
        FAILED=$((FAILED + 1))
    fi

    echo ""
done

# ==============================================================================
# SHOW INSTALLED PRINTERS
# ==============================================================================
echo "[ INSTALLED PRINTERS ]"
echo "--------------------------------------------------------------"
lpstat -p 2>/dev/null || echo "No printers installed"

# ==============================================================================
# FINAL STATUS
# ==============================================================================
echo ""
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"
echo "Installed  : $INSTALLED printer(s)"
echo "Failed     : $FAILED printer(s)"

if [ "$FAILED" -eq 0 ]; then
    echo "Result     : SUCCESS"
    exit 0
else
    echo "Result     : PARTIAL (some printers failed)"
    exit 1
fi

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"
