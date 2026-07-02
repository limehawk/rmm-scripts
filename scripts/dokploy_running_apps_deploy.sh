#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Dokploy Deploy Running Apps                                  v3.3.0
#  AUTHOR   : Limehawk.io
#  DATE     : July 2026
#  USAGE    : ./dokploy_running_apps_deploy.sh
# ================================================================================
#  FILE     : dokploy_running_apps_deploy.sh
#  DESCRIPTION : Redeploys all running Dokploy apps via local API
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automates redeployment of all running Dokploy applications by querying
#    the Dokploy PostgreSQL database for application status, then triggering
#    deployments via the local Dokploy API. The API key is read from a
#    root-only file on the host (env var override supported), so the
#    schedule body holds no secret; calls hit localhost to avoid external
#    routing issues.
#
#  DATA SOURCES & PRIORITY
#
#    - Dokploy PostgreSQL database (application table)
#    - Local Dokploy API (localhost:3000)
#
#  REQUIRED INPUTS
#
#    Inputs are hardcoded in the script body except the API key:
#      - DOKPLOY_DB_CONTAINER: Name filter for Dokploy postgres container
#      - DOKPLOY_LOCAL_URL: Local Dokploy API base URL
#      - DOKPLOY_API_KEY: Dokploy API key. Resolved in order:
#        1. DOKPLOY_API_KEY environment variable, if set
#        2. Contents of DOKPLOY_API_KEY_FILE (root-only file on the host)
#
#  SETTINGS
#
#    Configuration defaults:
#      - DOKPLOY_DB_CONTAINER: "dokploy-postgres" (container name filter)
#      - DOKPLOY_LOCAL_URL: "http://localhost:3000" (internal API)
#      - DOKPLOY_API_KEY: unset (generate in Dokploy Settings > API/CLI)
#      - DOKPLOY_API_KEY_FILE: "/root/.dokploy_api_key" (chmod 600)
#
#  BEHAVIOR
#
#    1. Queries the Dokploy database for all applications
#    2. Skips applications with "idle" status
#    3. Triggers deployment via application.deploy API for non-idle apps in parallel
#    4. Waits for all deployments and reports results
#    5. Exits 1 if any deployment failed so the scheduler surfaces the failure
#
#  PREREQUISITES
#
#    - Dokploy running with PostgreSQL container accessible
#    - Script must run on the Dokploy host server
#    - curl installed
#
#  SECURITY NOTES
#
#    - API key lives in a root-only file on the host (chmod 600) — outside
#      the schedule body, the Dokploy database, and version control
#    - No secrets in logs
#    - All API calls are localhost-only, no external network traffic
#
#  ENDPOINTS
#
#    - http://localhost:3000/api/application.deploy (local API)
#
#  EXIT CODES
#
#    0 - Success (all triggered deployments accepted)
#    1 - Failure (validation error or one or more deployments failed)
#
#  EXAMPLE RUN
#
#    [INFO] INPUT VALIDATION
#    ==============================================================
#    All inputs validated.
#
#    [RUN] QUERYING DATABASE
#    ==============================================================
#    Found 21 applications. Filtering by status...
#
#    [RUN] PROCESSING APPLICATIONS
#    ==============================================================
#    Skipping idle app : frontend (applicationId: abc123)
#    Queued for deployment : hudu-app
#    Queued for deployment : it-tools
#
#    [RUN] DEPLOYING 15 APPLICATIONS (PARALLEL)
#    ==============================================================
#    [OK] hudu-app
#    [OK] it-tools
#    [ERROR] backend
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Redeployed : 14
#    Skipped (idle) : 6
#    Failed : 1
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-07-02 v3.3.0 Read API key from root-only key file so the schedule
#                    body holds no secret; env var still overrides
#  2026-07-02 v3.2.0 Source API key from DOKPLOY_API_KEY env var, exit 1 on
#                    deploy failures, fix doubled zero in final count output
#  2026-03-23 v3.1.0 Switch to application.deploy API via localhost
#  2026-03-22 v3.0.0 Rewrite to use database + localhost webhooks
#  2026-03-22 v2.0.1 Fix field delimiter — use pipe instead of tab for parsing
#  2026-03-22 v2.0.0 Rewrite to use Docker Swarm directly, no API token needed
#  2026-01-19 v1.1.1 Updated to two-line ASCII console output style
#  2025-12-23 v1.1.0 Updated to Limehawk Script Framework
#  2024-11-18 v1.0.0 Initial release
# ================================================================================

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
DOKPLOY_DB_CONTAINER="dokploy-postgres"                  # Dokploy postgres container name
DOKPLOY_LOCAL_URL="http://localhost:3000"                 # Dokploy internal API URL
DOKPLOY_API_KEY="${DOKPLOY_API_KEY:-}"                   # API key — env var override; normally left empty
DOKPLOY_API_KEY_FILE="/root/.dokploy_api_key"            # Root-only key file on the host (chmod 600)
# ============================================================================

set -e

# ============================================================================
# INPUT VALIDATION
# ============================================================================
echo ""
echo "[INFO] INPUT VALIDATION"
echo "=============================================================="

ERROR_OCCURRED=false
ERROR_TEXT=""

# Resolve API key: env var wins, otherwise read the root-only key file
if [[ -z "$DOKPLOY_API_KEY" && -r "$DOKPLOY_API_KEY_FILE" ]]; then
    DOKPLOY_API_KEY=$(<"$DOKPLOY_API_KEY_FILE")
fi

if [[ -z "$DOKPLOY_DB_CONTAINER" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- DOKPLOY_DB_CONTAINER is not configured"
fi

if [[ -z "$DOKPLOY_LOCAL_URL" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- DOKPLOY_LOCAL_URL is not configured"
fi

if [[ -z "$DOKPLOY_API_KEY" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- DOKPLOY_API_KEY is not configured (put the key in $DOKPLOY_API_KEY_FILE with chmod 600, or set the env var)"
fi

if [[ "$ERROR_OCCURRED" = true ]]; then
    echo -e "$ERROR_TEXT"
    echo ""
    exit 1
fi

echo "All inputs validated."

# ============================================================================
# QUERY DATABASE
# ============================================================================
echo ""
echo "[RUN] QUERYING DATABASE"
echo "=============================================================="

DB_CONTAINER=$(docker ps -q -f "name=$DOKPLOY_DB_CONTAINER")

if [[ -z "$DB_CONTAINER" ]]; then
    echo ""
    echo "[ERROR] ERROR OCCURRED"
    echo "=============================================================="
    echo "Dokploy postgres container not found."
    echo ""
    exit 1
fi

# Query: app name, project name, status, applicationId (pipe-delimited, no headers)
APP_DATA=$(docker exec "$DB_CONTAINER" psql -U dokploy -d dokploy -t -A -F '|' \
    -c "SELECT a.name, p.name, a.\"applicationStatus\", a.\"applicationId\" FROM application a JOIN environment e ON a.\"environmentId\" = e.\"environmentId\" JOIN project p ON e.\"projectId\" = p.\"projectId\"" 2>/dev/null)

if [[ -z "$APP_DATA" ]]; then
    echo "No applications found in database."
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
fi

APP_COUNT=$(echo "$APP_DATA" | wc -l)
echo "Found $APP_COUNT applications. Filtering by status..."

# ============================================================================
# PROCESS APPLICATIONS
# ============================================================================
echo ""
echo "[RUN] PROCESSING APPLICATIONS"
echo "=============================================================="

SKIPPED_IDLE=0
DEPLOY_LIST=""

while IFS='|' read -r APP_NAME PROJECT_NAME APP_STATUS APP_ID; do
    DISPLAY_NAME="$PROJECT_NAME/$APP_NAME"

    if [[ "$APP_STATUS" == "idle" ]]; then
        echo "Skipping idle app : $DISPLAY_NAME"
        SKIPPED_IDLE=$((SKIPPED_IDLE + 1))
        continue
    fi

    echo "Queued for deployment : $DISPLAY_NAME"
    DEPLOY_LIST="${DEPLOY_LIST}${DISPLAY_NAME}|${APP_ID}"$'\n'
done <<< "$APP_DATA"

# Remove trailing newline
DEPLOY_LIST=$(echo "$DEPLOY_LIST" | sed '/^$/d')

if [[ -z "$DEPLOY_LIST" ]]; then
    echo "No running applications to deploy."
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Redeployed : 0"
    echo "Skipped (idle) : $SKIPPED_IDLE"
    echo "Failed : 0"
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
fi

DEPLOY_COUNT=$(echo "$DEPLOY_LIST" | wc -l)

echo ""
echo "[RUN] DEPLOYING $DEPLOY_COUNT APPLICATIONS (PARALLEL)"
echo "=============================================================="

RESULTS_FILE=$(mktemp)

echo "$DEPLOY_LIST" | xargs -P 0 -I {} sh -c '
    APP_NAME=$(echo "{}" | cut -d"|" -f1)
    APP_ID=$(echo "{}" | cut -d"|" -f2)
    RESPONSE=$(curl -s -w "|%{http_code}" --max-time 30 -X POST "'"$DOKPLOY_LOCAL_URL"'/api/application.deploy" -H "Content-Type: application/json" -H "x-api-key: '"$DOKPLOY_API_KEY"'" -d "{\"applicationId\": \"$APP_ID\"}" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d "|")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "[OK] $APP_NAME"
    else
        echo "[ERROR] $APP_NAME (HTTP $HTTP_CODE)"
    fi
' | tee "$RESULTS_FILE"

# grep -c prints the count (including 0) itself; || true only absorbs the
# nonzero exit status so set -e doesn't kill the script on a zero count
DEPLOYED=$(grep -c "^\[OK\]" "$RESULTS_FILE" || true)
FAILED=$(grep -c "^\[ERROR\]" "$RESULTS_FILE" || true)
rm -f "$RESULTS_FILE"

# ============================================================================
# FINAL STATUS
# ============================================================================
echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Redeployed : $DEPLOYED"
echo "Skipped (idle) : $SKIPPED_IDLE"
echo "Failed : $FAILED"

echo ""
if [[ "$FAILED" -gt 0 ]]; then
    echo "[ERROR] SCRIPT COMPLETED WITH FAILURES"
    echo "=============================================================="
    exit 1
fi

echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="

exit 0
