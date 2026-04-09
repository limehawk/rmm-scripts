#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Workstation Auto-Rename (macOS)                              v1.1.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./workstation_rename_auto_macos.sh
# ================================================================================
#  FILE     : workstation_rename_auto_macos.sh
#  DESCRIPTION : Auto-renames macOS device using CLIENT-USER-UUID pattern
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automatically renames a macOS device using a standardized naming pattern:
#    CLIENT3-USER-UUID. Sets HostName, ComputerName, and LocalHostName.
#    Designed for RMM deployment with automatic client/user detection.
#
#  DATA SOURCES & PRIORITY
#
#    - RMM Variable: $YourClientNameHere for client name
#    - Console User: Current logged-in user
#    - Hardware UUID: System's unique identifier
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded or from RMM variables:
#      - CLIENT_NAME: RMM variable $YourClientNameHere (3-char abbreviation used)
#
#  SETTINGS
#
#    Naming Pattern (max 15 chars for NetBIOS compatibility):
#      CLIENT3-USERUUID
#        CLIENT3 : 3-character abbreviation of client name
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
#    The script performs the following actions in order:
#    1. Gets client name from RMM variable
#    2. Retrieves current logged-in console user
#    3. Gets hardware UUID from system
#    4. Builds hostname: CLIENT3-USER-UUID (exactly 15 chars)
#    5. Sets HostName, ComputerName, and LocalHostName
#    6. Flushes DNS cache
#
#  PREREQUISITES
#
#    - Root/sudo access required
#    - macOS 10.14 or later
#    - RMM variable $YourClientNameHere must be set
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Runs with elevated privileges (sudo required)
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
#     Client Name              : Acme Corp
#     Client Segment (3-char)  : ACM
#
#    [INFO] SYSTEM VALUES
#    ==============================================================
#     Console User             : jsmith
#     User Segment             : JSMITH
#     Hardware UUID            : 12345678-90AB-CDEF-1234-567890ABCDEF
#
#    [INFO] BUILD HOSTNAME
#    ==============================================================
#     Desired Name             : ACM-JSMITH-CDEF
#     Name Length              : 15
#
#    [RUN] RENAME ACTION
#    ==============================================================
#     Status                   : RENAMING TO ACM-JSMITH-CDEF
#     Result                   : RENAME SUCCESSFUL
#
#    [INFO] RESULT
#    ==============================================================
#     Hostname set to: ACM-JSMITH-CDEF
#     HostName, ComputerName, and LocalHostName updated
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-01 v1.0.0 Initial release
# ================================================================================

set -e

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
CLIENT_NAME="$YourClientNameHere"
MAX_HOST_LEN=15
MIN_UUID_LEN=3
MAX_USER_LEN=8
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Sanitize string: uppercase, alphanumeric only
sanitize() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]'
}

# Get 3-char abbreviation
abbr3() {
    local s
    s=$(sanitize "$1")
    echo "${s:0:3}"
}

# Print section header
print_section() {
    local status="$1"
    local title="$2"
    echo ""
    echo "[$status] $title"
    echo "=============================================================="
}

# Print key-value
print_kv() {
    printf " %-24s : %s\n" "$1" "$2"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_section "INFO" "INPUT VALIDATION"

# Validate client name
if [ -z "$CLIENT_NAME" ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "CLIENT_NAME is required (set \$YourClientNameHere in RMM)"
    echo ""
    exit 1
fi

CLIENT_SEG=$(abbr3 "$CLIENT_NAME")
print_kv "Client Name" "$CLIENT_NAME"
print_kv "Client Segment (3-char)" "$CLIENT_SEG"

print_section "INFO" "SYSTEM VALUES"

# Get current user (console user, not root)
CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "")
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    CURRENT_USER=$(who | grep console | awk '{print $1}' | head -1)
fi
USER_SEG=$(sanitize "$CURRENT_USER")
USER_SEG="${USER_SEG:0:$MAX_USER_LEN}"

print_kv "Console User" "$CURRENT_USER"
print_kv "User Segment" "$USER_SEG"

# Get hardware UUID
HARDWARE_UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
if [ -z "$HARDWARE_UUID" ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Could not retrieve hardware UUID"
    echo ""
    exit 1
fi
UUID_CLEAN=$(echo "$HARDWARE_UUID" | tr -d '-' | tr '[:lower:]' '[:upper:]')

print_kv "Hardware UUID" "$HARDWARE_UUID"
print_kv "UUID (clean)" "$UUID_CLEAN"

# Get current hostname
CURRENT_HOST=$(scutil --get ComputerName 2>/dev/null || hostname -s)
print_kv "Current Hostname" "$CURRENT_HOST"

print_section "INFO" "BUILD HOSTNAME"

# Build the hostname: CLIENT3-USER-UUID (exactly 15 chars)
PREFIX="${CLIENT_SEG}-"
PREFIX_LEN=${#PREFIX}

# Calculate remaining space
REMAINING=$((MAX_HOST_LEN - PREFIX_LEN))

# User takes what it can, UUID fills the rest (min 3)
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

# Get UUID suffix
UUID_LEN=${#UUID_CLEAN}
UUID_START=$((UUID_LEN - UUID_TAKE))
UUID_SUFFIX="${UUID_CLEAN:$UUID_START:$UUID_TAKE}"

# Build final hostname
USER_PART="${USER_SEG:0:$USER_TAKE}"
DESIRED_NAME="${PREFIX}${USER_PART}${UUID_SUFFIX}"
DESIRED_NAME=$(echo "$DESIRED_NAME" | tr '[:lower:]' '[:upper:]')

print_kv "Prefix" "$PREFIX"
print_kv "User Part" "$USER_PART"
print_kv "UUID Suffix" "$UUID_SUFFIX"
print_kv "Desired Name" "$DESIRED_NAME"
print_kv "Name Length" "${#DESIRED_NAME}"

print_section "RUN" "RENAME ACTION"

# Check if already named correctly
CURRENT_UPPER=$(echo "$CURRENT_HOST" | tr '[:lower:]' '[:upper:]')
if [ "$CURRENT_UPPER" = "$DESIRED_NAME" ]; then
    print_kv "Status" "HOSTNAME ALREADY MATCHES"
    print_kv "Action" "NO RENAME NEEDED"
else
    print_kv "Status" "RENAMING TO $DESIRED_NAME"

    # Set all hostname types
    if sudo scutil --set HostName "$DESIRED_NAME" && \
       sudo scutil --set ComputerName "$DESIRED_NAME" && \
       sudo scutil --set LocalHostName "$DESIRED_NAME"; then
        print_kv "Result" "RENAME SUCCESSFUL"
    else
        echo ""
        echo "[ERROR] ERROR OCCURRED"
        echo "=============================================================="
        echo "Failed to set hostname"
        echo ""
        exit 1
    fi

    # Flush DNS cache
    print_kv "Action" "Flushing DNS cache"
    sudo killall -HUP mDNSResponder 2>/dev/null || true
fi

print_section "INFO" "RESULT"
echo " Hostname set to: $DESIRED_NAME"
echo " HostName, ComputerName, and LocalHostName updated"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
