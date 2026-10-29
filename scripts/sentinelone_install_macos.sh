#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : SentinelOne Install (macOS)                                  v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : October 2026
#  USAGE    : sudo ./sentinelone_install_macos.sh
# ================================================================================
#  FILE     : sentinelone_install_macos.sh
#  DESCRIPTION : Installs the SentinelOne agent on macOS from a pre-downloaded pkg with a site token
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Installs the SentinelOne endpoint agent on macOS using the site token
#    from a Level custom field. The installer pkg is downloaded ahead of time
#    by a Level automation step; this script registers the token the way
#    SentinelOne documents (a token file beside the pkg), runs the installer,
#    and verifies the agent answers. Skips if the agent is already present.
#
#  DATA SOURCES & PRIORITY
#
#    - Level custom field {{cf_s1_site_token}}: site token (REQUIRED)
#    - /var/tmp/SentinelAgent.pkg: installer placed by the Level automation
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - SITE_TOKEN: SentinelOne site token, injected at runtime from the
#                    Level custom field cf_s1_site_token
#
#  SETTINGS
#
#    Configuration details and default values:
#      - PKG_PATH     : /var/tmp/SentinelAgent.pkg (pre-downloaded by Level)
#      - TOKEN_FILE   : /var/tmp/com.sentinelone.registration-token
#      - SENTINELCTL  : /usr/local/bin/sentinelctl
#      - AGENT_BUNDLE : /Library/Sentinel/sentinel-agent.bundle
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Validates the site token is present and was substituted by Level
#    2. Exits 0 without changes if the agent is already installed
#    3. Fails if the pre-downloaded pkg is missing
#    4. Writes the token file next to the pkg and runs installer -target /
#    5. Verifies with sentinelctl version and status
#    6. Removes the token file (always) and the pkg
#
#  PREREQUISITES
#
#    - macOS with root privileges (Level runs as root)
#    - Installer pkg already at /var/tmp/SentinelAgent.pkg
#    - Level custom field cf_s1_site_token set on the device's group
#
#  SECURITY NOTES
#
#    - Site token is never printed in full (first 10 characters + ***)
#    - Token file is mode 600 and deleted on every exit path
#    - No secrets in logs
#
#  ENDPOINTS
#
#    Not applicable - the pkg is downloaded by a separate Level step
#
#  EXIT CODES
#
#    0 = Success (installed or already present)
#    1 = Failure (bad token, pkg missing, installer or verification failed)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Site Token : eyJ1cmwiOi***
#    Installer  : /var/tmp/SentinelAgent.pkg
#
#    [RUN] PRE-CHECK
#    ==============================================================
#    SentinelOne not detected
#
#    [RUN] INSTALLATION
#    ==============================================================
#    Token file written
#    installer: The install was successful.
#
#    [RUN] VERIFICATION
#    ==============================================================
#    Agent version : 24.3.2.7753
#    Agent status  : running
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
#  2026-10-29 v1.0.0 Initial release
# ================================================================================

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
SITE_TOKEN="{{cf_s1_site_token}}"                           # Level custom field, set per group
PKG_PATH="/var/tmp/SentinelAgent.pkg"                        # Pre-downloaded by the Level automation
TOKEN_FILE="/var/tmp/com.sentinelone.registration-token"    # SentinelOne reads this beside the pkg
SENTINELCTL="/usr/local/bin/sentinelctl"                     # Agent CLI, present after install
AGENT_BUNDLE="/Library/Sentinel/sentinel-agent.bundle"       # Agent bundle, present after install
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print an error section and exit 1
fail() {
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "$1"
    echo ""
    echo "[ERROR] FINAL STATUS"
    echo "=============================================================="
    echo "Result : FAILED"
    exit 1
}

# The token file must never outlive the script, success or failure
trap 'rm -f "$TOKEN_FILE"' EXIT

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="

if [[ -z "$SITE_TOKEN" ]]; then
    fail "SITE_TOKEN is empty. Set the cf_s1_site_token custom field in Level."
elif [[ "$SITE_TOKEN" =~ ^\{\{.*\}\}$ ]]; then
    fail "SITE_TOKEN placeholder was not substituted. Set cf_s1_site_token in Level."
fi

echo "Site Token : ${SITE_TOKEN:0:10}***"
echo "Installer  : $PKG_PATH"

echo ""
echo "[RUN] PRE-CHECK"
echo "=============================================================="

if [[ -d "$AGENT_BUNDLE" || -x "$SENTINELCTL" ]]; then
    echo "SentinelOne already installed"
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Result : SUCCESS (already installed)"
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
fi
echo "SentinelOne not detected"

echo ""
echo "[RUN] INSTALLATION"
echo "=============================================================="

if [[ ! -f "$PKG_PATH" ]]; then
    fail "Installer not found at $PKG_PATH. The Level download step did not run or failed."
fi

# SentinelOne's documented macOS method: token file beside the pkg, then installer
(umask 077; echo "$SITE_TOKEN" > "$TOKEN_FILE") || fail "Could not write token file $TOKEN_FILE"
echo "Token file written"

if ! installer -pkg "$PKG_PATH" -target /; then
    fail "installer returned an error for $PKG_PATH"
fi

echo ""
echo "[RUN] VERIFICATION"
echo "=============================================================="

# The agent takes a few seconds to come up after the pkg finishes
for _ in 1 2 3 4 5; do
    [[ -x "$SENTINELCTL" ]] && break
    sleep 3
done

if [[ ! -x "$SENTINELCTL" ]]; then
    fail "sentinelctl not found at $SENTINELCTL after install"
fi

echo "Agent version : $("$SENTINELCTL" version 2>&1 | head -n 1)"
echo "Agent status  : $("$SENTINELCTL" status 2>&1 | head -n 1)"

rm -f "$PKG_PATH"

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Result : SUCCESS"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
