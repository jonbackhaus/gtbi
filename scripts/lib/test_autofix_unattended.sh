#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for autofix_unattended.sh
# Run: bash scripts/lib/test_autofix_unattended.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module
source "$SCRIPT_DIR/autofix_unattended.sh"

TESTS_PASSED=0
TESTS_FAILED=0

setup_autofix_state_dir() {
    local state_dir="$1"
    export GTBI_STATE_DIR="$state_dir"
    export GTBI_CHANGES_FILE="$GTBI_STATE_DIR/changes.jsonl"
    export GTBI_UNDOS_FILE="$GTBI_STATE_DIR/undos.jsonl"
    export GTBI_BACKUPS_DIR="$GTBI_STATE_DIR/backups"
    export GTBI_LOCK_FILE="$GTBI_STATE_DIR/.lock"
    export GTBI_INTEGRITY_FILE="$GTBI_STATE_DIR/.integrity"

    GTBI_CHANGE_RECORDS=()
    GTBI_CHANGE_ORDER=()
    GTBI_SESSION_ID=""
    GTBI_AUTOFIX_INITIALIZED=false
    GTBI_AUTOFIX_LOCK_FD=""

    rm -rf "$GTBI_STATE_DIR"
    mkdir -p "$GTBI_BACKUPS_DIR"
    : > "$GTBI_CHANGES_FILE"
    : > "$GTBI_UNDOS_FILE"
}

cleanup_test_dir() {
    local test_dir="$1"
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

test_pass() {
    local name="$1"
    echo -e "\033[32m[PASS]\033[0m $name"
    ((++TESTS_PASSED))
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "\033[31m[FAIL]\033[0m $name"
    [[ -n "$reason" ]] && echo "       Reason: $reason"
    ((++TESTS_FAILED))
}

# Test: Check function returns valid JSON
test_check_returns_json() {
    local result
    result=$(autofix_unattended_upgrades_check 2>/dev/null)

    if ! echo "$result" | jq . &>/dev/null; then
        test_fail "check_returns_json" "Output is not valid JSON"
        return
    fi

    # Verify required fields exist
    local status
    status=$(echo "$result" | jq -r '.status')
    if [[ -z "$status" ]]; then
        test_fail "check_returns_json" "Missing 'status' field"
        return
    fi

    local held_locks
    held_locks=$(echo "$result" | jq -r '.held_locks | type')
    if [[ "$held_locks" != "array" ]]; then
        test_fail "check_returns_json" "held_locks should be array"
        return
    fi

    test_pass "check_returns_json"
}

# Test: Check returns valid status values
test_check_valid_status() {
    local result
    result=$(autofix_unattended_upgrades_check 2>/dev/null)
    local status
    status=$(echo "$result" | jq -r '.status')

    case "$status" in
        none|active|locks_held|processes_running)
            test_pass "check_valid_status ($status)"
            ;;
        *)
            test_fail "check_valid_status" "Unknown status: $status"
            ;;
    esac
}

# Test: needs_fix function returns boolean-like result
test_needs_fix_returns_correctly() {
    # This function uses exit codes, so test that behavior
    local result
    if autofix_unattended_upgrades_needs_fix 2>/dev/null; then
        result="needs_fix"
    else
        result="clean"
    fi

    # Either result is valid depending on system state
    if [[ "$result" == "needs_fix" || "$result" == "clean" ]]; then
        test_pass "needs_fix_returns_correctly (returned: $result)"
    else
        test_fail "needs_fix_returns_correctly" "Invalid result"
    fi
}

# Test: Dry-run mode doesn't modify system
test_dry_run_no_changes() {
    # Get state before
    local before_active="false"
    if systemctl is-active unattended-upgrades &>/dev/null 2>&1; then
        before_active="true"
    fi

    # Run dry-run
    autofix_unattended_upgrades_fix "dry-run" &>/dev/null

    # Get state after
    local after_active="false"
    if systemctl is-active unattended-upgrades &>/dev/null 2>&1; then
        after_active="true"
    fi

    if [[ "$before_active" == "$after_active" ]]; then
        test_pass "dry_run_no_changes"
    else
        test_fail "dry_run_no_changes" "System state changed during dry-run"
    fi
}

test_fix_manages_session_and_records_changes() {
    local test_dir="/tmp/test_autofix_unattended_fix_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if ! (
        sudo() { "$@"; }
        autofix_unattended_upgrades_check() {
            jq -n \
                --arg status "active" \
                --arg details "test fixture" \
                '{status: $status, details: $details, held_locks: [], apt_pids: ""}'
        }
        systemctl() {
            case "${1:-}" in
                is-active) return 0 ;;
                is-enabled) return 1 ;;
                stop|start) return 0 ;;
            esac
            return 0
        }
        pgrep() { return 1; }
        # Treat any real host lock file as actively held so the fixture never
        # mutates /var/lib/dpkg/* or other system apt locks.
        fuser() { return 0; }
        dpkg() { return 0; }
        apt-get() { return 0; }

        autofix_unattended_upgrades_fix "fix"
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "fix mode failed in isolated fixture"
        return
    fi

    if [[ -f "$GTBI_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "session marker was left behind after standalone fix"
        return
    fi

    if ! jq -e 'select(.category == "unattended")' "$GTBI_CHANGES_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "standalone fix did not record unattended changes"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "fix_manages_session_and_records_changes"
}

test_restore_manages_session_and_persists_marker() {
    local test_dir="/tmp/test_autofix_unattended_restore_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    cat > "$GTBI_CHANGES_FILE" <<'EOF'
{"id":"chg_0001","category":"unattended","description":"Stopped unattended-upgrades service","session_id":"sess_fixture"}
EOF

    if ! (
        sudo() { "$@"; }
        systemctl() {
            case "${1:-}" in
                start) return 0 ;;
            esac
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "restore mode failed in isolated fixture"
        return
    fi

    if [[ -f "$GTBI_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "session marker was left behind after restore"
        return
    fi

    if ! jq -e 'select(.auto_restored == "unattended-upgrades")' "$GTBI_UNDOS_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "restore did not persist unattended auto-restore marker"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_manages_session_and_persists_marker"
}

test_restore_fails_closed_on_unresolved_session_marker() {
    local test_dir="/tmp/test_autofix_unattended_restore_incomplete_$$"
    local state_dir="$test_dir/state"
    local sentinel="$test_dir/systemctl-started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    cat > "$GTBI_CHANGES_FILE" <<'EOF'
{"id":"chg_0001","category":"unattended","description":"Stopped unattended-upgrades service","session_id":"sess_fixture"}
EOF

    cat > "$GTBI_UNDOS_FILE" <<'EOF'
{"auto_restored":"unattended-upgrades","timestamp":"2026-04-16T00:00:00Z"}
EOF

    cat > "$GTBI_STATE_DIR/.session" <<'EOF'
{"id":"sess_stale","start":"2026-04-16T00:00:00Z","pid":123}
EOF

    if (
        sudo() { "$@"; }
        systemctl() {
            case "${1:-}" in
                start)
                    : > "$sentinel"
                    return 0
                    ;;
            esac
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "restore unexpectedly succeeded with a stale session marker"
        return
    fi

    if [[ -f "$sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "restore attempted to start unattended-upgrades despite inconsistent autofix state"
        return
    fi

    if [[ ! -f "$GTBI_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "stale session marker was unexpectedly removed"
        return
    fi

    if ! jq -e 'select(.auto_restored == "unattended-upgrades")' "$GTBI_UNDOS_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "existing auto-restore marker was unexpectedly removed"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_fails_closed_on_unresolved_session_marker"
}

test_stop_service_rolls_back_when_record_change_fails() {
    local test_dir="/tmp/test_autofix_unattended_stop_rollback_$$"
    local state_dir="$test_dir/state"
    local stopped_sentinel="$test_dir/stopped"
    local started_sentinel="$test_dir/started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if (
        sudo() { "$@"; }
        # shellcheck disable=SC2123
        PATH="/definitely-missing-for-this-test"

        systemctl() {
            case "${1:-}" in
                is-active|is-enabled) return 0 ;;
                stop)
                    : > "$stopped_sentinel"
                    return 0
                    ;;
                start)
                    : > "$started_sentinel"
                    return 0
                    ;;
            esac
            return 0
        }

        record_change() {
            return 1
        }

        _autofix_stop_unattended_service
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop unexpectedly succeeded when record_change failed"
        return
    fi

    if [[ ! -f "$stopped_sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop was not attempted"
        return
    fi

    if [[ ! -f "$started_sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service was not restarted after journaling failure"
        return
    fi

    if [[ -s "$GTBI_CHANGES_FILE" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop wrote change records despite journaling failure"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "stop_service_rolls_back_when_record_change_fails"
}

test_kill_stuck_processes_does_not_record_failed_kill() {
    local test_dir="/tmp/test_autofix_unattended_kill_failure_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if (
        sudo() { "$@"; }
        pgrep() {
            if [[ "${1:-}" == "-x" ]]; then
                echo "123"
                return 0
            fi
            return 1
        }

        pkill() {
            return 0
        }

        _autofix_kill_stuck_processes
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "kill_stuck_processes_does_not_record_failed_kill" "kill helper unexpectedly succeeded while processes still appeared alive"
        return
    fi

    if [[ -s "$GTBI_CHANGES_FILE" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "kill_stuck_processes_does_not_record_failed_kill" "failed kill still wrote a change record"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "kill_stuck_processes_does_not_record_failed_kill"
}

# Test: CLI modes work
test_cli_modes() {
    local failed=0

    # Test check mode
    if ! bash "$SCRIPT_DIR/autofix_unattended.sh" check &>/dev/null; then
        failed=$((failed + 1))
        echo "       check mode failed"
    fi

    # Test dry-run mode
    if ! bash "$SCRIPT_DIR/autofix_unattended.sh" dry-run &>/dev/null; then
        failed=$((failed + 1))
        echo "       dry-run mode failed"
    fi

    # Test help (invalid mode shows usage)
    if bash "$SCRIPT_DIR/autofix_unattended.sh" --help &>/dev/null 2>&1; then
        # Should exit 1 for unknown mode
        :
    fi

    if [[ $failed -eq 0 ]]; then
        test_pass "cli_modes"
    else
        test_fail "cli_modes" "$failed mode(s) failed"
    fi
}

# Test: Lock file list is properly defined
test_lock_file_constants() {
    if [[ ${#APT_LOCK_FILES[@]} -lt 3 ]]; then
        test_fail "lock_file_constants" "Should have at least 3 lock files defined"
        return
    fi

    # All paths should be absolute
    for lock in "${APT_LOCK_FILES[@]}"; do
        if [[ "$lock" != /* ]]; then
            test_fail "lock_file_constants" "Lock path not absolute: $lock"
            return
        fi
    done

    test_pass "lock_file_constants"
}

# Run all tests
main() {
    echo "==========================================="
    echo "Running autofix_unattended.sh unit tests"
    echo "==========================================="

    test_check_returns_json
    test_check_valid_status
    test_needs_fix_returns_correctly
    test_dry_run_no_changes
    test_fix_manages_session_and_records_changes
    test_restore_manages_session_and_persists_marker
    test_restore_fails_closed_on_unresolved_session_marker
    test_stop_service_rolls_back_when_record_change_fails
    test_kill_stuck_processes_does_not_record_failed_kill
    test_cli_modes
    test_lock_file_constants

    echo "==========================================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    echo "All tests passed!"
    exit 0
}

main "$@"
