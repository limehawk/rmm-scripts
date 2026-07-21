#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Level Agent Install (macOS)                                  v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : July 2026
#  USAGE    : sudo ./level_agent_install_macos.sh
# ================================================================================
#  FILE     : level_agent_install_macos.sh
#  DESCRIPTION : Installs Level RMM agent on macOS with install key and group id
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Downloads and runs the Level macOS installer, registering the device to a
#    specific Level group. Install key and group id come from SuperOps runtime
#    variables at run time — nothing secret is stored in the public script.
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
#      - LEVEL_GROUP_ID    : Numeric Level group id (e.g. 55896)
#                            SuperOps: $YourLevelGroupIdHere
#                            Script FAILS if empty or unreplaced
#
#  SETTINGS
#
#    - INSTALL_SCRIPT_URL : Level official macOS install script URL
#    - SKIP_IF_INSTALLED  : Skip when Level is already present (default true)
#
#  BEHAVIOR
#
#    1. Validates install key and group id (hard-fail if either missing)
#    2. Optionally skips if Level is already installed
#    3. Exports LEVEL_API_KEY=<key>:<groupId>
#    4. Runs: bash -c "$(curl -L https://downloads.level.io/install_mac_os.sh)"
#    5. Verifies Level is present on disk
#
#  PREREQUISITES
#
#    - macOS operating system
#    - Root/sudo privileges
#    - curl available (standard on macOS)
#    - Network access to downloads.level.io
#    - SuperOps runtime variables set on the script trigger
#
#  SECURITY NOTES
#
#    - No secrets in the public repo — keys only via SuperOps runtime vars
#    - Install key is masked in console output (prefix only)
#    - Group id is logged in full (not secret)
#    - Use the Level UI "Add device" install key, not the REST API token
#    - Installer downloaded over HTTPS
#
#  ENDPOINTS
#
#    - https://downloads.level.io/install_mac_os.sh - Level official macOS installer
#
#  EXIT CODES
#
#    0 = Success (installed or already present)
#    1 = Failure (missing inputs, download, install, or verify)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Install Key      : nRuy...***
#    Group Id         : 55896
#    Inputs validated successfully
#
#    [RUN] PRE-CHECK
#    ==============================================================
#    Level not detected
#
#    [RUN] INSTALLATION
#    ==============================================================
#    Running Level macOS installer...
#    Installer finished with exit code 0
#
#    [RUN] VERIFICATION
#    ==============================================================
#    Level detected
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
#  2026-07-21 v1.0.0 Initial release - Level macOS install via SuperOps runtime
#                    vars (install key + group id). No secrets in repo. Matches
#                    official payload: LEVEL_API_KEY=key:group bash -c "$(curl ...)"
# ================================================================================

# ============================================================================
# HARDCODED INPUTS (MANDATORY)
# ============================================================================
# SuperOps replaces $Your*Here placeholders at runtime. Never put real keys here.
LEVEL_INSTALL_KEY="$YourLevelInstallKeyHere"   # Level UI install key (not REST API key)
LEVEL_GROUP_ID="$YourLevelGroupIdHere"         # Numeric group id (required)

INSTALL_SCRIPT_URL="https://downloads.level.io/install_mac_os.sh"
SKIP_IF_INSTALLED="true"

# ============================================================================
# HELPERS
# ============================================================================
level_is_installed() {
    # Common Level macOS install locations
    if [ -d "/Applications/Level.app" ]; then
        echo "/Applications/Level.app"
        return 0
    fi
    if [ -d "/usr/local/level" ]; then
        echo "/usr/local/level"
        return 0
    fi
    if [ -d "/Library/Level" ]; then
        echo "/Library/Level"
        return 0
    fi
    if launchctl list 2>/dev/null | grep -qi 'level'; then
        echo "launchctl:level"
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

if [ "$ERROR_OCCURRED" = true ]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo -e "$ERROR_TEXT"
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

EXISTING_PATH=""
if EXISTING_PATH=$(level_is_installed); then
    if [ "$SKIP_IF_INSTALLED" = "true" ]; then
        echo "Level already present: $EXISTING_PATH"
        echo ""
        echo "[OK] FINAL STATUS"
        echo "=============================================================="
        echo "Result : SUCCESS (already installed)"
        echo ""
        echo "[OK] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 0
    else
        echo "Level detected, reinstalling..."
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
echo "LEVEL_API_KEY=<masked>:${LEVEL_GROUP_ID}"

# Official Level shape:
#   LEVEL_API_KEY=<key>:<group> bash -c "$(curl -L https://downloads.level.io/install_mac_os.sh)"
export LEVEL_API_KEY="${LEVEL_INSTALL_KEY}:${LEVEL_GROUP_ID}"

set +e
bash -c "$(curl -fsSL "$INSTALL_SCRIPT_URL")"
INSTALL_EXIT=$?
set -e

echo "Installer finished with exit code $INSTALL_EXIT"

if [ "$INSTALL_EXIT" -ne 0 ]; then
    echo ""
    echo "[ERROR] INSTALLATION FAILED"
    echo "=============================================================="
    echo "Level installer exited with code $INSTALL_EXIT"
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
MAX_ATTEMPTS=5

while [ "$VERIFIED" = false ] && [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    sleep 3
    echo "Attempt $ATTEMPT : Checking..."
    if DETECTED=$(level_is_installed); then
        echo "Level detected: $DETECTED"
        VERIFIED=true
    fi
done

if [ "$VERIFIED" = false ]; then
    echo "Level not detected after $MAX_ATTEMPTS attempts"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED - Installation could not be verified"
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
