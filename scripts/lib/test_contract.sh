#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317,SC2329
# ============================================================
# Test script for contract.sh
# Run: bash scripts/lib/test_contract.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/contract.sh"

TESTS_PASSED=0
TESTS_FAILED=0

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

# Reset environment for each test
reset_env() {
    unset TARGET_USER TARGET_HOME MODE
    unset SCRIPT_DIR GTBI_BOOTSTRAP_DIR GTBI_LIB_DIR
    unset GTBI_GENERATED_DIR GTBI_ASSETS_DIR GTBI_CHECKSUMS_YAML GTBI_MANIFEST_YAML
}

# Define stub functions for contract requirements
define_required_functions() {
    log_detail() { :; }
    run_as_target() { :; }
    run_as_target_shell() { :; }
    run_as_root_shell() { :; }
    run_as_current_shell() { :; }
    _gtbi_is_interactive() { return 1; }
    export -f log_detail run_as_target run_as_target_shell run_as_root_shell run_as_current_shell _gtbi_is_interactive
}

# Define stub functions WITHOUT security.sh helpers.
# Contract should not require _gtbi_is_interactive (security is opt-in via gtbi_security_init).
define_required_functions_no_security() {
    log_detail() { :; }
    run_as_target() { :; }
    run_as_target_shell() { :; }
    run_as_root_shell() { :; }
    run_as_current_shell() { :; }
    export -f log_detail run_as_target run_as_target_shell run_as_root_shell run_as_current_shell
}

# Undefine functions
undefine_required_functions() {
    unset -f run_as_target run_as_target_shell run_as_root_shell run_as_current_shell
}

# ============================================================
# Test Cases
# ============================================================

test_missing_target_user() {
    local name="Missing TARGET_USER fails contract"
    reset_env
    define_required_functions

    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when TARGET_USER is missing"
    fi
}

test_missing_target_home() {
    local name="Missing TARGET_HOME fails contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when TARGET_HOME is missing"
    fi
}

test_missing_mode() {
    local name="Missing MODE fails contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when MODE is missing"
    fi
}

test_all_basic_vars_present() {
    local name="All basic vars present passes contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should pass with all required vars"
    fi
}

test_security_helpers_optional() {
    local name="Missing _gtbi_is_interactive does not fail contract"
    reset_env
    define_required_functions_no_security

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Contract should not require security.sh helpers"
    fi
}

test_bootstrap_mode_missing_vars() {
    local name="Bootstrap mode (empty SCRIPT_DIR) requires GTBI_BOOTSTRAP_DIR"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR=""  # Empty triggers bootstrap check

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when GTBI_BOOTSTRAP_DIR is missing in bootstrap mode"
    fi
}

test_bootstrap_mode_all_vars() {
    local name="Bootstrap mode with all vars passes"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR=""  # Bootstrap mode
    GTBI_BOOTSTRAP_DIR="/tmp/gtbi"
    GTBI_LIB_DIR="/tmp/gtbi/lib"
    GTBI_GENERATED_DIR="/tmp/gtbi/generated"
    GTBI_ASSETS_DIR="/tmp/gtbi/assets"
    GTBI_CHECKSUMS_YAML="/tmp/gtbi/checksums.yaml"
    GTBI_MANIFEST_YAML="/tmp/gtbi/gtbi.manifest.yaml"

    if gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should pass with all bootstrap vars"
    fi
}

test_missing_run_as_target_function() {
    local name="Missing run_as_target function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_target

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_target is missing"
    fi
}

test_missing_run_as_target_shell_function() {
    local name="Missing run_as_target_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_target_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_target_shell is missing"
    fi
}

test_missing_run_as_root_shell_function() {
    local name="Missing run_as_root_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_root_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_root_shell is missing"
    fi
}

test_missing_run_as_current_shell_function() {
    local name="Missing run_as_current_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_current_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! gtbi_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_current_shell is missing"
    fi
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "GTBI Contract Tests"
echo "==================="
echo ""

test_missing_target_user
test_missing_target_home
test_missing_mode
test_all_basic_vars_present
test_security_helpers_optional
test_bootstrap_mode_missing_vars
test_bootstrap_mode_all_vars
test_missing_run_as_target_function
test_missing_run_as_target_shell_function
test_missing_run_as_root_shell_function
test_missing_run_as_current_shell_function

echo ""
echo "==================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
