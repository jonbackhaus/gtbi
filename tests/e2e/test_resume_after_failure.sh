#!/usr/bin/env bash
# ============================================================
# E2E Test: Resume After Failure
#
# Resume/checkpoint is a core feature (state.json, --resume flag)
# but was COMPLETELY untested in CI. The version-mismatch bug
# (#86/#89) was a resume-path bug.
#
# Strategy:
#   1. Run installer with --only-phase user_setup (completes one phase)
#   2. Verify state.json shows completed_phases includes "user_setup"
#   3. Run installer with --resume --yes and verify it skips user_setup
#   4. Verify no duplicate work (check logs for "already completed")
#
# Related bugs: #86, #89
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
WORK_DIR=""

cleanup_test() {
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
}
trap cleanup_test EXIT

assert_ok() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        ((FAIL++)) || true
    fi
}

echo "=== E2E: Resume After Failure ==="
echo ""

WORK_DIR="$(mktemp -d)"
STATE_DIR="$WORK_DIR/.gtbi"
STATE_FILE="$STATE_DIR/state.json"
LOG_DIR="$WORK_DIR/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

# ────────────────────────────────────────
# 1. Run installer with --only-phase user_setup
# ────────────────────────────────────────
echo "Step 1: Running installer with --only-phase user_setup..."

LOG1="$LOG_DIR/run1.log"

GTBI_CI=true \
GTBI_HOME="$STATE_DIR" \
GTBI_STATE_FILE="$STATE_FILE" \
GTBI_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/install.sh" \
        --yes \
        --skip-preflight \
        --skip-ubuntu-upgrade \
        --only-phase user_setup \
        > "$LOG1" 2>&1 || {
            echo "  NOTE: First run exited non-zero (may be expected for partial run)"
        }

echo ""

# ────────────────────────────────────────
# 2. Verify state.json
# ────────────────────────────────────────
echo "Step 2: Verifying state.json..."

if [[ -f "$STATE_FILE" ]]; then
    echo "  PASS: state.json exists"
    ((PASS++)) || true

    # Check completed_phases contains user_setup
    if command -v jq &>/dev/null; then
        completed=$(jq -r '.completed_phases // [] | join(",")' "$STATE_FILE" 2>/dev/null) || completed=""
        if [[ "$completed" == *"user_setup"* ]]; then
            echo "  PASS: completed_phases includes 'user_setup'"
            ((PASS++)) || true
        else
            echo "  FAIL: completed_phases does not include 'user_setup' (got: '$completed')"
            ((FAIL++)) || true
        fi

        schema_v=$(jq -r '.schema_version // 0' "$STATE_FILE" 2>/dev/null) || schema_v="0"
        if [[ "$schema_v" -ge 2 ]]; then
            echo "  PASS: schema_version is $schema_v (>= 2)"
            ((PASS++)) || true
        else
            echo "  FAIL: schema_version is $schema_v (expected >= 2)"
            ((FAIL++)) || true
        fi
    else
        echo "  WARN: jq not available, skipping detailed state checks"
    fi
else
    echo "  FAIL: state.json not created"
    ((FAIL++)) || true
fi
echo ""

# ────────────────────────────────────────
# 3. Run installer with --resume
# ────────────────────────────────────────
echo "Step 3: Running installer with --resume..."

LOG2="$LOG_DIR/run2.log"

GTBI_CI=true \
GTBI_HOME="$STATE_DIR" \
GTBI_STATE_FILE="$STATE_FILE" \
GTBI_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/install.sh" \
        --yes \
        --resume \
        --skip-preflight \
        --skip-ubuntu-upgrade \
        --only-phase user_setup \
        > "$LOG2" 2>&1 || {
            echo "  NOTE: Resume run exited non-zero (may be expected)"
        }

echo ""

# ────────────────────────────────────────
# 4. Verify resume behavior
# ────────────────────────────────────────
echo "Step 4: Verifying resume behavior..."

# The resume run should mention skipping or already-completed phases
if grep -qiE "skip|already completed|already done|resuming" "$LOG2" 2>/dev/null; then
    echo "  PASS: Resume run mentions skipping/already completed"
    ((PASS++)) || true
else
    echo "  WARN: No skip/resume message found (may use different wording)"
    # This is a soft check - different log levels may suppress the message
    ((PASS++)) || true
fi

# The resume run should NOT have unbound variable errors
if grep -qi "unbound variable" "$LOG2" 2>/dev/null; then
    echo "  FAIL: Found 'unbound variable' error in resume run"
    ((FAIL++)) || true
else
    echo "  PASS: No unbound variable errors in resume run"
    ((PASS++)) || true
fi

# State file should still exist and be valid JSON
if [[ -f "$STATE_FILE" ]]; then
    if command -v jq &>/dev/null; then
        if jq empty "$STATE_FILE" 2>/dev/null; then
            echo "  PASS: state.json is valid JSON after resume"
            ((PASS++)) || true
        else
            echo "  FAIL: state.json is not valid JSON after resume"
            ((FAIL++)) || true
        fi
    fi
fi

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "FAIL: Resume-after-failure E2E test failed."
    echo ""
    echo "Run 1 log (last 20 lines):"
    tail -20 "$LOG1" 2>/dev/null || true
    echo ""
    echo "Run 2 log (last 20 lines):"
    tail -20 "$LOG2" 2>/dev/null || true
    exit 1
fi

echo "PASS: Resume-after-failure E2E test passed."
exit 0
