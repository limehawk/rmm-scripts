#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Service Restart (macOS)                            v1.0.0
# FILE   : splashtop_service_restart_macos.sh
# ==============================================================================
# PURPOSE:
#   Restarts the Splashtop Streamer service on macOS by unloading and
#   reloading the launch daemon.
#
# USAGE:
#   sudo ./splashtop_service_restart_macos.sh
#
# PREREQUISITES:
#   - macOS
#   - Root/sudo privileges
#   - Splashtop Streamer installed
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

PLIST_PATH="/Library/LaunchDaemons/com.splashtop.streamer-for-admin.plist"

echo ""
echo "[ SPLASHTOP SERVICE RESTART - macOS ]"
echo "--------------------------------------------------------------"

# Check if plist exists
if [ ! -f "$PLIST_PATH" ]; then
    echo "[ERROR] Splashtop launch daemon not found"
    echo "Is Splashtop Streamer installed?"
    exit 1
fi

# Stop service
echo "Stopping Splashtop service..."
sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Start service
echo "Starting Splashtop service..."
sudo launchctl load "$PLIST_PATH" || {
    echo "[ERROR] Failed to start Splashtop service"
    exit 1
}

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop services restarted successfully"
exit 0
