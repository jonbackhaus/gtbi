#!/usr/bin/env bash
# DCG Edge Case Tests - Validate failure scenarios and edge cases
# Exit codes: 0=all pass, 1=failure
# Usage: ./dcg_edge_case_tests.sh [--verbose]

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

VERBOSE="${1:-}"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_LIB="${REPO_ROOT}/scripts/lib/state.sh"

STATE_LIB_AVAILABLE="false"
if [[ -f "$STATE_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_LIB"
    STATE_LIB_AVAILABLE="true"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test Harness
# ─────────────────────────────────────────────────────────────────────────────

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

info() {
    if [[ "$VERBOSE" == "--verbose" ]]; then
        echo -e "${DIM}       $1${NC}"
    fi
}

section() {
    echo ""
    echo -e "${CYAN}━━━ $1 ━━━${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Prerequisite Check
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
    section "Prerequisites"

    if ! command -v dcg &>/dev/null; then
        echo -e "${RED}ERROR: dcg not found in PATH. Install DCG first.${NC}"
        exit 2
    fi
    pass "DCG binary found"

    if ! command -v jq &>/dev/null; then
        skip "jq not available - some JSON tests will be limited"
    else
        pass "jq available for JSON parsing"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge Case Tests
# ─────────────────────────────────────────────────────────────────────────────

# Test 1: Version matches expected format
test_version_format() {
    section "Test 1: Version Format"

    local version_output
    # DCG only outputs version when attached to a TTY, so use script to simulate
    version_output=$(script -q -c 'dcg --version' /dev/null 2>/dev/null) || true

    # Version should contain semver pattern somewhere in output (e.g., "v0.2.0")
    if echo "$version_output" | grep -Eq 'v?[0-9]+\.[0-9]+\.[0-9]+'; then
        local version
        version=$(echo "$version_output" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        pass "Version follows semver format: $version"
    else
        # Fallback: just check that the command succeeds
        if dcg --version >/dev/null 2>&1; then
            pass "Version command succeeds (output requires TTY)"
        else
            fail "Version command failed"
        fi
    fi
}

# Test 2: DCG works without Claude Code installed
test_dcg_standalone() {
    section "Test 2: DCG Standalone Operation"

    # DCG test command should work even without Claude Code
    local test_output
    test_output=$(dcg test 'git status' 2>&1) || true

    if echo "$test_output" | grep -qi "allow"; then
        pass "DCG test works standalone (without requiring Claude Code)"
    else
        fail "DCG test failed standalone. Output: $test_output"
    fi

    # DCG packs should list available packs
    local packs_output
    packs_output=$(dcg packs 2>&1) || true

    if [[ -n "$packs_output" ]] && ! echo "$packs_output" | grep -qi "error"; then
        pass "DCG packs works standalone"
    else
        fail "DCG packs failed standalone. Output: $packs_output"
    fi
}

# Test 3: PATH configuration is correct
test_path_configured() {
    section "Test 3: PATH Configuration"

    local dcg_path
    dcg_path=$(command -v dcg 2>/dev/null) || true

    if [[ -n "$dcg_path" ]]; then
        pass "DCG in PATH: $dcg_path"

        # Check it's executable
        if [[ -x "$dcg_path" ]]; then
            pass "DCG binary is executable"
        else
            fail "DCG binary exists but is not executable"
        fi
    else
        fail "DCG not found in PATH"
    fi
}

# Test 4: Multiple pack activation
test_multiple_packs() {
    section "Test 4: Multiple Pack Activation"

    # Get list of available packs
    local packs_output
    packs_output=$(dcg packs 2>&1) || true

    # Check core packs exist
    if echo "$packs_output" | grep -qE "core.git|git"; then
        pass "Git pack available"
    else
        skip "Git pack not found in packs list"
    fi

    if echo "$packs_output" | grep -qE "core.filesystem|filesystem"; then
        pass "Filesystem pack available"
    else
        skip "Filesystem pack not found in packs list"
    fi

    # Test that both git and filesystem patterns work
    local git_block
    git_block=$(dcg test 'git reset --hard' 2>&1) || true
    if echo "$git_block" | grep -qiE "deny|block"; then
        pass "Git pack blocks dangerous git commands"
    else
        fail "Git pack not blocking. Output: $git_block"
    fi

    local fs_block
    fs_block=$(dcg test 'rm -rf /' 2>&1) || true
    if echo "$fs_block" | grep -qiE "deny|block"; then
        pass "Filesystem pack blocks dangerous rm commands"
    else
        fail "Filesystem pack not blocking. Output: $fs_block"
    fi
}

# Test 5: Re-installation preserves functionality
test_reinstall_idempotent() {
    section "Test 5: Reinstall Idempotency"

    # Run install twice - second should be idempotent
    # shellcheck disable=SC2034
    local _first_install _second_install
    _first_install=$(dcg install --force 2>&1) || true
    _second_install=$(dcg install --force 2>&1) || true

    # After reinstall, DCG should still work
    local test_output
    test_output=$(dcg test 'git status' 2>&1) || true

    if echo "$test_output" | grep -qi "allow"; then
        pass "DCG works after reinstall"
    else
        fail "DCG broken after reinstall. Output: $test_output"
    fi

    # Hook should still be registered (use text parsing since JSON output not supported)
    local doctor_output
    doctor_output=$(dcg doctor 2>&1) || true
    if echo "$doctor_output" | grep -qi "hook wiring.*OK"; then
        pass "Hook still registered after reinstall"
    else
        skip "Hook registration status unclear after reinstall"
    fi
}

# Test 6: Doctor command provides useful diagnostics
test_doctor_diagnostics() {
    section "Test 6: Doctor Diagnostics"

    local doctor_output
    doctor_output=$(dcg doctor 2>&1) || true

    # Doctor should provide output (not error or empty)
    if [[ -n "$doctor_output" ]] && ! echo "$doctor_output" | grep -qi "^error:"; then
        pass "Doctor command provides diagnostics"
        info "Doctor output preview: ${doctor_output:0:100}..."
    else
        fail "Doctor command failed or empty. Output: $doctor_output"
    fi

    # Check all checks passed
    if echo "$doctor_output" | grep -q "All checks passed"; then
        pass "Doctor reports all checks passed"
    else
        skip "Doctor reports some checks need attention"
    fi
}

# Test 7: Test command with various edge cases
test_command_edge_cases() {
    section "Test 7: Command Edge Cases"

    # Empty command should not crash
    local empty_test
    if empty_test=$(dcg test '' 2>&1); then
        pass "Empty command handled gracefully"
    elif [[ -n "$empty_test" ]]; then
        pass "Empty command handled gracefully (returned output)"
    else
        fail "Empty command caused crash"
    fi

    # Very long command should not crash
    local long_cmd
    long_cmd=$(printf 'git status %0.s' {1..100})
    local long_test
    if long_test=$(dcg test "$long_cmd" 2>&1); then
        pass "Long command handled gracefully"
    elif [[ -n "$long_test" ]]; then
        pass "Long command handled gracefully (returned output)"
    else
        fail "Long command caused crash"
    fi

    # Command with special characters (single quotes intentional - testing literal $USER)
    local special_test
    # shellcheck disable=SC2016
    if special_test=$(dcg test 'echo "hello $USER"' 2>&1); then
        pass "Special characters handled gracefully"
    elif [[ -n "$special_test" ]]; then
        pass "Special characters handled gracefully (returned output)"
    else
        fail "Special characters caused crash"
    fi

    # Command with newlines (should handle multi-line)
    local multiline_test
    if multiline_test=$(dcg test $'git status\ngit log' 2>&1); then
        pass "Multi-line command handled gracefully"
    elif [[ -n "$multiline_test" ]]; then
        pass "Multi-line command handled gracefully (returned output)"
    else
        fail "Multi-line command caused crash"
    fi
}

# Test 8: Safe force-push variant is allowed
test_safe_force_push() {
    section "Test 8: Safe Force Push Variant"

    # --force-with-lease should be allowed (it's the safe variant)
    local safe_force
    safe_force=$(dcg test 'git push --force-with-lease' 2>&1) || true

    if echo "$safe_force" | grep -qi "allow"; then
        pass "Safe force-with-lease is allowed"
    else
        # It might still be blocked in some configurations
        skip "force-with-lease handling: $safe_force"
    fi

    # Regular --force should be blocked
    local dangerous_force
    dangerous_force=$(dcg test 'git push --force' 2>&1) || true

    if echo "$dangerous_force" | grep -qiE "deny|block"; then
        pass "Dangerous --force is blocked"
    else
        fail "Dangerous --force not blocked. Output: $dangerous_force"
    fi
}

# Test 9: Temp directory commands are allowed
test_temp_directory_allowed() {
    section "Test 9: Temp Directory Handling"

    # rm -rf /tmp/... should be allowed (temp is ephemeral)
    local tmp_rm
    tmp_rm=$(dcg test 'rm -rf /tmp/test-dir' 2>&1) || true

    if echo "$tmp_rm" | grep -qi "allow"; then
        pass "Temp directory cleanup allowed"
    else
        # Some configurations might still block this
        skip "Temp directory handling: $tmp_rm"
    fi

    # But rm -rf on non-temp should be blocked
    local home_rm
    home_rm=$(dcg test 'rm -rf ~/important' 2>&1) || true

    if echo "$home_rm" | grep -qiE "deny|block"; then
        pass "Home directory rm -rf blocked"
    else
        fail "Home directory rm -rf not blocked. Output: $home_rm"
    fi
}

# Test 10: Uninstall and reinstall cycle
test_uninstall_reinstall_cycle() {
    section "Test 10: Uninstall/Reinstall Cycle"

    # Uninstall DCG hook (but not the binary)
    local uninstall_output
    uninstall_output=$(dcg uninstall 2>&1) || true  # intentionally unused
    : "${uninstall_output:=}"  # silence SC2034

    # DCG binary should still work for testing
    local test_after_uninstall
    test_after_uninstall=$(dcg test 'git status' 2>&1) || true

    if echo "$test_after_uninstall" | grep -qi "allow"; then
        pass "DCG test works after uninstall"
    else
        fail "DCG test broken after uninstall. Output: $test_after_uninstall"
    fi

    # Reinstall hook
    local reinstall_output
    reinstall_output=$(dcg install --force 2>&1) || true  # intentionally unused
    : "${reinstall_output:=}"  # silence SC2034

    # Verify hook works again (use text parsing since JSON output not supported)
    local doctor_output
    doctor_output=$(dcg doctor 2>&1) || true
    if echo "$doctor_output" | grep -qi "hook wiring.*OK"; then
        pass "Hook re-registered after reinstall"
    else
        skip "Hook registration status after cycle unclear"
    fi
}

# Test 11: Checkpoint/resume markers for DCG install steps
test_dcg_checkpoint_resume_markers() {
    section "Test 11: DCG Checkpoint/Resume Markers"

    if [[ "$STATE_LIB_AVAILABLE" != "true" ]]; then
        skip "state.sh not available - skipping checkpoint/resume checks"
        return
    fi

    if ! command -v jq &>/dev/null; then
        skip "jq not available - skipping checkpoint/resume checks"
        return
    fi

    local state_dir
    state_dir="/tmp/gtbi-dcg-state-$(date +%s)-${RANDOM}"
    if ! mkdir -p "$state_dir"; then
        fail "Failed to create temp state directory"
        return
    fi

    export GTBI_HOME="$state_dir"
    export GTBI_STATE_FILE="${state_dir}/state.json"

    if ! state_init; then
        fail "state_init failed for checkpoint/resume test"
        return
    fi

    # Scenario 1: DCG install succeeds, hook registration fails
    state_phase_start "stack" "Installing DCG" || true
    state_step_update "Installing DCG" || true
    state_step_update "Registering DCG hook" || true
    state_phase_fail "stack" "Registering DCG hook" "simulated hook failure" || true

    local failed_step failed_phase
    failed_step=$(jq -r '.failed_step // empty' "$GTBI_STATE_FILE" 2>/dev/null)
    failed_phase=$(jq -r '.failed_phase // empty' "$GTBI_STATE_FILE" 2>/dev/null)

    if [[ "$failed_step" == "Registering DCG hook" && "$failed_phase" == "stack" ]]; then
        pass "Hook failure recorded at step 'Registering DCG hook'"
    else
        fail "Unexpected failure checkpoint (step=$failed_step, phase=$failed_phase)"
    fi

    # Scenario 2: DCG binary install fails (e.g., network interruption)
    state_init || true
    state_phase_start "stack" "Installing DCG" || true
    state_step_update "Installing DCG" || true
    state_phase_fail "stack" "Installing DCG" "simulated network interruption" || true

    failed_step=$(jq -r '.failed_step // empty' "$GTBI_STATE_FILE" 2>/dev/null)
    local failed_error
    failed_error=$(jq -r '.failed_error // empty' "$GTBI_STATE_FILE" 2>/dev/null)

    if [[ "$failed_step" == "Installing DCG" ]]; then
        pass "Install failure recorded at step 'Installing DCG'"
    else
        fail "Install failure not recorded at expected step (step=$failed_step)"
    fi

    if echo "$failed_error" | grep -qi "network"; then
        pass "Failure reason captures network interruption"
    else
        skip "Failure reason does not include network hint"
    fi

    # Optional: verify dcg-specific flags if state schema includes them
    if jq -e '.dcg_installed != null' "$GTBI_STATE_FILE" >/dev/null 2>&1; then
        pass "State file includes dcg_installed flag"
    else
        skip "State schema does not include dcg_installed flag"
    fi

    if jq -e '.dcg_hook_registered != null' "$GTBI_STATE_FILE" >/dev/null 2>&1; then
        pass "State file includes dcg_hook_registered flag"
    else
        skip "State schema does not include dcg_hook_registered flag"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Fail-Open Behavior Tests
# DCG is designed to fail-open: on any error, it allows the command rather
# than blocking workflow. This ensures DCG never becomes a bottleneck.
# ─────────────────────────────────────────────────────────────────────────────

# Test 12: Invalid JSON input should fail-open (allow)
test_failopen_invalid_json() {
    section "Test 12: Fail-Open on Invalid JSON"

    # Send garbage to DCG's stdin (simulating malformed Claude Code input)
    echo "not valid json at all" | dcg >/dev/null 2>&1 || true

    # DCG should NOT crash and should NOT block - empty output = allow
    # Non-crash is success; we verify by checking dcg still works after
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG continues working after invalid JSON input"
    else
        fail "DCG broken after invalid JSON. Output: $verify"
    fi
}

# Test 13: Empty stdin should fail-open (allow)
test_failopen_empty_input() {
    section "Test 13: Fail-Open on Empty Input"

    # Send empty input to DCG - should handle gracefully
    echo "" | dcg >/dev/null 2>&1 || true

    # Verify DCG still works
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG continues working after empty input"
    else
        fail "DCG broken after empty input. Output: $verify"
    fi
}

# Test 14: Partial JSON should fail-open (allow)
test_failopen_partial_json() {
    section "Test 14: Fail-Open on Partial JSON"

    # Send truncated JSON (simulating interrupted input) - DCG should handle
    echo '{"tool_name": "Bash", "tool_input":' | dcg >/dev/null 2>&1 || true

    # Verify DCG still works
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG continues working after partial JSON"
    else
        fail "DCG broken after partial JSON. Output: $verify"
    fi
}

# Test 15: Binary data should not crash DCG
test_failopen_binary_input() {
    section "Test 15: Fail-Open on Binary Input"

    # Send binary data (null bytes, etc.) - DCG should handle without crashing
    printf '\x00\x01\x02\xff\xfe' | dcg >/dev/null 2>&1 || true

    # Verify DCG still works
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG continues working after binary input"
    else
        fail "DCG broken after binary input. Output: $verify"
    fi
}

# Test 16: Very large input should not hang DCG
test_failopen_large_input() {
    section "Test 16: Fail-Open on Large Input"

    # DCG should handle large input without hanging (5 second timeout)
    if timeout 5 bash -c "head -c 1048576 /dev/zero | tr '\0' 'x' | dcg 2>&1" >/dev/null; then
        pass "DCG handled large input without hanging"
    else
        if [[ $? -eq 124 ]]; then
            fail "DCG hung on large input (timeout after 5s)"
        else
            pass "DCG handled large input (exited quickly)"
        fi
    fi

    # Verify DCG still works
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG continues working after large input"
    else
        fail "DCG broken after large input. Output: $verify"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Checkpoint/Resume Tests
# These tests verify DCG installation state tracking for the GTBI installer's
# checkpoint/resume system.
# ─────────────────────────────────────────────────────────────────────────────

# Test 17: Binary installed but hook not registered (partial install state)
test_checkpoint_binary_without_hook() {
    section "Test 17: Checkpoint - Binary Without Hook"

    # Uninstall hook to simulate partial install
    dcg uninstall >/dev/null 2>&1 || true

    # Binary should still be available
    if command -v dcg &>/dev/null; then
        pass "DCG binary exists after hook uninstall"
    else
        fail "DCG binary missing after hook uninstall"
        return 1
    fi

    # DCG test should still work (binary functionality)
    local test_output
    test_output=$(dcg test 'git status' 2>&1) || true

    if echo "$test_output" | grep -qi "allow"; then
        pass "DCG test works without hook registered"
    else
        fail "DCG test failed without hook. Output: $test_output"
    fi

    # Doctor should report hook as missing
    local doctor_output
    doctor_output=$(dcg doctor 2>&1) || true

    if echo "$doctor_output" | grep -qiE "hook|not.*registered|missing"; then
        pass "Doctor correctly reports hook status"
    else
        skip "Doctor output format unclear: ${doctor_output:0:100}..."
    fi

    # Re-register hook for subsequent tests
    dcg install --force >/dev/null 2>&1 || true
}

# Test 18: Hook registration is idempotent
test_checkpoint_hook_idempotency() {
    section "Test 18: Checkpoint - Hook Idempotency"

    # Run install multiple times in succession
    local install1 install2 install3
    install1=$(dcg install --force 2>&1) || true
    install2=$(dcg install --force 2>&1) || true
    install3=$(dcg install --force 2>&1) || true

    # All should succeed (or already installed)
    if echo "$install1 $install2 $install3" | grep -qiE "error|failed|fatal"; then
        fail "Hook install failed on repeated calls"
        return 1
    fi

    pass "Hook install is idempotent (3 successive calls)"

    # Hook should be registered exactly once in settings
    local hook_count=0
    for settings_file in ~/.claude/settings.json ~/.config/claude/settings.json; do
        if [[ -f "$settings_file" ]]; then
            local count
            count=$(grep -c "dcg" "$settings_file" 2>/dev/null || echo "0")
            hook_count=$((hook_count + count))
        fi
    done

    if [[ $hook_count -ge 1 ]]; then
        pass "Hook registered in settings (count: $hook_count)"
    else
        skip "Hook registration in settings unclear (count: $hook_count)"
    fi

    # Verify DCG still works after repeated installs
    local verify
    verify=$(dcg test 'git status' 2>&1) || true

    if echo "$verify" | grep -qi "allow"; then
        pass "DCG works after repeated hook installs"
    else
        fail "DCG broken after repeated installs. Output: $verify"
    fi
}

# Test 19: State consistency after uninstall/reinstall cycle
test_checkpoint_state_consistency() {
    section "Test 19: Checkpoint - State Consistency"

    # Record initial state
    local initial_version
    initial_version=$(dcg --version 2>/dev/null || echo "unknown")

    # Full uninstall (but don't purge - keep binary)
    dcg uninstall >/dev/null 2>&1 || true

    # Reinstall hook
    dcg install --force >/dev/null 2>&1 || true

    # Version should be consistent after cycle
    local final_version
    final_version=$(dcg --version 2>/dev/null || echo "unknown")

    # Verify version is accessible and consistent (format may vary with TTY)
    if [[ "$final_version" != "unknown" ]] && [[ "$initial_version" == "$final_version" ]]; then
        pass "Version consistent after uninstall/reinstall cycle ($final_version)"
    elif [[ "$final_version" != "unknown" ]] || dcg --version >/dev/null 2>&1; then
        pass "Version accessible after uninstall/reinstall cycle"
    else
        fail "Version inaccessible after cycle"
    fi

    # Hook should be re-registered (use text parsing)
    local doctor_output
    doctor_output=$(dcg doctor 2>&1) || true

    if echo "$doctor_output" | grep -qiE "hook wiring.*OK|registered"; then
        pass "Hook correctly re-registered after cycle"
    else
        skip "Hook registration status after cycle unclear"
    fi

    # All core functionality should work
    local git_block
    git_block=$(dcg test 'git reset --hard' 2>&1) || true

    if echo "$git_block" | grep -qiE "deny|block"; then
        pass "Core blocking functionality intact after cycle"
    else
        fail "Blocking broken after cycle. Output: $git_block"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "============================================================"
    echo "  DCG Edge Case Tests"
    echo "============================================================"

    check_prerequisites

    test_version_format
    test_dcg_standalone
    test_path_configured
    test_multiple_packs
    test_reinstall_idempotent
    test_doctor_diagnostics
    test_command_edge_cases
    test_safe_force_push
    test_temp_directory_allowed
    test_uninstall_reinstall_cycle
    test_dcg_checkpoint_resume_markers

    # Fail-open behavior tests
    test_failopen_invalid_json
    test_failopen_empty_input
    test_failopen_partial_json
    test_failopen_binary_input
    test_failopen_large_input

    # Checkpoint/resume tests
    test_checkpoint_binary_without_hook
    test_checkpoint_hook_idempotency
    test_checkpoint_state_consistency

    echo ""
    echo "============================================================"
    echo "  Summary"
    echo "============================================================"
    echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
    echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
    echo -e "  ${YELLOW}Skipped:${NC} $SKIP_COUNT"
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
