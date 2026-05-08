#!/usr/bin/env bash
# ============================================================
# Lint: RCH Offload Policy
#
# Agent-facing docs and templates must not teach CPU-heavy Rust
# commands without the explicit RCH offload prefix.
#
# Suppress intentional explanatory examples with:
#   rch-policy: allow
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SUPPRESSION_MARKER="rch-policy: allow"
CARGO_RCH_RE='(^|[^[:alnum:]_./-])cargo[[:space:]]+(build|test|clippy|check|bench|doc|run)([[:space:]]|$|[^[:alnum:]_-])'
CROSS_RCH_RE='(^|[^[:alnum:]_./-])cross[[:space:]]+(build|test|clippy|check|run)([[:space:]]|$|[^[:alnum:]_-])'
RUSTC_RCH_RE='(^|[^[:alnum:]_./-])rustc([[:space:]]|$|[^[:alnum:]_-])'

DEFAULT_TARGETS=(
    "AGENTS.md"
    "README.md"
    "acfs/AGENTS.md"
    "scripts/generate-root-agents-md.sh"
    "scripts/lib/newproj_agents.sh"
    "acfs/onboard/lessons/17_rch.md"
    "acfs/onboard/lessons/21_git_strategy.md"
    "apps/web/components/lessons/agents-md-lesson.tsx"
)

if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=("${DEFAULT_TARGETS[@]}")
fi

violations=0
checked_files=0

echo "=== RCH Offload Policy Linter ==="
echo "Scanning agent-facing docs/templates for local CPU-heavy Rust commands..."
echo ""

requires_rch_offload() {
    local line="$1"

    [[ "$line" == *"$SUPPRESSION_MARKER"* ]] && return 1
    [[ "$line" == *"rch exec --"* ]] && return 1

    if [[ "$line" =~ $CARGO_RCH_RE ]]; then
        return 0
    fi
    if [[ "$line" =~ $CROSS_RCH_RE ]]; then
        return 0
    fi
    if [[ "$line" =~ $RUSTC_RCH_RE ]]; then
        return 0
    fi

    return 1
}

scan_file() {
    local relative_path="$1"
    local file="$REPO_ROOT/$relative_path"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: target file missing: $relative_path"
        violations=$((violations + 1))
        return 0
    fi

    checked_files=$((checked_files + 1))

    local lineno=0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        if requires_rch_offload "$line"; then
            echo "VIOLATION: $relative_path:$lineno: CPU-heavy Rust command must use RCH"
            echo "  $line"
            echo "  Fix: prefix build/test/check/clippy/run examples with 'rch exec --'."
            echo "  Suppress only explanatory non-agent examples with '$SUPPRESSION_MARKER'."
            echo ""
            violations=$((violations + 1))
        fi
    done < "$file"
}

for target in "${TARGETS[@]}"; do
    scan_file "$target"
done

echo "---"
echo "Checked $checked_files files, found $violations violation(s)."

if [[ $violations -gt 0 ]]; then
    exit 1
fi

echo "PASS: RCH offload policy examples are compliant."
