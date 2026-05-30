#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for security.sh
# Run: bash scripts/lib/test_security.sh
#
# Tests non-network functions locally. Network functions tested
# with local file:// URLs where possible.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/security.sh"

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

# Create temp directory for test fixtures
setup_fixtures() {
    TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gtbi_test_security.XXXXXX")
    trap 'rm -rf "$TEST_TMP_DIR"' EXIT

    # Create a simple test script
    echo '#!/bin/bash
echo "Hello from test script"' > "$TEST_TMP_DIR/test_script.sh"

    # Create a test checksums.yaml
    cat > "$TEST_TMP_DIR/checksums.yaml" << 'EOF'
# Test checksums file
installers:
  test_tool:
    url: "https://example.com/install.sh"
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  another_tool:
    url: "https://example.com/another.sh"
    sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
EOF
}

# ============================================================
# Test Cases: HTTPS Enforcement
# ============================================================

test_is_https_valid() {
    local name="is_https returns true for HTTPS URLs"

    if is_https "https://example.com/install.sh"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_is_https_invalid() {
    local name="is_https returns false for HTTP URLs"

    if ! is_https "http://example.com/install.sh"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_is_https_ftp() {
    local name="is_https returns false for FTP URLs"

    if ! is_https "ftp://example.com/file"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_enforce_https_valid() {
    local name="enforce_https passes for HTTPS URLs"

    if enforce_https "https://example.com/install.sh" "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_enforce_https_invalid() {
    local name="enforce_https fails for HTTP URLs"

    if ! enforce_https "http://example.com/install.sh" "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: SHA256 Calculation
# ============================================================

test_calculate_sha256_empty() {
    local name="calculate_sha256 handles empty input"

    # SHA256 of empty string
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    local actual

    actual=$(printf '' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

test_calculate_sha256_known_value() {
    local name="calculate_sha256 produces correct hash for known input"

    # SHA256 of "abc"
    local expected="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    local actual

    actual=$(printf 'abc' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

test_calculate_sha256_with_newline() {
    local name="calculate_sha256 handles content with newlines"

    # SHA256 of "hello\n" (with trailing newline)
    local expected="5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    local actual

    actual=$(printf 'hello\n' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

# ============================================================
# Test Cases: Checksums File Loading
# ============================================================

test_load_checksums_file_not_found() {
    local name="load_checksums fails gracefully for missing file"

    if ! load_checksums "/nonexistent/file.yaml" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail for missing file"
    fi
}

test_load_checksums_parses_correctly() {
    local name="load_checksums parses YAML correctly"
    setup_fixtures

    # Clear existing checksums
    LOADED_CHECKSUMS=()

    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local test_checksum="${LOADED_CHECKSUMS[test_tool]:-}"
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    if [[ "$test_checksum" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $test_checksum"
    fi
}

test_load_checksums_multiple_tools() {
    local name="load_checksums loads multiple tools"
    setup_fixtures

    # Clear existing checksums
    LOADED_CHECKSUMS=()

    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local count=0
    for key in "${!LOADED_CHECKSUMS[@]}"; do
        ((++count))
    done

    if [[ $count -eq 2 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 2 tools, Got: $count"
    fi
}

test_get_checksum_existing() {
    local name="get_checksum returns correct value for existing tool"
    setup_fixtures

    LOADED_CHECKSUMS=()
    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local result
    result=$(get_checksum "test_tool")
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    if [[ "$result" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $result"
    fi
}

test_get_checksum_missing() {
    local name="get_checksum returns empty for missing tool"
    setup_fixtures

    LOADED_CHECKSUMS=()
    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local result
    result=$(get_checksum "nonexistent_tool")

    if [[ -z "$result" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected empty, Got: $result"
    fi
}

# ============================================================
# Test Cases: Mismatch Recording
# ============================================================

test_record_checksum_mismatch() {
    local name="record_checksum_mismatch adds entry"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "test_tool" "https://example.com" "expected123" "actual456"

    if [[ ${#CHECKSUM_MISMATCHES[@]} -eq 1 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 1 entry, Got: ${#CHECKSUM_MISMATCHES[@]}"
    fi
}

test_clear_checksum_mismatches() {
    local name="clear_checksum_mismatches clears all entries"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"
    record_checksum_mismatch "tool2" "url2" "exp2" "act2"
    clear_checksum_mismatches

    if [[ ${#CHECKSUM_MISMATCHES[@]} -eq 0 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 0 entries after clear, Got: ${#CHECKSUM_MISMATCHES[@]}"
    fi
}

test_count_checksum_mismatches() {
    local name="count_checksum_mismatches returns correct count"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"
    record_checksum_mismatch "tool2" "url2" "exp2" "act2"
    record_checksum_mismatch "tool3" "url3" "exp3" "act3"

    local count
    count=$(count_checksum_mismatches)

    if [[ "$count" -eq 3 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 3, Got: $count"
    fi
}

test_has_checksum_mismatches_true() {
    local name="has_checksum_mismatches returns true when entries exist"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"

    if has_checksum_mismatches; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_has_checksum_mismatches_false() {
    local name="has_checksum_mismatches returns false when empty"

    CHECKSUM_MISMATCHES=()

    if ! has_checksum_mismatches; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: Retryable Exit Codes
# ============================================================

test_retryable_exit_code_dns() {
    local name="DNS error (6) is retryable"

    if gtbi_is_retryable_curl_exit_code 6; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_retryable_exit_code_connect() {
    local name="Connect error (7) is retryable"

    if gtbi_is_retryable_curl_exit_code 7; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_retryable_exit_code_timeout() {
    local name="Timeout (28) is retryable"

    if gtbi_is_retryable_curl_exit_code 28; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_non_retryable_exit_code() {
    local name="HTTP error (22) is not retryable"

    if ! gtbi_is_retryable_curl_exit_code 22; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_non_retryable_exit_code_success() {
    local name="Success (0) is not retryable"

    if ! gtbi_is_retryable_curl_exit_code 0; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: KNOWN_INSTALLERS Array
# ============================================================

test_known_installers_has_entries() {
    local name="KNOWN_INSTALLERS array has expected entries"

    local count=0
    for key in "${!KNOWN_INSTALLERS[@]}"; do
        ((++count))
    done

    if [[ $count -gt 5 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected >5 entries, Got: $count"
    fi
}

test_known_installers_all_https() {
    local name="All KNOWN_INSTALLERS URLs are HTTPS"

    local all_https=true
    for key in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$key]}"
        if ! is_https "$url"; then
            all_https=false
            break
        fi
    done

    if [[ "$all_https" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Found non-HTTPS URL"
    fi
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "GTBI Security Tests"
echo "==================="
echo ""

# HTTPS tests
test_is_https_valid
test_is_https_invalid
test_is_https_ftp
test_enforce_https_valid
test_enforce_https_invalid

# SHA256 tests
test_calculate_sha256_empty
test_calculate_sha256_known_value
test_calculate_sha256_with_newline

# Checksums file tests
test_load_checksums_file_not_found
test_load_checksums_parses_correctly
test_load_checksums_multiple_tools
test_get_checksum_existing
test_get_checksum_missing

# Mismatch recording tests
test_record_checksum_mismatch
test_clear_checksum_mismatches
test_count_checksum_mismatches
test_has_checksum_mismatches_true
test_has_checksum_mismatches_false

# Retryable exit code tests
test_retryable_exit_code_dns
test_retryable_exit_code_connect
test_retryable_exit_code_timeout
test_non_retryable_exit_code
test_non_retryable_exit_code_success

# KNOWN_INSTALLERS tests
test_known_installers_has_entries
test_known_installers_all_https

echo ""
echo "==================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
