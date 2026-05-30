#!/usr/bin/env bash
# ============================================================
# E2E Test: git_safety_guard Complete Removal Verification
#
# Verifies that git_safety_guard has been completely removed and
# replaced with DCG (Destructive Command Guard).
#
# Related: bead bd-33vh.8
#
# Usage:
#   # Run inside Docker container after install:
#   ./tests/e2e/test_git_safety_guard_removal.sh --user ubuntu --home /home/ubuntu
#
#   # Or run locally as a specific user:
#   ./tests/e2e/test_git_safety_guard_removal.sh --user $(whoami) --home "$HOME"
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
# ============================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/git_safety_guard_removal_test_${TIMESTAMP}.log"
RESULTS_FILE="/tmp/git_safety_guard_removal_results_${TIMESTAMP}.json"

# Parse arguments
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOME="${TARGET_HOME:-/home/ubuntu}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) TARGET_USER="$2"; shift 2 ;;
        --home) TARGET_HOME="$2"; shift 2 ;;
        --help) head -30 "$0" | grep -E '^#' | sed 's/^# //'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Results tracking
PASSED=0
FAILED=0
RESULTS_JSON=""

# Logging functions
log() {
    local level="$1" test_name="$2" message="$3"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] [%s] %s\n' "$ts" "$level" "$test_name" "$message" | tee -a "$LOG_FILE"
}

record_result() {
    local test_name="$1" status="$2" message="$3"
    if [[ "$status" == "pass" ]]; then
        ((PASSED++)) || true
        log "PASS" "$test_name" "$message"
    else
        ((FAILED++)) || true
        log "FAIL" "$test_name" "$message"
    fi
    # Append to JSON results
    if [[ -n "$RESULTS_JSON" ]]; then
        RESULTS_JSON="${RESULTS_JSON},"
    fi
    RESULTS_JSON="${RESULTS_JSON}\"${test_name}\":{\"status\":\"${status}\",\"message\":\"${message}\"}"
}

# Initialize log
{
    echo "=== git_safety_guard Removal E2E Test ==="
    echo "Timestamp: $(date)"
    echo "User: $TARGET_USER"
    echo "Home: $TARGET_HOME"
    echo ""
} > "$LOG_FILE"

log "INFO" "init" "Starting git_safety_guard removal verification"
log "INFO" "init" "Target user: $TARGET_USER, Home: $TARGET_HOME"

# ============================================================
# Test Case 1: No gtbi/claude/hooks/ directory
# ============================================================
log "INFO" "test" "Checking for hooks directory..."
hooks_dir="${TARGET_HOME}/.gtbi/claude/hooks"
if [[ -d "$hooks_dir" ]]; then
    record_result "hooks_directory" "fail" "Directory exists: $hooks_dir"
else
    record_result "hooks_directory" "pass" "No hooks directory"
fi

# ============================================================
# Test Case 2: No git_safety_guard.py file
# ============================================================
log "INFO" "test" "Checking for git_safety_guard.py..."
found_guard_py=false
for loc in "${TARGET_HOME}/.gtbi/claude/hooks/git_safety_guard.py" "${TARGET_HOME}/.claude/hooks/git_safety_guard.py"; do
    if [[ -f "$loc" ]]; then
        record_result "guard_py_file" "fail" "File exists: $loc"
        found_guard_py=true
        break
    fi
done
if [[ "$found_guard_py" == "false" ]]; then
    record_result "guard_py_file" "pass" "No git_safety_guard.py found"
fi

# ============================================================
# Test Case 3: Doctor output verification
# ============================================================
log "INFO" "test" "Checking doctor output..."
doctor_output=""
# Use timeout to prevent hanging (60s should be plenty for a fresh install)
if command -v gtbi >/dev/null 2>&1; then
    doctor_output=$(timeout 60 gtbi doctor 2>&1 || true)
elif [[ -f "${REPO_ROOT}/scripts/lib/doctor.sh" ]]; then
    # For local testing, skip doctor (takes too long without full setup)
    log "INFO" "test" "Skipping doctor check (local run without gtbi command)"
fi

if [[ -n "$doctor_output" ]]; then
    # Check for git_safety_guard mentions (should NOT exist)
    if echo "$doctor_output" | grep -qi 'git.safety.guard'; then
        record_result "doctor_no_guard" "fail" "Doctor mentions git_safety_guard"
    else
        record_result "doctor_no_guard" "pass" "Doctor clean of git_safety_guard"
    fi

    # Check for DCG mentions (should exist)
    if echo "$doctor_output" | grep -qiE 'DCG|Destructive Command Guard'; then
        record_result "doctor_has_dcg" "pass" "Doctor mentions DCG"
    else
        record_result "doctor_has_dcg" "fail" "Doctor does not mention DCG"
    fi
else
    log "INFO" "test" "Could not run doctor (skipping doctor checks)"
fi

# ============================================================
# Test Case 4: Settings.json verification
# ============================================================
log "INFO" "test" "Checking settings.json..."
settings_file=""
for loc in "${TARGET_HOME}/.claude/settings.json" "${TARGET_HOME}/.config/claude/settings.json"; do
    if [[ -f "$loc" ]]; then
        settings_file="$loc"
        break
    fi
done

if [[ -n "$settings_file" ]]; then
    if grep -q 'git_safety_guard' "$settings_file" 2>/dev/null; then
        record_result "settings_json" "fail" "settings.json contains git_safety_guard"
    else
        record_result "settings_json" "pass" "settings.json clean"
    fi
else
    record_result "settings_json" "pass" "No settings.json (OK for fresh install)"
fi

# ============================================================
# Test Case 5: Install log verification (if available)
# ============================================================
log "INFO" "test" "Checking install logs..."
install_log=""
for loc in "/repo/tests/artifacts/install.log" "${REPO_ROOT}/tests/artifacts/install.log"; do
    if [[ -f "$loc" ]]; then
        install_log="$loc"
        break
    fi
done

if [[ -n "$install_log" ]]; then
    if grep -qi 'Git Safety Guard' "$install_log" 2>/dev/null; then
        record_result "install_log_no_guard" "fail" "Install log mentions 'Git Safety Guard'"
    else
        record_result "install_log_no_guard" "pass" "Install log clean of 'Git Safety Guard'"
    fi

    if grep -qiE 'DCG|Destructive Command Guard' "$install_log" 2>/dev/null; then
        record_result "install_log_has_dcg" "pass" "Install log mentions DCG"
    else
        record_result "install_log_has_dcg" "fail" "Install log does not mention DCG"
    fi
else
    log "INFO" "test" "Install log not found (skipping install log checks)"
fi

# ============================================================
# Test Case 6: Codebase audit
# ============================================================
log "INFO" "test" "Running codebase audit..."
audit_script="${REPO_ROOT}/scripts/tests/audit_git_safety_guard_removal.sh"
if [[ -f "$audit_script" ]]; then
    if bash "$audit_script" >> "$LOG_FILE" 2>&1; then
        record_result "codebase_audit" "pass" "Audit passed"
    else
        record_result "codebase_audit" "fail" "Audit found references"
    fi
else
    log "INFO" "test" "Audit script not found (skipping)"
fi

# ============================================================
# Generate JSON results
# ============================================================
cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "user": "$TARGET_USER",
  "home": "$TARGET_HOME",
  "passed": $PASSED,
  "failed": $FAILED,
  "results": {$RESULTS_JSON}
}
EOF

# ============================================================
# Summary
# ============================================================
echo "" | tee -a "$LOG_FILE"
echo "=== Test Summary ===" | tee -a "$LOG_FILE"
echo "Passed: $PASSED" | tee -a "$LOG_FILE"
echo "Failed: $FAILED" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE"
echo "Results JSON: $RESULTS_FILE"

if [[ $FAILED -gt 0 ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "❌ VERIFICATION FAILED - git_safety_guard artifacts detected" | tee -a "$LOG_FILE"
    exit 1
else
    echo "" | tee -a "$LOG_FILE"
    echo "✅ VERIFICATION PASSED - git_safety_guard completely removed" | tee -a "$LOG_FILE"
    exit 0
fi
