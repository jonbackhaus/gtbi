#!/usr/bin/env bash
# ============================================================
# GTBI Resume Behavior Integration Checks
#
# These tests validate state.sh resume logic in a realistic environment
# without re-running the full installer multiple times.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../scripts/lib/state.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/state.sh"

failures=0

pass() {
  echo "✅ $1"
}

fail() {
  echo "❌ $1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, got $actual)"
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_false() {
  local label="$1"
  shift
  if "$@"; then
    fail "$label"
  else
    pass "$label"
  fi
}

assert_file_missing() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    fail "$label (file still exists: $path)"
  else
    pass "$label"
  fi
}

new_state_file() {
  local tag="$1"
  local home="/tmp/gtbi-home-${tag}-$$-${RANDOM}"
  echo "${home}/state.json"
}

init_state_with_completed() {
  local state_file="$1"
  shift

  export GTBI_STATE_FILE="$state_file"
  export GTBI_HOME
  GTBI_HOME="$(dirname "$state_file")"
  export MODE="vibe"
  export TARGET_USER="ubuntu"
  export GTBI_VERSION="0.3.0"

  state_init

  for phase in "$@"; do
    state_phase_complete "$phase"
  done
}

test_normal_resume() {
  local state_file
  state_file="$(new_state_file normal)"
  init_state_with_completed "$state_file" \
    "user_setup" "filesystem" "shell_setup" "cli_tools" "languages"

  export GTBI_FORCE_REINSTALL=false
  export GTBI_FORCE_RESUME=false
  export GTBI_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 0 "$rc" "normal resume returns 0"

  assert_true "completed phase is skipped (user_setup)" state_should_skip_phase "user_setup"
  assert_false "pending phase is not skipped (agents)" state_should_skip_phase "agents"
}

test_force_reinstall() {
  local state_file
  state_file="$(new_state_file force)"
  init_state_with_completed "$state_file" "user_setup" "filesystem"

  export GTBI_FORCE_REINSTALL=true
  export GTBI_FORCE_RESUME=false
  export GTBI_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "force reinstall returns 1 (fresh install)"
  assert_file_missing "$state_file" "force reinstall removes state file"
  export GTBI_FORCE_REINSTALL=false
}

test_force_resume_without_completed_phases() {
  local state_file
  state_file="$(new_state_file force-resume-empty)"
  init_state_with_completed "$state_file"
  state_update '.failed_phase = "user_setup"'

  export GTBI_FORCE_REINSTALL=false
  export GTBI_FORCE_RESUME=true
  export GTBI_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 0 "$rc" "force resume works when a phase failed before any phase completed"

  export GTBI_FORCE_RESUME=false
}

test_force_reinstall_without_completed_phases() {
  local state_file
  state_file="$(new_state_file force-reinstall-empty)"
  init_state_with_completed "$state_file"
  state_update '.failed_phase = "user_setup"'

  export GTBI_FORCE_REINSTALL=true
  export GTBI_FORCE_RESUME=false
  export GTBI_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "force reinstall works when a phase failed before any phase completed"
  assert_file_missing "$state_file" "force reinstall removes failed zero-progress state file"

  export GTBI_FORCE_REINSTALL=false
}

test_corrupted_state() {
  local state_file
  state_file="$(new_state_file corrupt)"
  mkdir -p "$(dirname "$state_file")"
  printf '%s' "not json" > "$state_file"
  export GTBI_STATE_FILE="$state_file"
  export GTBI_HOME
  GTBI_HOME="$(dirname "$state_file")"

  export GTBI_FORCE_REINSTALL=false
  export GTBI_FORCE_RESUME=false
  export GTBI_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "corrupted state returns fresh install"
  assert_file_missing "$state_file" "corrupted state file is removed"
}

test_interrupt_phase() {
  local state_file
  state_file="$(new_state_file interrupt)"
  init_state_with_completed "$state_file"

  phase_fail() { return 2; }
  phase_ok() { return 0; }

  run_phase "cli_tools" "4/9 CLI Tools" phase_fail || true
  assert_false "failed phase not marked complete" state_is_phase_completed "cli_tools"

  run_phase "cli_tools" "4/9 CLI Tools" phase_ok
  local rc=$?
  assert_eq 0 "$rc" "rerun phase succeeds after failure"
  assert_true "phase marked complete after rerun" state_is_phase_completed "cli_tools"
}

test_state_lock_tracks_current_state_file() {
  local first_state second_state first_fd first_lock second_fd second_lock
  first_state="$(new_state_file lock-first)"
  second_state="$(new_state_file lock-second)"

  export GTBI_STATE_FILE="$first_state"
  _state_acquire_lock || {
    fail "state lock acquired for first state file"
    return
  }
  first_fd="$GTBI_LOCK_FD"
  first_lock="$(readlink "/proc/$$/fd/$first_fd" 2>/dev/null || true)"
  _state_release_lock

  export GTBI_STATE_FILE="$second_state"
  _state_acquire_lock || {
    fail "state lock acquired for second state file"
    return
  }
  second_fd="$GTBI_LOCK_FD"
  second_lock="$(readlink "/proc/$$/fd/$second_fd" 2>/dev/null || true)"
  _state_release_lock

  assert_eq "${first_state}.lock" "$first_lock" "first state lock targets first state file"
  assert_eq "${second_state}.lock" "$second_lock" "state lock retargets after GTBI_STATE_FILE changes"
}

test_state_write_atomic_does_not_sync_by_default() {
  local state_file sync_calls content
  state_file="$(new_state_file no-sync)"
  mkdir -p "$(dirname "$state_file")"
  content='{"ok":true}'
  sync_calls=0

  sync() {
    sync_calls=$((sync_calls + 1))
    return 99
  }

  export GTBI_STATE_DURABLE_SYNC=false
  if ! state_write_atomic "$state_file" "$content"; then
    unset -f sync
    fail "state_write_atomic succeeds when sync is unavailable by default"
    return
  fi
  unset -f sync

  assert_eq 0 "$sync_calls" "state_write_atomic does not call sync by default"
  assert_eq "$content" "$(tr -d '\n' < "$state_file")" "state_write_atomic writes expected content"
}

test_version_mismatch() {
  local state_file
  state_file="$(new_state_file version)"
  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
{
  "schema_version": 99,
  "version": "9.9.9",
  "completed_phases": []
}
EOF
  export GTBI_STATE_FILE="$state_file"
  export GTBI_HOME
  GTBI_HOME="$(dirname "$state_file")"

  local rc
  if state_check_version; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "version mismatch returns incompatible"
}

main() {
  echo ""
  echo "=== GTBI Resume Behavior Checks ==="
  test_normal_resume
  test_corrupted_state
  test_force_reinstall
  test_force_resume_without_completed_phases
  test_force_reinstall_without_completed_phases
  test_interrupt_phase
  test_state_lock_tracks_current_state_file
  test_state_write_atomic_does_not_sync_by_default
  test_version_mismatch

  echo ""
  if [[ "$failures" -gt 0 ]]; then
    echo "Resume checks: ${failures} failure(s)" >&2
    exit 1
  fi

  echo "Resume checks: all passed"
}

main "$@"
