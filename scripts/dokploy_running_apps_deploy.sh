#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Dokploy Deploy Running Apps                                  v3.5.0
#  AUTHOR   : Limehawk.io
#  DATE     : July 2026
#  USAGE    : ./dokploy_running_apps_deploy.sh
# ================================================================================
#  FILE     : dokploy_running_apps_deploy.sh
#  DESCRIPTION : Redeploys running Dokploy apps and verifies each outcome + version
# --------------------------------------------------------------------------------
#  README
# --------------------------------------------------------------------------------
#  PURPOSE
#
#    Automates redeployment of all running Dokploy applications with no stored
#    secret, then verifies what actually happened. Queries the Dokploy database
#    for each app's status and its built-in deploy webhook token, triggers that
#    webhook on localhost, waits for the deploy to finish, and reports the real
#    outcome (from the deployment table) plus whether the running image changed.
#    Because every app already carries its own webhook token in the database,
#    the script needs no API key.
#
#  DATA SOURCES & PRIORITY
#
#    - Dokploy PostgreSQL database (application table: status, sourceType,
#      branch, watchPaths, refreshToken, appName, applicationId;
#      deployment table: status, errorMessage)
#    - Docker (swarm service -> running container image id, before/after)
#    - Local Dokploy deploy webhook (localhost:3000/api/deploy/<token>)
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - DOKPLOY_DB_CONTAINER: Name filter for Dokploy postgres container
#      - DOKPLOY_LOCAL_URL: Local Dokploy base URL
#      - DEPLOY_TIMEOUT: Max seconds to wait per app for a deploy to settle
#      - POLL_INTERVAL: Seconds between deployment-status checks
#
#  SETTINGS
#
#    Configuration defaults:
#      - DOKPLOY_DB_CONTAINER: "dokploy-postgres" (container name filter)
#      - DOKPLOY_LOCAL_URL: "http://localhost:3000" (internal base URL)
#      - DEPLOY_TIMEOUT: 300 (seconds per app)
#      - POLL_INTERVAL: 4 (seconds)
#
#  BEHAVIOR
#
#    1. Queries the Dokploy database for all applications
#    2. Skips applications with "idle" status
#    3. For each non-idle app, in parallel:
#         a. Records the running image id (before)
#         b. Triggers the app's deploy webhook (docker: bare POST; git: a
#            GitHub-style push payload with branch + watchPaths-matched file)
#         c. Waits for the new deployment row to reach done/error (or timeout)
#         d. Records the running image id (after) and classifies the result
#    4. Reports per app: updated (before->after), no change, failed, or timeout
#    5. Prints a summary and exits 1 if any app failed or could not be verified
#
#  PREREQUISITES
#
#    - Script must run on the Dokploy host server (Dokploy schedule or cron)
#    - Dokploy postgres container accessible via docker exec
#    - docker and curl installed
#    - Each target app must have "Auto Deploy" enabled — the webhook rejects
#      apps with auto deploy turned off
#
#  SECURITY NOTES
#
#    - No API key or stored secret: each app's own webhook token is read from
#      the local database at runtime and used only against localhost
#    - No secrets in logs (only app names, image ids, and outcomes are printed)
#    - All calls are localhost-only, no external network traffic
#
#  ENDPOINTS
#
#    - http://localhost:3000/api/deploy/<refreshToken> (per-app deploy webhook)
#
#  EXIT CODES
#
#    0 - Success (all triggered deployments verified done)
#    1 - Failure (validation error, a deploy failed, or could not be verified)
#
#  EXAMPLE RUN
#
#    [RUN] DEPLOYING 11 APPLICATIONS (PARALLEL)
#    ==============================================================
#    [OK]   hudu/hudu-app        updated  9f3c1a->b47e02  (4s)
#    [OK]   n8n/n8n              no change  a1d0f7  (1s)
#    [FAIL] mealie/frontend      deploy error (12s)
#           build failed: npm ERR! missing script: build
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Updated   : 7
#    Unchanged : 3
#    Failed    : 1
#    Skipped (idle) : 9
#    Elapsed   : 2m03s
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-07-02 v3.5.0 Verify each deploy: wait for the deployment outcome, report
#                    real done/error + failure reason, per-app duration, and the
#                    before->after image id (updated vs unchanged)
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
DEPLOY_TIMEOUT=300                                       # Max seconds to wait per app
POLL_INTERVAL=4                                          # Seconds between status checks
# ============================================================================

set -e
RUN_START=$(date +%s)

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

# Small helpers used throughout (all localhost / local docker socket)
db() { docker exec "$DB_CONTAINER" psql -U dokploy -d dokploy -t -A -F '|' -c "$1" 2>/dev/null; }

# Running image id for a swarm service (empty if no local container)
image_id() {
    local svc="$1" cid
    cid=$(docker ps -q --filter "label=com.docker.swarm.service.name=$svc" | head -1)
    [[ -n "$cid" ]] && docker inspect -f '{{.Image}}' "$cid" 2>/dev/null | sed 's/^sha256://'
}

# Query per app: project, name, status, sourceType, branch, watchPaths, token,
# appName, applicationId (pipe-delimited, no headers).
APP_DATA=$(db "SELECT p.name, a.name, a.\"applicationStatus\", a.\"sourceType\", a.branch, a.\"watchPaths\", a.\"refreshToken\", a.\"appName\", a.\"applicationId\" FROM application a JOIN environment e ON a.\"environmentId\" = e.\"environmentId\" JOIN project p ON e.\"projectId\" = p.\"projectId\"")

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

while IFS='|' read -r PROJECT_NAME APP_NAME APP_STATUS SOURCE_TYPE BRANCH WATCHPATHS TOKEN APPNAME APPID; do
    DISPLAY_NAME="$PROJECT_NAME/$APP_NAME"

    if [[ "$APP_STATUS" == "idle" ]]; then
        echo "Skipping idle app : $DISPLAY_NAME"
        SKIPPED_IDLE=$((SKIPPED_IDLE + 1))
        continue
    fi

    # Decide how to trigger this app's webhook based on its source type.
    if [[ "$SOURCE_TYPE" == "docker" ]]; then
        MODE="docker"
        REF=""
        SAMPLE=""
    else
        MODE="git"
        REF="refs/heads/${BRANCH}"
        # Strip psql array braces; derive one file path matching the first glob.
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
    DEPLOY_LIST="${DEPLOY_LIST}${DISPLAY_NAME}|${MODE}|${TOKEN}|${REF}|${SAMPLE}|${APPNAME}|${APPID}"$'\n'
done <<< "$APP_DATA"

DEPLOY_LIST=$(echo "$DEPLOY_LIST" | sed '/^$/d')

if [[ -z "$DEPLOY_LIST" ]]; then
    echo "No running applications to deploy."
    echo ""
    echo "[OK] FINAL STATUS"
    echo "=============================================================="
    echo "Updated   : 0"
    echo "Unchanged : 0"
    echo "Failed    : 0"
    echo "Skipped (idle) : $SKIPPED_IDLE"
    echo ""
    echo "[OK] SCRIPT COMPLETED"
    echo "=============================================================="
    exit 0
fi

DEPLOY_COUNT=$(echo "$DEPLOY_LIST" | wc -l)

# ============================================================================
# DEPLOY + VERIFY (per app, in parallel)
# ============================================================================
# Triggers the webhook, waits for the deployment to settle, and classifies the
# result by comparing the running image id before and after. Writes one result
# line (plus optional error detail) to $2.
deploy_one() {
    # Handle errors explicitly via status codes; a stray non-zero must not
    # abort the worker before it writes its result line.
    set +e
    local rec="$1" outfile="$2"
    local DISPLAY MODE TOKEN REF SAMPLE APPNAME APPID
    IFS='|' read -r DISPLAY MODE TOKEN REF SAMPLE APPNAME APPID <<< "$rec"

    local before after start elapsed
    before=$(image_id "$APPNAME")
    start=$(date +%s)

    # Newest existing deployment id, so we can detect the one we trigger.
    local last_dep
    last_dep=$(db "SELECT \"deploymentId\" FROM deployment WHERE \"applicationId\"='$APPID' ORDER BY \"createdAt\" DESC LIMIT 1")

    # Trigger the webhook
    local url="$DOKPLOY_LOCAL_URL/api/deploy/$TOKEN" code body
    if [[ "$MODE" == "docker" ]]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST "$url" 2>/dev/null)
    else
        if [[ -n "$SAMPLE" ]]; then
            body="{\"ref\":\"$REF\",\"commits\":[{\"modified\":[\"$SAMPLE\"]}]}"
        else
            body="{\"ref\":\"$REF\"}"
        fi
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST "$url" -H "x-github-event: push" -H "Content-Type: application/json" -d "$body" 2>/dev/null)
    fi

    if [[ "$code" != "200" ]]; then
        printf '[FAIL] %-28s trigger rejected (HTTP %s)\n' "$DISPLAY" "$code" > "$outfile"
        return
    fi

    # Wait for a NEW deployment row to reach done/error
    local dep_id status row
    dep_id=""; status=""
    while (( $(date +%s) - start < DEPLOY_TIMEOUT )); do
        row=$(db "SELECT \"deploymentId\", status FROM deployment WHERE \"applicationId\"='$APPID' ORDER BY \"createdAt\" DESC LIMIT 1")
        dep_id="${row%%|*}"
        status="${row#*|}"
        if [[ "$dep_id" != "$last_dep" && ( "$status" == "done" || "$status" == "error" ) ]]; then
            break
        fi
        sleep "$POLL_INTERVAL"
    done
    elapsed=$(( $(date +%s) - start ))
    after=$(image_id "$APPNAME")

    if [[ "$status" == "error" && "$dep_id" != "$last_dep" ]]; then
        local errmsg
        errmsg=$(db "SELECT COALESCE(\"errorMessage\",'') FROM deployment WHERE \"deploymentId\"='$dep_id'" | head -1)
        printf '[FAIL] %-28s deploy error (%ss)\n' "$DISPLAY" "$elapsed" > "$outfile"
        [[ -n "$errmsg" ]] && printf '       %s\n' "${errmsg:0:200}" >> "$outfile"
    elif [[ "$dep_id" == "$last_dep" || "$status" != "done" ]]; then
        printf '[WARN] %-28s not verified after %ss (still building?)\n' "$DISPLAY" "$elapsed" > "$outfile"
    elif [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
        printf '[OK]   %-28s updated  %s->%s  (%ss)\n' "$DISPLAY" "${before:0:6}" "${after:0:6}" "$elapsed" > "$outfile"
    elif [[ -n "$before" && "$before" == "$after" ]]; then
        printf '[OK]   %-28s no change  %s  (%ss)\n' "$DISPLAY" "${before:0:6}" "$elapsed" > "$outfile"
    else
        printf '[OK]   %-28s redeployed  (%ss)\n' "$DISPLAY" "$elapsed" > "$outfile"
    fi
}

echo ""
echo "[RUN] DEPLOYING $DEPLOY_COUNT APPLICATIONS (PARALLEL)"
echo "=============================================================="

RESULTS_DIR=$(mktemp -d)
IDX=0
while IFS= read -r REC; do
    IDX=$((IDX + 1))
    deploy_one "$REC" "$RESULTS_DIR/$(printf '%03d' "$IDX").out" &
done <<< "$DEPLOY_LIST"
wait

# Print results in the original (queued) order
RESULTS_FILE=$(mktemp)
cat "$RESULTS_DIR"/*.out > "$RESULTS_FILE" 2>/dev/null
cat "$RESULTS_FILE"
rm -rf "$RESULTS_DIR"

UPDATED=$(grep -c 'updated ' "$RESULTS_FILE" || true)
NOCHANGE=$(grep -cE 'no change|redeployed' "$RESULTS_FILE" || true)
FAILED=$(grep -c '^\[FAIL\]' "$RESULTS_FILE" || true)
WARNED=$(grep -c '^\[WARN\]' "$RESULTS_FILE" || true)
rm -f "$RESULTS_FILE"

# ============================================================================
# FINAL STATUS
# ============================================================================
RUN_ELAPSED=$(( $(date +%s) - RUN_START ))
ELAPSED_FMT="$((RUN_ELAPSED / 60))m$((RUN_ELAPSED % 60))s"

echo ""
echo "[OK] FINAL STATUS"
echo "=============================================================="
echo "Updated   : $UPDATED"
echo "Unchanged : $NOCHANGE"
echo "Failed    : $FAILED"
echo "Not verified : $WARNED"
echo "Skipped (idle) : $SKIPPED_IDLE"
echo "Elapsed   : $ELAPSED_FMT"

echo ""
if [[ "$FAILED" -gt 0 || "$WARNED" -gt 0 ]]; then
    echo "[ERROR] SCRIPT COMPLETED WITH FAILURES"
    echo "=============================================================="
    exit 1
fi

echo "[OK] SCRIPT COMPLETED"
echo "=============================================================="

exit 0
