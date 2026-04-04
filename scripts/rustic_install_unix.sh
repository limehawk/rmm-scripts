#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Rustic Install (Linux/macOS)                               v1.0.0
#  AUTHOR   : Limehawk.io
#  DATE     : April 2026
#  USAGE    : sudo ./rustic_install_unix.sh
# ================================================================================
#  FILE     : rustic_install_unix.sh
#  DESCRIPTION : Installs Rustic, configures backend repository, schedules daily backups
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    All-in-one installer for Rustic backup on Linux and macOS with
#    multi-backend support. Detects OS and architecture, downloads the
#    Rustic binary from GitHub releases (SHA256-verified), generates a
#    TOML configuration profile with backend-specific settings, initializes
#    an encrypted repository scoped to the machine hostname, deploys a
#    daily backup runner script, and creates a systemd timer (Linux) or
#    launchd plist (macOS). Designed for deployment via SuperOps RMM.
#
#  DATA SOURCES & PRIORITY
#
#    - Hardcoded backend credentials and repo password (operator fills per deployment)
#    - Rustic binary from GitHub releases (SHA256-verified)
#
#  REQUIRED INPUTS
#
#    SuperOps runtime variables (prompted at deploy time):
#      - $YourBackendType   : Backend type: b2, s3, local, sftp, rest
#      - $YourBackendPath   : Bucket name (B2/S3), local path, host:port (SFTP), or URL (REST)
#      - $YourRepoPassword  : Encryption passphrase (create one, store in 1Password)
#      - $YourClientName    : Short client ID for logs (e.g., bell, gruman)
#
#    Conditional (B2/S3 only):
#      - $YourBackendKeyId  : Access key ID (B2 keyID or S3 access key)
#      - $YourBackendAppKey : Secret key (B2 applicationKey or S3 secret)
#
#    Conditional (S3 only):
#      - $YourBackendRegion : S3 region (e.g., us-east-1)
#
#    Optional:
#      - $YourBackupPaths    : Comma-separated paths (empty = defaults)
#      - $YourExcludePatterns: Comma-separated globs (empty = defaults)
#      - $YourBackupHour     : Hour 0-23 (empty = default 2)
#
#  SETTINGS
#
#    Configuration with sensible defaults:
#      - Backup paths (Linux) : /home, /etc, /var/lib
#      - Backup paths (macOS) : /Users, /etc
#      - Exclude patterns     : Temp files, caches, dev artifacts, large binaries
#      - Retention            : 7 daily, 4 weekly, 6 monthly
#      - Rustic version       : 0.11.1
#
#  BEHAVIOR
#
#    The script performs the following actions in order:
#    1. Validates all hardcoded inputs are non-empty and backend-appropriate
#    2. Detects OS (Linux/macOS) and architecture (x86_64/aarch64/arm64/armv7l)
#    3. Downloads Rustic binary from GitHub (skips if correct version installed)
#    4. Verifies SHA256 checksum before extracting
#    5. Generates TOML configuration profile for the selected backend
#    6. Initializes repository (skips if already exists)
#    7. Generates daily backup script with log rotation
#    8. Creates systemd timer (Linux) or launchd plist (macOS)
#    9. Runs dry-run backup to verify connectivity and path access
#
#  PREREQUISITES
#
#    - Linux (glibc or musl) or macOS 11+
#    - Root privileges (runs as root via RMM)
#    - curl and tar installed
#    - Network access to GitHub releases and the configured backend
#
#  SECURITY NOTES
#
#    - Backend credentials are embedded in the TOML config file
#    - Config directory is chmod 700, config file is chmod 600
#    - No secrets printed to console output
#    - Repo password encrypts all backup data at rest
#
#  ENDPOINTS
#
#    - GitHub Releases (rustic-rs/rustic) - binary download
#    - Configured backend (B2/S3/SFTP/REST/local) - backup storage
#
#  EXIT CODES
#
#    0 = Success
#    1 = Failure (validation, download, init, or config error)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#      OS         : Linux (x86_64)
#      Backend    : b2
#      Path       : limehawk-backups-bell
#      Client     : bell
#      Repository : opendal:b2 -> /bell/server01
#      Rustic     : v0.11.1 (GitHub release)
#      Schedule   : Daily at 02:00
#      Retention  : 7 daily, 4 weekly, 6 monthly
#      Backup Paths : 3 paths configured
#      Excludes     : 15 patterns configured
#
#    [RUN] INSTALL RUSTIC
#    ==============================================================
#      Downloading rustic v0.11.1...
#      SHA256 verified
#      Installed at /usr/local/bin/rustic
#
#    [RUN] GENERATE CONFIGURATION
#    ==============================================================
#      Generated /etc/rustic/rustic.toml
#      Backend: b2
#
#    [RUN] INITIALIZE REPOSITORY
#    ==============================================================
#      Initializing new repository...
#      Repository initialized successfully
#
#    [RUN] CREATE BACKUP SCRIPT
#    ==============================================================
#      Generated /usr/local/bin/rustic-backup.sh
#
#    [RUN] CREATE SCHEDULE
#    ==============================================================
#      Scheduler  : systemd timer
#      Schedule   : Daily at 02:00
#      Timer enabled successfully
#
#    [RUN] TEST BACKUP
#    ==============================================================
#      Running dry-run backup...
#      Dry-run completed successfully
#
#    [OK] FINAL STATUS
#    ==============================================================
#      Result   : SUCCESS
#      Rustic   : v0.11.1
#      Backend  : b2
#      Client   : bell
#      Schedule : Daily at 02:00
#
#    [OK] SCRIPT COMPLETED
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

# --- REQUIRED: SuperOps runtime variables (prompted at deploy time) ---
# shellcheck disable=SC2154  # Variables injected by RMM at deploy time
BACKEND_TYPE="${YourBackendType:-}"       # b2, s3, local, sftp, rest
BACKEND_PATH="${YourBackendPath:-}"       # Bucket name, local path, host:port, or URL
REPO_PASSWORD="${YourRepoPassword:-}"     # Encryption passphrase (store in 1Password)
CLIENT_NAME="${YourClientName:-}"         # Short client ID (e.g., bell, gruman)

# --- CONDITIONAL: B2/S3 only ---
BACKEND_KEY_ID="${YourBackendKeyId:-}"    # B2 keyID or S3 access key ID
BACKEND_APP_KEY="${YourBackendAppKey:-}"  # B2 applicationKey or S3 secret key

# --- CONDITIONAL: S3 only ---
BACKEND_REGION="${YourBackendRegion:-}"   # S3 region (e.g., us-east-1)

# --- OPTIONAL: Comma-separated overrides (empty = defaults) ---
BACKUP_PATHS_RAW="${YourBackupPaths:-}"        # Comma-separated paths (empty = defaults)
EXCLUDE_PATTERNS_RAW="${YourExcludePatterns:-}" # Comma-separated globs (empty = defaults)
BACKUP_HOUR_RAW="${YourBackupHour:-}"           # Hour 0-23 (empty = default 2)

# ==== DEFAULTS ====
RUSTIC_VERSION="0.11.1"
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

# ==== OS DETECTION ====
OS_TYPE="$(uname -s)"    # Linux or Darwin
ARCH="$(uname -m)"       # x86_64, aarch64, arm64, armv7l
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"

# ==== PATHS ====
RUSTIC_BIN="/usr/local/bin/rustic"
CONFIG_DIR="/etc/rustic"
CONFIG_FILE="/etc/rustic/rustic.toml"
LOG_DIR="/var/log/rustic"
BACKUP_SCRIPT="/usr/local/bin/rustic-backup.sh"

# ==== TARGET MAPPING ====
TARGET=""
case "${OS_TYPE}" in
    Linux)
        case "${ARCH}" in
            x86_64)  TARGET="x86_64-unknown-linux-musl" ;;
            aarch64) TARGET="aarch64-unknown-linux-musl" ;;
            armv7l)  TARGET="armv7-unknown-linux-gnueabihf" ;;
            *)
                ERROR_OCCURRED=true
                ERROR_TEXT="- Unsupported Linux architecture: ${ARCH}"
                ;;
        esac
        ;;
    Darwin)
        case "${ARCH}" in
            x86_64) TARGET="x86_64-apple-darwin" ;;
            arm64)  TARGET="aarch64-apple-darwin" ;;
            *)
                ERROR_OCCURRED=true
                ERROR_TEXT="- Unsupported macOS architecture: ${ARCH}"
                ;;
        esac
        ;;
    *)
        ERROR_OCCURRED=true
        ERROR_TEXT="- Unsupported operating system: ${OS_TYPE}"
        ;;
esac

# SHA256 command differs by platform
SHA256_CMD=""
if [[ "${OS_TYPE}" == "Linux" ]]; then
    SHA256_CMD="sha256sum"
elif [[ "${OS_TYPE}" == "Darwin" ]]; then
    SHA256_CMD="shasum -a 256"
fi

# Download URLs
DOWNLOAD_URL="https://github.com/rustic-rs/rustic/releases/download/v${RUSTIC_VERSION}/rustic-v${RUSTIC_VERSION}-${TARGET}.tar.gz"
SHA256_URL="${DOWNLOAD_URL}.sha256"

# ==== RESOLVE OPTIONAL INPUTS ====

# Default backup paths by OS
if [[ "${OS_TYPE}" == "Darwin" ]]; then
    DEFAULT_BACKUP_PATHS=("/Users" "/etc")
else
    DEFAULT_BACKUP_PATHS=("/home" "/etc" "/var/lib")
fi

DEFAULT_EXCLUDE_PATTERNS=(
    "*.tmp"
    "*.temp"
    ".DS_Store"
    "Thumbs.db"
    "node_modules"
    ".git"
    "__pycache__"
    "*.iso"
    "*.vmdk"
    "*.vhdx"
    ".Trash"
    "Library/Caches"
    "/var/log"
    "/var/cache"
    "/var/tmp"
)

# Backup paths: use custom if provided, otherwise defaults
BACKUP_PATHS=()
if [[ -z "${BACKUP_PATHS_RAW}" || "${BACKUP_PATHS_RAW}" == '$YourBackupPaths' ]]; then
    BACKUP_PATHS=("${DEFAULT_BACKUP_PATHS[@]}")
else
    IFS=',' read -ra BACKUP_PATHS <<< "${BACKUP_PATHS_RAW}"
    # Trim whitespace from each element
    for i in "${!BACKUP_PATHS[@]}"; do
        BACKUP_PATHS[$i]="$(echo "${BACKUP_PATHS[$i]}" | xargs)"
    done
fi

# Exclude patterns: use custom if provided, otherwise defaults
EXCLUDE_PATTERNS=()
if [[ -z "${EXCLUDE_PATTERNS_RAW}" || "${EXCLUDE_PATTERNS_RAW}" == '$YourExcludePatterns' ]]; then
    EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
else
    IFS=',' read -ra EXCLUDE_PATTERNS <<< "${EXCLUDE_PATTERNS_RAW}"
    for i in "${!EXCLUDE_PATTERNS[@]}"; do
        EXCLUDE_PATTERNS[$i]="$(echo "${EXCLUDE_PATTERNS[$i]}" | xargs)"
    done
fi

# Backup hour: use custom if provided, otherwise default 2
BACKUP_HOUR=2
if [[ -z "${BACKUP_HOUR_RAW}" || "${BACKUP_HOUR_RAW}" == '$YourBackupHour' ]]; then
    BACKUP_HOUR=2
elif [[ "${BACKUP_HOUR_RAW}" =~ ^[0-9]+$ ]]; then
    BACKUP_HOUR="${BACKUP_HOUR_RAW}"
else
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- Backup hour '${BACKUP_HOUR_RAW}' is not a valid integer."
fi

# ==== VALIDATION ====

# Normalize backend type
BACKEND_TYPE="$(echo "${BACKEND_TYPE}" | tr '[:upper:]' '[:lower:]' | xargs)"

if [[ -z "${BACKEND_TYPE}" || "${BACKEND_TYPE}" == '$YourBackendType' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourBackendType was not replaced."
fi
if [[ -z "${BACKEND_PATH}" || "${BACKEND_PATH}" == '$YourBackendPath' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourBackendPath was not replaced."
fi
if [[ -z "${REPO_PASSWORD}" || "${REPO_PASSWORD}" == '$YourRepoPassword' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourRepoPassword was not replaced."
fi
if [[ -z "${CLIENT_NAME}" || "${CLIENT_NAME}" == '$YourClientName' ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourClientName was not replaced."
fi

# Validate backend type is recognized
VALID_BACKENDS="b2 s3 local sftp rest"
if [[ "${ERROR_OCCURRED}" != "true" ]] && ! echo "${VALID_BACKENDS}" | grep -qw "${BACKEND_TYPE}"; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- Invalid backend type '${BACKEND_TYPE}'. Must be one of: b2, s3, local, sftp, rest"
fi

# Conditional validation: B2 and S3 require key credentials
if [[ "${BACKEND_TYPE}" == "b2" || "${BACKEND_TYPE}" == "s3" ]]; then
    if [[ -z "${BACKEND_KEY_ID}" || "${BACKEND_KEY_ID}" == '$YourBackendKeyId' ]]; then
        ERROR_OCCURRED=true
        if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
        ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourBackendKeyId is required for ${BACKEND_TYPE} backend."
    fi
    if [[ -z "${BACKEND_APP_KEY}" || "${BACKEND_APP_KEY}" == '$YourBackendAppKey' ]]; then
        ERROR_OCCURRED=true
        if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
        ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourBackendAppKey is required for ${BACKEND_TYPE} backend."
    fi
fi

# Conditional validation: S3 requires region
if [[ "${BACKEND_TYPE}" == "s3" ]]; then
    if [[ -z "${BACKEND_REGION}" || "${BACKEND_REGION}" == '$YourBackendRegion' ]]; then
        ERROR_OCCURRED=true
        if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
        ERROR_TEXT="${ERROR_TEXT}- SuperOps runtime variable \$YourBackendRegion is required for s3 backend."
    fi
fi

if [[ "${#BACKUP_PATHS[@]}" -eq 0 ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- At least one backup path is required."
fi

if [[ "${BACKUP_HOUR}" -lt 0 || "${BACKUP_HOUR}" -gt 23 ]]; then
    ERROR_OCCURRED=true
    if [[ -n "${ERROR_TEXT}" ]]; then ERROR_TEXT="${ERROR_TEXT}"$'\n'; fi
    ERROR_TEXT="${ERROR_TEXT}- Backup hour must be between 0 and 23 (got ${BACKUP_HOUR})."
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

# ==== BUILD DISPLAY VALUES (no secrets) ====
if [[ -z "${HOSTNAME_SHORT}" ]]; then
    HOSTNAME_SHORT="UNKNOWN"
    echo "[WARN] hostname is empty, using 'UNKNOWN' as hostname"
fi
REPO_ROOT="/${CLIENT_NAME}/${HOSTNAME_SHORT}"

DISPLAY_REPO=""
case "${BACKEND_TYPE}" in
    b2)    DISPLAY_REPO="opendal:b2 -> ${REPO_ROOT}" ;;
    s3)    DISPLAY_REPO="opendal:s3 -> ${REPO_ROOT}" ;;
    local) DISPLAY_REPO="${BACKEND_PATH}/${CLIENT_NAME}/${HOSTNAME_SHORT}" ;;
    sftp)  DISPLAY_REPO="opendal:sftp -> ${REPO_ROOT}" ;;
    rest)  DISPLAY_REPO="rest:${BACKEND_PATH}/${CLIENT_NAME}/${HOSTNAME_SHORT}" ;;
esac

BACKUP_HOUR_FMT="$(printf '%02d' "${BACKUP_HOUR}")"

# ==== INPUT VALIDATION OUTPUT ====
echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="
echo "  OS           : ${OS_TYPE} (${ARCH})"
echo "  Backend      : ${BACKEND_TYPE}"
echo "  Path         : ${BACKEND_PATH}"
echo "  Client       : ${CLIENT_NAME}"
echo "  Repository   : ${DISPLAY_REPO}"
echo "  Rustic       : v${RUSTIC_VERSION} (GitHub release)"
echo "  Schedule     : Daily at ${BACKUP_HOUR_FMT}:00"
echo "  Retention    : ${KEEP_DAILY} daily, ${KEEP_WEEKLY} weekly, ${KEEP_MONTHLY} monthly"
echo "  Backup Paths : ${#BACKUP_PATHS[@]} paths configured"
echo "  Excludes     : ${#EXCLUDE_PATTERNS[@]} patterns configured"

# ==== INSTALL RUSTIC ====
echo ""
echo "[RUN] INSTALL RUSTIC"
echo "=============================================================="

# Create directory structure
mkdir -p "${CONFIG_DIR}" "${LOG_DIR}"
chmod 700 "${CONFIG_DIR}"

# Check if rustic is already installed at the correct version
SKIP_DOWNLOAD=false
if [[ -x "${RUSTIC_BIN}" ]]; then
    CURRENT_VERSION="$("${RUSTIC_BIN}" --version 2>/dev/null || true)"
    if echo "${CURRENT_VERSION}" | grep -q "${RUSTIC_VERSION}"; then
        echo "  Rustic v${RUSTIC_VERSION} already installed, skipping download"
        SKIP_DOWNLOAD=true
    fi
fi

if [[ "${SKIP_DOWNLOAD}" != "true" ]]; then
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TEMP_DIR}"' EXIT

    ARCHIVE_PATH="${TEMP_DIR}/rustic.tar.gz"
    SHA256_PATH="${TEMP_DIR}/rustic.tar.gz.sha256"

    # Download archive and checksum
    echo "  Downloading rustic v${RUSTIC_VERSION}..."
    if ! curl --silent --show-error --fail -L -o "${ARCHIVE_PATH}" "${DOWNLOAD_URL}"; then
        echo ""
        echo "[ERROR] INSTALL RUSTIC FAILED"
        echo "=============================================================="
        echo "  Failed to download rustic binary from ${DOWNLOAD_URL}"
        echo ""
        echo "[ERROR] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 1
    fi

    if ! curl --silent --show-error --fail -L -o "${SHA256_PATH}" "${SHA256_URL}"; then
        echo ""
        echo "[ERROR] INSTALL RUSTIC FAILED"
        echo "=============================================================="
        echo "  Failed to download SHA256 checksum from ${SHA256_URL}"
        echo ""
        echo "[ERROR] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 1
    fi

    # Verify SHA256
    EXPECTED_HASH="$(awk '{print $1}' "${SHA256_PATH}" | tr '[:upper:]' '[:lower:]')"
    ACTUAL_HASH="$(${SHA256_CMD} "${ARCHIVE_PATH}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"

    if [[ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]]; then
        echo ""
        echo "[ERROR] INSTALL RUSTIC FAILED"
        echo "=============================================================="
        echo "  SHA256 mismatch: expected ${EXPECTED_HASH}, got ${ACTUAL_HASH}"
        echo ""
        echo "[ERROR] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 1
    fi
    echo "  SHA256 verified"

    # Extract archive
    tar -xzf "${ARCHIVE_PATH}" -C "${TEMP_DIR}"

    # Find and copy rustic binary
    EXTRACTED_BIN="$(find "${TEMP_DIR}" -name 'rustic' -type f | head -1)"
    if [[ -z "${EXTRACTED_BIN}" ]]; then
        echo ""
        echo "[ERROR] INSTALL RUSTIC FAILED"
        echo "=============================================================="
        echo "  rustic binary not found in extracted archive"
        echo ""
        echo "[ERROR] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 1
    fi

    cp "${EXTRACTED_BIN}" "${RUSTIC_BIN}"
    chmod 755 "${RUSTIC_BIN}"
    echo "  Installed at ${RUSTIC_BIN}"

    # Clean up temp dir (trap handles this, but be explicit)
    rm -rf "${TEMP_DIR}"
    trap - EXIT
fi

# ==== GENERATE CONFIGURATION ====
echo ""
echo "[RUN] GENERATE CONFIGURATION"
echo "=============================================================="

# Build TOML backup sources array
TOML_SOURCES=""
for P in "${BACKUP_PATHS[@]}"; do
    if [[ -n "${TOML_SOURCES}" ]]; then
        TOML_SOURCES="${TOML_SOURCES},"$'\n'
    fi
    TOML_SOURCES="${TOML_SOURCES}  \"${P}\""
done

# Build TOML exclude globs (prefix with ! for rustic)
TOML_GLOBS=""
for E in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ -n "${TOML_GLOBS}" ]]; then
        TOML_GLOBS="${TOML_GLOBS},"$'\n'
    fi
    TOML_GLOBS="${TOML_GLOBS}  \"!${E}\""
done

# Build repository section based on backend type
REPO_SECTION=""
case "${BACKEND_TYPE}" in
    b2)
        REPO_SECTION="[repository]
repository = \"opendal:b2\"
password = \"${REPO_PASSWORD}\"

[repository.options]
application_key_id = \"${BACKEND_KEY_ID}\"
application_key = \"${BACKEND_APP_KEY}\"
bucket = \"${BACKEND_PATH}\"
root = \"/${CLIENT_NAME}/${HOSTNAME_SHORT}\""
        ;;
    s3)
        REPO_SECTION="[repository]
repository = \"opendal:s3\"
password = \"${REPO_PASSWORD}\"

[repository.options]
access_key_id = \"${BACKEND_KEY_ID}\"
secret_access_key = \"${BACKEND_APP_KEY}\"
bucket = \"${BACKEND_PATH}\"
region = \"${BACKEND_REGION}\"
root = \"/${CLIENT_NAME}/${HOSTNAME_SHORT}\""
        ;;
    local)
        LOCAL_REPO_PATH="${BACKEND_PATH}/${CLIENT_NAME}/${HOSTNAME_SHORT}"
        REPO_SECTION="[repository]
repository = \"${LOCAL_REPO_PATH}\"
password = \"${REPO_PASSWORD}\"
no-cache = true"
        ;;
    sftp)
        # Parse user@host:port format if present
        SFTP_USER=""
        SFTP_ENDPOINT="${BACKEND_PATH}"
        if [[ "${BACKEND_PATH}" =~ ^([^@]+)@(.+)$ ]]; then
            SFTP_USER="${BASH_REMATCH[1]}"
            SFTP_ENDPOINT="${BASH_REMATCH[2]}"
        fi
        SFTP_USER_LINE=""
        if [[ -n "${SFTP_USER}" ]]; then
            SFTP_USER_LINE=$'\n'"user = \"${SFTP_USER}\""
        fi
        REPO_SECTION="[repository]
repository = \"opendal:sftp\"
password = \"${REPO_PASSWORD}\"

[repository.options]
endpoint = \"${SFTP_ENDPOINT}\"${SFTP_USER_LINE}
root = \"/${CLIENT_NAME}/${HOSTNAME_SHORT}\""
        ;;
    rest)
        REST_URL="${BACKEND_PATH%/}"
        REPO_SECTION="[repository]
repository = \"rest:${REST_URL}/${CLIENT_NAME}/${HOSTNAME_SHORT}\"
password = \"${REPO_PASSWORD}\""
        ;;
esac

# Write full TOML config
cat > "${CONFIG_FILE}" << TOML
# Limehawk Rustic Backup Configuration
# Generated $(date '+%Y-%m-%d') by rustic_install_unix.sh
# Client: ${CLIENT_NAME} | Host: ${HOSTNAME_SHORT} | Backend: ${BACKEND_TYPE}

${REPO_SECTION}

[global]
log-level = "info"
log-file = "/var/log/rustic/rustic.log"
no-progress = true

[backup]
exclude-if-present = [".nobackup", "CACHEDIR.TAG"]
host = "${HOSTNAME_SHORT}"

[[backup.snapshots]]
sources = [
${TOML_SOURCES}
]
globs = [
${TOML_GLOBS}
]

[forget]
prune = true
keep-daily = ${KEEP_DAILY}
keep-weekly = ${KEEP_WEEKLY}
keep-monthly = ${KEEP_MONTHLY}
TOML

chmod 600 "${CONFIG_FILE}"
echo "  Generated ${CONFIG_FILE}"
echo "  Backend: ${BACKEND_TYPE}"

# ==== INITIALIZE REPOSITORY ====
echo ""
echo "[RUN] INITIALIZE REPOSITORY"
echo "=============================================================="

export RUSTIC_CONFIG_FILE="${CONFIG_FILE}"

echo "  Repository : ${DISPLAY_REPO}"

# Check if repo already exists (snapshots returns 0 if repo exists)
if "${RUSTIC_BIN}" snapshots --json > /dev/null 2>&1; then
    echo "  Repository already initialized, skipping"
else
    echo "  Initializing new repository..."
    if ! "${RUSTIC_BIN}" init 2>&1; then
        echo ""
        echo "[ERROR] INITIALIZE REPOSITORY FAILED"
        echo "=============================================================="
        echo "  rustic init failed"
        echo ""
        echo "[ERROR] SCRIPT COMPLETED"
        echo "=============================================================="
        exit 1
    fi
    echo "  Repository initialized successfully"
fi

# ==== CREATE BACKUP SCRIPT ====
echo ""
echo "[RUN] CREATE BACKUP SCRIPT"
echo "=============================================================="

cat > "${BACKUP_SCRIPT}" << 'BACKUPEOF'
#!/bin/bash
# Limehawk Rustic Daily Backup
# DO NOT EDIT - regenerate by re-running the installer

set -euo pipefail

LOG_DIR="/var/log/rustic"
LOG_FILE="${LOG_DIR}/rustic-backup-$(date '+%Y-%m-%d').log"
CONFIG_FILE="/etc/rustic/rustic.toml"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# All output goes to log file
exec >> "${LOG_FILE}" 2>&1

export RUSTIC_CONFIG_FILE="${CONFIG_FILE}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup"

# Run backup
/usr/local/bin/rustic backup || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup completed"

# Run retention policy with prune
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applying retention policy"
/usr/local/bin/rustic forget --prune || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retention policy applied"

# Integrity check on a small subset of data
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running integrity check"
/usr/local/bin/rustic check --read-data-subset=1/100 || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Integrity check completed"

unset RUSTIC_CONFIG_FILE

# Rotate logs older than 30 days
find "${LOG_DIR}" -name 'rustic-backup-*.log' -mtime +30 -delete 2>/dev/null || true

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup run complete"
BACKUPEOF

chmod 755 "${BACKUP_SCRIPT}"
echo "  Generated ${BACKUP_SCRIPT}"

# ==== CREATE SCHEDULE ====
echo ""
echo "[RUN] CREATE SCHEDULE"
echo "=============================================================="

if [[ "${OS_TYPE}" == "Linux" ]]; then
    # --- systemd timer ---
    echo "  Scheduler  : systemd timer"

    cat > /etc/systemd/system/rustic-backup.service << SERVICEEOF
[Unit]
Description=Limehawk Rustic Backup (${CLIENT_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rustic-backup.sh
Nice=10
IOSchedulingClass=idle
SERVICEEOF

    cat > /etc/systemd/system/rustic-backup.timer << TIMEREOF
[Unit]
Description=Limehawk Rustic Backup Timer (${CLIENT_NAME})

[Timer]
OnCalendar=*-*-* ${BACKUP_HOUR_FMT}:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl daemon-reload
    systemctl enable --now rustic-backup.timer
    echo "  Schedule   : Daily at ${BACKUP_HOUR_FMT}:00"
    echo "  Timer enabled successfully"

elif [[ "${OS_TYPE}" == "Darwin" ]]; then
    # --- launchd plist ---
    echo "  Scheduler  : launchd"

    PLIST_PATH="/Library/LaunchDaemons/io.limehawk.rustic-backup.plist"

    cat > "${PLIST_PATH}" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.limehawk.rustic-backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/rustic-backup.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${BACKUP_HOUR}</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/rustic/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/rustic/launchd-stderr.log</string>
</dict>
</plist>
PLISTEOF

    # Unload existing if present, then load
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    launchctl load "${PLIST_PATH}"
    echo "  Schedule   : Daily at ${BACKUP_HOUR_FMT}:00"
    echo "  Plist loaded successfully"
fi

# ==== TEST BACKUP ====
echo ""
echo "[RUN] TEST BACKUP"
echo "=============================================================="

echo "  Running dry-run backup..."
if "${RUSTIC_BIN}" backup --dry-run 2>&1; then
    echo "  Dry-run completed successfully"
else
    echo ""
    echo "[WARN] TEST BACKUP"
    echo "=============================================================="
    echo "  Dry-run failed"
    echo "  Installation is complete but verify backend connectivity manually"
fi

unset RUSTIC_CONFIG_FILE

# ==== FINAL STATUS ====
echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "  Result   : SUCCESS"
echo "  Rustic   : v${RUSTIC_VERSION}"
echo "  Backend  : ${BACKEND_TYPE}"
echo "  Client   : ${CLIENT_NAME}"
echo "  Schedule : Daily at ${BACKUP_HOUR_FMT}:00"

echo ""
echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="
exit 0
