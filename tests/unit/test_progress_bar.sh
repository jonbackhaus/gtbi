#!/usr/bin/env bash
# Unit tests for ACFS progress bar library
# Related: bead bd-21kh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the progress library
source "$REPO_ROOT/scripts/lib/progress.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    ((TESTS_PASSED++))
    echo "PASS: $*"
}

fail() {
    ((TESTS_FAILED++))
    echo "FAIL: $*"
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    echo ""
    echo "Running: $test_name"
}

# Test 1: progress_init sets variables correctly
test_progress_init() {
    run_test "progress_init sets variables"

    progress_init 10

    if [[ "$ACFS_PROGRESS_TOTAL" == "10" ]]; then
        pass "ACFS_PROGRESS_TOTAL set to 10"
    else
        fail "ACFS_PROGRESS_TOTAL is '$ACFS_PROGRESS_TOTAL', expected '10'"
    fi

    if [[ "$ACFS_PROGRESS_CURRENT" == "0" ]]; then
        pass "ACFS_PROGRESS_CURRENT starts at 0"
    else
        fail "ACFS_PROGRESS_CURRENT is '$ACFS_PROGRESS_CURRENT', expected '0'"
    fi
}

# Test 2: progress_update increments counter
test_progress_update() {
    run_test "progress_update increments counter"

    progress_init 5
    progress_update "module1" >/dev/null 2>&1

    if [[ "$ACFS_PROGRESS_CURRENT" == "1" ]]; then
        pass "Counter incremented to 1"
    else
        fail "Counter is '$ACFS_PROGRESS_CURRENT', expected '1'"
    fi

    progress_update "module2" >/dev/null 2>&1
    progress_update "module3" >/dev/null 2>&1

    if [[ "$ACFS_PROGRESS_CURRENT" == "3" ]]; then
        pass "Counter incremented to 3"
    else
        fail "Counter is '$ACFS_PROGRESS_CURRENT', expected '3'"
    fi
}

test_progress_update_without_init() {
    run_test "progress_update before init is a no-op"

    local output
    local status=0
    output=$(/usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        progress_update "before-init" >/dev/null 2>&1
        printf "after\n"
    ' _ "$REPO_ROOT/scripts/lib/progress.sh" 2>&1) || status=$?

    if [[ "$status" -eq 0 && "$output" == "after" ]]; then
        pass "progress_update survived without initialized total"
    else
        fail "progress_update before init status/output was '$status/$output', expected '0/after'"
    fi
}

# Test 3: _progress_bar generates correct bar
test_progress_bar() {
    run_test "_progress_bar generates ASCII bar"

    local bar

    bar="$(_progress_bar 0 10 10)"
    if [[ "$bar" == "░░░░░░░░░░" ]]; then
        pass "0% bar correct"
    else
        fail "0% bar is '$bar', expected '░░░░░░░░░░'"
    fi

    bar="$(_progress_bar 5 10 10)"
    if [[ "$bar" == "█████░░░░░" ]]; then
        pass "50% bar correct"
    else
        fail "50% bar is '$bar', expected '█████░░░░░'"
    fi

    bar="$(_progress_bar 10 10 10)"
    if [[ "$bar" == "██████████" ]]; then
        pass "100% bar correct"
    else
        fail "100% bar is '$bar', expected '██████████'"
    fi
}

# Test 4: progress_finish resets state
test_progress_finish() {
    run_test "progress_finish resets state"

    progress_init 10
    ACFS_PROGRESS_CURRENT=5
    progress_finish 2>/dev/null

    if [[ "$ACFS_PROGRESS_TOTAL" == "0" ]]; then
        pass "ACFS_PROGRESS_TOTAL reset to 0"
    else
        fail "ACFS_PROGRESS_TOTAL is '$ACFS_PROGRESS_TOTAL', expected '0'"
    fi

    if [[ "$ACFS_PROGRESS_CURRENT" == "0" ]]; then
        pass "ACFS_PROGRESS_CURRENT reset to 0"
    else
        fail "ACFS_PROGRESS_CURRENT is '$ACFS_PROGRESS_CURRENT', expected '0'"
    fi
}

# Test 5: NO_COLOR disables TTY mode
test_no_color() {
    run_test "NO_COLOR environment variable"

    export NO_COLOR=1
    _progress_check_tty

    if [[ "$ACFS_PROGRESS_IS_TTY" == "false" ]]; then
        pass "NO_COLOR disables TTY mode"
    else
        fail "ACFS_PROGRESS_IS_TTY is '$ACFS_PROGRESS_IS_TTY', expected 'false'"
    fi

    unset NO_COLOR
}

# Run all tests
main() {
    echo "========================================="
    echo "ACFS Progress Bar Unit Tests"
    echo "========================================="

    test_progress_init
    test_progress_update
    test_progress_update_without_init
    test_progress_bar
    test_progress_finish
    test_no_color

    echo ""
    echo "========================================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed (total: $TESTS_RUN)"
    echo "========================================="

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
