#!/bin/bash
#
# ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
# ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
# ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
# ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
# ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
# ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ================================================================================
#  SCRIPT   : Dokploy Deploy Running Apps                                  v3.9.0
#  AUTHOR   : Limehawk.io
#  DATE     : October 2026
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
#    Docker Compose stacks are covered the same way. Docker-source apps and
#    stacks whose images have not changed are left alone (no restart).
#    Because every app already carries its own webhook token in the database,
#    the script needs no API key. Tuned for low-resource hosts (e.g. Pi Zero):
#    sequential deploys, load/memory gates, cooldowns, and a single-instance lock.
#
#  DATA SOURCES & PRIORITY
#
#    - Dokploy PostgreSQL database (application table: status, sourceType,
#      branch, watchPaths, refreshToken, appName, applicationId, dockerImage,
#      autoDeploy; compose table: composeStatus, refreshToken, appName,
#      composeId, autoDeploy;
#      deployment table: status, errorMessage)
#    - Docker (swarm service -> running container image id, before/after;
#      compose project label -> every container's image for stacks;
#      docker pull of each docker-source / stack image to check for a newer one)
#    - Local Dokploy deploy webhooks (localhost:3000/api/deploy/<token>,
#      localhost:3000/api/deploy/compose/<token>)
#    - Host /proc/loadavg and /proc/meminfo (resource gates between apps)
#
#  REQUIRED INPUTS
#
#    All inputs are hardcoded in the script body:
#      - DOKPLOY_DB_CONTAINER: Name filter for Dokploy postgres container
#      - DOKPLOY_LOCAL_URL: Local Dokploy base URL
#      - DEPLOY_TIMEOUT: Max seconds to wait per app for a deploy to settle
#      - POLL_INTERVAL: Seconds between deployment-status checks
#      - DEPLOY_COOLDOWN: Seconds to rest after a deploy that changed something
#      - MAX_LOAD: 1-min load ceiling before starting next app (0 = off;
#        empty = 2*nproc). Off by default: Docker hosts idle near nproc so a
#        load gate stalls the run while free RAM is still fine. Sequential
#        deploys + cooldown + free-RAM gate are the real protection.
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
#      - DEPLOY_COOLDOWN: 30 (seconds; only after updates or failed builds)
#      - MAX_LOAD: 0 (disabled; set e.g. 4 or empty for 2*nproc if needed)
#      - MIN_FREE_MB: 48 (set 0 to disable)
#      - RESOURCE_WAIT_MAX: 600 (seconds)
#
#  BEHAVIOR
#
#    1. Takes a non-blocking flock so overlapping schedule runs exit cleanly
#    2. Lowers own scheduling priority (nice/ionice best-effort)
#    3. Queries the Dokploy database for all applications and compose stacks
#    4. Skips applications with "idle" status or with Auto Deploy turned off
#    5. Orders queue: docker-source apps first (cheap), then git-source (builds)
#    6. For each non-idle app, one at a time:
#         a. Records the running image id (before)
#         b. Docker-source / compose: pulls the image(s); if everything running
#            already has the newest, reports "up to date" and moves on (no
#            deploy, no cooldown)
#         c. If the previous deploy changed something, cools down first
#         d. Waits until load and free memory are under thresholds (or timeout)
#         e. Triggers the deploy webhook (docker / compose: bare POST; git: a
#            GitHub-style push payload with branch + watchPaths-matched file)
#         f. Waits for the new deployment row to reach done/error (or timeout)
#         g. Records the running image id (after) and prints the result
#    7. Prints a summary and exits 1 if any app failed or could not be verified
#
#  PREREQUISITES
#
#    - Script must run on the Dokploy host server (Dokploy schedule or cron)
#    - Dokploy postgres container accessible via docker exec
#    - docker and curl installed
#    - Apps with "Auto Deploy" off are skipped — the webhook rejects them
#
#  SECURITY NOTES
#
#    - No API key or stored secret: each app's own webhook token is read from
#      the local database at runtime and used only against localhost
#    - No secrets in logs (only app names, image ids, and outcomes are printed)
#    - Webhook and database calls are localhost-only; the only outbound
#      traffic is docker pull to each app's own image registry
#
#  ENDPOINTS
#
#    - http://localhost:3000/api/deploy/<refreshToken> (per-app deploy webhook)
#    - http://localhost:3000/api/deploy/compose/<refreshToken> (per-stack)
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
#    [OK]   wiki/app             up to date  a1d0f7
#    [OK]   chat/app             updated  9f3c1a->b47e02  (16s)
#    Cooldown 30s before docs/site...
#    [FAIL] docs/site            deploy error (52s)
#           build failed: npm ERR! missing script: build
#
#    [OK] FINAL STATUS
#    ==============================================================
#    Updated   : 7
#    Unchanged : 3
#    Failed    : 1
#    Skipped (idle) : 9
#    Skipped (auto deploy off) : 0
#    Elapsed   : 2m03s
#
#    [OK] SCRIPT COMPLETED
#    ==============================================================
#
# --------------------------------------------------------------------------------
#  CHANGELOG
# --------------------------------------------------------------------------------
#  2026-10-23 v3.9.0 Cover Docker Compose stacks: pull every image in the stack,
#                    skip if all current, else trigger the compose webhook and
#                    verify like apps.
#  2026-10-23 v3.8.1 Skip apps with Auto Deploy off instead of failing them
#                    (webhook returns HTTP 400). Print the webhook's reply
#                    when a trigger is rejected.
#  2026-10-23 v3.8.0 Pull docker-source images first and skip apps already on
#                    the newest image (no needless restart). Cool down only
#                    after a deploy that changed something, not after no-ops.
#                    Count results directly instead of grepping output.
#  2026-07-20 v3.7.2 Default MAX_LOAD=0 (load gate off). Live host idles at
#                    load 2–4 on 2 cores with 1.5GB+ free; load waits wasted
#                    minutes while deploys themselves finish in ~15s. Rely on
#                    sequential + cooldown + free-RAM gate instead.
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
MAX_LOAD=0                                               # 1-min load ceiling; 0=off; empty=2*nproc
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
# "0" (default) disables the load gate — busy Docker hosts idle near nproc.
# Empty -> 2*nproc for hosts that still want a thrash ceiling.
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

DB_CONTAINER=$(docker ps -q -f "name=$DOKPLOY_DB_CONTAINER" | head -1)

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

# "image-ref image-id" for every container of a compose stack.
stack_images() {
    docker ps -aq --filter "label=com.docker.compose.project=$1" \
        | xargs -r docker inspect -f '{{.Config.Image}} {{.Image}}' 2>/dev/null \
        | sed 's/sha256://' | sort -u
}

# What is running now: an app's container image id, or for a compose stack a
# hash of all its containers' image ids. Empty if nothing is running.
fingerprint() {
    local mode="$1" name="$2" ids
    if [[ "$mode" == "compose" ]]; then
        ids=$(stack_images "$name" | awk '{print $2}' | sort)
        [[ -n "$ids" ]] && md5sum <<< "$ids" | cut -d' ' -f1
    else
        image_id "$name"
    fi
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
# appName, id, dockerImage, autoDeploy (pipe-delimited, no headers).
# Compose stacks come back with sourceType "compose" and no branch/image.
APP_DATA=$(db "SELECT p.name, a.name, a.\"applicationStatus\"::text, a.\"sourceType\"::text, a.branch, a.\"watchPaths\"::text, a.\"refreshToken\", a.\"appName\", a.\"applicationId\", a.\"dockerImage\", a.\"autoDeploy\" FROM application a JOIN environment e ON a.\"environmentId\" = e.\"environmentId\" JOIN project p ON e.\"projectId\" = p.\"projectId\"
    UNION ALL
    SELECT p.name, c.name, c.\"composeStatus\"::text, 'compose', '', '', c.\"refreshToken\", c.\"appName\", c.\"composeId\", '', c.\"autoDeploy\" FROM compose c JOIN environment e ON c.\"environmentId\" = e.\"environmentId\" JOIN project p ON e.\"projectId\" = p.\"projectId\"")

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
SKIPPED_NOAUTO=0
DEPLOY_LIST=""

while IFS='|' read -r PROJECT_NAME APP_NAME APP_STATUS SOURCE_TYPE BRANCH WATCHPATHS TOKEN APPNAME APPID IMAGE AUTODEPLOY; do
    DISPLAY_NAME="$PROJECT_NAME/$APP_NAME"

    if [[ "$APP_STATUS" == "idle" ]]; then
        echo "Skipping idle app : $DISPLAY_NAME"
        SKIPPED_IDLE=$((SKIPPED_IDLE + 1))
        continue
    fi

    # The deploy webhook rejects apps with Auto Deploy off (HTTP 400).
    if [[ "$AUTODEPLOY" != "t" ]]; then
        echo "Skipping app (auto deploy off) : $DISPLAY_NAME"
        SKIPPED_NOAUTO=$((SKIPPED_NOAUTO + 1))
        continue
    fi

    # Decide how to trigger this app's webhook based on its source type.
    if [[ "$SOURCE_TYPE" == "docker" || "$SOURCE_TYPE" == "compose" ]]; then
        MODE="$SOURCE_TYPE"
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
    DEPLOY_LIST="${DEPLOY_LIST}${DISPLAY_NAME}|${MODE}|${TOKEN}|${REF}|${SAMPLE}|${APPNAME}|${APPID}|${IMAGE}"$'\n'
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
    echo "Skipped (auto deploy off) : $SKIPPED_NOAUTO"
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
echo "Queue order : docker-source first, then compose and git-source ($DEPLOY_COUNT apps)"
if [[ "$MAX_LOAD" == "0" ]]; then
    echo "Resource gates : load off | free >= ${MIN_FREE_MB}MB | cooldown ${DEPLOY_COOLDOWN}s after changes"
else
    echo "Resource gates : load < ${MAX_LOAD} | free >= ${MIN_FREE_MB}MB | cooldown ${DEPLOY_COOLDOWN}s after changes"
fi

# ============================================================================
# DEPLOY + VERIFY (per app, sequential — one at a time)
# ============================================================================
# Docker-source only: pull the app's image and compare it with the running
# container. True when the container already runs the newest image, so the
# redeploy (a container restart) can be skipped. Any doubt -> false -> deploy.
image_current() {
    local image="$1" running="$2" latest
    [[ -n "$image" && -n "$running" ]] || return 1
    docker pull -q "$image" >/dev/null 2>&1 || return 1
    latest=$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null | sed 's/^sha256://')
    [[ -n "$latest" && "$latest" == "$running" ]]
}

# Compose: true only when every container in the stack is current.
stack_current() {
    local ref id any=1
    while read -r ref id; do
        image_current "$ref" "$id" || return 1
        any=0
    done < <(stack_images "$1")
    return $any
}

# Triggers the webhook, waits for the deployment to settle, and classifies the
# result by comparing the running image id before and after. Prints the result
# line and sets RESULT (updated|unchanged|failed|unverified) and COOLDOWN_DUE
# (true when the host did real work and should rest before the next deploy).
deploy_one() {
    local DISPLAY="$1" MODE="$2" TOKEN="$3" REF="$4" SAMPLE="$5" APPNAME="$6" APPID="$7" before="$8"
    local after start elapsed last_dep url code body reply dep_id status row errmsg idcol
    start=$(date +%s)
    COOLDOWN_DUE=true
    idcol="applicationId"
    [[ "$MODE" == "compose" ]] && idcol="composeId"

    # Newest existing deployment id, so we can detect the one we trigger.
    last_dep=$(db "SELECT \"deploymentId\" FROM deployment WHERE \"$idcol\"='$APPID' ORDER BY \"createdAt\" DESC LIMIT 1")

    # Trigger the webhook
    url="$DOKPLOY_LOCAL_URL/api/deploy/$TOKEN"
    [[ "$MODE" == "compose" ]] && url="$DOKPLOY_LOCAL_URL/api/deploy/compose/$TOKEN"
    if [[ "$MODE" == "docker" || "$MODE" == "compose" ]]; then
        reply=$(curl -s -w '\n%{http_code}' --max-time 60 -X POST "$url" 2>/dev/null)
    else
        if [[ -n "$SAMPLE" ]]; then
            body="{\"ref\":\"$REF\",\"commits\":[{\"modified\":[\"$SAMPLE\"]}]}"
        else
            body="{\"ref\":\"$REF\"}"
        fi
        reply=$(curl -s -w '\n%{http_code}' --max-time 60 -X POST "$url" -H "x-github-event: push" -H "Content-Type: application/json" -d "$body" 2>/dev/null)
    fi

    code="${reply##*$'\n'}"
    if [[ "$code" != "200" ]]; then
        printf '[FAIL] %-28s trigger rejected (HTTP %s)\n' "$DISPLAY" "$code"
        reply="${reply%$'\n'*}"
        [[ -n "$reply" ]] && printf '       %s\n' "${reply:0:200}"
        RESULT=failed
        COOLDOWN_DUE=false
        return
    fi

    # Wait for a NEW deployment row to reach done/error
    dep_id=""; status=""
    while (( $(date +%s) - start < DEPLOY_TIMEOUT )); do
        row=$(db "SELECT \"deploymentId\", status FROM deployment WHERE \"$idcol\"='$APPID' ORDER BY \"createdAt\" DESC LIMIT 1")
        dep_id="${row%%|*}"
        status="${row#*|}"
        if [[ "$dep_id" != "$last_dep" && ( "$status" == "done" || "$status" == "error" ) ]]; then
            break
        fi
        sleep "$POLL_INTERVAL"
    done
    elapsed=$(( $(date +%s) - start ))
    after=$(fingerprint "$MODE" "$APPNAME")

    if [[ "$status" == "error" && "$dep_id" != "$last_dep" ]]; then
        errmsg=$(db "SELECT COALESCE(\"errorMessage\",'') FROM deployment WHERE \"deploymentId\"='$dep_id'" | head -1)
        printf '[FAIL] %-28s deploy error (%ss)\n' "$DISPLAY" "$elapsed"
        [[ -n "$errmsg" ]] && printf '       %s\n' "${errmsg:0:200}"
        RESULT=failed
    elif [[ "$dep_id" == "$last_dep" || "$status" != "done" ]]; then
        printf '[WARN] %-28s not verified after %ss (still building?)\n' "$DISPLAY" "$elapsed"
        RESULT=unverified
    elif [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
        printf '[OK]   %-28s updated  %s->%s  (%ss)\n' "$DISPLAY" "${before:0:6}" "${after:0:6}" "$elapsed"
        RESULT=updated
    elif [[ -n "$before" && "$before" == "$after" ]]; then
        printf '[OK]   %-28s no change  %s  (%ss)\n' "$DISPLAY" "${before:0:6}" "$elapsed"
        RESULT=unchanged
        COOLDOWN_DUE=false
    else
        printf '[OK]   %-28s redeployed  (%ss)\n' "$DISPLAY" "$elapsed"
        RESULT=unchanged
    fi
}

echo ""
echo "[RUN] DEPLOYING $DEPLOY_COUNT APPLICATIONS (SEQUENTIAL, LOW-RESOURCE)"
echo "=============================================================="

# Per-app errors are reported through RESULT; a stray non-zero (a db poll, a
# missing container) must not end the run halfway through the queue.
set +e
UPDATED=0
NOCHANGE=0
FAILED=0
WARNED=0
COOLDOWN_DUE=false

while IFS='|' read -r DISPLAY MODE TOKEN REF SAMPLE APPNAME APPID IMAGE; do
    BEFORE=$(fingerprint "$MODE" "$APPNAME")

    if { [[ "$MODE" == "docker" ]] && image_current "$IMAGE" "$BEFORE"; } \
        || { [[ "$MODE" == "compose" ]] && stack_current "$APPNAME"; }; then
        printf '[OK]   %-28s up to date  %s\n' "$DISPLAY" "${BEFORE:0:6}"
        NOCHANGE=$((NOCHANGE + 1))
        continue
    fi

    # Rest only after a deploy that did real work, never after a no-op.
    if [[ "$COOLDOWN_DUE" == true ]] && (( DEPLOY_COOLDOWN > 0 )); then
        echo "Cooldown ${DEPLOY_COOLDOWN}s before $DISPLAY..."
        sleep "$DEPLOY_COOLDOWN"
    fi
    wait_for_resources "$DISPLAY"

    deploy_one "$DISPLAY" "$MODE" "$TOKEN" "$REF" "$SAMPLE" "$APPNAME" "$APPID" "$BEFORE"
    case "$RESULT" in
        updated)    UPDATED=$((UPDATED + 1)) ;;
        unchanged)  NOCHANGE=$((NOCHANGE + 1)) ;;
        failed)     FAILED=$((FAILED + 1)) ;;
        unverified) WARNED=$((WARNED + 1)) ;;
    esac
done <<< "$DEPLOY_LIST"

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
echo "Skipped (auto deploy off) : $SKIPPED_NOAUTO"
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
