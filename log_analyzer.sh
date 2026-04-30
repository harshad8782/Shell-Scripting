#!/bin/bash
# ============================================================
# log_analyzer.sh — DevOps-Integrated Log Analysis
#
# USE CASE:
#   Runs as a Jenkins pipeline stage after application
#   deployment. Analyzes Docker container logs, fails the
#   pipeline if critical errors are found (blocking bad
#   deployments), creates GitHub issues for warnings, and
#   sends email with attached stats report to the DevOps team.
#
#   Integrated with:
#     - Jenkins  : exit codes control pipeline pass/fail
#     - Docker   : pulls logs directly from running container
#     - GitHub   : auto-creates issues for error threshold breaches
#     - Email    : sends HTML email with .txt stats report attached
#
# Exit Codes:
#   0 = clean        → Jenkins: SUCCESS
#   1 = config error → Jenkins: FAILURE
#   2 = warnings     → Jenkins: UNSTABLE
#   3 = critical     → Jenkins: FAILURE (blocks deploy)
# ============================================================

set -uo pipefail

# ─────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────

CONTAINER_NAME="${CONTAINER_NAME:-devops-app}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Use PWD as fallback — PWD is always the Jenkins workspace when run via sh step
REPORT_DIR="${WORKSPACE:-$PWD}/reports"
STATS_FILE="$REPORT_DIR/log_stats_${CONTAINER_NAME}_${TIMESTAMP}.txt"

ERROR_PATTERNS=("ERROR" "FATAL" "CRITICAL" "EXCEPTION")
WARN_PATTERNS=("WARN" "WARNING" "DEPRECATED")
CRITICAL_THRESHOLD=5
WARN_THRESHOLD=10
LOG_LINES=500

BUILD_URL="${BUILD_URL:-local}"
JOB_NAME="${JOB_NAME:-local}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"

ALERT_EMAIL="${ALERT_EMAIL:-devops@company.com}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO="${GITHUB_REPO:-harshad8782/DevOps-CICD}"

# ─────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ─────────────────────────────────────────
# STEP 1 — VALIDATE
# ─────────────────────────────────────────

validate() {
    log "Validating environment..."
    log "REPORT_DIR resolved to: $REPORT_DIR"
    log "STATS_FILE will be: $STATS_FILE"

    if ! command -v docker &> /dev/null; then
        log "ERROR: Docker not found"
        exit 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "ERROR: Container '$CONTAINER_NAME' is not running"
        exit 1
    fi

    mkdir -p "$REPORT_DIR" || {
        log "ERROR: Cannot create report directory $REPORT_DIR"
        exit 1
    }

    log "Report directory created: $REPORT_DIR"
    log "Validation passed. Container '$CONTAINER_NAME' is running."
}

# ─────────────────────────────────────────
# STEP 2 — FETCH DOCKER LOGS
# ─────────────────────────────────────────

fetch_container_logs() {
    log "Fetching last $LOG_LINES lines from container: $CONTAINER_NAME"
    TEMP_LOG=$(mktemp /tmp/container_log_XXXX.log)
    docker logs "$CONTAINER_NAME" --tail "$LOG_LINES" > "$TEMP_LOG" 2>&1
    log "Fetched $(wc -l < "$TEMP_LOG") log lines"
    echo "$TEMP_LOG"
}

# ─────────────────────────────────────────
# STEP 3 — ANALYZE + WRITE STATS FILE
# ─────────────────────────────────────────

analyze_logs() {
    local log_file="$1"
    local critical_found=0
    local warn_found=0
    local total_issues=0

    log "Writing stats file: $STATS_FILE"

    cat > "$STATS_FILE" << EOF
====================================================
  LOG ANALYSIS STATS REPORT
====================================================
Generated     : $(date '+%Y-%m-%d %H:%M:%S')
Container     : $CONTAINER_NAME
Jenkins Job   : $JOB_NAME
Build Number  : #$BUILD_NUMBER
Build URL     : $BUILD_URL
Lines Scanned : $LOG_LINES
Alert Email   : $ALERT_EMAIL
====================================================

--------------------------------------------------
  CRITICAL ERROR PATTERNS  (threshold: $CRITICAL_THRESHOLD)
--------------------------------------------------
EOF

    for pattern in "${ERROR_PATTERNS[@]}"; do
        local count
        count=$(grep -i -c "$pattern" "$log_file" 2>/dev/null || echo 0)
        total_issues=$((total_issues + count))

        echo "  $pattern : $count occurrences" >> "$STATS_FILE"

        if [ "$count" -gt 0 ]; then
            echo "  Last 3 occurrences:" >> "$STATS_FILE"
            grep -i "$pattern" "$log_file" | tail -3 | sed 's/^/    -> /' >> "$STATS_FILE"
        fi

        if [ "$count" -gt "$CRITICAL_THRESHOLD" ]; then
            critical_found=$((critical_found + 1))
            echo "  !! THRESHOLD EXCEEDED — pipeline will be blocked" >> "$STATS_FILE"
            log "CRITICAL: '$pattern' count ($count) exceeds threshold ($CRITICAL_THRESHOLD)"
        fi

        echo "" >> "$STATS_FILE"
    done

    cat >> "$STATS_FILE" << EOF
--------------------------------------------------
  WARNING PATTERNS  (threshold: $WARN_THRESHOLD)
--------------------------------------------------
EOF

    for pattern in "${WARN_PATTERNS[@]}"; do
        local count
        count=$(grep -i -c "$pattern" "$log_file" 2>/dev/null || echo 0)

        echo "  $pattern : $count occurrences" >> "$STATS_FILE"

        if [ "$count" -gt "$WARN_THRESHOLD" ]; then
            warn_found=$((warn_found + 1))
            echo "  !! THRESHOLD EXCEEDED — pipeline marked unstable" >> "$STATS_FILE"
            log "WARNING: '$pattern' count ($count) exceeds threshold ($WARN_THRESHOLD)"
        fi

        echo "" >> "$STATS_FILE"
    done

    log "Stats file written successfully: $STATS_FILE"
    ls -lh "$STATS_FILE"

    echo "$critical_found $warn_found $total_issues"
}

# ─────────────────────────────────────────
# STEP 4 — WRITE SUMMARY TO STATS FILE
# ─────────────────────────────────────────

write_summary() {
    local status="$1"
    local critical="$2"
    local warnings="$3"
    local total="$4"

    cat >> "$STATS_FILE" << EOF
====================================================
  PIPELINE DECISION SUMMARY
====================================================
Status          : $status
Critical Issues : $critical pattern(s) exceeded threshold
Warnings        : $warnings pattern(s) exceeded threshold
Total Issues    : $total

Action          : $(decision_text "$status")

Next Steps      :
$(next_steps "$status")
====================================================
EOF

    log "Summary written to stats file"
    log "Final stats file location: $STATS_FILE"
}

decision_text() {
    case "$1" in
        "PASSED")   echo "All checks passed. Deployment is proceeding." ;;
        "UNSTABLE") echo "Warnings found. Deployment allowed but review required." ;;
        "FAILED")   echo "Critical errors found. Deployment has been BLOCKED." ;;
    esac
}

next_steps() {
    case "$1" in
        "PASSED")
            echo "  No action required. Monitor production for anomalies."
            ;;
        "UNSTABLE")
            echo "  1. Review warning patterns in the attached stats report
  2. Investigate root cause before next deployment
  3. Consider adding fixes in next sprint"
            ;;
        "FAILED")
            echo "  1. Review critical errors in the attached stats report
  2. Check GitHub — an issue has been auto-created
  3. Fix the errors and re-trigger the Jenkins pipeline
  4. Do NOT manually deploy — pipeline is blocked for safety"
            ;;
    esac
}

# ─────────────────────────────────────────
# STEP 5 — CREATE GITHUB ISSUE
# ─────────────────────────────────────────

create_github_issue() {
    local title="$1"
    local body="$2"

    [ -z "$GITHUB_TOKEN" ] && {
        log "GITHUB_TOKEN not set — skipping GitHub issue creation"
        return 0
    }

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPO}/issues" \
        -d "{
            \"title\": \"$title\",
            \"body\": \"$body\",
            \"labels\": [\"bug\", \"devops\", \"auto-generated\"]
        }")

    local issue_url
    issue_url=$(echo "$response" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
    log "GitHub issue created: $issue_url"
}

# ─────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────

main() {
    log "============================================"
    log "  Log Analyzer — DevOps CI/CD Integration"
    log "  Container : $CONTAINER_NAME"
    log "  Job       : $JOB_NAME #$BUILD_NUMBER"
    log "  Alerting  : $ALERT_EMAIL"
    log "  PWD       : $PWD"
    log "  WORKSPACE : ${WORKSPACE:-NOT SET}"
    log "  REPORT_DIR: $REPORT_DIR"
    log "============================================"

    validate

    TEMP_LOG=$(fetch_container_logs)

    read -r critical_count warn_count total_issues <<< "$(analyze_logs "$TEMP_LOG")"

    rm -f "$TEMP_LOG"

    if [ "$critical_count" -gt 0 ]; then
        STATUS="FAILED"
        write_summary "$STATUS" "$critical_count" "$warn_count" "$total_issues"

        create_github_issue \
            "Critical log errors in $CONTAINER_NAME — Build #$BUILD_NUMBER" \
            "Log analysis failed for container \`$CONTAINER_NAME\` in Jenkins job \`$JOB_NAME\` build #$BUILD_NUMBER.\n\nCritical patterns exceeded threshold: $critical_count\nTotal issues found: $total_issues\n\nBuild URL: $BUILD_URL\n\n*Auto-generated by log_analyzer.sh*"

        log "Result: FAILED — $critical_count critical issue(s). Deployment blocked."
        exit 3

    elif [ "$warn_count" -gt 0 ]; then
        STATUS="UNSTABLE"
        write_summary "$STATUS" "$critical_count" "$warn_count" "$total_issues"

        log "Result: UNSTABLE — $warn_count warning(s). Deployment allowed."
        exit 2

    else
        STATUS="PASSED"
        write_summary "$STATUS" "0" "0" "$total_issues"

        log "Result: PASSED — No issues found. Deployment proceeding."
        exit 0
    fi
}

main "$@"