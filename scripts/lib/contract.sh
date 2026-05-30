#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# GTBI Installer - Runtime Contract Validation
# Ensures required env vars and helper functions exist before
# invoking generated modules or orchestrator logic.
#
# NOTE: Do not enable strict mode here. This file is sourced
# by other scripts and must not leak set -euo pipefail.
# ============================================================

CONTRACT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${GTBI_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$CONTRACT_SCRIPT_DIR/logging.sh" 2>/dev/null || true
fi

gtbi_require_contract() {
    local context="${1:-generated}"
    local missing=()

    [[ -z "${TARGET_USER:-}" ]] && missing+=("TARGET_USER")
    [[ -z "${TARGET_HOME:-}" ]] && missing+=("TARGET_HOME")
    [[ -z "${MODE:-}" ]] && missing+=("MODE")

    # When running via curl|bash, SCRIPT_DIR is empty and we expect
    # a bootstrap directory to be prepared with libs, manifest, assets.
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        [[ -z "${GTBI_BOOTSTRAP_DIR:-}" ]] && missing+=("GTBI_BOOTSTRAP_DIR")
        [[ -z "${GTBI_LIB_DIR:-}" ]] && missing+=("GTBI_LIB_DIR")
        [[ -z "${GTBI_GENERATED_DIR:-}" ]] && missing+=("GTBI_GENERATED_DIR")
        [[ -z "${GTBI_ASSETS_DIR:-}" ]] && missing+=("GTBI_ASSETS_DIR")
        [[ -z "${GTBI_CHECKSUMS_YAML:-}" ]] && missing+=("GTBI_CHECKSUMS_YAML")
        [[ -z "${GTBI_MANIFEST_YAML:-}" ]] && missing+=("GTBI_MANIFEST_YAML")
    fi

    if ! declare -f log_detail >/dev/null 2>&1; then
        missing+=("log_detail function")
    fi
    if ! declare -f run_as_target >/dev/null 2>&1; then
        missing+=("run_as_target function")
    fi
    if ! declare -f run_as_target_shell >/dev/null 2>&1; then
        missing+=("run_as_target_shell function")
    fi
    if ! declare -f run_as_root_shell >/dev/null 2>&1; then
        missing+=("run_as_root_shell function")
    fi
    if ! declare -f run_as_current_shell >/dev/null 2>&1; then
        missing+=("run_as_current_shell function")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        if declare -f log_error >/dev/null 2>&1; then
            log_error "GTBI contract violation (${context})"
            if declare -f log_detail >/dev/null 2>&1; then
                log_detail "Missing: ${missing[*]}"
                log_detail "Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions."
            else
                echo "    Missing: ${missing[*]}" >&2
                echo "    Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions." >&2
            fi
        else
            echo "ERROR: GTBI contract violation (${context})" >&2
            echo "Missing: ${missing[*]}" >&2
            echo "Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions." >&2
        fi
        return 1
    fi

    return 0
}
