#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : SuperOps Agent Uninstall - Alt Path (macOS)                  v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./superops_agent_alt_path_uninstall_macos.sh
# ================================================================================
#  FILE     : superops_agent_alt_path_uninstall_macos.sh
#  DESCRIPTION : Uninstalls SuperOps agent from alternate /Library/limehawk path
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Uninstalls the SuperOps agent from macOS systems by executing the agent's
#    built-in uninstall script from an alternate path (/Library/limehawk).
#
#  DATA SOURCES & PRIORITY
#
#    - Hardcoded path to the uninstall script
#
#  REQUIRED INPUTS
#
#    No inputs required.
#
#  SETTINGS
#
#    Default configuration:
#      - Uninstall script path: /Library/limehawk/uninstall.sh
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Executes the uninstall script with sudo privileges
#    2. Reports completion status
#
#  PREREQUISITES
#
#    - The uninstall script must exist at the specified path
#    - The user running the script must have sudo privileges
#
#  SECURITY NOTES
#
#    - This script runs with sudo privileges
#    - Will remove software from the system
#
#  ENDPOINTS
#
#    Not applicable - local system operation only
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure
#
#  EXAMPLE RUN
#
#    [RUN] UNINSTALLING AGENT
#    ==============================================================
#    Attempting to uninstall SuperOps agent from alternate path...
#
#    [OK] FINAL STATUS
#    ==============================================================
#    SuperOps agent uninstallation from alternate path completed.
#
#    [OK] SCRIPT COMPLETE
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-02 v1.0.0 Initial version, extracted from SuperOps
# ================================================================================

set -e

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[RUN] UNINSTALLING AGENT"
echo "=============================================================="
echo "Attempting to uninstall SuperOps agent from alternate path..."

sudo bash /Library/limehawk/uninstall.sh

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "SuperOps agent uninstallation from alternate path completed."

echo ""
echo "[OK] SCRIPT COMPLETE"
echo "=============================================================="

exit 0
