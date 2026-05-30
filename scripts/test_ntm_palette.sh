#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
pass() { echo "✅ PASS: $1"; }
fail() { echo "❌ FAIL: $1"; exit 1; }

# ============================================
# Test 1: Palette file exists after install
# ============================================
test_palette_exists() {
    log "Test 1: Palette file exists after install"

    local palette="$HOME/.config/ntm/command_palette.md"

    if [[ -f "$palette" ]]; then
        pass "Test 1: Palette file exists"
    else
        fail "Test 1: Palette file not found at $palette"
    fi
}

# ============================================
# Test 2: Palette has substantial content
# ============================================
test_palette_content() {
    log "Test 2: Palette has substantial content"

    local palette="$HOME/.config/ntm/command_palette.md"
    local lines=$(wc -l < "$palette")

    log "  Palette has $lines lines"

    if [[ $lines -gt 50 ]]; then
        pass "Test 2: Palette has $lines lines (>50)"
    else
        fail "Test 2: Palette too small ($lines lines)"
    fi
}

# ============================================
# Test 3: NTM palette command shows entries
# ============================================
test_ntm_palette_command() {
    log "Test 3: ntm palette shows entries"

    if ! command -v ntm >/dev/null 2>&1; then
        log "  Skipping: ntm not installed"
        pass "Test 3: Skipped (ntm not available)"
        return
    fi

    local count=$(ntm palette --list 2>/dev/null | wc -l || echo "0")

    log "  ntm palette shows $count entries"

    if [[ $count -gt 5 ]]; then
        pass "Test 3: Palette has $count entries (>5)"
    else
        fail "Test 3: Too few palette entries ($count)"
    fi
}

# ============================================
# Test 4: File owned by current user
# ============================================
test_ownership() {
    log "Test 4: File owned by current user"

    local palette="$HOME/.config/ntm/command_palette.md"
    local owner=$(stat -c '%U' "$palette" 2>/dev/null || stat -f '%Su' "$palette")

    if [[ "$owner" == "$(whoami)" ]]; then
        pass "Test 4: Owned by $owner (correct)"
    else
        fail "Test 4: Owned by $owner, expected $(whoami)"
    fi
}

# ============================================
# Test 5: Works without ~/.gtbi
# ============================================
test_works_without_gtbi() {
    log "Test 5: Works without ~/.gtbi"

    if ! command -v ntm >/dev/null 2>&1; then
        log "  Skipping: ntm not installed"
        pass "Test 5: Skipped"
        return
    fi

    # Temporarily rename .gtbi if it exists
    local gtbi_dir="$HOME/.gtbi"
    local gtbi_backup="$HOME/.gtbi.backup.$$"

    if [[ -d "$gtbi_dir" ]]; then
        mv "$gtbi_dir" "$gtbi_backup"
    fi

    # Test ntm palette still works
    local count=$(ntm palette --list 2>/dev/null | wc -l || echo "0")

    # Restore .gtbi
    if [[ -d "$gtbi_backup" ]]; then
        mv "$gtbi_backup" "$gtbi_dir"
    fi

    if [[ $count -gt 5 ]]; then
        pass "Test 5: Palette works without ~/.gtbi"
    else
        fail "Test 5: Palette broken without ~/.gtbi"
    fi
}

main() {
    echo "========================================"
    echo "NTM Palette E2E Tests"
    echo "========================================"

    test_palette_exists
    test_palette_content
    test_ntm_palette_command
    test_ownership
    test_works_without_gtbi

    echo ""
    echo "========================================"
    echo "All E2E tests passed!"
    echo "========================================"
}

main "$@"
