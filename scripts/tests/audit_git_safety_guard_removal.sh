#!/usr/bin/env bash
# Audit script to verify complete removal of git_safety_guard
# Run from repo root: ./scripts/tests/audit_git_safety_guard_removal.sh
#
# Related: bead bd-33vh.6

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! REPO_ROOT="$(git -C "$SCRIPT_DIR/../.." rev-parse --show-toplevel 2>/dev/null)"; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
cd "$REPO_ROOT"

echo "=== Auditing git_safety_guard Removal ==="
echo ""

FOUND=0
BLUE="${BLUE:-}"
RED="${RED:-}"
NC="${NC:-}"

filter_allowed_git_safety_guard_refs() {
    grep -v '.beads/' |
        grep -v '^./tests/' |
        grep -v '^./scripts/tests/' |
        grep -v 'scripts/lib/update.sh' |
        grep -v 'CHANGELOG.md'
}

# Check 1: Literal string matches
echo "[1/5] Checking for 'git_safety_guard' literal string..."
# Exclusions:
#   - update.sh: intentional migration cleanup code
#   - CHANGELOG.md: historical documentation
#   - tests: fixtures and removal-verification scripts necessarily mention the legacy name
if grep -rn 'git_safety_guard' --include='*.sh' --include='*.py' --include='*.ts' --include='*.tsx' --include='*.md' --include='*.yaml' --include='*.json' . 2>/dev/null | filter_allowed_git_safety_guard_refs; then
    echo "❌ FOUND: git_safety_guard references"
    FOUND=1
else
    echo "✓ Clean: No git_safety_guard literals found"
fi

# Check 2: 'Git Safety Guard' (display name)
echo ""
echo "[2/5] Checking for 'Git Safety Guard' display name..."
# Same exclusions as check 1
if grep -rni 'Git Safety Guard' --include='*.sh' --include='*.py' --include='*.ts' --include='*.tsx' --include='*.md' . 2>/dev/null | filter_allowed_git_safety_guard_refs; then
    echo "❌ FOUND: Git Safety Guard references"
    FOUND=1
else
    echo "✓ Clean: No 'Git Safety Guard' found"
fi

# Check 3: Python hook file
echo ""
echo "[3/5] Checking for git_safety_guard.py file..."
if find . -name 'git_safety_guard.py' -not -path './.beads/*' -not -path './tests/*' -not -path './scripts/tests/*' 2>/dev/null | grep .; then
    echo "❌ FOUND: git_safety_guard.py file exists"
    FOUND=1
else
    echo "✓ Clean: No git_safety_guard.py file"
fi

# Check 4: Hooks directory
echo ""
echo "[4/5] Checking for gtbi/claude/hooks/ directory..."
if [[ -d "gtbi/claude/hooks" ]]; then
    echo "❌ FOUND: gtbi/claude/hooks/ directory exists"
    FOUND=1
else
    echo "✓ Clean: No gtbi/claude/hooks/ directory"
fi

# Check 5: Doctor check function
echo ""
echo "[5/5] Checking doctor.sh for git_safety references..."
# Check doctor.sh for remaining checks
echo -e "\n${BLUE}Checking doctor.sh...${NC}"
if grep -nE 'safety_guard|Git safety' scripts/lib/doctor.sh 2>/dev/null; then
    echo -e "${RED}Found remaining references in doctor.sh!${NC}"
    FOUND=1
else
    echo "✓ Clean: Doctor.sh has no git_safety references"
fi

echo ""
echo "=== Audit Complete ==="

if [[ $FOUND -eq 0 ]]; then
    echo "✅ All checks passed - git_safety_guard completely removed"
    exit 0
else
    echo "❌ Some checks failed - cleanup needed"
    exit 1
fi
