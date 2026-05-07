#!/usr/bin/env bash
# ============================================================
# ACFS Progress Bar Library
# Provides visual progress tracking during tool installation.
#
# Related: bead bd-21kh
# ============================================================

# NOTE: Do not enable strict mode here. This file is sourced by
# installers and must not leak set -euo pipefail.

# Global progress state
ACFS_PROGRESS_TOTAL=0
ACFS_PROGRESS_CURRENT=0
ACFS_PROGRESS_START_TIME=0
ACFS_PROGRESS_ENABLED=true
ACFS_PROGRESS_IS_TTY=false
ACFS_PROGRESS_LAST_LINE_LEN=0

_progress_is_nonnegative_integer() {
    local value="${1:-}"
    [[ "$value" =~ ^[0-9]+$ ]]
}

_progress_is_positive_integer() {
    local value="${1:-}"
    _progress_is_nonnegative_integer "$value" || return 1
    (( 10#$value > 0 ))
}

# Check if we should use color/formatting
_progress_check_tty() {
    # Disable progress bar if NO_COLOR is set or output is not a TTY
    if [[ -n "${NO_COLOR:-}" ]]; then
        ACFS_PROGRESS_ENABLED=true  # Still show text, just no colors
        ACFS_PROGRESS_IS_TTY=false
    elif [[ -t 2 ]]; then
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=true
    else
        # Non-TTY (piped output) - use simple line-by-line
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=false
    fi
}

# Initialize progress tracking
# Usage: progress_init <total_items>
progress_init() {
    local total="${1:-0}"

    _progress_check_tty

    if ! _progress_is_positive_integer "$total"; then
        ACFS_PROGRESS_TOTAL=0
        ACFS_PROGRESS_CURRENT=0
        ACFS_PROGRESS_START_TIME=0
        ACFS_PROGRESS_LAST_LINE_LEN=0
        ACFS_PROGRESS_ENABLED=false
        return
    fi

    ACFS_PROGRESS_TOTAL="$total"
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_START_TIME=$(date +%s)
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Build ASCII progress bar
# Usage: _progress_bar <current> <total> <width>
_progress_bar() {
    local current="${1:-0}"
    local total="${2:-0}"
    local width="${3:-20}"

    if ! _progress_is_positive_integer "$width"; then
        width=20
    fi

    if ! _progress_is_positive_integer "$total" || ! _progress_is_nonnegative_integer "$current"; then
        printf '%*s' "$width" ""
        return
    fi

    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf '%s' "$bar"
}

# Update progress display
# Usage: progress_update <item_name> [<item_description>]
progress_update() {
    local item_name="${1:-}"
    local item_desc="${2:-}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_positive_integer "${ACFS_PROGRESS_TOTAL:-0}"; then
        ACFS_PROGRESS_ENABLED=false
        return
    fi
    if ! _progress_is_nonnegative_integer "${ACFS_PROGRESS_CURRENT:-0}"; then
        ACFS_PROGRESS_CURRENT=0
    fi

    ((ACFS_PROGRESS_CURRENT++)) || true

    local current="$ACFS_PROGRESS_CURRENT"
    local total="$ACFS_PROGRESS_TOTAL"
    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi

    # Truncate item name if too long
    local display_name="$item_name"
    if [[ ${#display_name} -gt 35 ]]; then
        display_name="${display_name:0:32}..."
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]]; then
        # Interactive TTY: in-place update
        local bar
        bar="$(_progress_bar "$current" "$total" 20)"

        # Build the progress line
        local line
        printf -v line "[%s] %d/%d (%d%%) %s" "$bar" "$current" "$total" "$percent" "$display_name"

        # Clear previous line and print new one
        # Use carriage return to overwrite, then clear to end of line
        printf '\r\033[K%s' "$line" >&2

        ACFS_PROGRESS_LAST_LINE_LEN=${#line}
    else
        # Non-TTY or NO_COLOR: simple line-by-line output
        printf '[%d/%d] Installing %s...\n' "$current" "$total" "$display_name" >&2
    fi
}

# Mark progress as complete (add newline for TTY mode)
progress_finish() {
    local total="${ACFS_PROGRESS_TOTAL:-0}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_nonnegative_integer "$total"; then
        total=0
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]] && [[ "$ACFS_PROGRESS_LAST_LINE_LEN" -gt 0 ]]; then
        # Print completion message and newline
        local bar
        bar="$(_progress_bar "$total" "$total" 20)"
        printf '\r\033[K[%s] %d/%d (100%%) Complete\n' "$bar" "$total" "$total" >&2
    fi

    # Reset state
    ACFS_PROGRESS_TOTAL=0
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Helper to count modules for a category/phase
# Usage: progress_count_modules <category> <phase>
# Returns count via stdout
progress_count_modules() {
    local category="$1"
    local phase="$2"
    local count=0
    local module key

    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "0"
        return
    fi

    for module in "${ACFS_EFFECTIVE_PLAN[@]:-}"; do
        key="$module"
        if [[ "${ACFS_MODULE_CATEGORY[$key]:-}" == "$category" ]] && \
           [[ "${ACFS_MODULE_PHASE[$key]:-}" == "$phase" ]]; then
            ((count++)) || true
        fi
    done

    echo "$count"
}
