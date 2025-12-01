#!/bin/bash
# ==============================================================================
# SCRIPT : Splashtop Uninstall (macOS)                                  v1.0.0
# FILE   : splashtop_uninstall_macos.sh
# ==============================================================================
# PURPOSE:
#   Completely removes Splashtop Streamer from macOS including all related
#   files, launch daemons, kernel extensions, and preferences.
#
# USAGE:
#   sudo ./splashtop_uninstall_macos.sh
#
# PREREQUISITES:
#   - macOS
#   - Root/sudo privileges
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

APP_BUNDLE_ID="com.splashtop.Splashtop-Streamer"
APP_NAME="Splashtop Streamer.app"

echo ""
echo "[ SPLASHTOP UNINSTALL - macOS ]"
echo "--------------------------------------------------------------"

# Kill running processes
echo "Stopping Splashtop processes..."
killall "Splashtop Streamer" 2>/dev/null || true
killall "inputserv" 2>/dev/null || true
killall "spupnp" 2>/dev/null || true
killall "SRProxy" 2>/dev/null || true
killall "SRFeature" 2>/dev/null || true
killall "SplashtopRemote" 2>/dev/null || true
killall "SRStreamerDaemon" 2>/dev/null || true

# Unload launch daemons
echo "Unloading launch daemons..."
sudo launchctl unload /Library/LaunchDaemons/com.splashtop.streamer-daemon.plist 2>/dev/null || true
sudo launchctl unload /Library/LaunchDaemons/com.splashtop.streamer-srioframebuffer.plist 2>/dev/null || true
sudo launchctl unload /Library/LaunchAgents/com.splashtop.streamer-for-user.plist 2>/dev/null || true
sudo launchctl unload /Library/LaunchAgents/com.splashtop.streamer-for-root.plist 2>/dev/null || true

# Remove launch daemon files
echo "Removing launch daemon files..."
sudo rm -rf /Library/LaunchDaemons/com.splashtop.streamer*.plist 2>/dev/null || true
sudo rm -rf /Library/LaunchAgents/com.splashtop.streamer*.plist 2>/dev/null || true

# Remove application
echo "Removing application..."
sudo rm -rf "/Applications/$APP_NAME" 2>/dev/null || true
sudo rm -rf "/Applications/Splashtop Streamer for Business.app" 2>/dev/null || true
sudo rm -rf "/Applications/SplashtopRemote.app" 2>/dev/null || true

# Remove shared data
echo "Removing shared data..."
sudo rm -rf /Users/Shared/SplashtopStreamer 2>/dev/null || true

# Remove kernel extensions
echo "Removing kernel extensions..."
sudo rm -rf /Library/Extensions/SRXFrameBufferConnector.kext 2>/dev/null || true
sudo rm -rf /Library/Extensions/SplashtopSoundDriver.kext 2>/dev/null || true
sudo rm -rf /System/Library/Extensions/SRXFrameBufferConnector.kext 2>/dev/null || true

# Remove audio plugin
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/SplashtopRemoteSound.driver" 2>/dev/null || true

# Remove preferences
echo "Removing preferences..."
sudo rm -rf ~/Library/Preferences/${APP_BUNDLE_ID}.plist* 2>/dev/null || true
sudo rm -rf /var/root/Library/Preferences/${APP_BUNDLE_ID}.plist* 2>/dev/null || true

# Remove user caches
sudo rm -rf ~/Library/Caches/${APP_BUNDLE_ID} 2>/dev/null || true
sudo rm -rf ~/Library/Caches/iris-proxy-pipe* 2>/dev/null || true

# Forget package receipts
echo "Cleaning package receipts..."
sudo pkgutil --forget com.splashtop.splashtopStreamer.com.splashtop.streamer-daemon.pkg 2>/dev/null || true
sudo pkgutil --forget com.splashtop.splashtopStreamer.SplashtopStreamer.pkg 2>/dev/null || true
sudo pkgutil --forget ${APP_BUNDLE_ID} 2>/dev/null || true

echo ""
echo "[ COMPLETE ]"
echo "--------------------------------------------------------------"
echo "Splashtop Streamer has been uninstalled"
exit 0
