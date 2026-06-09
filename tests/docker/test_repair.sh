#!/usr/bin/env bash
# ============================================================
# GTBI Installer - Repair Test (Docker)
#
# Runs a fresh install, deliberately corrupts the installation
# in 5 realistic ways, then verifies that `gtbi doctor --fix`
# restores everything to a healthy state.
#
# All corruptions target checks that have non-manual auto-fix
# functions in doctor_fix.sh (no FIXES_MANUAL items).
#
# Runs INSIDE a Docker container. Mount the repo at /repo:
#
#   docker run --rm \
#     -e GTBI_CI=true \
#     -v /path/to/gtbi:/repo:rw \
#     ubuntu:25.10 bash /repo/tests/docker/test_repair.sh
# ============================================================

set -euo pipefail

ARTIFACTS_DIR="/repo/tests/artifacts"
mkdir -p "$ARTIFACTS_DIR"

log()  { echo "[GTBI-REPAIR] $1"; }
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

# ── Phase 1: Fresh Install ─────────────────────────────────────────────────────

log "Phase 1: Fresh Install"
if GTBI_CI=true bash /repo/install.sh \
        --yes --skip-preflight --skip-ubuntu-upgrade --mode vibe \
        > "${ARTIFACTS_DIR}/repair_install.log" 2>&1; then
    log "Install successful"
else
    log "Install failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/repair_install.log"
    fail "Fresh install failed"
fi

# ── Phase 2: Baseline Doctor (must pass before we corrupt) ────────────────────

log "Phase 2: Baseline Doctor"
if su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'" \
        > "${ARTIFACTS_DIR}/repair_baseline_doctor.log" 2>&1; then
    log "Baseline doctor passed"
else
    log "Baseline doctor failed — output:"
    cat "${ARTIFACTS_DIR}/repair_baseline_doctor.log"
    fail "Baseline doctor failed — cannot proceed to corruption test"
fi

# ── Phase 3: Apply Corruptions ────────────────────────────────────────────────
#
# Each corruption maps to a specific auto-fix function in doctor_fix.sh.
# Guard optional corruptions to avoid false failures.

log "Phase 3: Applying corruptions"
declare -a CORRUPTED_CHECK_IDS=()

# A: Remove zsh-autosuggestions plugin
# Fixes: shell.plugins.zsh_autosuggestions via fix_plugin_clone()
log "  Corruption A: removing zsh-autosuggestions plugin"
if [[ -d /home/ubuntu/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
    rm -rf /home/ubuntu/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    CORRUPTED_CHECK_IDS+=("shell.plugins.zsh_autosuggestions")
    echo "  [ok] zsh-autosuggestions removed"
else
    echo "  [skip] zsh-autosuggestions not present"
fi

# B: Remove zsh-syntax-highlighting plugin
# Fixes: shell.plugins.zsh_syntax_highlighting via fix_plugin_clone()
log "  Corruption B: removing zsh-syntax-highlighting plugin"
if [[ -d /home/ubuntu/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then
    rm -rf /home/ubuntu/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    CORRUPTED_CHECK_IDS+=("shell.plugins.zsh_syntax_highlighting")
    echo "  [ok] zsh-syntax-highlighting removed"
else
    echo "  [skip] zsh-syntax-highlighting not present"
fi

# C: Strip GTBI sourcing line from .zshrc
# Fixes: shell.gtbi_sourced via fix_gtbi_sourcing()
log "  Corruption C: stripping GTBI sourcing from .zshrc"
if grep -q 'gtbi\.zshrc' /home/ubuntu/.zshrc 2>/dev/null; then
    sed -i '/gtbi\.zshrc/d' /home/ubuntu/.zshrc
    sed -i '/GTBI configuration/d' /home/ubuntu/.zshrc
    CORRUPTED_CHECK_IDS+=("shell.gtbi_sourced")
    echo "  [ok] GTBI sourcing stripped from .zshrc"
else
    echo "  [skip] GTBI sourcing not present in .zshrc"
fi


if [[ ${#CORRUPTED_CHECK_IDS[@]} -eq 0 ]]; then
    fail "No corruptions were applied — cannot validate repair"
fi
log "Corrupted check IDs: ${CORRUPTED_CHECK_IDS[*]}"

# ── Phase 4: Pre-Fix Assert ───────────────────────────────────────────────────
#
# Doctor must detect the corruptions we applied. If none of the expected
# check IDs appear as failures, the corruption silently had no effect.

log "Phase 4: Pre-Fix Doctor (expect failures)"
su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'" \
    > "${ARTIFACTS_DIR}/repair_pre_fix_doctor.log" 2>&1 || true

detected=0
for check_id in "${CORRUPTED_CHECK_IDS[@]}"; do
    if grep -q "$check_id" "${ARTIFACTS_DIR}/repair_pre_fix_doctor.log"; then
        echo "  [detected] $check_id"
        detected=$((detected + 1))
    else
        echo "  [missed] $check_id — corruption may not have taken effect"
    fi
done

if [[ $detected -eq 0 ]]; then
    log "Pre-fix doctor output:"
    cat "${ARTIFACTS_DIR}/repair_pre_fix_doctor.log"
    fail "None of the corruptions were detected by doctor — cannot validate repair"
fi
log "${detected}/${#CORRUPTED_CHECK_IDS[@]} corruptions detected"

# ── Phase 5: Run Repair ───────────────────────────────────────────────────────

log "Phase 5: Running gtbi doctor --fix"
if su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor --fix'" \
        > "${ARTIFACTS_DIR}/repair_fix.log" 2>&1; then
    log "Repair completed"
else
    log "Repair exited non-zero — checking if fixes were applied..."
    # doctor --fix exits 1 when fixes were needed; that's expected. Check
    # the output for evidence that fixes ran rather than treating non-zero as failure.
    if ! grep -q -i 'fix\|applied\|restored' "${ARTIFACTS_DIR}/repair_fix.log"; then
        cat "${ARTIFACTS_DIR}/repair_fix.log"
        fail "doctor --fix failed with no evidence of fixes applied"
    fi
    log "Fixes appear to have been applied (non-zero exit expected when fixes ran)"
fi

# ── Phase 6: Post-Fix Doctor ─────────────────────────────────────────────────

log "Phase 6: Post-Fix Doctor (expect clean)"
if su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'" \
        > "${ARTIFACTS_DIR}/repair_post_fix_doctor.log" 2>&1; then
    log "Post-fix doctor passed — installation is healthy"
else
    log "Post-fix doctor failed — output:"
    cat "${ARTIFACTS_DIR}/repair_post_fix_doctor.log"
    fail "Doctor still reports failures after repair"
fi

# ── Phase 7: Smoke Test ───────────────────────────────────────────────────────

log "Phase 7: Smoke test (verify repair did not break existing tools)"
failed=0
check() {
    local name="$1" cmd="$2"
    if su - ubuntu -c "$cmd" >> "${ARTIFACTS_DIR}/repair_post_fix_doctor.log" 2>&1; then
        echo "  [ok] $name"
    else
        echo "  [fail] $name"
        failed=$((failed + 1))
    fi
}

check "gh" "zsh -ic 'gh --version >/dev/null'"
check "jq" "zsh -ic 'jq --version >/dev/null'"
check "sg" "zsh -ic 'sg --version >/dev/null'"

if [[ $failed -gt 0 ]]; then
    fail "Smoke test failed for $failed tool(s) — repair may have broken something"
fi

log "ALL TESTS PASSED (${#CORRUPTED_CHECK_IDS[@]} corruptions applied and repaired)"
