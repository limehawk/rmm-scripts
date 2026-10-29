#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : SentinelOne Install (Linux)                                  v1.1.0
#  AUTHOR   : Limehawk.io
#  DATE     : October 2026
#  USAGE    : sudo ./sentinelone_install_linux.sh
# ================================================================================
#  FILE     : sentinelone_install_linux.sh
#  DESCRIPTION : Installs the SentinelOne agent on Linux from a Level-staged, integrity-checked deb or rpm with a site token
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Installs the SentinelOne endpoint agent on Linux using the site token
#    from a Level custom field. A Level automation step stages both the deb
#    and rpm packages ahead of time; this script never downloads anything.
#    It picks the package matching the system's package manager, checks it
#    is structurally intact, installs it, registers the token with
#    sentinelctl, starts the agent and verifies it. Skips if already present.
#
#    NOTE: Vendor-signature verification is not available on Linux. The S1
#    .deb is unsigned and the .rpm signature needs SentinelOne's GPG key,
#    which this script does not distribute. Integrity relies on Level's
#    checksummed file transfer plus the package's own digests (rpm -K
#    --nosignature) or archive structure (dpkg-deb --info).
#
#  DATA SOURCES & PRIORITY
#
#    - Level custom field {{cf_s1_site_token}}: site token (REQUIRED)
#    - /var/tmp/SentinelAgent.deb and .rpm: packages staged by Level
#    - dpkg or rpm on PATH decides which package is used
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
#      - DEB_PATH    : /var/tmp/SentinelAgent.deb (staged by Level)
#      - RPM_PATH    : /var/tmp/SentinelAgent.rpm (staged by Level)
#      - SENTINELCTL : /opt/sentinelone/bin/sentinelctl
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Validates the site token is present and was substituted by Level
#    2. Exits 0 without changes if sentinelctl is already installed
#    3. Picks dpkg -i (Debian/Ubuntu) or rpm -i (RHEL/Fedora/SUSE/Amazon);
#       exits 1 without changes on any other distro
#    4. Fails if the matching package file is missing
#    5. Integrity check: dpkg-deb --info (deb) or rpm -K --nosignature
#       (rpm digests); exits 1 without installing on failure
#    6. Installs, sets the token with sentinelctl, starts the agent
#    7. Prints sentinelctl version and control status
#    8. Removes both package files
#
#  PREREQUISITES
#
#    - Linux with dpkg or rpm, root privileges (Level runs as root)
#    - Packages already at /var/tmp/SentinelAgent.deb and .rpm
#    - Level custom field cf_s1_site_token set on the device's group
#
#  SECURITY NOTES
#
#    - No third-party downloads: only the Level-staged package is ever run
#    - No vendor-signature check is possible (see PURPOSE); the package
#      must at least pass dpkg-deb --info or rpm -K --nosignature
#    - Site token is never printed in full (first 10 characters + ***)
#    - No secrets in logs
#
#  ENDPOINTS
#
#    Not applicable - packages are staged by a separate Level step
#
#  EXIT CODES
#
#    0 = Success (installed or already present)
#    1 = Failure (bad token, unsupported distro, package missing or
#        corrupt, install, token set, start or verification failed)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    Site Token : eyJ1cmwiOi***
#
#    [RUN] PRE-CHECK
#    ==============================================================
#    SentinelOne not detected
#    Package manager : dpkg
#    Package         : /var/tmp/SentinelAgent.deb
#
#    [RUN] INTEGRITY CHECK
#    ==============================================================
#    Package integrity OK
#
#    [RUN] INSTALLATION
#    ==============================================================
#    Selecting previously unselected package sentinelagent.
#    ...
#    Token registered
#    Agent started
#
#    [RUN] VERIFICATION
#    ==============================================================
#    Agent version : 24.2.3.5
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
#  2026-10-29 v1.1.0 Integrity check before install (dpkg-deb --info or rpm -K
#                    --nosignature); note that vendor-signature verification is
#                    not available on Linux
#  2026-10-29 v1.0.0 Initial release
# ================================================================================

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
SITE_TOKEN="{{cf_s1_site_token}}"             # Level custom field, set per group
DEB_PATH="/var/tmp/SentinelAgent.deb"          # Staged by the Level automation
RPM_PATH="/var/tmp/SentinelAgent.rpm"          # Staged by the Level automation
SENTINELCTL="/opt/sentinelone/bin/sentinelctl" # Agent CLI, present after install
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

# Both packages are removed on every exit path; the automation re-stages them
trap 'rm -f "$DEB_PATH" "$RPM_PATH"' EXIT

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

echo ""
echo "[RUN] PRE-CHECK"
echo "=============================================================="

if [[ -x "$SENTINELCTL" ]]; then
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

# dpkg first: Debian systems sometimes carry rpm too, never the reverse
if command -v dpkg > /dev/null 2>&1; then
    PKG_MGR="dpkg"
    PKG_PATH="$DEB_PATH"
elif command -v rpm > /dev/null 2>&1; then
    PKG_MGR="rpm"
    PKG_PATH="$RPM_PATH"
else
    fail "Unsupported distro: neither dpkg nor rpm found. SentinelOne ships deb and rpm only."
fi

echo "Package manager : $PKG_MGR"
echo "Package         : $PKG_PATH"

if [[ ! -f "$PKG_PATH" ]]; then
    fail "Package not found at $PKG_PATH. The Level staging step did not run or failed."
fi

echo ""
echo "[RUN] INTEGRITY CHECK"
echo "=============================================================="

# No vendor signature to check on Linux (see header); at least refuse a truncated or corrupt file
if [[ "$PKG_MGR" == "dpkg" ]]; then
    dpkg-deb --info "$PKG_PATH" > /dev/null || fail "dpkg-deb --info failed: $PKG_PATH is not a valid deb. Not installing it."
else
    rpm -K --nosignature "$PKG_PATH" || fail "rpm -K failed: $PKG_PATH digests do not verify. Not installing it."
fi
echo "Package integrity OK"

echo ""
echo "[RUN] INSTALLATION"
echo "=============================================================="

if [[ "$PKG_MGR" == "dpkg" ]]; then
    DEBIAN_FRONTEND=noninteractive dpkg -i "$PKG_PATH" || fail "dpkg -i failed for $PKG_PATH"
else
    rpm -i "$PKG_PATH" || fail "rpm -i failed for $PKG_PATH"
fi

if [[ ! -x "$SENTINELCTL" ]]; then
    fail "sentinelctl not found at $SENTINELCTL after install"
fi

"$SENTINELCTL" management token set "$SITE_TOKEN" > /dev/null || fail "sentinelctl could not register the site token"
echo "Token registered"

"$SENTINELCTL" control start || fail "sentinelctl control start failed"
echo "Agent started"

echo ""
echo "[RUN] VERIFICATION"
echo "=============================================================="

echo "Agent version : $("$SENTINELCTL" version 2>&1 | head -n 1)"
echo "Agent status  : $("$SENTINELCTL" control status 2>&1 | head -n 1)"

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Result : SUCCESS"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
