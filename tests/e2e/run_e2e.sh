#!/usr/bin/env bash
# ============================================================
# GTBI E2E Test Runner
#
# Runs all E2E tests with proper environment setup and reporting.
#
# Usage:
#   ./run_e2e.sh                    # Run all E2E tests
#   ./run_e2e.sh --quick            # Run only CLI tests (no expect)
#   ./run_e2e.sh --with-expect      # Install expect and run all tests
#   ./run_e2e.sh test_happy_path    # Run specific test file
# ============================================================

set -euo pipefail

# Determine paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$PROJECT_ROOT/tests"
E2E_DIR="$TESTS_DIR/e2e"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

# Options
QUICK_MODE=false
INSTALL_EXPECT=false
SPECIFIC_TEST=""
VERBOSE=false

# ============================================================
# Argument Parsing
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        --with-expect)
            INSTALL_EXPECT=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] [test_file]"
            echo ""
            echo "Options:"
            echo "  --quick, -q       Run only CLI tests (no expect required)"
            echo "  --with-expect     Install expect if missing, then run all tests"
            echo "  --verbose, -v     Show verbose output"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Arguments:"
            echo "  test_file         Run specific test file (e.g., test_happy_path)"
            exit 0
            ;;
        test_*)
            SPECIFIC_TEST="$1"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ============================================================
# Prerequisites Check
# ============================================================

check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"

    # Check bats
    if ! command -v bats &>/dev/null; then
        echo -e "${RED}ERROR: bats not found${NC}"
        echo "Install with: apt install bats"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} bats found"

    # Check expect (optional)
    if command -v expect &>/dev/null; then
        echo -e "${GREEN}✓${NC} expect found"
    else
        if [[ "$INSTALL_EXPECT" == "true" ]]; then
            echo -e "${YELLOW}Installing expect...${NC}"
            if sudo apt-get install -y expect &>/dev/null; then
                echo -e "${GREEN}✓${NC} expect installed"
            else
                echo -e "${YELLOW}⚠${NC} Could not install expect"
            fi
        else
            echo -e "${YELLOW}⚠${NC} expect not found (some tests will be skipped)"
            echo "  Install with: apt install expect"
            echo "  Or run with: --with-expect"
        fi
    fi

    # Check script command (for PTY)
    if command -v script &>/dev/null; then
        echo -e "${GREEN}✓${NC} script found (PTY support)"
    else
        echo -e "${YELLOW}⚠${NC} script not found (limited TUI testing)"
    fi

    echo ""
}

# ============================================================
# Environment Setup
# ============================================================

setup_environment() {
    echo -e "${BLUE}Setting up test environment...${NC}"

    # Create logs directory
    mkdir -p "$E2E_DIR/logs"

    # Set environment variables
    export E2E_DIR
    export PROJECT_ROOT
    export GTBI_LIB_DIR="$PROJECT_ROOT/scripts/lib"

    # Disable CI detection for interactive tests
    unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL TRAVIS CIRCLECI

    # Set terminal
    export TERM="${TERM:-xterm-256color}"
    export COLUMNS="${COLUMNS:-80}"
    export LINES="${LINES:-24}"

    echo -e "${GREEN}✓${NC} Environment configured"
    echo ""
}

# ============================================================
# Test Execution
# ============================================================

run_tests() {
    local test_files=()

    if [[ -n "$SPECIFIC_TEST" ]]; then
        # Run specific test
        if [[ -f "$E2E_DIR/${SPECIFIC_TEST}.bats" ]]; then
            test_files=("$E2E_DIR/${SPECIFIC_TEST}.bats")
        else
            echo -e "${RED}Test file not found: ${SPECIFIC_TEST}.bats${NC}"
            exit 1
        fi
    else
        # Run all tests
        test_files=("$E2E_DIR"/test_*.bats)
    fi

    echo -e "${BLUE}Running E2E tests...${NC}"
    echo -e "${GRAY}Test files: ${#test_files[@]}${NC}"
    echo ""

    # Build bats options
    local bats_opts=()
    if [[ "$VERBOSE" == "true" ]]; then
        bats_opts+=("--verbose-run")
    fi
    bats_opts+=("--print-output-on-failure")

    # Filter tests in quick mode
    if [[ "$QUICK_MODE" == "true" ]]; then
        echo -e "${YELLOW}Quick mode: Skipping expect-based tests${NC}"
        echo ""
        # We'll use the skip_without_expect helper in tests
        export GTBI_E2E_QUICK_MODE=1
    fi

    # Run bats
    local start_time
    start_time=$(date +%s)

    local exit_code=0
    bats "${bats_opts[@]}" "${test_files[@]}" || exit_code=$?

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo -e "${BLUE}============================================================${NC}"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ All E2E tests passed${NC} (${duration}s)"
    else
        echo -e "${RED}✗ Some E2E tests failed${NC} (${duration}s)"
    fi
    echo -e "${BLUE}============================================================${NC}"

    return $exit_code
}

# ============================================================
# Cleanup
# ============================================================

cleanup() {
    # Clean up old log files (keep last 10)
    if [[ -d "$E2E_DIR/logs" ]]; then
        local log_count
        log_count=$(find "$E2E_DIR/logs" -name "*.log" -type f | wc -l)
        if [[ $log_count -gt 50 ]]; then
            echo -e "${GRAY}Cleaning up old logs...${NC}"
            find "$E2E_DIR/logs" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
        fi
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          GTBI E2E Test Suite                              ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites
    setup_environment
    cleanup

    run_tests
}

main "$@"
