#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : SuperOps Agent Uninstall (macOS)                             v2.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : August 2026
#  USAGE    : sudo ./superops_agent_uninstall_macos.sh
# ================================================================================
#  FILE     : superops_agent_uninstall_macos.sh
#  DESCRIPTION : Uninstalls SuperOps/Limehawk RMM agent from macOS
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#  Uninstalls the SuperOps RMM agent from macOS by running the vendor
#  uninstall.sh from every known SuperOps and Limehawk install path.
#  Already-removed is success.
#
#  DATA SOURCES & PRIORITY
#  1) Vendor uninstall.sh in known install directories
#
#  REQUIRED INPUTS
#  - UNINSTALL_PATHS : hardcoded list of vendor uninstall.sh locations
#
#  SETTINGS
#  - Tries each path in order and runs the first uninstall.sh found
#  - Missing agent is exit 0
#
#  BEHAVIOR
#  1. Looks for uninstall.sh under /Library/superops, limehawk, limehawkrmm,
#     Limehawkrmmagent
#  2. Runs the first one found with sudo
#  3. Reports already-removed if none exist
#
#  PREREQUISITES
#  - Bash, macOS, sudo
#
#  SECURITY NOTES
#  - No secrets in logs
#  - Runs only the vendor uninstall script
#
#  ENDPOINTS
#  - Not applicable
#
#  EXIT CODES
#  - 0 success (uninstalled or already absent)
#  - 1 failure
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Uninstall Script : /Library/limehawk/uninstall.sh
#
#    [RUN] UNINSTALLING
#    ==============================================================
#    Executing vendor uninstall script...
#    Uninstall script completed successfully
#
#    [OK] FINAL STATUS
#    ==============================================================
#    SuperOps agent uninstalled successfully
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-08-19 v2.0.0 One macOS uninstaller. Try SuperOps + Limehawk paths.
#                    Already-removed is success. Folded alt-path script.
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-02 v1.0.0 Initial migration from SuperOps
# ================================================================================

set -e

ERROR_OCCURRED=0
ERROR_TEXT=""

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
UNINSTALL_PATHS="/Library/superops/uninstall.sh /Library/SuperOps/uninstall.sh /Library/limehawk/uninstall.sh /Library/limehawkrmm/uninstall.sh /Library/Limehawkrmmagent/uninstall.sh"

UNINSTALL_SCRIPT=""
for candidate in $UNINSTALL_PATHS; do
    if [ -f "$candidate" ]; then
        UNINSTALL_SCRIPT="$candidate"
        break
    fi
done

echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="
if [ -n "$UNINSTALL_SCRIPT" ]; then
    echo "Uninstall Script : $UNINSTALL_SCRIPT"
else
    echo "Uninstall Script : (none found)"
fi

echo ""
echo "[RUN] UNINSTALLING"
echo "=============================================================="

if [ -z "$UNINSTALL_SCRIPT" ]; then
    echo "No vendor uninstall script found - agent already absent"
else
    echo "Executing vendor uninstall script..."
    if ! sudo bash "$UNINSTALL_SCRIPT"; then
        ERROR_OCCURRED=1
        ERROR_TEXT="Uninstall script execution failed.
Check the output above for specific error messages from the uninstaller."
    else
        echo "Uninstall script completed successfully"
    fi
fi

if [ "$ERROR_OCCURRED" -eq 1 ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "$ERROR_TEXT"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "SuperOps agent uninstallation failed. See error details above."
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
if [ -z "$UNINSTALL_SCRIPT" ]; then
    echo "SuperOps agent already absent"
else
    echo "SuperOps agent uninstalled successfully"
fi

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
