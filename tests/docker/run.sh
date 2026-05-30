#!/usr/bin/env bash
# ============================================================
# GTBI Docker Test Runner
#
# Local orchestrator for Docker-based integration tests.
# All tests run inside fresh Ubuntu containers against the
# locally checked-out repo.
#
# Usage:
#   ./tests/docker/run.sh install              # Sunny-day fresh install
#   ./tests/docker/run.sh upgrade              # Version upgrade path
#   ./tests/docker/run.sh repair               # Install → corrupt → fix
#   ./tests/docker/run.sh all                  # upgrade + repair
#   ./tests/docker/run.sh --all-ubuntu install # Run on all Ubuntu versions
#
# Options:
#   --ubuntu VERSION   Ubuntu version (e.g. 25.10). Repeatable.
#   --all-ubuntu       Run on 24.04, 25.04, and 25.10
#   --mode MODE        vibe|safe (default: vibe; install subcommand only)
#   --prebake          Build gtbi-prereqs:VERSION before running
#   --use-prebaked     Use gtbi-prereqs:VERSION instead of ubuntu:VERSION
#   --help
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
    cat <<'EOF'
tests/docker/run.sh - GTBI Docker integration test runner

Subcommands:
  install    Sunny-day fresh install, tool verification, and idempotency
  upgrade    Old GTBI release -> current installer -> doctor
  repair     Install -> corrupt -> gtbi doctor --fix -> doctor
  all        Run upgrade and repair

Options:
  --ubuntu VERSION   Ubuntu version (default: 25.10). Repeatable.
  --all-ubuntu       Run on 24.04, 25.04, 25.10
  --mode MODE        vibe|safe (default: vibe)
  --prebake          Build gtbi-prereqs:VERSION before running
  --use-prebaked     Use gtbi-prereqs:VERSION instead of ubuntu:VERSION
  --help

Examples:
  ./tests/docker/run.sh install
  ./tests/docker/run.sh --all-ubuntu upgrade
  ./tests/docker/run.sh --ubuntu 24.04 repair
  ./tests/docker/run.sh --prebake --use-prebaked --ubuntu 25.10 repair
  ./tests/docker/run.sh all
EOF
}

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found — install Docker Desktop or docker engine." >&2
    exit 1
fi

declare -a UBUNTU_VERSIONS=()
SUBCOMMAND=""
MODE="vibe"
PREBAKE=false
USE_PREBAKED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|upgrade|repair|all)
            SUBCOMMAND="$1"
            shift
            ;;
        --ubuntu)
            UBUNTU_VERSIONS+=("${2:?--ubuntu requires a version}")
            shift 2
            ;;
        --all-ubuntu)
            UBUNTU_VERSIONS=("24.04" "25.04" "25.10")
            shift
            ;;
        --mode)
            MODE="${2:?--mode requires vibe or safe}"
            case "$MODE" in vibe|safe) ;; *)
                echo "ERROR: --mode must be vibe or safe (got: '$MODE')" >&2; exit 1 ;;
            esac
            shift 2
            ;;
        --prebake)
            PREBAKE=true
            shift
            ;;
        --use-prebaked)
            USE_PREBAKED=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$SUBCOMMAND" ]]; then
    echo "ERROR: subcommand required (install|upgrade|repair|all)" >&2
    usage >&2
    exit 1
fi

if [[ ${#UBUNTU_VERSIONS[@]} -eq 0 ]]; then
    UBUNTU_VERSIONS=("25.10")
fi

prebake() {
    local version="$1"
    echo "" >&2
    echo "=== Building gtbi-prereqs:${version} ===" >&2
    docker build \
        --build-arg "UBUNTU_VERSION=${version}" \
        -f "${SCRIPT_DIR}/Dockerfile.prereqs" \
        -t "gtbi-prereqs:${version}" \
        "${SCRIPT_DIR}"
}

image_for() {
    local version="$1"
    if [[ "$USE_PREBAKED" == "true" ]]; then
        echo "gtbi-prereqs:${version}"
    else
        echo "ubuntu:${version}"
    fi
}

run_one() {
    local version="$1" test_script="$2"
    local image
    image="$(image_for "$version")"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local scenario
    scenario="$(basename "$test_script" .sh)"

    echo "" >&2
    echo "============================================================" >&2
    echo "[GTBI Test] ${scenario} — Ubuntu ${version}" >&2
    echo "Image: ${image}" >&2
    echo "============================================================" >&2

    mkdir -p "${REPO_ROOT}/tests/artifacts"

    docker pull "$image" >/dev/null 2>&1 || true

    docker run --rm \
        -e DEBIAN_FRONTEND=noninteractive \
        -e GTBI_CI=true \
        -e GTBI_TEST_MODE="${MODE}" \
        -v "${REPO_ROOT}:/repo:rw" \
        "$image" bash "/repo/tests/docker/${scenario}.sh"
}

failures=0

run_scenario() {
    local version="$1" scenario="$2"
    if ! run_one "$version" "$scenario"; then
        echo "" >&2
        echo "[FAIL] ${scenario} on Ubuntu ${version}" >&2
        failures=$((failures + 1))
    fi
}

for version in "${UBUNTU_VERSIONS[@]}"; do
    [[ "$PREBAKE" == "true" ]] && prebake "$version"

    case "$SUBCOMMAND" in
        install)
            run_scenario "$version" "test_install"
            ;;
        upgrade)
            run_scenario "$version" "test_upgrade"
            ;;
        repair)
            run_scenario "$version" "test_repair"
            ;;
        all)
            run_scenario "$version" "test_upgrade"
            run_scenario "$version" "test_repair"
            ;;
    esac
done

echo "" >&2
if [[ $failures -gt 0 ]]; then
    echo "FAIL: ${failures} test run(s) failed." >&2
    exit 1
fi
echo "✓ All requested Docker tests passed." >&2
