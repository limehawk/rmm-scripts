#!/bin/bash
# ==============================================================================
# SCRIPT : Network Printer Install (macOS)                              v1.0.0
# FILE   : printer_install_macos.sh
# ==============================================================================
# PURPOSE:
#   Installs network printers on macOS using CUPS/lpadmin. Supports PPD files
#   for full driver functionality. Can install from local PPD or download from
#   a URL.
#
# CONFIGURATION:
#   Edit the variables below to configure:
#   - PRINTERS array: hostname|location|printername for each printer
#   - PPD_SOURCE: "local" or "url"
#   - PPD_PATH/PPD_URL: Path or URL to PPD file
#   - PROTOCOL: lpd, ipp, or ipps
#
# USAGE:
#   sudo ./printer_install_macos.sh
#
# PREREQUISITES:
#   - macOS 10.12 or later
#   - Root/sudo privileges
#   - PPD file for the printer model
#   - Network access to printers and PPD URL (if using URL)
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
# If display_name is empty, hostname prefix will be used
PRINTERS=(
    "printer1.example.com|Main Office|Office Printer"
    "printer2.example.com|Sales Dept|Sales Printer"
)

# Protocol: lpd, ipp, or ipps
PROTOCOL="lpd"

# PPD source: "local" or "url"
PPD_SOURCE="local"

# For local PPD: full path to the .ppd or .ppd.gz file
PPD_PATH="/Library/Printers/PPDs/Contents/Resources/YourPrinter.ppd.gz"

# For URL PPD: URL to download the PPD file from
PPD_URL=""

# Optional: Driver package URL (for full driver install)
# Leave empty if using generic PPD or driver already installed
DRIVER_URL=""

# ==============================================================================
# SCRIPT START
# ==============================================================================

echo ""
echo "[ NETWORK PRINTER INSTALL - macOS ]"
echo "--------------------------------------------------------------"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (sudo)."
    exit 1
fi

echo "Protocol   : $PROTOCOL"
echo "PPD Source : $PPD_SOURCE"
echo "Printers   : ${#PRINTERS[@]}"

# ==============================================================================
# DOWNLOAD DRIVER PACKAGE (OPTIONAL)
# ==============================================================================
if [ -n "$DRIVER_URL" ]; then
    echo ""
    echo "[ DOWNLOADING DRIVER ]"
    echo "--------------------------------------------------------------"

    DRIVER_FILE="/tmp/printer_driver.zip"
    echo "Downloading from: $DRIVER_URL"

    if ! curl -sL -o "$DRIVER_FILE" "$DRIVER_URL"; then
        echo "[ERROR] Failed to download driver package"
        exit 1
    fi

    echo "Extracting driver..."
    sudo unzip -o "$DRIVER_FILE" -d "/Library/Printers/" > /dev/null
    rm -f "$DRIVER_FILE"
    echo "Driver installed"
fi

# ==============================================================================
# SETUP PPD FILE
# ==============================================================================
echo ""
echo "[ SETTING UP PPD ]"
echo "--------------------------------------------------------------"

PPD_DEST="/Library/Printers/PPDs/Contents/Resources/"
ACTIVE_PPD=""

if [ "$PPD_SOURCE" = "url" ] && [ -n "$PPD_URL" ]; then
    PPD_FILENAME=$(basename "$PPD_URL")
    DOWNLOADED_PPD="/tmp/$PPD_FILENAME"
    ACTIVE_PPD="${PPD_DEST}${PPD_FILENAME}"

    echo "Downloading PPD from: $PPD_URL"
    if ! curl -sL -o "$DOWNLOADED_PPD" "$PPD_URL"; then
        echo "[ERROR] Failed to download PPD file"
        exit 1
    fi

    # Ensure destination exists
    sudo mkdir -p "$PPD_DEST"

    # Copy to PPD directory
    sudo cp "$DOWNLOADED_PPD" "$ACTIVE_PPD"
    sudo chown root:wheel "$ACTIVE_PPD"
    sudo chmod 644 "$ACTIVE_PPD"
    rm -f "$DOWNLOADED_PPD"

    echo "PPD installed: $ACTIVE_PPD"

elif [ "$PPD_SOURCE" = "local" ]; then
    if [ ! -f "$PPD_PATH" ]; then
        echo "[ERROR] PPD file not found: $PPD_PATH"
        exit 1
    fi
    ACTIVE_PPD="$PPD_PATH"
    echo "Using local PPD: $ACTIVE_PPD"
else
    echo "[ERROR] Invalid PPD_SOURCE: $PPD_SOURCE (must be 'local' or 'url')"
    exit 1
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

    # Use hostname prefix if no display name provided
    if [ -z "$DISPLAY_NAME" ]; then
        DISPLAY_NAME=$(echo "$HOSTNAME" | cut -d'.' -f1)
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
        lpd)  URI="lpd://${HOSTNAME}/" ;;
        ipp)  URI="ipp://${HOSTNAME}/ipp/print" ;;
        ipps) URI="ipps://${HOSTNAME}/ipp/print" ;;
        *)    URI="${PROTOCOL}://${HOSTNAME}/" ;;
    esac

    # Install printer
    if /usr/sbin/lpadmin -p "$PRINTER_NAME" \
        -L "$LOCATION" \
        -D "$DISPLAY_NAME" \
        -v "$URI" \
        -P "$ACTIVE_PPD" \
        -E \
        -o printer-is-shared=false \
        -o printer-error-policy=abort-job; then

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
# FINAL STATUS
# ==============================================================================
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
