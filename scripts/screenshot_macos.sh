#!/bin/bash
# ==============================================================================
# SCRIPT : Screenshot Capture (macOS)                                   v1.0.0
# FILE   : screenshot_macos.sh
# ==============================================================================
# PURPOSE:
#   Captures a screenshot on macOS and saves it with a timestamped filename.
#   Uses the native screencapture utility for silent capture.
#
# USAGE:
#   ./screenshot_macos.sh
#
# PREREQUISITES:
#   - macOS 10.12 or later
#   - screencapture utility (standard macOS component)
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Save location - uses /tmp for RMM compatibility
SAVE_DIR="/tmp/screenshots"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="screenshot_${TIMESTAMP}.png"
SAVE_PATH="${SAVE_DIR}/${FILENAME}"

echo ""
echo "[ SCREENSHOT CAPTURE - macOS ]"
echo "--------------------------------------------------------------"

# ==============================================================================
# CREATE DIRECTORY
# ==============================================================================
if [ ! -d "$SAVE_DIR" ]; then
    echo "Creating screenshot directory..."
    mkdir -p "$SAVE_DIR"
fi

# ==============================================================================
# CAPTURE SCREENSHOT
# ==============================================================================
echo "Capturing screenshot..."

# -x = no sound, captures silently
if screencapture -x "$SAVE_PATH"; then
    echo ""
    echo "[ FINAL STATUS ]"
    echo "--------------------------------------------------------------"
    echo "Result    : SUCCESS"
    echo "Saved to  : $SAVE_PATH"
else
    echo ""
    echo "[ ERROR OCCURRED ]"
    echo "--------------------------------------------------------------"
    echo "Failed to capture screenshot"
    exit 1
fi

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
