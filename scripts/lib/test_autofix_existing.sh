#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for autofix_existing.sh
# Run: bash scripts/lib/test_autofix_existing.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module
source "$SCRIPT_DIR/autofix_existing.sh"

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

# Test: Check function returns valid JSON
test_check_returns_json() {
    local result
    result=$(autofix_existing_gtbi_check 2>/dev/null)

    if ! echo "$result" | jq . &>/dev/null; then
        test_fail "check_returns_json" "Output is not valid JSON"
        return
    fi

    # Verify required fields exist
    local state
    state=$(echo "$result" | jq -r '.state')
    if [[ -z "$state" ]]; then
        test_fail "check_returns_json" "Missing 'state' field"
        return
    fi

    local version
    version=$(echo "$result" | jq -r '.version')
    if [[ -z "$version" ]]; then
        test_fail "check_returns_json" "Missing 'version' field"
        return
    fi

    local markers
    markers=$(echo "$result" | jq -r '.markers | type')
    if [[ "$markers" != "array" ]]; then
        test_fail "check_returns_json" "markers should be array"
        return
    fi

    test_pass "check_returns_json"
}

# Test: State detection returns valid values
test_state_detection() {
    local state
    state=$(detect_installation_state 2>/dev/null)

    case "$state" in
        none|complete|partial|marker_only)
            test_pass "state_detection ($state)"
            ;;
        *)
            test_fail "state_detection" "Unknown state: $state"
            ;;
    esac
}

# Test: Version detection returns something
test_version_detection() {
    local version
    version=$(get_installed_version 2>/dev/null)

    if [[ -z "$version" ]]; then
        test_fail "version_detection" "Empty version returned"
        return
    fi

    # Version should be either "unknown" or match semver-ish pattern
    if [[ "$version" == "unknown" ]] || [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        test_pass "version_detection ($version)"
    else
        test_fail "version_detection" "Invalid version format: $version"
    fi
}

# Test: Version comparison
test_version_compare() {
    local failed=0

    # Test equal versions
    local result
    result=$(version_compare "1.0.0" "1.0.0")
    if [[ "$result" != "0" ]]; then
        echo "       1.0.0 == 1.0.0 should be 0, got $result"
        failed=$((failed + 1))
    fi

    # Test less than
    result=$(version_compare "1.0.0" "2.0.0")
    if [[ "$result" != "-1" ]]; then
        echo "       1.0.0 < 2.0.0 should be -1, got $result"
        failed=$((failed + 1))
    fi

    # Test greater than
    result=$(version_compare "2.0.0" "1.0.0")
    if [[ "$result" != "1" ]]; then
        echo "       2.0.0 > 1.0.0 should be 1, got $result"
        failed=$((failed + 1))
    fi

    # Test minor version comparison
    result=$(version_compare "1.2.0" "1.3.0")
    if [[ "$result" != "-1" ]]; then
        echo "       1.2.0 < 1.3.0 should be -1, got $result"
        failed=$((failed + 1))
    fi

    # Test patch version comparison
    result=$(version_compare "1.0.5" "1.0.3")
    if [[ "$result" != "1" ]]; then
        echo "       1.0.5 > 1.0.3 should be 1, got $result"
        failed=$((failed + 1))
    fi

    # Test unknown version handling
    result=$(version_compare "unknown" "1.0.0")
    if [[ "$result" != "0" ]]; then
        echo "       unknown vs 1.0.0 should be 0, got $result"
        failed=$((failed + 1))
    fi

    if [[ $failed -eq 0 ]]; then
        test_pass "version_compare"
    else
        test_fail "version_compare" "$failed comparison(s) failed"
    fi
}

# Test: Migration check
test_migration_check() {
    # Major version change should require migration
    if ! version_requires_migration "1.0.0" "2.0.0"; then
        test_fail "migration_check" "Major version change should require migration"
        return
    fi

    # Same major version should not require migration
    if version_requires_migration "1.0.0" "1.5.0"; then
        test_fail "migration_check" "Same major version should not require migration"
        return
    fi

    # Unknown version should require migration check
    if ! version_requires_migration "unknown" "1.0.0"; then
        test_fail "migration_check" "Unknown version should require migration"
        return
    fi

    test_pass "migration_check"
}

# Test: CLI modes work
test_cli_modes() {
    local failed=0

    # Test check mode
    if ! bash "$SCRIPT_DIR/autofix_existing.sh" check &>/dev/null; then
        failed=$((failed + 1))
        echo "       check mode failed"
    fi

    # Test version mode
    if ! bash "$SCRIPT_DIR/autofix_existing.sh" version &>/dev/null; then
        failed=$((failed + 1))
        echo "       version mode failed"
    fi

    # Test needs-handling mode (exit code can vary based on system)
    bash "$SCRIPT_DIR/autofix_existing.sh" needs-handling &>/dev/null || true

    if [[ $failed -eq 0 ]]; then
        test_pass "cli_modes"
    else
        test_fail "cli_modes" "$failed mode(s) failed"
    fi
}

# Test: Installation markers constant is properly defined
test_marker_constants() {
    local -a markers=()
    mapfile -t markers < <(autofix_existing_installation_markers 2>/dev/null || true)

    if [[ ${#markers[@]} -lt 3 ]]; then
        test_fail "marker_constants" "Should have at least 3 installation markers"
        return
    fi

    # All marker paths should include HOME or start with /
    for marker in "${markers[@]}"; do
        if [[ "$marker" != /* ]] && [[ "$marker" != *'$HOME'* ]] && [[ "$marker" != "$HOME"* ]]; then
            test_fail "marker_constants" "Invalid marker path: $marker"
            return
        fi
    done

    test_pass "marker_constants"
}

# Test: Shell configs constant is properly defined
test_shell_configs_constant() {
    local -a shell_configs=()
    mapfile -t shell_configs < <(autofix_existing_shell_configs 2>/dev/null || true)

    if [[ ${#shell_configs[@]} -lt 2 ]]; then
        test_fail "shell_configs_constant" "Should have at least 2 shell configs"
        return
    fi

    # Should include bashrc and zshrc at minimum
    local has_bashrc=false
    local has_zshrc=false

    for config in "${shell_configs[@]}"; do
        case "$config" in
            *bashrc*) has_bashrc=true ;;
            *zshrc*) has_zshrc=true ;;
        esac
    done

    if ! $has_bashrc || ! $has_zshrc; then
        test_fail "shell_configs_constant" "Should include both bashrc and zshrc"
        return
    fi

    test_pass "shell_configs_constant"
}

# Run all tests
main() {
    echo "==========================================="
    echo "Running autofix_existing.sh unit tests"
    echo "==========================================="

    test_check_returns_json
    test_state_detection
    test_version_detection
    test_version_compare
    test_migration_check
    test_cli_modes
    test_marker_constants
    test_shell_configs_constant

    echo "==========================================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    echo "All tests passed!"
    exit 0
}

main "$@"
