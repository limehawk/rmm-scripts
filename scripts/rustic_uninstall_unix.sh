#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Rustic Uninstall (Unix)                                    v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : April 2026
#  USAGE    : sudo ./rustic_uninstall_unix.sh
# ================================================================================
#  FILE     : rustic_uninstall_unix.sh
#  DESCRIPTION : Removes rustic binary, config, schedule, and logs (Linux/macOS)
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Removes all components installed by rustic_install_unix.sh. Detects OS
#    (Linux/macOS), stops and disables the backup schedule (systemd timer on
#    Linux, launchd plist on macOS), removes the Rustic binary and backup
#    runner script, and deletes the configuration directory and log directory.
#    The remote backup repository is NOT touched.
#
#  DATA SOURCES & PRIORITY
#
#    - Local filesystem only; no network access required
#
#  REQUIRED INPUTS
#
#    None. No runtime variables required.
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Detects OS (Linux/macOS)
#    2. Stops and removes the backup schedule
#       - Linux: stops/disables rustic-backup.timer and rustic-backup.service,
#         reloads systemd daemon
#       - macOS: unloads and removes io.limehawk.rustic-backup.plist
#    3. Removes /usr/local/bin/rustic (binary)
#    4. Removes /usr/local/bin/rustic-backup.sh (runner script)
#    5. Removes /etc/rustic (config directory)
#    6. Removes /var/log/rustic (log directory)
#    7. Reports final status
#
#    Partial removal is acceptable. The script always exits 0.
#
#  PREREQUISITES
#
#    - Linux or macOS
#    - Root privileges (runs as root via RMM)
#
#  SECURITY NOTES
#
#    - Remote backup repository and its data are not affected
#    - Config files (which contain backend credentials) are deleted
#
#  EXIT CODES
#
#    0 = Success (always)
#
#  EXAMPLE RUN
#
#    [RUN] REMOVE SCHEDULE
#    ==============================================================
#      OS: Linux
#      rustic-backup.timer is active — stopping and disabling...
#      Timer stopped and disabled
#      Removed /etc/systemd/system/rustic-backup.timer
#      Removed /etc/systemd/system/rustic-backup.service
#      systemd daemon reloaded
#
#    [RUN] REMOVE FILES
#    ==============================================================
#      Removed /usr/local/bin/rustic
#      Removed /usr/local/bin/rustic-backup.sh
#      Removed /etc/rustic
#      Removed /var/log/rustic
#
#    [OK] FINAL STATUS
#    ==============================================================
#      Result : SUCCESS
#      Note   : Remote backup repository was NOT deleted
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

# ==== DETECT OS ====
OS_TYPE="$(uname -s)"

# ==== HELPERS ====
print_header() {
    echo ""
    echo "$1"
    echo "=============================================================="
}

# ==============================================================
#  [RUN] REMOVE SCHEDULE
# ==============================================================
print_header "[RUN] REMOVE SCHEDULE"
echo "  OS: ${OS_TYPE}"

if [[ "${OS_TYPE}" == "Linux" ]]; then
    TIMER_FILE="/etc/systemd/system/rustic-backup.timer"
    SERVICE_FILE="/etc/systemd/system/rustic-backup.service"

    if systemctl is-active --quiet rustic-backup.timer 2>/dev/null; then
        echo "  rustic-backup.timer is active — stopping and disabling..."
        systemctl stop rustic-backup.timer
        systemctl disable rustic-backup.timer
        echo "  Timer stopped and disabled"
    else
        echo "  rustic-backup.timer is not active (skipping stop/disable)"
    fi

    if [[ -f "${TIMER_FILE}" ]]; then
        rm -f "${TIMER_FILE}"
        echo "  Removed ${TIMER_FILE}"
    else
        echo "  ${TIMER_FILE} not found (skipping)"
    fi

    if [[ -f "${SERVICE_FILE}" ]]; then
        rm -f "${SERVICE_FILE}"
        echo "  Removed ${SERVICE_FILE}"
    else
        echo "  ${SERVICE_FILE} not found (skipping)"
    fi

    systemctl daemon-reload
    echo "  systemd daemon reloaded"

elif [[ "${OS_TYPE}" == "Darwin" ]]; then
    PLIST_FILE="/Library/LaunchDaemons/io.limehawk.rustic-backup.plist"

    if [[ -f "${PLIST_FILE}" ]]; then
        launchctl unload "${PLIST_FILE}" 2>/dev/null || true
        rm -f "${PLIST_FILE}"
        echo "  Unloaded and removed ${PLIST_FILE}"
    else
        echo "  ${PLIST_FILE} not found (skipping)"
    fi

else
    echo "  Unrecognised OS (${OS_TYPE}) — skipping schedule removal"
fi

# ==============================================================
#  [RUN] REMOVE FILES
# ==============================================================
print_header "[RUN] REMOVE FILES"

BINARY="/usr/local/bin/rustic"
RUNNER="/usr/local/bin/rustic-backup.sh"
CONFIG_DIR="/etc/rustic"
LOG_DIR="/var/log/rustic"

if [[ -f "${BINARY}" ]]; then
    rm -f "${BINARY}"
    echo "  Removed ${BINARY}"
else
    echo "  ${BINARY} not found (skipping)"
fi

if [[ -f "${RUNNER}" ]]; then
    rm -f "${RUNNER}"
    echo "  Removed ${RUNNER}"
else
    echo "  ${RUNNER} not found (skipping)"
fi

if [[ -d "${CONFIG_DIR}" ]]; then
    rm -rf "${CONFIG_DIR}"
    echo "  Removed ${CONFIG_DIR}"
else
    echo "  ${CONFIG_DIR} not found (skipping)"
fi

if [[ -d "${LOG_DIR}" ]]; then
    rm -rf "${LOG_DIR}"
    echo "  Removed ${LOG_DIR}"
else
    echo "  ${LOG_DIR} not found (skipping)"
fi

# ==============================================================
#  [OK] FINAL STATUS
# ==============================================================
print_header "[OK] FINAL STATUS"
echo "  Result : SUCCESS"
echo "  Note   : Remote backup repository was NOT deleted"

print_header "[OK] SCRIPT COMPLETE"
echo ""

exit 0
