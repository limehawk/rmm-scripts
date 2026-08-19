#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : SuperOps Agent Uninstall (Linux)                             v1.2.0
#  AUTHOR   : Limehawk.io
#  DATE     : August 2026
#  USAGE    : sudo ./superops_agent_uninstall_linux.sh
# ================================================================================
#  FILE     : superops_agent_uninstall_linux.sh
#  DESCRIPTION : Uninstalls SuperOps RMM agent from Linux using vendor script
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#  Uninstalls the SuperOps RMM agent from Linux by running the vendor
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
#  - Sets executable permissions before running
#  - Missing agent is exit 0
#
#  BEHAVIOR
#  1. Looks for uninstall.sh under /opt/superopsrmm, SuperOpsRMM, limehawkrmm,
#     limehawk, Limehawkrmmagent, and /usr/local/superops
#  2. chmod +x and runs the first one found
#  3. Reports already-removed if none exist
#
#  PREREQUISITES
#  - Bash shell
#  - Linux operating system
#  - Root/sudo privileges (for uninstallation)
#
#  SECURITY NOTES
#  - No secrets in logs
#  - Executes only the vendor uninstall script
#  - Requires root privileges to execute
#
#  ENDPOINTS
#  - N/A (local uninstallation only)
#
#  EXIT CODES
#  - 0 success
#  - 1 failure
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Uninstall Script: /opt/superopsrmm/uninstall.sh
#
#    [RUN] UNINSTALLING
#    ==============================================================
#    Checking for uninstall script...
#    Uninstall script found
#    Setting executable permissions...
#    Executing uninstall script...
#    Removing SuperOps RMM Agent...
#    Stopping services...
#    Removing files...
#    Uninstall script completed successfully
#
#    [INFO] RESULT
#    ==============================================================
#    Status: Success
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#    SuperOps agent uninstalled successfully
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-08-19 v1.2.0 Try SuperOps + Limehawk paths. Already-removed is success.
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-02 v1.0.0 Initial migration from SuperOps
# ================================================================================

# Exit on error
set -e

# ==== STATE ====
ERROR_OCCURRED=0
ERROR_TEXT=""

# ==== HARDCODED INPUTS (MANDATORY) ====
UNINSTALL_PATHS="/opt/superopsrmm/uninstall.sh /opt/SuperOpsRMM/uninstall.sh /usr/local/superops/uninstall.sh /opt/limehawkrmm/uninstall.sh /opt/limehawk/uninstall.sh /opt/Limehawkrmmagent/uninstall.sh"

UNINSTALL_SCRIPT_PATH=""
for candidate in $UNINSTALL_PATHS; do
    if [ -f "$candidate" ]; then
        UNINSTALL_SCRIPT_PATH="$candidate"
        break
    fi
done

# ==== RUNTIME OUTPUT ====
echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="
if [ -n "$UNINSTALL_SCRIPT_PATH" ]; then
    echo "Uninstall Script : $UNINSTALL_SCRIPT_PATH"
else
    echo "Uninstall Script : (none found)"
fi

echo ""
echo "[RUN] UNINSTALLING"
echo "=============================================================="

if [ -z "$UNINSTALL_SCRIPT_PATH" ]; then
    echo "No vendor uninstall script found - agent already absent"
else
    echo "Uninstall script found"
    echo "Setting executable permissions..."
    if ! chmod +x "$UNINSTALL_SCRIPT_PATH"; then
        ERROR_OCCURRED=1
        ERROR_TEXT="Failed to set executable permissions on uninstall script.
You may need to run this script with sudo."
    fi

    if [ "$ERROR_OCCURRED" -eq 0 ]; then
        echo "Executing uninstall script..."
        if ! "$UNINSTALL_SCRIPT_PATH"; then
            ERROR_OCCURRED=1
            ERROR_TEXT="Uninstall script execution failed.
Check the output above for specific error messages from the uninstaller."
        else
            echo "Uninstall script completed successfully"
        fi
    fi
fi

# ==== OUTPUT RESULTS ====
if [ "$ERROR_OCCURRED" -eq 1 ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "$ERROR_TEXT"
fi

echo ""
echo "[INFO] RESULT"
echo "=============================================================="
if [ "$ERROR_OCCURRED" -eq 1 ]; then
    echo "Status : Failure"
else
    echo "Status : Success"
fi

echo ""
if [ "$ERROR_OCCURRED" -eq 1 ]; then
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "SuperOps agent uninstallation failed. See error details above."
else
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    if [ -z "$UNINSTALL_SCRIPT_PATH" ]; then
        echo "SuperOps agent already absent"
    else
        echo "SuperOps agent uninstalled successfully"
    fi
fi

if [ "$ERROR_OCCURRED" -eq 1 ]; then
    exit 1
else
    exit 0
fi
