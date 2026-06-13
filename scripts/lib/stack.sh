#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# GTBI - Gastown Stack Library
# Provides helpers for the Gastown stack: Dolt + beads (bd)
# ============================================================

STACK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${GTBI_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$STACK_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Dolt helpers
# ============================================================

stack_dolt_is_installed() {
    command -v dolt >/dev/null 2>&1
}

stack_dolt_version() {
    dolt version 2>/dev/null | head -1
}

stack_dolt_verify() {
    if ! stack_dolt_is_installed; then
        log_error "Dolt not found in PATH"
        return 1
    fi
    local ver
    ver="$(stack_dolt_version)" || return 1
    log_success "Dolt: $ver"
    return 0
}

# ============================================================
# beads (bd) helpers
# ============================================================

stack_bd_is_installed() {
    command -v bd >/dev/null 2>&1
}

stack_bd_version() {
    bd --version 2>/dev/null | head -1
}

stack_bd_verify() {
    if ! stack_bd_is_installed; then
        log_error "beads (bd) not found in PATH"
        return 1
    fi
    local ver
    ver="$(stack_bd_version)" || return 1
    log_success "beads: $ver"
    return 0
}

# ============================================================
# Gastown (gt) helpers
# ============================================================

stack_gastown_is_installed() {
    command -v gt >/dev/null 2>&1
}

stack_gastown_version() {
    gt version 2>/dev/null | head -1
}

stack_gastown_verify() {
    if ! stack_gastown_is_installed; then
        log_error "Gastown (gt) not found in PATH"
        return 1
    fi
    local ver
    ver="$(stack_gastown_version)" || return 1
    log_success "Gastown: $ver"
    return 0
}

# ============================================================
# Stack health check (called by gtbi doctor)
# ============================================================

stack_doctor() {
    local failed=0

    log_section "Gastown Stack"

    if stack_dolt_verify; then
        : # logged in stack_dolt_verify
    else
        ((failed += 1))
    fi

    if stack_bd_verify; then
        : # logged in stack_bd_verify
    else
        ((failed += 1))
    fi

    if stack_gastown_verify; then
        : # logged in stack_gastown_verify
    else
        ((failed += 1))
    fi

    if [[ $failed -gt 0 ]]; then
        log_warn "Stack doctor: $failed component(s) failed"
        return 1
    fi
    log_success "Stack doctor: all components healthy"
    return 0
}
