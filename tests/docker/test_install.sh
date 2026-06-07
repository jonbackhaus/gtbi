#!/usr/bin/env bash
# ============================================================
# GTBI Installer - Fresh Install Test (Docker)
#
# Runs the full installer, verifies all key tools, then checks
# idempotency by running the installer a second time.
#
# Runs INSIDE a Docker container. Mount the repo at /repo:
#
#   docker run --rm \
#     -e GTBI_CI=true \
#     -v /path/to/gtbi:/repo:rw \
#     ubuntu:25.10 bash /repo/tests/docker/test_install.sh
#
# Environment:
#   GTBI_TEST_MODE   vibe|safe (default: vibe)
#   GTBI_TEST_STRICT true|false (default: false)
# ============================================================

set -euo pipefail

ARTIFACTS_DIR="/repo/tests/artifacts"
mkdir -p "$ARTIFACTS_DIR"

log()  { echo "[GTBI-INSTALL] $1"; }
fail() { echo "[FAIL] $1" >&2; exit 1; }

# Bootstrap prerequisites if not already present
if ! command -v sudo >/dev/null 2>&1; then
    log "Installing bootstrap prerequisites..."
    apt-get update -qq
    apt-get install -y -qq sudo curl git ca-certificates jq unzip tar xz-utils gnupg >/dev/null
fi

# Pre-configure sudoers if not already done
if [[ ! -f /etc/sudoers.d/90-gtbi-ubuntu ]]; then
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-gtbi-ubuntu
    chmod 440 /etc/sudoers.d/90-gtbi-ubuntu
fi

TEST_MODE="${GTBI_TEST_MODE:-vibe}"
STRICT="${GTBI_TEST_STRICT:-false}"

INSTALL_ARGS=(--yes --skip-preflight --skip-ubuntu-upgrade --mode "${TEST_MODE}")
[[ "$STRICT" == "true" ]] && INSTALL_ARGS+=(--strict)

# ── Phase 1: Fresh Install ─────────────────────────────────────────────────────

log "Phase 1: Fresh Install (mode=${TEST_MODE})"
if GTBI_CI=true bash /repo/install.sh "${INSTALL_ARGS[@]}" > "${ARTIFACTS_DIR}/install.log" 2>&1; then
    log "Install successful"
else
    log "Install failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/install.log"
    fail "Fresh install failed"
fi

# ── Phase 2: Verification ─────────────────────────────────────────────────────

log "Phase 2: Verification"
VERIFY_LOG="${ARTIFACTS_DIR}/install_verify.log"
failed=0

check() {
    local name="$1" cmd="$2" optional="${3:-}"
    if su - ubuntu -c "$cmd" >> "$VERIFY_LOG" 2>&1; then
        echo "  [ok] $name"
    elif [[ "$optional" == "optional" ]]; then
        echo "  [skip] $name (optional)"
    else
        echo "  [fail] $name"
        failed=$((failed + 1))
    fi
}

check "version_file"    "zsh -ic 'test -f ~/.gtbi/VERSION'"
check "doctor"          "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'"

# System tools
check "gh"       "zsh -ic 'gh --version >/dev/null'"
check "jq"       "zsh -ic 'jq --version >/dev/null'"
check "sg"       "zsh -ic 'sg --version >/dev/null'"
check "git_lfs"  "zsh -ic 'git-lfs version >/dev/null'"
check "rsync"    "zsh -ic 'rsync --version >/dev/null'"
check "strace"   "zsh -ic 'strace --version >/dev/null'"
check "lsof"     "zsh -ic 'command -v lsof >/dev/null'"
check "dig"      "zsh -ic 'command -v dig >/dev/null'"
check "nc"       "zsh -ic 'command -v nc >/dev/null'"

# GTBI tools
check "onboard" "zsh -ic 'onboard --help >/dev/null'"

# Dicklesworthstone stack (optional — not installed by default in GTBI)
check "ntm"        "zsh -ic 'ntm --help >/dev/null'"                               optional
check "ubs"        "zsh -ic 'ubs --help >/dev/null'"                               optional
check "bv"         "zsh -ic 'bv --help >/dev/null'"                                optional
check "cass"       "zsh -ic 'cass --help >/dev/null'"                              optional
check "cm"         "zsh -ic 'cm --help >/dev/null'"                                optional
check "caam"       "zsh -ic 'caam --help >/dev/null'"                              optional
check "slb"        "zsh -ic 'slb --help >/dev/null'"                               optional
check "dcg"        "zsh -ic 'dcg --version >/dev/null'"                            optional
check "dcg_doctor" "zsh -ic 'dcg doctor >/dev/null 2>&1'"                          optional
check "ru"         "zsh -ic 'ru --version >/dev/null'"                             optional
check "br"         "zsh -ic 'br --version >/dev/null'"                             optional

# Stack tools (optional — may not be installed in all configurations)
check "ms"      "zsh -ic 'ms --version >/dev/null'"                           optional
check "apr"     "zsh -ic 'apr --help >/dev/null'"                             optional
check "jfp"     "zsh -ic 'jfp --version >/dev/null'"                          optional
check "pt"      "zsh -ic 'pt --help >/dev/null'"                              optional
check "brenner" "zsh -ic 'brenner --version >/dev/null 2>&1 || brenner --help >/dev/null 2>&1'" optional
check "rch"     "zsh -ic 'rch --version >/dev/null 2>&1 || rch --help >/dev/null 2>&1'"         optional
check "wa"      "zsh -ic 'wa --version >/dev/null 2>&1 || wa --help >/dev/null 2>&1'"           optional
check "sysmoni" "zsh -ic 'sysmoni --version >/dev/null 2>&1 || sysmoni --help >/dev/null 2>&1'" optional

# AI agents
check "claude" "zsh -ic 'claude --version >/dev/null'"
check "codex"  "zsh -ic 'codex --version >/dev/null'"
check "gemini" "zsh -ic 'gemini --version >/dev/null'"

if [[ $failed -gt 0 ]]; then
    log "Verification failed with $failed error(s). See $VERIFY_LOG"
    fail "Verification failed"
fi

# ── Phase 3: Idempotency ───────────────────────────────────────────────────────

log "Phase 3: Idempotency Check"
if GTBI_CI=true bash /repo/install.sh "${INSTALL_ARGS[@]}" > "${ARTIFACTS_DIR}/idempotency.log" 2>&1; then
    log "Idempotency run successful"
else
    log "Idempotency run failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/idempotency.log"
    fail "Idempotency failed"
fi

if ! su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'" >/dev/null 2>&1; then
    fail "Doctor failed after idempotency run"
fi

log "ALL TESTS PASSED"
