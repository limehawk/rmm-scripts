#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Rustic Restore (Unix)                                      v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : April 2026
#  USAGE    : sudo ./rustic_restore_unix.sh
# ================================================================================
#  FILE     : rustic_restore_unix.sh
#  DESCRIPTION : Restores files from a rustic backup snapshot (Linux/macOS)
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Targeted file and directory restore from a rustic backup snapshot on
#    Linux and macOS. Reads the existing rustic TOML configuration to connect
#    to the configured backend, lists available snapshots for reference, then
#    restores the specified path from a chosen snapshot (or "latest") to a
#    given destination directory. Designed for deployment via SuperOps RMM.
#
#  DATA SOURCES & PRIORITY
#
#    - Existing rustic TOML config at /etc/rustic/rustic.toml
#    - Rustic binary at /usr/local/bin/rustic
#
#  REQUIRED INPUTS
#
#    SuperOps runtime variables (prompted at deploy time):
#      - $YourRestorePath  : Path within the snapshot to restore (e.g., /etc/nginx)
#      - $YourDestination  : Local destination directory for restored files
#
#    Optional:
#      - $YourSnapshotId   : Snapshot ID to restore from (default: latest)
#
#  SETTINGS
#
#    Hardcoded paths:
#      - Rustic binary  : /usr/local/bin/rustic
#      - Config file    : /etc/rustic/rustic.toml
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Parses inputs; defaults SNAPSHOT_ID to "latest" if empty or unreplaced
#    2. Validates binary exists and is executable, config file exists,
#       RESTORE_PATH is provided, DESTINATION is provided
#    3. Exports RUSTIC_CONFIG_FILE for rustic to pick up
#    4. Displays input validation summary
#    5. Lists available snapshots for operator reference (non-fatal if it fails)
#    6. Creates the destination directory if it does not exist
#    7. Runs: rustic restore "<snapshot>:<path>" "<destination>"
#    8. Reports final status and exits 0 on success, 1 on failure
#
#  PREREQUISITES
#
#    - rustic installed at /usr/local/bin/rustic (use rustic_install_unix.sh)
#    - /etc/rustic/rustic.toml configured with valid backend credentials
#    - Linux or macOS with root privileges
#    - Network access to the configured backend
#
#  SECURITY NOTES
#
#    - No credentials are passed on the command line; rustic reads them from TOML
#    - Destination directory is created by this script (mkdir -p)
#    - Restored files inherit the permissions stored in the snapshot
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure (validation, restore error)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#      Snapshot     : latest
#      Restore Path : /etc/nginx
#      Destination  : /tmp/restore/nginx
#
#    [INFO] AVAILABLE SNAPSHOTS
#    ==============================================================
#      ID        Time                 Host       Tags
#      --------  -------------------  ---------  ----
#      a1b2c3d4  2026-04-03 02:01:15  server01
#      e5f6a7b8  2026-04-02 02:00:44  server01
#
#    [RUN] RESTORE
#    ==============================================================
#      Restoring latest:/etc/nginx -> /tmp/restore/nginx ...
#      restore done
#
#    [OK] FINAL STATUS
#    ==============================================================
#      Destination  : /tmp/restore/nginx
#
#    [OK] SCRIPT COMPLETE
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-04-04 v1.0.0 Initial release
# ================================================================================

set -euo pipefail

# ==== STATE ====
ERROR_OCCURRED=false
ERROR_TEXT=""

# ==== HARDCODED INPUTS (MANDATORY) ====

# shellcheck disable=SC2154  # Variables injected by RMM at deploy time
SNAPSHOT_ID="${YourSnapshotId:-}"    # Snapshot ID to restore (default: latest)
RESTORE_PATH="${YourRestorePath:-}"  # Path within snapshot to restore (REQUIRED)
DESTINATION="${YourDestination:-}"   # Local destination directory (REQUIRED)

# ==== PATHS ====
RUSTIC_BIN="/usr/local/bin/rustic"
CONFIG_FILE="/etc/rustic/rustic.toml"

# ==== PARSE INPUTS ====

# Default SNAPSHOT_ID to "latest" if empty or still holds the literal placeholder
if [[ -z "${SNAPSHOT_ID}" || "${SNAPSHOT_ID}" == '$YourSnapshotId' ]]; then
    SNAPSHOT_ID="latest"
fi

# ==== VALIDATION ====

if [[ ! -x "${RUSTIC_BIN}" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}- Rustic binary not found or not executable: ${RUSTIC_BIN}"$'\n'
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- Rustic config file not found: ${CONFIG_FILE}"
fi

if [[ -z "${RESTORE_PATH}" || "${RESTORE_PATH}" == '$YourRestorePath' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourRestorePath is required."
fi

if [[ -z "${DESTINATION}" || "${DESTINATION}" == '$YourDestination' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourDestination is required."
fi

if [[ "${ERROR_OCCURRED}" == "true" ]]; then
    echo ""
    echo "[ERROR] INPUT VALIDATION"
    echo "=============================================================="
    echo "${ERROR_TEXT}"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

# ==== EXPORT CONFIG ====
export RUSTIC_CONFIG_FILE="${CONFIG_FILE}"

# ==== INPUT VALIDATION OUTPUT ====
echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="
echo "  Snapshot     : ${SNAPSHOT_ID}"
echo "  Restore Path : ${RESTORE_PATH}"
echo "  Destination  : ${DESTINATION}"

# ==== AVAILABLE SNAPSHOTS ====
echo ""
echo "[INFO] AVAILABLE SNAPSHOTS"
echo "=============================================================="
"${RUSTIC_BIN}" snapshots 2>&1 | sed 's/^/  /' || true

# ==== CREATE DESTINATION ====
mkdir -p "${DESTINATION}"

# ==== RESTORE ====
echo ""
echo "[RUN] RESTORE"
echo "=============================================================="
echo "  Restoring ${SNAPSHOT_ID}:${RESTORE_PATH} -> ${DESTINATION} ..."

if ! "${RUSTIC_BIN}" restore "${SNAPSHOT_ID}:${RESTORE_PATH}" "${DESTINATION}"; then
    echo ""
    echo "[ERROR] RESTORE FAILED"
    echo "=============================================================="
    echo "  rustic restore exited with a non-zero status."
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

# ==== FINAL STATUS ====
echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "  Destination  : ${DESTINATION}"
echo ""
echo "[OK] SCRIPT COMPLETE"
echo "=============================================================="
exit 0
