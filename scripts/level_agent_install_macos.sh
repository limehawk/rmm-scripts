#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Level Agent Install (macOS)                                  v2.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : August 2026
#  USAGE    : sudo ./level_agent_install_macos.sh
# ================================================================================
#  FILE     : level_agent_install_macos.sh
#  DESCRIPTION : Installs the Level RMM agent on macOS and verifies enrollment
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Downloads and runs the Level macOS installer, registering the device to a
#    specific Level group. Install key and group id come from SuperOps runtime
#    variables at run time — nothing secret is stored in the public script.
#    The script verifies that the agent enrolled and connected to Level, not
#    just that files landed on disk.
#
#  DATA SOURCES & PRIORITY
#
#    1) SuperOps runtime: $YourLevelInstallKeyHere (Level UI install key)
#    2) SuperOps runtime: $YourLevelGroupIdHere (numeric group id)
#    3) Fixed install script URL: https://downloads.level.io/install_mac_os.sh
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body (SuperOps replaces placeholders):
#      - LEVEL_INSTALL_KEY : Level UI install key (NOT the REST API key)
#                            SuperOps: $YourLevelInstallKeyHere
#                            If the key already ends in :<groupId> (copied from
#                            a group-scoped Add device modal), it is used
#                            verbatim.
#      - LEVEL_GROUP_ID    : Numeric Level group id (e.g. 55896)
#                            SuperOps: $YourLevelGroupIdHere
#                            Script FAILS if empty or unreplaced
#
#  SETTINGS
#
#    - INSTALL_SCRIPT_URL   : Level official macOS install script URL
#    - SKIP_IF_HEALTHY      : Skip when Level is already enrolled and connected
#    - MAX_VERIFY_ATTEMPTS  : Verification retries after install (default 6)
#    - VERIFY_DELAY_SECONDS : Delay between retries (default 10; ~60s max wait)
#
#  BEHAVIOR
#
#    1. Validates install key and group id (hard-fail if either missing)
#    2. Runs level --check when Level is already present
#       - Skips only when the agent reports a live connection
#       - Reinstalls over a broken or unenrolled agent
#    3. Exports LEVEL_API_KEY=<key>:<groupId>
#    4. Runs: bash -c "$(curl -L https://downloads.level.io/install_mac_os.sh)"
#    5. Verifies enrollment with level --check (connection required)
#
#    GROUP ASSIGNMENT CAVEAT (verified 2026-08-02 on a Windows test VM; the
#    enrollment flow is the same agent):
#    The group id in the install key only applies at FIRST enrollment. A
#    machine with an existing agent identity re-attaches to its existing Level
#    device record and keeps its current group (or no group). To re-home such
#    a device, move it in the Level console, or wipe the agent identity first.
#    A wipe creates a new device record; the old record goes offline as a
#    duplicate.
#
#  PREREQUISITES
#
#    - macOS operating system
#    - Root/sudo privileges
#    - curl available (standard on macOS)
#    - Network access to downloads.level.io, online.level.io, agents.level.io
#    - SuperOps runtime variables set on the script trigger
#
#  SECURITY NOTES
#
#    - No secrets in the public repo — keys only via SuperOps runtime vars
#    - Install key is masked in console output (prefix only)
#    - Group id is logged in full (not secret)
#    - Console output uses [masked], not angle brackets — some RMM log viewers
#      strip angle-bracket text as HTML
#    - Use the Level UI "Add device" install key, not the REST API token
#    - Installer downloaded over HTTPS
#
#  ENDPOINTS
#
#    - https://downloads.level.io/install_mac_os.sh - Level official macOS installer
#
#  EXIT CODES
#
#    0 = Success (enrolled and connected, or already healthy)
#    1 = Failure (missing inputs, download, install, or enrollment not confirmed)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Install Key      : nRuy...***
#    Group Id         : 55896
#    Installer URL    : https://downloads.level.io/install_mac_os.sh
#    Inputs validated successfully
#
#    [RUN] PRE-CHECK
#    ==============================================================
#    Checking for existing Level installation...
#    Level not detected
#
#    [RUN] INSTALLATION
#    ==============================================================
#    Running Level macOS installer...
#    LEVEL_API_KEY=[masked]:55896
#    Installer finished with exit code 0
#
#    [RUN] VERIFICATION
#    ==============================================================
#    Attempt 1 : Running level --check
#    Level enrolled and connected
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Result : SUCCESS
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-08-02 v2.0.0 Replace the path/launchctl existence check with
#                    level --check, so a failed enrollment no longer reports
#                    SUCCESS. Skip an existing agent only when it reports a
#                    live connection; reinstall over a broken one. Accept keys
#                    that already carry :<groupId> without doubling the group.
#                    Log [masked] instead of angle brackets (RMM consoles
#                    strip angle-bracket text as HTML). Document that the
#                    group only applies at first enrollment.
#  2026-07-21 v1.0.0 Initial release - Level macOS install via SuperOps runtime
#                    vars (install key + group id). No secrets in repo. Matches
#                    official payload: LEVEL_API_KEY=key:group bash -c "$(curl ...)"
# ================================================================================

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# SuperOps replaces $Your*Here placeholders at runtime. Never put real keys here.
LEVEL_INSTALL_KEY="$YourLevelInstallKeyHere"   # Level UI install key (not REST API key)
LEVEL_GROUP_ID="$YourLevelGroupIdHere"         # Numeric group id (required)

INSTALL_SCRIPT_URL="https://downloads.level.io/install_mac_os.sh"  # Official Level macOS installer
SKIP_IF_HEALTHY="true"                                             # Skip when already enrolled and connected

MAX_VERIFY_ATTEMPTS=6     # Verification retries after install
VERIFY_DELAY_SECONDS=10   # Delay between retries (~60s max wait)

# ============================================================================
# HELPERS
# ============================================================================
find_level_binary() {
    # The Level agent CLI. Locations vary by installer version.
    local candidates=(
        "/usr/local/bin/level"
        "/opt/level/level"
        "/Library/Level/level"
        "/Applications/Level.app/Contents/MacOS/level"
    )
    local c
    for c in "${candidates[@]}"; do
        if [ -x "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    if command -v level >/dev/null 2>&1; then
        command -v level
        return 0
    fi
    return 1
}

level_check_connected() {
    # Returns 0 when level --check reports a live connection.
    # Enrollment is proven by a live connection, not by files on disk.
    local exe out
    exe=$(find_level_binary) || return 1
    out=$("$exe" --check 2>&1)
    # [[:space:]] not \s — macOS BSD grep does not support \s in ERE.
    if echo "$out" | grep -qiE '^[[:space:]]*realtime client[[:space:]]+Connected[[:space:]]*$'; then
        return 0
    fi
    if echo "$out" | grep -qiE '^[[:space:]]*(online|agents)\.level\.io[[:space:]]+OK[[:space:]]*$'; then
        return 0
    fi
    return 1
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================
ERROR_OCCURRED=false
ERROR_TEXT=""

if [ -z "$LEVEL_INSTALL_KEY" ] || [ "$LEVEL_INSTALL_KEY" = '$''YourLevelInstallKeyHere' ]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}
- SuperOps runtime variable \$YourLevelInstallKeyHere was not replaced. Set it to the Level UI install key from Add device (not the REST API key)."
fi

if [ -z "$LEVEL_GROUP_ID" ] || [ "$LEVEL_GROUP_ID" = '$''YourLevelGroupIdHere' ]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}
- SuperOps runtime variable \$YourLevelGroupIdHere was not replaced. Set it to the numeric Level group id (e.g. 55896). Group id is required."
fi

if [ "$ERROR_OCCURRED" = false ]; then
    if ! [[ "$LEVEL_GROUP_ID" =~ ^[0-9]+$ ]]; then
        ERROR_OCCURRED=true
        ERROR_TEXT="${ERROR_TEXT}
- Level group id must be numeric digits only (got: ${LEVEL_GROUP_ID})."
    fi
fi

# A key copied from a group-scoped Add device modal already ends in :<groupId>.
# Use it verbatim in that case so the group is not doubled.
FULL_INSTALL_KEY=""
if [ "$ERROR_OCCURRED" = false ]; then
    if [[ "$LEVEL_INSTALL_KEY" =~ :([0-9]+)$ ]]; then
        EMBEDDED_GROUP="${BASH_REMATCH[1]}"
        if [ "$EMBEDDED_GROUP" != "$LEVEL_GROUP_ID" ]; then
            ERROR_OCCURRED=true
            ERROR_TEXT="${ERROR_TEXT}
- Install key already carries group ${EMBEDDED_GROUP}, but group id input is ${LEVEL_GROUP_ID}. Fix one of the two inputs."
        else
            FULL_INSTALL_KEY="$LEVEL_INSTALL_KEY"
        fi
    else
        FULL_INSTALL_KEY="${LEVEL_INSTALL_KEY}:${LEVEL_GROUP_ID}"
    fi
fi

if [ "$ERROR_OCCURRED" = true ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo -e "$ERROR_TEXT"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED - input validation"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="
if [ "${#LEVEL_INSTALL_KEY}" -gt 4 ]; then
    MASKED_KEY="${LEVEL_INSTALL_KEY:0:4}...***"
else
    MASKED_KEY="***"
fi
echo "Install Key      : $MASKED_KEY"
echo "Group Id         : $LEVEL_GROUP_ID"
echo "Installer URL    : $INSTALL_SCRIPT_URL"
echo "Inputs validated successfully"

# ============================================================================
# PRE-CHECK
# ============================================================================
echo ""
echo "[RUN] PRE-CHECK"
echo "=============================================================="
echo "Checking for existing Level installation..."

if EXISTING_BIN=$(find_level_binary); then
    echo "Level present: $EXISTING_BIN"
    if level_check_connected; then
        if [ "$SKIP_IF_HEALTHY" = "true" ]; then
            echo ""
            echo "[OK] FINAL STATUS"
            echo "=============================================================="
            echo "Result : SUCCESS (already enrolled and connected)"
            echo "Note   : an existing agent keeps its current Level group."
            echo ""
            echo "[OK] SCRIPT COMPLETED"
            echo "=============================================================="
            exit 0
        fi
        echo "Level connected, reinstalling anyway..."
    else
        echo "Agent is present but not connected. Reinstalling..."
        echo "Note: a reinstall keeps the existing agent identity and group."
    fi
else
    echo "Level not detected"
fi

# ============================================================================
# INSTALLATION
# ============================================================================
echo ""
echo "[RUN] INSTALLATION"
echo "=============================================================="
echo "Running Level macOS installer..."
echo "LEVEL_API_KEY=[masked]:${LEVEL_GROUP_ID}"

# Official Level shape (group applies at first enrollment only):
#   LEVEL_API_KEY=<key>:<group> bash -c "$(curl -L https://downloads.level.io/install_mac_os.sh)"
export LEVEL_API_KEY="$FULL_INSTALL_KEY"

# Download first so a curl failure is reported as a download failure —
# bash -c "" on an empty substitution would exit 0 and mask it.
INSTALLER_BODY=$(curl -fsSL "$INSTALL_SCRIPT_URL")
CURL_EXIT=$?
if [ "$CURL_EXIT" -ne 0 ] || [ -z "$INSTALLER_BODY" ]; then
    echo ""
    echo "[ERROR] DOWNLOAD FAILED"
    echo "=============================================================="
    echo "curl exited with code $CURL_EXIT fetching the installer"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED - could not download the Level installer"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

bash -c "$INSTALLER_BODY"
INSTALL_EXIT=$?

echo "Installer finished with exit code $INSTALL_EXIT"

if [ "$INSTALL_EXIT" -ne 0 ]; then
    echo ""
    echo "[ERROR] INSTALLATION FAILED"
    echo "=============================================================="
    echo "Level installer exited with code $INSTALL_EXIT"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED - the Level installer did not complete"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

# ============================================================================
# VERIFICATION
# ============================================================================
echo ""
echo "[RUN] VERIFICATION"
echo "=============================================================="

VERIFIED=false
ATTEMPT=0

while [ "$VERIFIED" = false ] && [ "$ATTEMPT" -lt "$MAX_VERIFY_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    sleep "$VERIFY_DELAY_SECONDS"
    echo "Attempt $ATTEMPT : Running level --check"
    if level_check_connected; then
        echo "Level enrolled and connected"
        VERIFIED=true
    fi
done

if [ "$VERIFIED" = false ]; then
    if EXE=$(find_level_binary); then
        "$EXE" --check 2>&1 || true
    else
        echo "Level binary not found after install"
    fi
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED - the agent installed but did not enroll"
    echo ""
    echo "[ERROR] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 1
fi

# ============================================================================
# FINAL STATUS
# ============================================================================
echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Result : SUCCESS"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
