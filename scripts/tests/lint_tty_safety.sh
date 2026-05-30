#!/usr/bin/env bash
# ============================================================
# Lint: Non-Interactive (TTY) Safety
#
# `read -r` prompts via stdin. When called from --yes mode or CI
# (no stdin/TTY), it fails or hangs. This caused issue #85.
#
# This linter detects `read -r` calls in lib files that lack both:
#   - A YES_MODE / GTBI_INTERACTIVE guard, AND
#   - A /dev/tty redirect
#
# Scope: scripts/lib/*.sh (excluding test files)
#
# NOTE: Heuristic linter. Suppress false positives with:
#   # lint:tty-ok
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"

warnings=0
checked=0

echo "=== Non-Interactive Safety Linter ==="
echo "Scanning scripts/lib/*.sh for unguarded read -r calls..."
echo ""

for file in "$LIB_DIR"/*.sh; do
    [[ -f "$file" ]] || continue
    basename_file="$(basename "$file")"

    # Skip test files
    if [[ "$basename_file" == test_* ]]; then
        continue
    fi

    ((checked++)) || true

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        lineno="${match%%:*}"
        line="${match#*:}"

        # Skip comments
        stripped="${line#"${line%%[![:space:]]*}"}"
        [[ "$stripped" == \#* ]] && continue

        # Skip lint suppression
        [[ "$line" == *"lint:tty-ok"* ]] && continue

        # Skip if the line reads from /dev/tty (safe for non-interactive)
        [[ "$line" == *"/dev/tty"* ]] && continue

        # Skip if the line reads from a file descriptor or pipe (not stdin)
        [[ "$line" == *"<&"* ]] && continue
        [[ "$line" == *"< <("* ]] && continue

        # Skip read -r inside a while read loop (reading from pipe/file, not user)
        [[ "$stripped" == *"while"*"read"* ]] && continue
        # Heuristic: IFS= read patterns are typically in while loops reading data
        [[ "$stripped" == IFS=* ]] && continue

        # Skip read -r -d '' (delimiter-based reads, typically reading heredocs)
        [[ "$line" == *"read -r -d"*"<<"* ]] && continue
        [[ "$line" == *"read -rd"*"<<"* ]] && continue

        # Skip read -ra (read into array from string, not interactive)
        [[ "$line" == *"read -ra"* ]] && continue

        # Check if there's a YES_MODE or GTBI_INTERACTIVE guard in the
        # surrounding context (within 10 lines before this read)
        has_guard=false
        start_line=$((lineno - 10))
        [[ $start_line -lt 1 ]] && start_line=1

        context=""
        context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null) || context=""

        # Check for common guard patterns
        if echo "$context" | grep -qE 'YES_MODE|GTBI_INTERACTIVE|--yes|non.interactive|is_interactive|is_ci_environment'; then
            has_guard=true
        fi

        # Also check if the enclosing function has a guard (common pattern)
        if echo "$context" | grep -qE 'if \[.*tty|test -t 0|test -t 1'; then
            has_guard=true
        fi

        if [[ "$has_guard" == "true" ]]; then
            continue
        fi

        echo "WARN: $basename_file:$lineno: read -r without YES_MODE guard or /dev/tty redirect"
        echo "  $line"
        echo "  Fix: Add YES_MODE/GTBI_INTERACTIVE check or redirect from /dev/tty"
        echo ""
        ((warnings++)) || true
    done < <(grep -nE '^\s*read\s+-r' "$file" || true)
done

echo "---"
echo "Checked $checked lib files, found $warnings warnings."

if [[ $warnings -gt 0 ]]; then
    echo ""
    echo "WARN: $warnings read -r call(s) without non-interactive guard."
    echo "These may hang or fail in --yes mode or CI (no TTY)."
    echo "Suppress false positives with: # lint:tty-ok"
    echo ""
    # Exit 0 for warnings (P1 linter)
    exit 0
fi

echo "PASS: All read -r calls have non-interactive guards."
exit 0
