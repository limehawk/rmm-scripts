#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Workstation Information Popup (macOS)                        v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : ./workstation_info_display_macos.sh
# ================================================================================
#  FILE     : workstation_info_display_macos.sh
#  DESCRIPTION : Displays system info popup dialog for macOS user self-service
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Displays a popup dialog showing system information to the end user.
#    Designed to be triggered from the RMM tray icon for user self-service.
#    Provides quick access to basic system details without opening System
#    Preferences.
#
#  DATA SOURCES & PRIORITY
#
#    - sw_vers: OS name and version
#    - scutil: Computer name
#    - sysctl: CPU and RAM information
#    - ipconfig: Network information
#
#  REQUIRED INPUTS
#
#    No hardcoded inputs required.
#
#  SETTINGS
#
#    Collects and displays:
#      - Operating System name and version
#      - Computer name and current user
#      - CPU name and core count
#      - Total RAM
#      - Network adapter info (IP address)
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Collects system information
#    2. Builds an AppleScript dialog
#    3. Displays popup to user (runs in background)
#    4. Exits immediately (popup remains)
#
#  PREREQUISITES
#
#    - macOS 10.14 or later
#    - No special privileges required
#    - AppleScript/osascript available
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Displays system info in user-facing dialog
#    - Runs in background to avoid blocking RMM
#
#  ENDPOINTS
#
#    Not applicable - local system operation only
#
#  EXIT CODES
#
#    0 = Success
#
#  EXAMPLE RUN
#
#    (Displays GUI popup to user with system information)
#
#    === Workstation Information ===
#
#    === Operating System ===
#    Name: macOS
#    Version: 14.2
#
#    === Computer ===
#    Name: WORKSTATION-01
#    User: jsmith
#
#    === Hardware ===
#    CPU: Apple M1
#    Cores: 8
#    RAM: 16.00 GB
#
#    === Network ===
#    IP Address: 192.168.1.100
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-12-01 v1.0.0 Initial release - migrated from SuperOps
# ================================================================================

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Collect system information
os_name=$(sw_vers -productName 2>/dev/null || echo "macOS")
os_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
computer_name=$(scutil --get ComputerName 2>/dev/null || hostname)
current_user=$(whoami)
cpu_name=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "Unknown")
total_ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.2f", $1/1024/1024/1024 }')

# Get primary network adapter info
primary_ip=$(ipconfig getifaddr en0 2>/dev/null || echo "Not connected")
if [[ "$primary_ip" == "Not connected" ]]; then
    primary_ip=$(ipconfig getifaddr en1 2>/dev/null || echo "Not connected")
fi

# Build the AppleScript dialog
applescript_code=$(cat <<EOF
display dialog "=== Workstation Information ===" & return & return ¬
  & "=== Operating System ===" & return ¬
  & "Name: $os_name" & return ¬
  & "Version: $os_version" & return & return ¬
  & "=== Computer ===" & return ¬
  & "Name: $computer_name" & return ¬
  & "User: $current_user" & return & return ¬
  & "=== Hardware ===" & return ¬
  & "CPU: $cpu_name" & return ¬
  & "Cores: $cpu_cores" & return ¬
  & "RAM: $total_ram GB" & return & return ¬
  & "=== Network ===" & return ¬
  & "IP Address: $primary_ip" ¬
  with title "Workstation Information" buttons {"OK"} default button "OK"
EOF
)

# Execute the AppleScript to display popup (run in background so script exits)
osascript -e "$applescript_code" >/dev/null 2>&1 &

exit 0
