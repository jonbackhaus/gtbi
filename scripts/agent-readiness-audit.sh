#!/usr/bin/env bash
# agent-readiness-audit.sh - local GTBI agent CLI and CAAM account readiness audit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${GTBI_AGENT_READINESS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if ! command -v bun >/dev/null 2>&1; then
    echo "agent-readiness-audit requires bun" >&2
    exit 127
fi

cd "$REPO_ROOT/packages/manifest"
exec bun run src/agent-readiness-audit.ts "$@"
