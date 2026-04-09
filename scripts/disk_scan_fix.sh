#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Disk Scan and Fix (macOS)                                  v2.0.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./disk_scan_fix.sh
# ================================================================================
#  FILE     : disk_scan_fix.sh
#  DESCRIPTION : Comprehensive disk and volume health check for macOS
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Performs a comprehensive health check on all mounted disks and volumes
#    on macOS. Verifies partition maps, file systems, and SMART status where
#    supported.
#
#  DATA SOURCES & PRIORITY
#
#    1. diskutil - macOS disk utility
#    2. System disk information
#
#  REQUIRED INPUTS
#
#    None - script auto-detects all mounted disks.
#
#  SETTINGS
#
#    - Scans all mounted disks
#    - Checks partition map health
#    - Verifies HFS and APFS volumes
#    - Reports SMART status when available
#
#  BEHAVIOR
#
#    1. Lists all mounted disks
#    2. For each disk:
#       - Verifies partition map
#       - Gets list of volumes (HFS/APFS)
#       - Verifies each volume's file system
#       - Checks SMART status if supported
#    3. Reports results for each disk/volume
#
#  PREREQUISITES
#
#    - macOS operating system
#    - Root/sudo privileges
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Read-only operations (verification only)
#    - Requires elevated privileges for disk access
#
#  ENDPOINTS
#
#    Not applicable - this script does not connect to any network endpoints
#
#  EXIT CODES
#
#    0 = Success - all checks completed
#    1 = Failure - error during disk verification
#
#  EXAMPLE RUN
#
#    [RUN] DISK SCAN
#    ==============================================================
#    Starting comprehensive disk and volume health check...
#
#    [INFO] DISK: disk0
#    ==============================================================
#    Checking partition map health for disk0...
#    [OK] Partition map of disk0 appears to be OK
#
#    [INFO] VOLUMES: disk0
#    ==============================================================
#    Checking file system health for disk0s1...
#    [OK] File system of disk0s1 appears to be OK
#
#    [INFO] SMART STATUS: disk0
#    ==============================================================
#    [OK] SMART status of disk0 indicates it is OK
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Result : SUCCESS
#    Comprehensive health check completed
#
#    [INFO] SCRIPT COMPLETE
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v2.0.1 Updated to two-line ASCII console output style
#  2026-01-14 v2.0.0 Complete rewrite with Limehawk Script Framework
#  2024-01-01 v1.0.0 Initial release
# ================================================================================

# ============================================================================
# STATE VARIABLES
# ============================================================================
ERROR_OCCURRED=false
DISKS_CHECKED=0
VOLUMES_CHECKED=0
SMART_CHECKED=0

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[RUN] DISK SCAN"
echo "=============================================================="
echo "Starting comprehensive disk and volume health check..."

# Get the list of all mounted disks
DISKS=$(diskutil list | grep 'disk[0-9]' | awk '{print $1}' | sort -u)

if [[ -z "$DISKS" ]]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "No disks found"
    echo ""
    exit 1
fi

# Loop through each disk
for disk in $DISKS; do
    echo ""
    echo "[INFO] DISK: $disk"
    echo "=============================================================="
    echo "Checking partition map health for $disk..."

    # Using diskutil to verify the partition map
    if diskutil verifyDisk "$disk" 2>&1; then
        echo "[OK] Partition map of $disk appears to be OK"
    else
        echo "[WARN] An error occurred with the partition map of $disk"
        echo "Check the disk using Disk Utility"
        ERROR_OCCURRED=true
    fi

    DISKS_CHECKED=$((DISKS_CHECKED + 1))

    # Get the list of volumes on the disk
    VOLUMES=$(diskutil list "$disk" | grep -E 'Apple_HFS|Apple_APFS' | awk '{print $NF}')

    if [[ -n "$VOLUMES" ]]; then
        echo ""
        echo "[INFO] VOLUMES: $disk"
        echo "=============================================================="

        # Loop through each volume on the disk
        for volume in $VOLUMES; do
            echo "Checking file system health for $volume..."

            # Using diskutil to verify the volume
            if diskutil verifyVolume "$volume" 2>&1; then
                echo "[OK] File system of $volume appears to be OK"
            else
                echo "[WARN] An error occurred with the file system of $volume"
                echo "Check the volume using Disk Utility"
                ERROR_OCCURRED=true
            fi

            VOLUMES_CHECKED=$((VOLUMES_CHECKED + 1))
        done
    fi

    # Check if the disk supports SMART status
    SMART_STATUS=$(diskutil info "$disk" 2>/dev/null | grep "SMART Status" | awk '{print $3}')

    if [[ "$SMART_STATUS" == "Verified" || "$SMART_STATUS" == "Supported" ]]; then
        echo ""
        echo "[INFO] SMART STATUS: $disk"
        echo "=============================================================="
        echo "Checking SMART status for $disk..."

        SMART_OUTPUT=$(diskutil info "$disk" | grep "SMART Status")
        echo "$SMART_OUTPUT"

        if echo "$SMART_OUTPUT" | grep -q "Verified"; then
            echo "[OK] SMART status of $disk indicates it is OK"
        else
            echo "[WARN] SMART status check indicates a potential issue with $disk"
            echo "Consider further diagnostics"
        fi

        SMART_CHECKED=$((SMART_CHECKED + 1))
    elif [[ -n "$SMART_STATUS" ]]; then
        echo ""
        echo "[INFO] SMART STATUS: $disk"
        echo "=============================================================="
        echo "SMART Status : $SMART_STATUS"
    fi
done

echo ""
echo "[INFO] SUMMARY"
echo "=============================================================="
echo "Disks Checked   : $DISKS_CHECKED"
echo "Volumes Checked : $VOLUMES_CHECKED"
echo "SMART Checked   : $SMART_CHECKED"

echo ""
if [[ "$ERROR_OCCURRED" = true ]]; then
    echo "[WARN] FINAL STATUS"
    echo "=============================================================="
    echo "Result : COMPLETED WITH WARNINGS"
    echo "Some checks reported issues - review output above"
else
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Result : SUCCESS"
    echo "Comprehensive health check completed"
fi

echo ""
echo "[INFO] SCRIPT COMPLETE"
echo "=============================================================="

if [[ "$ERROR_OCCURRED" = true ]]; then
    exit 1
else
    exit 0
fi
