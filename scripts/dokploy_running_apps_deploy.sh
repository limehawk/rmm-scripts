#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Dokploy Deploy Running Apps                                  v3.4.0
#  AUTHOR   : Limehawk.io
#  DATE     : July 2026
#  USAGE    : ./dokploy_running_apps_deploy.sh
# ================================================================================
#  FILE     : dokploy_running_apps_deploy.sh
#  DESCRIPTION : Redeploys all running Dokploy apps via per-app deploy webhooks
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automates redeployment of all running Dokploy applications with no stored
#    secret. Queries the Dokploy PostgreSQL database for each app's status and
#    its built-in deploy webhook token, then triggers that webhook on localhost.
#    Because every app already carries its own webhook token in the database,
#    the script needs no API key: nothing secret is stored in the schedule body,
#    on disk, or in version control.
#
#  DATA SOURCES & PRIORITY
#
#    - Dokploy PostgreSQL database (application table: status, sourceType,
#      branch, watchPaths, refreshToken)
#    - Local Dokploy deploy webhook (localhost:3000/api/deploy/<token>)
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - DOKPLOY_DB_CONTAINER: Name filter for Dokploy postgres container
#      - DOKPLOY_LOCAL_URL: Local Dokploy base URL
#
#  SETTINGS
#
#    Configuration defaults:
#      - DOKPLOY_DB_CONTAINER: "dokploy-postgres" (container name filter)
#      - DOKPLOY_LOCAL_URL: "http://localhost:3000" (internal base URL)
#
#  BEHAVIOR
#
#    1. Queries the Dokploy database for all applications
#    2. Skips applications with "idle" status
#    3. Triggers each non-idle app's deploy webhook in parallel:
#         - docker-source apps: a bare POST to the webhook
#         - git-source apps: a GitHub-style push payload carrying the app's
#           branch, plus a file path that satisfies any watchPaths filter
#    4. Waits for all deployments and reports results
#    5. Exits 1 if any deployment failed so the scheduler surfaces the failure
#
#  PREREQUISITES
#
#    - Script must run on the Dokploy host server (Dokploy schedule or cron)
#    - Dokploy postgres container accessible via docker exec
#    - curl installed
#    - Each target app must have "Auto Deploy" enabled — the webhook rejects
#      apps with auto deploy turned off
#
#  SECURITY NOTES
#
#    - No API key or stored secret: each app's own webhook token is read from
#      the local database at runtime and used only against localhost
#    - No secrets in logs (only app names and HTTP codes are printed)
#    - All calls are localhost-only, no external network traffic
#
#  ENDPOINTS
#
#    - http://localhost:3000/api/deploy/<refreshToken> (per-app deploy webhook)
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
#    Found 20 applications. Filtering by status...
#
#    [RUN] PROCESSING APPLICATIONS
#    ==============================================================
#    Skipping idle app : change-detection/frontend
#    Queued for deployment : hudu/hudu-app
#    Queued for deployment : slime-scanner/backend
#
#    [RUN] DEPLOYING 11 APPLICATIONS (PARALLEL)
#    ==============================================================
#    [OK] hudu/hudu-app
#    [OK] slime-scanner/backend
#    [ERROR] mealie/frontend (HTTP 400)
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Redeployed : 10
#    Skipped (idle) : 9
#    Failed : 1
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-07-02 v3.4.0 Deploy via each app's own webhook token (read from DB) —
#                    removes the stored API key entirely; docker apps use a bare
#                    POST, git apps a branch/watchPaths-matched push payload
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
DOKPLOY_LOCAL_URL="http://localhost:3000"                 # Dokploy internal base URL
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

if [[ -z "$DOKPLOY_DB_CONTAINER" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- DOKPLOY_DB_CONTAINER is not configured"
fi

if [[ -z "$DOKPLOY_LOCAL_URL" ]]; then
    ERROR_OCCURRED=true
    ERROR_TEXT="${ERROR_TEXT}\n- DOKPLOY_LOCAL_URL is not configured"
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

# Query per app: project, name, status, sourceType, branch, watchPaths, token
# (pipe-delimited, no headers). watchPaths is a text[]; psql prints it as
# {a/**,b/**} or {} — parsed below.
APP_DATA=$(docker exec "$DB_CONTAINER" psql -U dokploy -d dokploy -t -A -F '|' \
    -c "SELECT p.name, a.name, a.\"applicationStatus\", a.\"sourceType\", a.branch, a.\"watchPaths\", a.\"refreshToken\" FROM application a JOIN environment e ON a.\"environmentId\" = e.\"environmentId\" JOIN project p ON e.\"projectId\" = p.\"projectId\"" 2>/dev/null)

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

while IFS='|' read -r PROJECT_NAME APP_NAME APP_STATUS SOURCE_TYPE BRANCH WATCHPATHS TOKEN; do
    DISPLAY_NAME="$PROJECT_NAME/$APP_NAME"

    if [[ "$APP_STATUS" == "idle" ]]; then
        echo "Skipping idle app : $DISPLAY_NAME"
        SKIPPED_IDLE=$((SKIPPED_IDLE + 1))
        continue
    fi

    # Decide how to trigger this app's webhook based on its source type.
    # docker apps redeploy on a bare POST; git apps need a push payload whose
    # branch matches and whose modified file satisfies any watchPaths filter.
    if [[ "$SOURCE_TYPE" == "docker" ]]; then
        MODE="docker"
        REF=""
        SAMPLE=""
    else
        MODE="git"
        REF="refs/heads/${BRANCH}"
        # Strip the psql array braces; derive one file path that matches the
        # first watchPaths glob (empty watchPaths => no filter => no path).
        WP="${WATCHPATHS#\{}"
        WP="${WP%\}}"
        if [[ -n "$WP" ]]; then
            FIRST_GLOB="${WP%%,*}"
            FIRST_GLOB="${FIRST_GLOB%\"}"
            FIRST_GLOB="${FIRST_GLOB#\"}"
            SAMPLE=$(printf '%s' "$FIRST_GLOB" | sed 's/\*\+/dokploy-redeploy/g')
        else
            SAMPLE=""
        fi
    fi

    echo "Queued for deployment : $DISPLAY_NAME"
    DEPLOY_LIST="${DEPLOY_LIST}${DISPLAY_NAME}|${MODE}|${TOKEN}|${REF}|${SAMPLE}"$'\n'
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
    REC="{}"
    DISPLAY=$(echo "$REC" | cut -d"|" -f1)
    MODE=$(echo "$REC" | cut -d"|" -f2)
    TOKEN=$(echo "$REC" | cut -d"|" -f3)
    REF=$(echo "$REC" | cut -d"|" -f4)
    SAMPLE=$(echo "$REC" | cut -d"|" -f5)
    URL="'"$DOKPLOY_LOCAL_URL"'/api/deploy/$TOKEN"
    if [ "$MODE" = "docker" ]; then
        RESPONSE=$(curl -s -w "|%{http_code}" --max-time 60 -X POST "$URL" 2>&1)
    else
        if [ -n "$SAMPLE" ]; then
            BODY="{\"ref\":\"$REF\",\"commits\":[{\"modified\":[\"$SAMPLE\"]}]}"
        else
            BODY="{\"ref\":\"$REF\"}"
        fi
        RESPONSE=$(curl -s -w "|%{http_code}" --max-time 60 -X POST "$URL" -H "x-github-event: push" -H "Content-Type: application/json" -d "$BODY" 2>&1)
    fi
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d "|")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "[OK] $DISPLAY"
    else
        echo "[ERROR] $DISPLAY (HTTP $HTTP_CODE)"
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
