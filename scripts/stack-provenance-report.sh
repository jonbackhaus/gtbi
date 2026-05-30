#!/usr/bin/env bash
# stack-provenance-report.sh - GTBI stack tool provenance and upstream release report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${GTBI_STACK_PROVENANCE_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if ! command -v bun >/dev/null 2>&1; then
    echo "stack-provenance-report requires bun" >&2
    exit 127
fi

cd "$REPO_ROOT/packages/manifest"
exec bun run src/stack-provenance-report.ts --root "$REPO_ROOT" "$@"
