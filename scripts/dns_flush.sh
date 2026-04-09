#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Flush DNS (macOS)                                          v2.0.1
#  AUTHOR   : Limehawk.io
#  DATE     : January 2026
#  USAGE    : sudo ./dns_flush.sh
# ================================================================================
#  FILE     : dns_flush.sh
#  DESCRIPTION : Flushes DNS cache on macOS across all supported versions
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Flushes the DNS cache on macOS to resolve DNS-related connectivity issues.
#    Automatically detects macOS version and uses the appropriate flush method.
#
#  DATA SOURCES & PRIORITY
#
#    1. System version (sw_vers -productVersion)
#
#  REQUIRED INPUTS
#
#    None - script auto-detects macOS version.
#
#  SETTINGS
#
#    - Auto-detection of macOS version
#    - Version-specific flush commands
#
#  BEHAVIOR
#
#    1. Detects macOS version
#    2. Selects appropriate DNS flush method
#    3. Executes flush command
#    4. Reports success or failure
#
#  PREREQUISITES
#
#    - macOS 10.6 or later
#    - Root/sudo privileges
#
#  SECURITY NOTES
#
#    - No secrets exposed in output
#    - Requires elevated privileges
#    - Safe operation - only clears DNS cache
#
#  ENDPOINTS
#
#    Not applicable - this script does not connect to any network endpoints
#
#  EXIT CODES
#
#    0 = Success - DNS cache flushed
#    1 = Failure - flush command failed
#
#  EXAMPLE RUN
#
#    [INFO] SYSTEM INFO
#    ==============================================================
#    macOS Version : 14.2.1
#    Flush Method  : mDNSResponder (10.10.4+)
#
#    [RUN] DNS FLUSH
#    ==============================================================
#    Flushing DNS cache...
#    [OK] DNS cache flushed successfully
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Result : SUCCESS
#    DNS Flushed
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
# FUNCTIONS
# ============================================================================

# macOS 10.10.4+ (Yosemite and later)
flush_dns_new() {
    sudo killall -HUP mDNSResponder
}

# macOS 10.10 - 10.10.3
flush_dns_old() {
    sudo discoveryutil mdnsflushcache
    sudo discoveryutil udnsflushcaches
}

# macOS 10.7 - 10.9 (Lion through Mavericks)
flush_dns_lion() {
    sudo killall -HUP mDNSResponder
}

# macOS 10.6 (Snow Leopard)
flush_dns_snow_leopard() {
    sudo dscacheutil -flushcache
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "[INFO] SYSTEM INFO"
echo "=============================================================="

# Get macOS version
OS_VERSION=$(sw_vers -productVersion)
echo "macOS Version : $OS_VERSION"

# Determine flush method based on version
FLUSH_METHOD=""
FLUSH_RESULT=0

if [[ "$OS_VERSION" == 10.6.* ]]; then
    FLUSH_METHOD="dscacheutil (10.6)"
elif [[ "$OS_VERSION" == 10.7.* || "$OS_VERSION" == 10.8.* || "$OS_VERSION" == 10.9.* ]]; then
    FLUSH_METHOD="mDNSResponder (10.7-10.9)"
elif [[ "$OS_VERSION" == 10.10.* ]]; then
    # Check for 10.10.0-10.10.3 vs 10.10.4+
    MINOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f3)
    if [[ -z "$MINOR_VERSION" || "$MINOR_VERSION" -lt 4 ]]; then
        FLUSH_METHOD="discoveryutil (10.10.0-10.10.3)"
    else
        FLUSH_METHOD="mDNSResponder (10.10.4+)"
    fi
else
    FLUSH_METHOD="mDNSResponder (10.10.4+)"
fi

echo "Flush Method  : $FLUSH_METHOD"

echo ""
echo "[RUN] DNS FLUSH"
echo "=============================================================="
echo "Flushing DNS cache..."

# Execute appropriate flush
if [[ "$OS_VERSION" == 10.6.* ]]; then
    flush_dns_snow_leopard
    FLUSH_RESULT=$?
elif [[ "$OS_VERSION" == 10.7.* || "$OS_VERSION" == 10.8.* || "$OS_VERSION" == 10.9.* ]]; then
    flush_dns_lion
    FLUSH_RESULT=$?
elif [[ "$OS_VERSION" == 10.10.* ]]; then
    MINOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f3)
    if [[ -z "$MINOR_VERSION" || "$MINOR_VERSION" -lt 4 ]]; then
        flush_dns_old
        FLUSH_RESULT=$?
    else
        flush_dns_new
        FLUSH_RESULT=$?
    fi
else
    flush_dns_new
    FLUSH_RESULT=$?
fi

# Check result
if [[ $FLUSH_RESULT -eq 0 ]]; then
    echo "[OK] DNS cache flushed successfully"
else
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Error: Unable to flush DNS cache"
    echo "Exit code: $FLUSH_RESULT"
    echo ""
    exit 1
fi

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Result : SUCCESS"
echo "DNS Flushed"

echo ""
echo "[INFO] SCRIPT COMPLETE"
echo "=============================================================="
exit 0
