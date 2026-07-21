#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Dokploy Deploy Running Apps                                  v3.7.1
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
#    the script needs no API key. Tuned for low-resource hosts (e.g. Pi Zero):
#    sequential deploys, load/memory gates, cooldowns, and a single-instance lock.
#
#  DATA SOURCES & PRIORITY
#
#    - Dokploy PostgreSQL database (application table: status, sourceType,
#      branch, watchPaths, refreshToken, appName, applicationId;
#      deployment table: status, errorMessage)
#    - Docker (swarm service -> running container image id, before/after)
#    - Local Dokploy deploy webhook (localhost:3000/api/deploy/<token>)
#    - Host /proc/loadavg and /proc/meminfo (resource gates between apps)
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - DOKPLOY_DB_CONTAINER: Name filter for Dokploy postgres container
#      - DOKPLOY_LOCAL_URL: Local Dokploy base URL
#      - DEPLOY_TIMEOUT: Max seconds to wait per app for a deploy to settle
#      - POLL_INTERVAL: Seconds between deployment-status checks
#      - DEPLOY_COOLDOWN: Seconds to rest after each app before the next
#      - MAX_LOAD: 1-min load ceiling before starting next app
#        (empty = 2*nproc; Docker hosts idle near nproc, so 1*nproc never
#        clears. Set 0 to disable the load gate.)
#      - MIN_FREE_MB: Min MemAvailable MB before starting next app (0=off)
#      - RESOURCE_WAIT_MAX: Max seconds to wait for headroom before proceeding
#
#  SETTINGS
#
#    Configuration defaults (low-resource profile):
#      - DOKPLOY_DB_CONTAINER: "dokploy-postgres" (container name filter)
#      - DOKPLOY_LOCAL_URL: "http://localhost:3000" (internal base URL)
#      - DEPLOY_TIMEOUT: 600 (seconds per app — git builds on small hosts)
#      - POLL_INTERVAL: 15 (seconds; fewer docker exec / psql polls)
#      - DEPLOY_COOLDOWN: 30 (seconds between apps)
#      - MAX_LOAD: empty (auto = 2*nproc; set 0 to disable)
#      - MIN_FREE_MB: 48 (set 0 to disable)
#      - RESOURCE_WAIT_MAX: 600 (seconds)
#
#  BEHAVIOR
#
#    1. Takes a non-blocking flock so overlapping schedule runs exit cleanly
#    2. Lowers own scheduling priority (nice/ionice best-effort)
#    3. Queries the Dokploy database for all applications
#    4. Skips applications with "idle" status
#    5. Orders queue: docker-source apps first (cheap), then git-source (builds)
#    6. For each non-idle app, one at a time:
#         a. Waits until load and free memory are under thresholds (or timeout)
#         b. Records the running image id (before)
#         c. Triggers the app's deploy webhook (docker: bare POST; git: a
#            GitHub-style push payload with branch + watchPaths-matched file)
#         d. Waits for the new deployment row to reach done/error (or timeout)
#         e. Records the running image id (after) and classifies the result
#         f. Prints that app's result, then cools down before the next app
#    7. Prints a summary and exits 1 if any app failed or could not be verified
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
#    0 - Success (all triggered deployments verified done), or another run
#        already holds the lock
#    1 - Failure (validation error, a deploy failed, or could not be verified)
#
#  EXAMPLE RUN
#
#    [RUN] DEPLOYING 11 APPLICATIONS (SEQUENTIAL, LOW-RESOURCE)
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
#  2026-07-20 v3.7.1 Auto MAX_LOAD is 2*nproc (was nproc). Docker hosts sit near
#                    nproc at "idle", so load < nproc blocked forever; only wait
#                    when load is thrashing. Log headroom waits at most every 30s.
#  2026-07-20 v3.7.0 Low-resource host profile: load/memory gates between apps,
#                    post-deploy cooldown, slower status polls, longer per-app
#                    timeout, docker-before-git queue order, single-instance flock,
#                    best-effort nice/ionice
#  2026-07-20 v3.6.0 Deploy apps sequentially (one at a time) instead of in
#                    parallel so builds do not contend for host CPU/disk/network
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
DEPLOY_TIMEOUT=600                                       # Max seconds to wait per app
POLL_INTERVAL=15                                         # Seconds between status checks
DEPLOY_COOLDOWN=30                                       # Seconds rest after each app
MAX_LOAD=""                                              # 1-min load ceiling; empty=2*nproc; 0=off
MIN_FREE_MB=48                                           # Min MemAvailable MB; 0=off
RESOURCE_WAIT_MAX=600                                    # Max seconds waiting for headroom
# ============================================================================

set -e
RUN_START=$(date +%s)

# Single-instance lock: overlapping schedule ticks exit 0 instead of stacking.
LOCK_FILE="/tmp/dokploy_running_apps_deploy.lock"
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
        echo ""
        echo "[WARN] Another deploy run is already active; exiting."
        echo "=============================================================="
        exit 0
    fi
fi

# Prefer not to fight production workloads for scheduler / disk IO.
renice +10 $$ >/dev/null 2>&1 || true
ionice -c3 -p $$ >/dev/null 2>&1 || true

# Resolve load ceiling once.
# Empty -> 2*nproc. Docker hosts with many containers often idle near nproc,
# so a ceiling of nproc never clears and the run stalls before app 1.
# "0" disables the load gate entirely.
if [[ -z "$MAX_LOAD" ]]; then
    MAX_LOAD=$(awk -v n="$(nproc 2>/dev/null || echo 1)" 'BEGIN {
        if (n + 0 < 1) n = 1
        printf "%.1f", n * 2
    }')
fi

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

# Current 1-min load average (empty if unreadable)
load_1m() {
    awk '{print $1}' /proc/loadavg 2>/dev/null
}

# MemAvailable in whole MiB (empty if unreadable)
free_mb() {
    awk '/MemAvailable:/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null
}

# True when load and free memory are within configured gates.
resources_ok() {
    local load free
    load=$(load_1m)
    free=$(free_mb)

    # Load gate (skip when MAX_LOAD is 0 or load unreadable)
    if [[ -n "$MAX_LOAD" && "$MAX_LOAD" != "0" && -n "$load" ]]; then
        if ! awk -v l="$load" -v max="$MAX_LOAD" 'BEGIN { exit !(l + 0 < max + 0) }'; then
            return 1
        fi
    fi

    # Memory gate (skip when MIN_FREE_MB is 0 or free unreadable)
    if [[ -n "$MIN_FREE_MB" && "$MIN_FREE_MB" -gt 0 && -n "$free" ]]; then
        if (( free < MIN_FREE_MB )); then
            return 1
        fi
    fi

    return 0
}

# Block until host has headroom (or RESOURCE_WAIT_MAX elapses). Proceeds anyway
# after the max so a stuck high-load host cannot hang the whole run forever.
wait_for_resources() {
    local label="$1"
    local start now load free waited last_log
    start=$(date +%s)
    last_log=-999

    if resources_ok; then
        return 0
    fi

    while true; do
        now=$(date +%s)
        waited=$((now - start))
        if (( waited >= RESOURCE_WAIT_MAX )); then
            load=$(load_1m)
            free=$(free_mb)
            echo "Proceeding without headroom for $label (waited ${waited}s; load=${load:-?} free=${free:-?}MB)"
            return 0
        fi
        if resources_ok; then
            if (( last_log >= 0 )); then
                echo "Headroom ok for $label after ${waited}s"
            fi
            return 0
        fi
        # Log at most once every 30s (not on every poll).
        if (( waited - last_log >= 30 )); then
            load=$(load_1m)
            free=$(free_mb)
            echo "Waiting for headroom before $label (load=${load:-?} free=${free:-?}MB / need load<${MAX_LOAD} free>=${MIN_FREE_MB}MB; max ${RESOURCE_WAIT_MAX}s)"
            last_log=$waited
        fi
        sleep 5
    done
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

# Docker-source redeploys are usually image pulls; git-source often builds.
# Run the cheap ones first so heavy builds do not delay the light queue.
DEPLOY_LIST=$(
    printf '%s\n' "$DEPLOY_LIST" | awk -F'|' '$2 == "docker"'
    printf '%s\n' "$DEPLOY_LIST" | awk -F'|' '$2 != "docker" && NF'
)
DEPLOY_LIST=$(echo "$DEPLOY_LIST" | sed '/^$/d')

DEPLOY_COUNT=$(echo "$DEPLOY_LIST" | wc -l)
echo "Queue order : docker-source first, then git-source ($DEPLOY_COUNT apps)"
echo "Resource gates : load < ${MAX_LOAD} | free >= ${MIN_FREE_MB}MB | cooldown ${DEPLOY_COOLDOWN}s"

# ============================================================================
# DEPLOY + VERIFY (per app, sequential — one at a time)
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
    set -e
}

echo ""
echo "[RUN] DEPLOYING $DEPLOY_COUNT APPLICATIONS (SEQUENTIAL, LOW-RESOURCE)"
echo "=============================================================="

RESULTS_FILE=$(mktemp)
IDX=0
while IFS= read -r REC; do
    IDX=$((IDX + 1))
    DISPLAY_PREVIEW="${REC%%|*}"

    wait_for_resources "$DISPLAY_PREVIEW"

    OUTFILE=$(mktemp)
    deploy_one "$REC" "$OUTFILE"
    cat "$OUTFILE"
    cat "$OUTFILE" >> "$RESULTS_FILE"
    rm -f "$OUTFILE"

    # Rest between apps so RAM/IO can settle (skip after the last one).
    if (( IDX < DEPLOY_COUNT && DEPLOY_COOLDOWN > 0 )); then
        echo "Cooldown ${DEPLOY_COOLDOWN}s before next app..."
        sleep "$DEPLOY_COOLDOWN"
    fi
done <<< "$DEPLOY_LIST"

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
