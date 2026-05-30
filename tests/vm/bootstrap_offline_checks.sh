#!/usr/bin/env bash
# ============================================================
# GTBI Bootstrap - Offline Simulation Test
#
# Validates the curl|bash bootstrap path without network by
# serving a local archive via a stubbed curl binary.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
  echo "[bootstrap-offline] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd tar
require_cmd bash
require_cmd grep
require_cmd cp
require_cmd mktemp

# This test exercises install.sh's archive bootstrap which uses GNU tar flags
# like --wildcards/--strip-components/--wildcards-match-slash.
# On macOS (BSD tar), these flags are not available; skip locally.
if ! tar --help 2>/dev/null | grep -q -- '--wildcards'; then
  log "Skipping offline bootstrap checks: GNU tar required (missing --wildcards)"
  exit 0
fi

create_archive() {
  local archive_path="$1"
  log "Creating archive: $archive_path"
  # Portable archive creation (GNU tar and BSD tar compatible):
  # create a staging dir with an explicit top-level folder, then tar it.
  local stage_dir
  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/gtbi-offline-stage.XXXXXX")"

  mkdir -p "$stage_dir/gtbi-offline/scripts"

  cp -R "$REPO_ROOT/scripts/lib" "$stage_dir/gtbi-offline/scripts/"
  cp -R "$REPO_ROOT/scripts/generated" "$stage_dir/gtbi-offline/scripts/"
  cp "$REPO_ROOT/scripts/preflight.sh" "$stage_dir/gtbi-offline/scripts/preflight.sh"
  # gtbi-global and gtbi-update are tracked in scripts/generated/internal_checksums.sh
  # (GTBI_INTERNAL_CHECKSUMS), so install.sh's integrity check will treat them as
  # "missing" and fail unless they're in the bootstrap archive.
  cp "$REPO_ROOT/scripts/gtbi-global" "$stage_dir/gtbi-offline/scripts/gtbi-global"
  cp "$REPO_ROOT/scripts/gtbi-update" "$stage_dir/gtbi-offline/scripts/gtbi-update"

  cp -R "$REPO_ROOT/gtbi" "$stage_dir/gtbi-offline/gtbi"
  cp "$REPO_ROOT/checksums.yaml" "$stage_dir/gtbi-offline/checksums.yaml"
  cp "$REPO_ROOT/gtbi.manifest.yaml" "$stage_dir/gtbi-offline/gtbi.manifest.yaml"
  cp "$REPO_ROOT/VERSION" "$stage_dir/gtbi-offline/VERSION"

  tar -czf "$archive_path" -C "$stage_dir" gtbi-offline
}

create_bad_archive() {
  local good_archive="$1"
  local bad_archive="$2"
  local bad_dir
  bad_dir="$(mktemp -d "${TMPDIR:-/tmp}/gtbi-offline-bad.XXXXXX")"

  log "Creating bad archive: $bad_archive"
  tar -xzf "$good_archive" -C "$bad_dir"
  printf '\n# bootstrap mismatch\n' >> "$bad_dir/gtbi-offline/gtbi.manifest.yaml"
  tar -czf "$bad_archive" -C "$bad_dir" gtbi-offline
}

create_stub_curl() {
  local stub_dir
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/gtbi-curl-stub.XXXXXX")"

  cat > "$stub_dir/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
  if [[ "$arg" == "--help" ]]; then
    echo "--proto"
    exit 0
  fi
  if [[ "$arg" == "--help"* ]]; then
    echo "--proto"
    exit 0
  fi
done

out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$arg"
    break
  fi
  prev="$arg"
done

if [[ -z "$out" ]]; then
  echo "stub curl: missing -o" >&2
  exit 1
fi

if [[ -z "${GTBI_TEST_ARCHIVE:-}" ]]; then
  echo "stub curl: GTBI_TEST_ARCHIVE not set" >&2
  exit 1
fi

cp "$GTBI_TEST_ARCHIVE" "$out"
CURL

  chmod +x "$stub_dir/curl"
  echo "$stub_dir"
}

run_bootstrap() {
  local archive_path="$1"
  local label="$2"
  local expect_failure="${3:-false}"

  log "$label: running bootstrap (archive=$archive_path)"
  local stub_dir
  stub_dir="$(create_stub_curl)"

  if [[ "$expect_failure" == "true" ]]; then
    set +e
    local output
    output="$(GTBI_TEST_MODE=1 GTBI_TEST_ARCHIVE="$archive_path" PATH="$stub_dir:$PATH" bash -lc "cat '$REPO_ROOT/install.sh' | bash -s -- --list-modules" 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
      echo "$output" >&2
      echo "ERROR: expected bootstrap failure for $label" >&2
      exit 1
    fi

    echo "$output" | grep -q "Bootstrap mismatch" || {
      echo "$output" >&2
      echo "ERROR: expected bootstrap mismatch message for $label" >&2
      exit 1
    }

    log "$label: bootstrap failure detected as expected"
    return 0
  fi

  set +e
  local output
  output="$(GTBI_TEST_MODE=1 GTBI_TEST_ARCHIVE="$archive_path" PATH="$stub_dir:$PATH" bash -lc "cat '$REPO_ROOT/install.sh' | bash -s -- --list-modules" 2>&1)"
  local status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "$output" >&2
    echo "ERROR: bootstrap command failed for $label (exit $status)" >&2
    exit 1
  fi

  echo "$output" | grep -q "Bootstrap archive ready" || {
    echo "$output" >&2
    echo "ERROR: bootstrap archive not reported ready for $label" >&2
    exit 1
  }

  echo "$output" | grep -q "Available GTBI Modules" || {
    echo "$output" >&2
    echo "ERROR: list-modules output missing for $label" >&2
    exit 1
  }

  log "$label: bootstrap success"
}

main() {
  local good_archive
  local bad_archive

  # mktemp portability: BSD mktemp requires Xs at the end of the template
  good_archive="$(mktemp "${TMPDIR:-/tmp}/gtbi-offline-archive.XXXXXX")"
  bad_archive="$(mktemp "${TMPDIR:-/tmp}/gtbi-offline-archive-bad.XXXXXX")"

  create_archive "$good_archive"
  run_bootstrap "$good_archive" "happy-path"

  create_bad_archive "$good_archive" "$bad_archive"
  run_bootstrap "$bad_archive" "mismatch-path" "true"

  log "offline bootstrap checks complete"
}

main "$@"
