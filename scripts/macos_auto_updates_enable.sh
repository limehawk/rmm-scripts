#!/bin/bash
set -euo pipefail
# ==============================================================================
# SCRIPT : Enable macOS Auto-Updates                                     v1.0.0
# FILE   : macos_auto_updates_enable.sh
# ==============================================================================
# PURPOSE:
#   Enables all automatic update settings on macOS including:
#   - Automatic checking for updates
#   - Automatic downloading of updates
#   - Automatic installation of macOS updates
#   - Automatic App Store updates
#   - Automatic security/data file updates
#
# PREREQUISITES:
#   - macOS 10.14 or later
#   - Root/sudo privileges
#
# EXIT CODES:
#   0 = Success
#   1 = Failure
# ==============================================================================

echo ""
echo "[ ENABLING AUTO-UPDATES ]"
echo "--------------------------------------------------------------"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo " Enabling automatic check for updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

echo " Enabling automatic download of updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true

echo " Enabling App Store auto-updates..."
defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true

echo " Enabling config data file updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true

echo " Enabling critical security updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

echo " Enabling automatic macOS updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true

echo ""
echo "[ VERIFICATION ]"
echo "--------------------------------------------------------------"
echo " AutomaticCheckEnabled          : $(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null || echo 'not set')"
echo " AutomaticDownload              : $(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo 'not set')"
echo " AutoUpdate (App Store)         : $(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null || echo 'not set')"
echo " ConfigDataInstall              : $(defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall 2>/dev/null || echo 'not set')"
echo " CriticalUpdateInstall          : $(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null || echo 'not set')"
echo " AutomaticallyInstallMacOSUpdates: $(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null || echo 'not set')"

echo ""
echo "[ FINAL STATUS ]"
echo "--------------------------------------------------------------"
echo " All auto-update settings have been enabled."

echo ""
echo "[ SCRIPT COMPLETED ]"
echo "--------------------------------------------------------------"

exit 0
