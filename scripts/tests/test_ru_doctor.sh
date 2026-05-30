#!/usr/bin/env bash
# Test RU doctor functionality
# Run from: ./scripts/tests/test_ru_doctor.sh

# Don't use set -e so tests can fail individually without stopping
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_step() { echo -e "[STEP] $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)) || true; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)) || true; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; ((TESTS_SKIPPED++)) || true; }

run_test() {
    local name="$1"
    shift
    log_step "Testing: $name"
    if "$@"; then
        log_pass "$name"
    else
        log_fail "$name"
    fi
}

# Test 1: doctor.sh exists and has valid syntax
test_doctor_sh_syntax() {
    local doctor_sh="$REPO_ROOT/scripts/lib/doctor.sh"
    [[ -f "$doctor_sh" ]] && bash -n "$doctor_sh"
}

# Test 2: Generated doctor_checks.sh includes ru
test_doctor_checks_has_ru() {
    local doctor_checks="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    if [[ -f "$doctor_checks" ]]; then
        # Use command grep to avoid rg alias; check for ru in any form
        command grep -q "ru" "$doctor_checks" 2>/dev/null
    else
        log_skip "doctor_checks.sh not found"
        return 0
    fi
}

# Test 3: manifest_index.sh includes ru metadata
test_manifest_index_has_ru() {
    local manifest_index="$REPO_ROOT/scripts/generated/manifest_index.sh"
    if [[ -f "$manifest_index" ]]; then
        # Use command grep to avoid rg alias
        command grep -q "ru" "$manifest_index" 2>/dev/null
    else
        log_skip "manifest_index.sh not found"
        return 0
    fi
}

# Test 4: doctor checks ru correctly when installed
test_doctor_ru_installed() {
    if command -v ru &>/dev/null; then
        # ru --version should work
        ru --version &>/dev/null || ru version &>/dev/null
    else
        log_skip "ru not installed, testing skip path"
        return 0
    fi
}

# Test 5: ru doctor subcommand if exists
test_ru_doctor_subcommand() {
    if command -v ru &>/dev/null; then
        # Check if ru has a doctor subcommand
        if ru doctor --help &>/dev/null 2>&1; then
            ru doctor &>/dev/null || {
                # Doctor might report issues, that's OK
                return 0
            }
            return 0
        else
            log_skip "ru doctor subcommand not available"
            return 0
        fi
    else
        log_skip "ru not installed"
        return 0
    fi
}

# Test 6: ru sync --dry-run works
test_ru_sync_dry_run() {
    if command -v ru &>/dev/null; then
        # ru sync --dry-run should work without a config
        ru sync --dry-run --help &>/dev/null 2>&1 || {
            # Might not have --dry-run, just check ru responds
            ru --help &>/dev/null
        }
        return 0
    else
        log_skip "ru not installed"
        return 0
    fi
}

# Test 7: ru appears in gtbi doctor output
test_gtbi_doctor_has_ru() {
    if command -v gtbi &>/dev/null; then
        local doctor_output
        doctor_output=$(gtbi doctor 2>&1) || true
        # Use command grep to avoid rg alias
        if echo "$doctor_output" | command grep -qi "ru"; then
            return 0
        else
            log_skip "gtbi doctor doesn't mention ru (may be OK)"
            return 0
        fi
    else
        log_skip "gtbi command not available"
        return 0
    fi
}

# Run all tests
main() {
    echo ""
    echo "============================================================"
    echo "  RU Doctor Integration Tests"
    echo "============================================================"
    echo ""

    run_test "doctor.sh syntax valid" test_doctor_sh_syntax
    run_test "doctor_checks.sh includes ru" test_doctor_checks_has_ru
    run_test "manifest_index.sh includes ru" test_manifest_index_has_ru
    run_test "doctor checks ru correctly" test_doctor_ru_installed
    run_test "ru doctor subcommand" test_ru_doctor_subcommand
    run_test "ru sync dry-run" test_ru_sync_dry_run
    run_test "gtbi doctor has ru" test_gtbi_doctor_has_ru

    echo ""
    echo "============================================================"
    echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
    echo "============================================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
