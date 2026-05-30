#!/usr/bin/env bash
# Unit tests for GTBI utility tools integration
# Tests that all utility binaries exist and basic operations succeed
#
# Utilities tested:
#   tru (toon_rust), rust_proxy, rano, xf, mdwb, pt, aadc, s2p, caut
#
# Related: bead bd-1ega.6.10

set -uo pipefail
# Note: Not using -e to allow tests to continue after failures

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/utilities_integration_tests_${TIMESTAMP}.log"
JSON_FILE="/tmp/utilities_integration_tests_${TIMESTAMP}.json"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Array to collect test results for JSON output
declare -a TEST_RESULTS=()

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

# Escape string for JSON (handle newlines, quotes, backslashes)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"      # Escape backslashes first
    s="${s//\"/\\\"}"      # Escape quotes
    s="${s//$'\n'/\\n}"    # Escape newlines
    s="${s//$'\r'/\\r}"    # Escape carriage returns
    s="${s//$'\t'/\\t}"    # Escape tabs
    printf '%s' "$s"
}

pass() {
    local test_name="$1"
    shift
    log "PASS: $*"
    ((PASS_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"pass\",\"message\":\"$escaped_msg\"}")
}

fail() {
    local test_name="$1"
    shift
    log "FAIL: $*"
    ((FAIL_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"fail\",\"message\":\"$escaped_msg\"}")
}

skip() {
    local test_name="$1"
    shift
    log "SKIP: $*"
    ((SKIP_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"skip\",\"message\":\"$escaped_msg\"}")
}

# Generic utility tester
test_utility() {
    local name="$1"
    local binary="$2"
    local test_num="$3"
    local description="$4"

    log "Test $test_num: $name ($binary) - $description"

    # Test binary exists
    if ! command -v "$binary" >/dev/null 2>&1; then
        skip "${binary}_binary" "$binary binary not found (tool may not be installed)"
        skip "${binary}_version" "$binary --version skipped (binary not found)"
        return 0
    fi

    pass "${binary}_binary" "$binary binary found at $(which "$binary")"

    # Test --version or --help works
    local version_output
    if version_output=$("$binary" --version 2>&1); then
        pass "${binary}_version" "$binary version: ${version_output:0:80}"
    elif version_output=$("$binary" --help 2>&1 | head -1); then
        pass "${binary}_version" "$binary help works: ${version_output:0:80}"
    else
        fail "${binary}_version" "$binary --version and --help both failed"
    fi
}

# ============================================================
# Utility-specific tests
# ============================================================

test_tru() {
    log ""
    log "========================================"
    log "Testing: toon_rust (tru)"
    log "========================================"
    test_utility "toon_rust" "tru" "1" "Token-optimized notation format"
}

test_rust_proxy() {
    log ""
    log "========================================"
    log "Testing: rust_proxy"
    log "========================================"
    test_utility "rust_proxy" "rust_proxy" "2" "Transparent proxy routing"
}

test_rano() {
    log ""
    log "========================================"
    log "Testing: rano"
    log "========================================"
    test_utility "rano" "rano" "3" "Network observer for AI CLIs"
}

test_xf() {
    log ""
    log "========================================"
    log "Testing: xf"
    log "========================================"
    test_utility "xf" "xf" "4" "X/Twitter archive search"
}

test_mdwb() {
    log ""
    log "========================================"
    log "Testing: markdown_web_browser (mdwb)"
    log "========================================"
    test_utility "markdown_web_browser" "mdwb" "5" "Convert websites to Markdown"
}

test_pt() {
    log ""
    log "========================================"
    log "Testing: process_tamer (pt)"
    log "========================================"
    test_utility "process_tamer" "pt" "6" "Find and terminate stuck processes"
}

test_aadc() {
    log ""
    log "========================================"
    log "Testing: aadc"
    log "========================================"
    test_utility "aadc" "aadc" "7" "ASCII diagram corrector"
}

test_s2p() {
    log ""
    log "========================================"
    log "Testing: source_to_prompt_tui (s2p)"
    log "========================================"
    test_utility "source_to_prompt_tui" "s2p" "8" "Code to LLM prompt generator"
}

test_caut() {
    log ""
    log "========================================"
    log "Testing: coding_agent_usage_tracker (caut)"
    log "========================================"
    test_utility "coding_agent_usage_tracker" "caut" "9" "LLM provider usage tracker"
}

# ============================================================
# JSON Output
# ============================================================

write_json_results() {
    local json_content
    json_content=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "summary": {
    "total": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "result": "$(if [[ $FAIL_COUNT -gt 0 ]]; then echo "FAILED"; else echo "PASSED"; fi)"
  },
  "tests": [
$(IFS=,; echo "${TEST_RESULTS[*]}" | sed 's/},{/},\n    {/g' | sed 's/^/    /')
  ]
}
EOF
)
    echo "$json_content" > "$JSON_FILE"
    log "JSON results written to: $JSON_FILE"
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    log ""
    log "========================================"
    log "TEST SUMMARY"
    log "========================================"
    log "Passed:  $PASS_COUNT"
    log "Failed:  $FAIL_COUNT"
    log "Skipped: $SKIP_COUNT"
    log "Total:   $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
    log ""
    log "Log file:  $LOG_FILE"
    log "JSON file: $JSON_FILE"
    log "========================================"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        log "OVERALL: FAILED"
        return 1
    else
        log "OVERALL: PASSED"
        return 0
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    log "========================================"
    log "GTBI Utility Tools Integration Tests"
    log "Started: $(date -Iseconds)"
    log "========================================"

    # Run all utility tests
    test_tru
    test_rust_proxy
    test_rano
    test_xf
    test_mdwb
    test_pt
    test_aadc
    test_s2p
    test_caut

    # Write JSON results
    write_json_results

    # Print summary
    print_summary
}

main "$@"
