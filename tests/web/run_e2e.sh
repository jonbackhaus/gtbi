#!/usr/bin/env bash
# ============================================================
# GTBI Web Wizard - E2E Test Runner
#
# Runs Playwright tests with structured logging, retries, and
# artifact collection in a predictable location.
#
# Usage:
#   ./tests/web/run_e2e.sh                 # Run all tests
#   ./tests/web/run_e2e.sh --headed        # Run with visible browser
#   ./tests/web/run_e2e.sh --project chromium   # Run specific project
#   ./tests/web/run_e2e.sh --debug         # Run with Playwright debug
#
# Requirements:
#   - bun installed
#   - Playwright browsers installed (bunx playwright install)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WEB_DIR="$REPO_ROOT/apps/web"

# Artifacts directory with timestamp
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACTS_DIR="${GTBI_E2E_ARTIFACTS:-$REPO_ROOT/test-results/web-e2e-$TIMESTAMP}"

# Colors (only if stderr is a terminal)
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    # shellcheck disable=SC2034
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    # shellcheck disable=SC2034
    BLUE='' # unused but kept for consistency
    CYAN=''
    GRAY=''
    BOLD=''
    NC=''
fi

# Logging functions
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_section() {
    echo "" >&2
    echo "${CYAN}[$(date '+%H:%M:%S')]${NC} ${BOLD}$1${NC}" >&2
}

log_info() {
    echo "${GRAY}  $1${NC}" >&2
}

log_success() {
    echo "${GREEN}  ✓ $1${NC}" >&2
}

log_warn() {
    echo "${YELLOW}  ⚠ $1${NC}" >&2
}

log_error() {
    echo "${RED}  ✗ $1${NC}" >&2
}

# Parse arguments
PLAYWRIGHT_ARGS=()
HEADED=""
PROJECT=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --headed)
            HEADED="--headed"
            shift
            ;;
        --project)
            PROJECT="--project ${2:-chromium}"
            shift 2
            ;;
        --debug)
            DEBUG="--debug"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --headed          Run with visible browser"
            echo "  --project <name>  Run specific browser project (chromium/firefox/webkit)"
            echo "  --debug           Run with Playwright inspector"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            PLAYWRIGHT_ARGS+=("$1")
            shift
            ;;
    esac
done

# ============================================================
# Main Script
# ============================================================

echo "" >&2
echo "${BOLD}============================================================${NC}" >&2
echo "${BOLD}GTBI Web Wizard E2E Tests${NC}" >&2
echo "${GRAY}Started: $(timestamp)${NC}" >&2
echo "${GRAY}Artifacts: ${ARTIFACTS_DIR}${NC}" >&2
echo "${BOLD}============================================================${NC}" >&2

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

# Check prerequisites
log_section "Prerequisites Check"

if ! command -v bun >/dev/null 2>&1; then
    log_error "bun not found. Please install bun."
    exit 1
fi
log_success "bun found: $(bun --version)"

if [[ ! -f "$WEB_DIR/package.json" ]]; then
    log_error "apps/web/package.json not found"
    exit 1
fi
log_success "apps/web exists"

# Check if playwright is installed
cd "$WEB_DIR"
if ! bun pm ls 2>/dev/null | grep -q "@playwright/test"; then
    log_warn "Playwright not installed. Running bun install..."
    bun install --frozen-lockfile 2>&1 | tee "$ARTIFACTS_DIR/install.log" >&2
fi
log_success "Dependencies installed"

# Install browsers if needed
log_section "Browser Setup"
if ! bunx playwright install --dry-run chromium 2>/dev/null | grep -q "already installed"; then
    log_info "Installing Playwright browsers..."
    bunx playwright install 2>&1 | tee "$ARTIFACTS_DIR/browser-install.log" >&2
fi
log_success "Browsers ready"

# Run tests
log_section "Running E2E Tests"
log_info "Project: ${PROJECT:-all}"
log_info "Mode: ${HEADED:-headless}"

START_TIME=$(date +%s)

# Build playwright command
PLAYWRIGHT_CMD="bunx playwright test"
[[ -n "$HEADED" ]] && PLAYWRIGHT_CMD="$PLAYWRIGHT_CMD $HEADED"
[[ -n "$PROJECT" ]] && PLAYWRIGHT_CMD="$PLAYWRIGHT_CMD $PROJECT"
[[ -n "$DEBUG" ]] && PLAYWRIGHT_CMD="$PLAYWRIGHT_CMD $DEBUG"
[[ ${#PLAYWRIGHT_ARGS[@]} -gt 0 ]] && PLAYWRIGHT_CMD="$PLAYWRIGHT_CMD ${PLAYWRIGHT_ARGS[*]}"

# Set output directory for Playwright
export PLAYWRIGHT_OUTPUT_DIR="$ARTIFACTS_DIR"

# Run tests and capture exit code
log_info "Command: $PLAYWRIGHT_CMD"
echo "" >&2

set +e
$PLAYWRIGHT_CMD \
    --output "$ARTIFACTS_DIR/test-results" \
    --reporter=list,json \
    2>&1 | tee "$ARTIFACTS_DIR/test-output.log"
TEST_EXIT_CODE=${PIPESTATUS[0]}
set -e

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Parse results from Playwright JSON output if available
log_section "Test Results"

# Look for test results JSON
JSON_REPORT="$ARTIFACTS_DIR/test-results/results.json"
if [[ -f "$JSON_REPORT" ]]; then
    PASSED=$(jq -r '.stats.expected // 0' "$JSON_REPORT" 2>/dev/null || echo "?")
    FAILED=$(jq -r '.stats.unexpected // 0' "$JSON_REPORT" 2>/dev/null || echo "?")
    SKIPPED=$(jq -r '.stats.skipped // 0' "$JSON_REPORT" 2>/dev/null || echo "?")
    TOTAL=$((PASSED + FAILED + SKIPPED))
else
    # Try to parse from log output
    PASSED=$(grep -c "✓" "$ARTIFACTS_DIR/test-output.log" 2>/dev/null || echo "0")
    FAILED=$(grep -cE "✘|×|failed" "$ARTIFACTS_DIR/test-output.log" 2>/dev/null || echo "0")
    SKIPPED=$(grep -cE "⊘|skipped" "$ARTIFACTS_DIR/test-output.log" 2>/dev/null || echo "0")
    TOTAL=$((PASSED + FAILED + SKIPPED))
fi

# Collect artifacts
log_section "Artifacts"

# Move Playwright artifacts to our directory
if [[ -d "$WEB_DIR/test-results" ]]; then
    cp -r "$WEB_DIR/test-results"/* "$ARTIFACTS_DIR/test-results/" 2>/dev/null || true
    log_success "Test results copied"
fi

if [[ -d "$WEB_DIR/playwright-report" ]]; then
    cp -r "$WEB_DIR/playwright-report" "$ARTIFACTS_DIR/" 2>/dev/null || true
    log_success "HTML report copied"
fi

# List screenshots and traces
SCREENSHOTS=$(find "$ARTIFACTS_DIR" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
TRACES=$(find "$ARTIFACTS_DIR" -name "*.zip" 2>/dev/null | wc -l | tr -d ' ')
VIDEOS=$(find "$ARTIFACTS_DIR" -name "*.webm" 2>/dev/null | wc -l | tr -d ' ')

[[ $SCREENSHOTS -gt 0 ]] && log_info "Screenshots: $SCREENSHOTS"
[[ $TRACES -gt 0 ]] && log_info "Traces: $TRACES"
[[ $VIDEOS -gt 0 ]] && log_info "Videos: $VIDEOS"

# Print summary
echo "" >&2
echo "${BOLD}============================================================${NC}" >&2
echo "${BOLD}Summary${NC}" >&2
echo "${BOLD}============================================================${NC}" >&2
echo "" >&2
echo "  Total tests:  $TOTAL" >&2
echo "  ${GREEN}Passed:       $PASSED${NC}" >&2
echo "  ${RED}Failed:       $FAILED${NC}" >&2
echo "  ${YELLOW}Skipped:      $SKIPPED${NC}" >&2
echo "" >&2
echo "  Duration:     ${DURATION}s" >&2
echo "  Artifacts:    $ARTIFACTS_DIR" >&2
echo "" >&2

if [[ $TEST_EXIT_CODE -eq 0 ]]; then
    echo "${GREEN}✅ All tests passed!${NC}" >&2
else
    echo "${RED}❌ $FAILED test(s) failed${NC}" >&2
fi
echo "${BOLD}============================================================${NC}" >&2

# Output JSON summary to stdout for machine parsing
cat <<EOF
{
  "suite": "GTBI Web Wizard E2E",
  "passed": $PASSED,
  "failed": $FAILED,
  "skipped": $SKIPPED,
  "total": $TOTAL,
  "duration_seconds": $DURATION,
  "artifacts_dir": "$ARTIFACTS_DIR",
  "screenshots": $SCREENSHOTS,
  "traces": $TRACES,
  "videos": $VIDEOS,
  "success": $([ "$TEST_EXIT_CODE" -eq 0 ] && echo "true" || echo "false")
}
EOF

exit "$TEST_EXIT_CODE"
