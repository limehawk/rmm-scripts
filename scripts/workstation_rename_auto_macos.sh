#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Workstation Auto-Rename (macOS)                              v2.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : July 2026
#  USAGE    : sudo ./workstation_rename_auto_macos.sh
# ================================================================================
#  FILE     : workstation_rename_auto_macos.sh
#  DESCRIPTION : Auto-renames macOS device using CLIENT3-USERUUID (Level)
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automatically renames a macOS device using CLIENT3-USERUUID (exactly 15
#    chars for NetBIOS compatibility). Sets HostName, ComputerName, and
#    LocalHostName. Client segment from Level group name. No external RMM API.
#
#  DATA SOURCES & PRIORITY
#
#    - Level system variable: {{level_group_name}}
#    - Console User: Current logged-in user
#    - Hardware UUID: System's unique identifier
#
#  REQUIRED INPUTS
#
#    - CLIENT_NAME: Level {{level_group_name}} (3-char abbreviation used)
#
#  SETTINGS
#
#    Naming Pattern (max 15 chars for NetBIOS compatibility):
#      CLIENT3-USERUUID
#        CLIENT3 : 3-character abbreviation of Level group name
#        USER    : Sanitized username (maximized, truncated if needed)
#        UUID    : Hardware UUID tail (at least 3 chars)
#
#    Configuration:
#      - MAX_HOST_LEN: 15 (NetBIOS limit)
#      - MIN_UUID_LEN: 3 (minimum UUID suffix)
#      - MAX_USER_LEN: 8 (maximum user segment)
#
#  BEHAVIOR
#
#    1. Gets client name from Level group system variable
#    2. Retrieves current logged-in console user
#    3. Gets hardware UUID from system
#    4. Builds hostname: CLIENT3-USERUUID (exactly 15 chars)
#    5. Sets HostName, ComputerName, and LocalHostName
#    6. Flushes DNS cache
#    7. Emits Level output slots DesiredHostname / RenameStatus
#
#  PREREQUISITES
#
#    - Root/sudo access (Level runAs: SYSTEM)
#    - macOS 10.14 or later
#    - Level agent; device in a named client group
#    - Must run via Level so {{level_group_name}} is interpolated
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Runs with elevated privileges
#    - Only alphanumeric characters and hyphens in hostname
#
#  ENDPOINTS
#
#    Not applicable - local system configuration only
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure (missing inputs, rename failed)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#     Client Name              : Bell Companies
#     Client Segment (3-char)  : BEL
#
#    [INFO] SYSTEM VALUES
#    ==============================================================
#     Console User             : jsmith
#     User Segment             : JSMITH
#     Hardware UUID            : 12345678-90AB-CDEF-1234-567890ABCDEF
#
#    [INFO] BUILD HOSTNAME
#    ==============================================================
#     Desired Name             : BEL-JSMITHCDEF1
#     Name Length              : 15
#
#    [RUN] RENAME ACTION
#    ==============================================================
#     Status                   : RENAMING TO BEL-JSMITHCDEF1
#     Result                   : RENAME SUCCESSFUL
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-07-22 v2.0.0 Ported to Level.io: client from {{level_group_name}};
#                    drop SuperOps placeholders; emit Level output slots
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-01 v1.0.0 Initial release
# ================================================================================

set -e

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Level interpolates {{level_*}} before the script runs.
CLIENT_NAME="{{level_group_name}}"
LEVEL_DEVICE_HOSTNAME="{{level_device_hostname}}"
MAX_HOST_LEN=15
MIN_UUID_LEN=3
MAX_USER_LEN=8
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

sanitize() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]'
}

abbr3() {
    local s
    s=$(sanitize "$1")
    echo "${s:0:3}"
}

print_section() {
    local status="$1"
    local title="$2"
    echo ""
    echo "[$status] $title"
    echo "=============================================================="
}

print_kv() {
    printf " %-24s : %s\n" "$1" "$2"
}

emit_level_slot() {
    # {{name=value}} — Level output slot (built without static braces in source)
    local name="$1"
    local value="$2"
    printf '\x7b\x7b%s=%s\x7d\x7d\n' "$name" "$value"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_section "INFO" "INPUT VALIDATION"

if [ -z "$CLIENT_NAME" ] || [[ "$CLIENT_NAME" == *"{{"* ]]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "LEVEL DID NOT INTERPOLATE level_group_name — RUN VIA LEVEL"
    echo "AND ASSIGN THE DEVICE TO A CLIENT GROUP"
    echo ""
    emit_level_slot "RenameStatus" "error"
    exit 1
fi

CLIENT_SEG=$(abbr3 "$CLIENT_NAME")
print_kv "Client Name" "$CLIENT_NAME"
print_kv "Client Segment (3-char)" "$CLIENT_SEG"
print_kv "Device Hostname (level)" "$LEVEL_DEVICE_HOSTNAME"

print_section "INFO" "SYSTEM VALUES"

CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "")
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    CURRENT_USER=$(who | grep console | awk '{print $1}' | head -1)
fi
USER_SEG=$(sanitize "$CURRENT_USER")
USER_SEG="${USER_SEG:0:$MAX_USER_LEN}"

print_kv "Console User" "$CURRENT_USER"
print_kv "User Segment" "$USER_SEG"

HARDWARE_UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
if [ -z "$HARDWARE_UUID" ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Could not retrieve hardware UUID"
    echo ""
    emit_level_slot "RenameStatus" "error"
    exit 1
fi
UUID_CLEAN=$(echo "$HARDWARE_UUID" | tr -d '-' | tr '[:lower:]' '[:upper:]')

print_kv "Hardware UUID" "$HARDWARE_UUID"
print_kv "UUID (clean)" "$UUID_CLEAN"

CURRENT_HOST=$(scutil --get ComputerName 2>/dev/null || hostname -s)
print_kv "Current Hostname" "$CURRENT_HOST"

print_section "INFO" "BUILD HOSTNAME"

PREFIX="${CLIENT_SEG}-"
PREFIX_LEN=${#PREFIX}
REMAINING=$((MAX_HOST_LEN - PREFIX_LEN))
MAX_USER_TAKE=$((REMAINING - MIN_UUID_LEN))
if [ $MAX_USER_TAKE -lt 0 ]; then
    MAX_USER_TAKE=0
fi

USER_TAKE=${#USER_SEG}
if [ $USER_TAKE -gt $MAX_USER_TAKE ]; then
    USER_TAKE=$MAX_USER_TAKE
fi

UUID_TAKE=$((MAX_HOST_LEN - PREFIX_LEN - USER_TAKE))
if [ $UUID_TAKE -lt $MIN_UUID_LEN ]; then
    UUID_TAKE=$MIN_UUID_LEN
fi

UUID_LEN=${#UUID_CLEAN}
UUID_START=$((UUID_LEN - UUID_TAKE))
UUID_SUFFIX="${UUID_CLEAN:$UUID_START:$UUID_TAKE}"

USER_PART="${USER_SEG:0:$USER_TAKE}"
DESIRED_NAME="${PREFIX}${USER_PART}${UUID_SUFFIX}"
DESIRED_NAME=$(echo "$DESIRED_NAME" | tr '[:lower:]' '[:upper:]')

print_kv "Prefix" "$PREFIX"
print_kv "User Part" "$USER_PART"
print_kv "UUID Suffix" "$UUID_SUFFIX"
print_kv "Desired Name" "$DESIRED_NAME"
print_kv "Name Length" "${#DESIRED_NAME}"

print_section "RUN" "RENAME ACTION"

RENAME_STATUS="already_matches"
CURRENT_UPPER=$(echo "$CURRENT_HOST" | tr '[:lower:]' '[:upper:]')
if [ "$CURRENT_UPPER" = "$DESIRED_NAME" ]; then
    print_kv "Status" "HOSTNAME ALREADY MATCHES"
    print_kv "Action" "NO RENAME NEEDED"
else
    print_kv "Status" "RENAMING TO $DESIRED_NAME"

    if sudo scutil --set HostName "$DESIRED_NAME" && \
       sudo scutil --set ComputerName "$DESIRED_NAME" && \
       sudo scutil --set LocalHostName "$DESIRED_NAME"; then
        print_kv "Result" "RENAME SUCCESSFUL"
        RENAME_STATUS="applied"
    else
        echo ""
        echo "[ERROR] ERROR OCCURRED"
        echo "=============================================================="
        echo "Failed to set hostname"
        echo ""
        emit_level_slot "RenameStatus" "error"
        exit 1
    fi

    print_kv "Action" "Flushing DNS cache"
    sudo killall -HUP mDNSResponder 2>/dev/null || true
fi

emit_level_slot "DesiredHostname" "$DESIRED_NAME"
emit_level_slot "RenameStatus" "$RENAME_STATUS"

print_section "INFO" "RESULT"
echo " Hostname set to: $DESIRED_NAME"
echo " HostName, ComputerName, and LocalHostName updated"
echo " Level follows OS hostname (no RMM asset API)"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
