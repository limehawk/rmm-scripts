#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Screenshot Capture (macOS)                                   v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : ./workstation_screenshot_macos.sh
# ================================================================================
#  FILE     : workstation_screenshot_macos.sh
#  DESCRIPTION : Captures screenshot of all displays on macOS
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Captures a screenshot on macOS and saves it with a timestamped filename.
#    Uses the native screencapture utility for silent capture. Designed for
#    RMM deployment to capture system state for troubleshooting.
#
#  DATA SOURCES & PRIORITY
#
#    - screencapture: Native macOS utility for screen capture
#
#  REQUIRED INPUTS
#
#    No hardcoded inputs required. Screenshot is saved to /tmp/screenshots/.
#
#  SETTINGS
#
#    Default configuration:
#      - Save directory: /tmp/screenshots
#      - Filename format: screenshot_YYYYMMDD_HHMMSS.png
#      - Silent capture: Enabled (-x flag)
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Creates screenshot directory if it doesn't exist
#    2. Generates timestamped filename
#    3. Captures screenshot silently (no sound)
#    4. Reports save location
#
#  PREREQUISITES
#
#    - macOS 10.12 or later
#    - screencapture utility (standard macOS component)
#    - Screen Recording permission may be required (System Preferences > Security)
#
#  SECURITY NOTES
#
#    - Screenshots are saved to /tmp (auto-cleaned on reboot)
#    - No secrets exposed in output
#    - May capture sensitive on-screen content
#
#  ENDPOINTS
#
#    Not applicable - local system operation only
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure (screencapture failed)
#
#  EXAMPLE RUN
#
#    [RUN] SCREENSHOT CAPTURE - macOS
#    ==============================================================
#    Creating screenshot directory...
#    Capturing screenshot...
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Result    : SUCCESS
#    Saved to  : /tmp/screenshots/screenshot_20241223_120000.png
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
# HARDCODED INPUTS
# ============================================================================
SAVE_DIR="/tmp/screenshots"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="screenshot_${TIMESTAMP}.png"
SAVE_PATH="${SAVE_DIR}/${FILENAME}"
# ============================================================================

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[RUN] SCREENSHOT CAPTURE - macOS"
echo "=============================================================="

# Create directory if needed
if [ ! -d "$SAVE_DIR" ]; then
    echo "Creating screenshot directory..."
    mkdir -p "$SAVE_DIR"
fi

# Capture screenshot
echo "Capturing screenshot..."

# -x = no sound, captures silently
if screencapture -x "$SAVE_PATH"; then
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Result    : SUCCESS"
    echo "Saved to  : $SAVE_PATH"
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
else
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Failed to capture screenshot"
    echo ""
    exit 1
fi
