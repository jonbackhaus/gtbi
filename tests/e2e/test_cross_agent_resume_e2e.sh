#!/usr/bin/env bash
# ============================================================
# E2E Test: Real Cross-Agent Resume + Native Conversion Matrix
#
# Non-mock integration test that:
#   1. Creates fresh sessions in codex/claude/gemini
#   2. Proves direct cross-resume fails (foreign ID not in target store)
#   3. Converts native X -> native Y and verifies:
#      - output is schema-compatible with real Y sessions
#      - file is written to real Y storage location
#      - Y CLI can resume converted Y session ID
#
# Optional baseline diagnostics:
#   - Self-resume checks for each CLI:
#       GTBI_INCLUDE_SELF_RESUME_BASELINE=true
#
# Artifacts:
#   tests/e2e/logs/cross_agent_resume_<timestamp>.log
#   tests/e2e/logs/cross_agent_resume_<timestamp>.json
#   tests/e2e/logs/cross_agent_resume_<timestamp>/*.log
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/tests/e2e/logs"
ARTIFACT_DIR="$LOG_DIR/cross_agent_resume_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/cross_agent_resume_${TIMESTAMP}.log"
JSON_FILE="$LOG_DIR/cross_agent_resume_${TIMESTAMP}.json"

mkdir -p "$LOG_DIR" "$ARTIFACT_DIR"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

declare -a RESULTS_JSON=()

INCLUDE_SELF_RESUME_BASELINE="${GTBI_INCLUDE_SELF_RESUME_BASELINE:-false}"
RUN_DIRECT_CROSS_BASELINE="${GTBI_INCLUDE_DIRECT_CROSS_BASELINE:-true}"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"

WORKSPACE_HINT="${GTBI_E2E_WORKSPACE_HINT:-$REPO_ROOT}"

log() {
    local level="${1:-INFO}"
    local test_name="${2:-general}"
    shift 2 || true
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$test_name] $message" | tee -a "$LOG_FILE"
}

json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

record_result() {
    local status="$1"
    local test_name="$2"
    local message="$3"
    local exit_code="${4:-}"
    local expected_session_id="${5:-}"
    local observed_session_id="${6:-}"
    local artifact_path="${7:-}"

    local escaped_message escaped_expected escaped_observed escaped_artifact
    escaped_message="$(json_escape "$message")"
    escaped_expected="$(json_escape "$expected_session_id")"
    escaped_observed="$(json_escape "$observed_session_id")"
    escaped_artifact="$(json_escape "$artifact_path")"

    RESULTS_JSON+=("{\"test\":\"$test_name\",\"status\":\"$(echo "$status" | tr '[:upper:]' '[:lower:]')\",\"message\":\"$escaped_message\",\"exit_code\":\"$exit_code\",\"expected_session_id\":\"$escaped_expected\",\"observed_session_id\":\"$escaped_observed\",\"artifact\":\"$escaped_artifact\"}")

    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        *) ;;
    esac

    log "$status" "$test_name" "$message"
    if [[ -n "$expected_session_id" || -n "$observed_session_id" ]]; then
        log "INFO" "$test_name" "expected_session_id=${expected_session_id:-<none>} observed_session_id=${observed_session_id:-<none>}"
    fi
    if [[ -n "$artifact_path" ]]; then
        log "INFO" "$test_name" "artifact=$artifact_path"
    fi
}

run_cmd() {
    local key="$1"
    local command="$2"
    local outfile="$ARTIFACT_DIR/${key}.log"

    log "INFO" "$key" "CMD: $command" >&2
    bash -lc "$command" > "$outfile" 2>&1
    local code=$?
    log "INFO" "$key" "exit=$code" >&2
    echo "$code"
}

extract_codex_session_id() {
    local file="$1"
    grep -E '^session id:' "$file" | awk '{print $3}' | tail -n 1
}

extract_json_blob() {
    local file="$1"
    awk '
        BEGIN { capture = 0 }
        {
            if (capture == 0) {
                brace_pos = index($0, "{")
                if (brace_pos > 0) {
                    capture = 1
                    print substr($0, brace_pos)
                }
            } else {
                print $0
            }
        }
    ' "$file"
}

extract_json_field() {
    local file="$1"
    local field="$2"
    extract_json_blob "$file" | jq -r "$field // empty" 2>/dev/null | head -n 1
}

assert_tool_available() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        record_result "PASS" "tool_${tool}" "Tool available at $(command -v "$tool")" "0"
        return 0
    fi
    record_result "FAIL" "tool_${tool}" "Required tool not available: $tool" "127"
    return 1
}

write_json_report() {
    local overall
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        overall="FAILED"
    else
        overall="PASSED"
    fi

    cat > "$JSON_FILE" <<EOF_JSON
{
  "test_suite": "GTBI Cross-Agent Resume + Conversion E2E",
  "timestamp": "$(date -Iseconds)",
  "workspace_hint": "$WORKSPACE_HINT",
  "log_file": "$LOG_FILE",
  "artifact_dir": "$ARTIFACT_DIR",
  "summary": {
    "total": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "result": "$overall"
  },
  "results": [
$(IFS=,; echo "${RESULTS_JSON[*]}" | sed 's/},{/},\
    {/g' | sed 's/^/    /')
  ]
}
EOF_JSON
    log "INFO" "report" "JSON report written to $JSON_FILE"
}

find_codex_session_file_by_id() {
    local session_id="$1"
    find "$CODEX_HOME/sessions" -type f -name "*${session_id}*.jsonl" 2>/dev/null | sort | tail -n 1
}

find_claude_session_file_by_id() {
    local session_id="$1"
    local workspace="${2:-$WORKSPACE_HINT}"

    local dir_key
    dir_key="$(printf '%s' "$workspace" | sed -E 's/[^[:alnum:]]/-/g')"
    local direct="$CLAUDE_HOME/projects/$dir_key/${session_id}.jsonl"
    if [[ -f "$direct" ]]; then
        echo "$direct"
        return 0
    fi
    find "$CLAUDE_HOME/projects" -type f -name "${session_id}.jsonl" 2>/dev/null | sort | tail -n 1
}

find_gemini_session_file_by_id() {
    local session_id="$1"
    find "$GEMINI_HOME/tmp" -type f -path '*/chats/session-*.json' 2>/dev/null | while IFS= read -r f; do
        if jq -e --arg sid "$session_id" '.sessionId == $sid' "$f" >/dev/null 2>&1; then
            echo "$f"
            break
        fi
    done
}

schema_check_claude() {
    local file="$1"
    jq -e 'fromjson? // . | type == "object"' "$file" >/dev/null 2>&1 || return 1
    local first
    first="$(jq -c 'fromjson? // . | select(.type=="user" or .type=="assistant")' "$file" | head -n 1)"
    [[ -z "$first" ]] && return 1
    jq -e '
        has("parentUuid") and has("isSidechain") and has("userType") and
        has("cwd") and has("sessionId") and has("version") and has("gitBranch") and
        has("type") and has("message") and has("uuid") and has("timestamp") and
        (.message | type == "object") and (.message.role != null)
    ' >/dev/null 2>&1 <<<"$first"
}

schema_check_codex() {
    local file="$1"
    local first
    first="$(head -n 1 "$file")"
    [[ -z "$first" ]] && return 1
    jq -e '.type == "session_meta" and (.payload.id != null) and (.payload.cwd != null)' >/dev/null 2>&1 <<<"$first" || return 1

    local has_user has_assistant
    has_user="$(jq -r 'select(.type=="event_msg" and .payload.type=="user_message") | "yes"' "$file" | head -n 1)"
    has_assistant="$(jq -r 'select(.type=="response_item") | "yes"' "$file" | head -n 1)"
    [[ "$has_user" == "yes" && "$has_assistant" == "yes" ]]
}

schema_check_gemini() {
    local file="$1"
    jq -e '
        type == "object" and
        (.sessionId | type == "string") and
        (.projectHash | type == "string") and
        (.startTime | type == "string") and
        (.lastUpdated | type == "string") and
        (.messages | type == "array") and
        ((.messages | length) > 0) and
        (.messages[0].id != null) and
        (.messages[0].timestamp != null) and
        (.messages[0].type != null) and
        (.messages[0].content != null)
    ' "$file" >/dev/null 2>&1
}

schema_check_for_target() {
    local target="$1"
    local file="$2"
    case "$target" in
        claude-code) schema_check_claude "$file" ;;
        codex) schema_check_codex "$file" ;;
        gemini) schema_check_gemini "$file" ;;
        *) return 1 ;;
    esac
}

path_check_for_target() {
    local target="$1"
    local path="$2"
    case "$target" in
        claude-code)
            [[ "$path" == "$CLAUDE_HOME/projects/"*".jsonl" ]]
            ;;
        codex)
            [[ "$path" == "$CODEX_HOME/sessions/"*".jsonl" ]]
            ;;
        gemini)
            [[ "$path" == "$GEMINI_HOME/tmp/"*"/chats/session-"*".json" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

extract_observed_id_for_target() {
    local target="$1"
    local resume_log="$2"
    case "$target" in
        claude-code)
            extract_json_field "$resume_log" '.session_id'
            ;;
        codex)
            extract_codex_session_id "$resume_log"
            ;;
        gemini)
            extract_json_field "$resume_log" '.session_id'
            ;;
        *)
            echo ""
            ;;
    esac
}

resume_converted_session() {
    local target="$1"
    local converted_id="$2"
    local key="$3"

    local marker reply observed code resume_log
    resume_log="$ARTIFACT_DIR/${key}.log"

    case "$target" in
        claude-code)
            marker="CONVERT-OK-CLAUDE"
            code="$(run_cmd "$key" "timeout 120 claude -r '$converted_id' -p --output-format json 'Respond with exactly ${marker}.'")"
            observed="$(extract_observed_id_for_target "$target" "$resume_log")"
            reply="$(extract_json_field "$resume_log" '.result')"
            if [[ "$code" -eq 0 && "$observed" == "$converted_id" && "$reply" == ${marker}* ]]; then
                return 0
            fi
            return 1
            ;;
        codex)
            marker="CONVERT-OK-CODEX"
            code="$(run_cmd "$key" "timeout 120 codex exec resume '$converted_id' 'Respond with exactly ${marker}.'")"
            observed="$(extract_observed_id_for_target "$target" "$resume_log")"
            if [[ "$code" -eq 0 && "$observed" == "$converted_id" ]] && grep -q "$marker" "$resume_log"; then
                return 0
            fi
            return 1
            ;;
        gemini)
            marker="CONVERT-OK-GEMINI"
            code="$(run_cmd "$key" "timeout 120 gemini --resume '$converted_id' -p 'Respond with exactly ${marker}.' --output-format json")"
            observed="$(extract_observed_id_for_target "$target" "$resume_log")"
            reply="$(extract_json_field "$resume_log" '.response')"
            if [[ "$code" -eq 0 && "$observed" == "$converted_id" && "$reply" == "$marker" ]]; then
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

evaluate_direct_cross_isolation() {
    local test_name="$1"
    local target="$2"
    local source="$3"
    local exit_code="$4"
    local foreign_id="$5"
    local observed_id="$6"
    local artifact="$7"

    if [[ "$exit_code" -ne 0 ]]; then
        record_result "PASS" "$test_name" "$target rejected foreign $source session id (expected direct isolation)" "$exit_code" "$foreign_id" "$observed_id" "$artifact"
    elif [[ "$observed_id" != "$foreign_id" ]]; then
        record_result "PASS" "$test_name" "$target did not reuse foreign $source session id (expected direct isolation)" "$exit_code" "$foreign_id" "$observed_id" "$artifact"
    else
        record_result "FAIL" "$test_name" "$target unexpectedly resumed foreign $source id without conversion" "$exit_code" "$foreign_id" "$observed_id" "$artifact"
    fi
}

run_conversion_pair() {
    local from="$1"
    local to="$2"
    local source_file="$3"
    local pair_key="$4"

    if [[ -z "$source_file" || ! -f "$source_file" ]]; then
        record_result "SKIP" "$pair_key" "Skipped because source file is unavailable" ""
        return 0
    fi

    local convert_key="convert_${pair_key}"
    local convert_cmd
    convert_cmd="timeout 120 env REPO_ROOT='$REPO_ROOT' SRC_FILE='$source_file' FROM_AGENT='$from' TO_AGENT='$to' WS_HINT='$WORKSPACE_HINT' bash -lc 'source \"\$REPO_ROOT/scripts/lib/session.sh\"; convert_session_native \"\$SRC_FILE\" --from \"\$FROM_AGENT\" --to \"\$TO_AGENT\" --workspace \"\$WS_HINT\" --json'"

    local code
    code="$(run_cmd "$convert_key" "$convert_cmd")"

    local convert_log="$ARTIFACT_DIR/${convert_key}.log"
    if [[ "$code" -ne 0 ]]; then
        record_result "FAIL" "$pair_key" "Conversion command failed (${from} -> ${to})" "$code" "" "" "$convert_log"
        return 0
    fi

    local target_session_id written_path
    target_session_id="$(extract_json_field "$convert_log" '.target_session_id')"
    written_path="$(extract_json_field "$convert_log" '.written_path')"

    if [[ -z "$target_session_id" || -z "$written_path" ]]; then
        record_result "FAIL" "$pair_key" "Conversion output missing target_session_id/written_path" "$code" "" "" "$convert_log"
        return 0
    fi

    if [[ ! -f "$written_path" ]]; then
        record_result "FAIL" "$pair_key" "Converted file missing on disk" "$code" "$target_session_id" "" "$written_path"
        return 0
    fi

    if path_check_for_target "$to" "$written_path"; then
        record_result "PASS" "${pair_key}_path" "Converted file placed in native $to location" "$code" "$target_session_id" "$target_session_id" "$written_path"
    else
        record_result "FAIL" "${pair_key}_path" "Converted file path is not native for $to" "$code" "$target_session_id" "$target_session_id" "$written_path"
    fi

    if schema_check_for_target "$to" "$written_path"; then
        record_result "PASS" "${pair_key}_schema" "Converted output is schema-compatible with native $to sessions" "$code" "$target_session_id" "$target_session_id" "$written_path"
    else
        record_result "FAIL" "${pair_key}_schema" "Converted output schema diverges from native $to expectations" "$code" "$target_session_id" "" "$written_path"
    fi

    local resume_key="resume_${pair_key}"
    if resume_converted_session "$to" "$target_session_id" "$resume_key"; then
        local resume_log="$ARTIFACT_DIR/${resume_key}.log"
        local observed
        observed="$(extract_observed_id_for_target "$to" "$resume_log")"
        record_result "PASS" "$pair_key" "$to successfully resumed converted session" "0" "$target_session_id" "$observed" "$resume_log"
    else
        local resume_log="$ARTIFACT_DIR/${resume_key}.log"
        local observed
        observed="$(extract_observed_id_for_target "$to" "$resume_log")"
        record_result "FAIL" "$pair_key" "$to failed to resume converted session" "1" "$target_session_id" "$observed" "$resume_log"
    fi
}

main() {
    log "INFO" "start" "Cross-agent resume + conversion E2E started"
    log "INFO" "start" "Log file: $LOG_FILE"
    log "INFO" "start" "Artifact dir: $ARTIFACT_DIR"
    log "INFO" "start" "Workspace hint: $WORKSPACE_HINT"
    log "INFO" "start" "Self-resume baseline enabled: $INCLUDE_SELF_RESUME_BASELINE"
    log "INFO" "start" "Direct cross baseline enabled: $RUN_DIRECT_CROSS_BASELINE"

    local has_preconditions=true
    for tool in timeout jq codex claude gemini; do
        if ! assert_tool_available "$tool"; then
            has_preconditions=false
        fi
    done

    if [[ "$has_preconditions" != "true" ]]; then
        write_json_report
        exit 1
    fi

    local COD_CREATE_LOG="$ARTIFACT_DIR/create_codex_session.log"
    local CLAUDE_CREATE_LOG="$ARTIFACT_DIR/create_claude_session.log"
    local GEMINI_CREATE_LOG="$ARTIFACT_DIR/create_gemini_session.log"

    local codex_id=""
    local claude_id=""
    local gemini_id=""
    local code

    code="$(run_cmd "create_codex_session" "timeout 120 codex exec --sandbox danger-full-access 'Respond with exactly READY-CODEX.'")"
    codex_id="$(extract_codex_session_id "$COD_CREATE_LOG")"
    if [[ "$code" -eq 0 && -n "$codex_id" ]] && grep -q 'READY-CODEX' "$COD_CREATE_LOG"; then
        record_result "PASS" "create_codex_session" "Created codex session successfully" "$code" "" "$codex_id" "$COD_CREATE_LOG"
    else
        record_result "FAIL" "create_codex_session" "Failed to create codex session" "$code" "" "$codex_id" "$COD_CREATE_LOG"
    fi

    code="$(run_cmd "create_claude_session" "timeout 120 claude -p --output-format json 'Respond with exactly READY-CLAUDE.'")"
    claude_id="$(extract_json_field "$CLAUDE_CREATE_LOG" '.session_id')"
    local claude_reply
    claude_reply="$(extract_json_field "$CLAUDE_CREATE_LOG" '.result')"
    if [[ "$code" -eq 0 && -n "$claude_id" && "$claude_reply" == READY-CLAUDE* ]]; then
        record_result "PASS" "create_claude_session" "Created claude session successfully" "$code" "" "$claude_id" "$CLAUDE_CREATE_LOG"
    else
        record_result "FAIL" "create_claude_session" "Failed to create claude session" "$code" "" "$claude_id" "$CLAUDE_CREATE_LOG"
    fi

    code="$(run_cmd "create_gemini_session" "timeout 120 gemini -p 'Respond with exactly READY-GEMINI.' --output-format json")"
    gemini_id="$(extract_json_field "$GEMINI_CREATE_LOG" '.session_id')"
    local gemini_reply
    gemini_reply="$(extract_json_field "$GEMINI_CREATE_LOG" '.response')"
    if [[ "$code" -eq 0 && -n "$gemini_id" && "$gemini_reply" == "READY-GEMINI" ]]; then
        record_result "PASS" "create_gemini_session" "Created gemini session successfully" "$code" "" "$gemini_id" "$GEMINI_CREATE_LOG"
    else
        record_result "FAIL" "create_gemini_session" "Failed to create gemini session" "$code" "" "$gemini_id" "$GEMINI_CREATE_LOG"
    fi

    local codex_file claude_file gemini_file
    codex_file="$(find_codex_session_file_by_id "$codex_id")"
    claude_file="$(find_claude_session_file_by_id "$claude_id" "$WORKSPACE_HINT")"
    gemini_file="$(find_gemini_session_file_by_id "$gemini_id")"

    if [[ -n "$codex_file" ]]; then
        record_result "PASS" "source_codex_file" "Located codex native session file" "0" "$codex_id" "$codex_id" "$codex_file"
    else
        record_result "FAIL" "source_codex_file" "Could not locate codex native session file" "1" "$codex_id" "" ""
    fi

    if [[ -n "$claude_file" ]]; then
        record_result "PASS" "source_claude_file" "Located claude native session file" "0" "$claude_id" "$claude_id" "$claude_file"
    else
        record_result "FAIL" "source_claude_file" "Could not locate claude native session file" "1" "$claude_id" "" ""
    fi

    if [[ -n "$gemini_file" ]]; then
        record_result "PASS" "source_gemini_file" "Located gemini native session file" "0" "$gemini_id" "$gemini_id" "$gemini_file"
    else
        record_result "FAIL" "source_gemini_file" "Could not locate gemini native session file" "1" "$gemini_id" "" ""
    fi

    # Optional self-resume baseline.
    if [[ "$INCLUDE_SELF_RESUME_BASELINE" == "true" ]]; then
        local COD_SELF_LOG="$ARTIFACT_DIR/self_resume_codex.log"
        local CLAUDE_SELF_LOG="$ARTIFACT_DIR/self_resume_claude.log"
        local GEMINI_SELF_LOG="$ARTIFACT_DIR/self_resume_gemini.log"

        if [[ -n "$codex_id" ]]; then
            code="$(run_cmd "self_resume_codex" "timeout 120 codex exec resume '$codex_id' 'Respond with exactly SELF-CODEX.'")"
            local codex_self_observed
            codex_self_observed="$(extract_codex_session_id "$COD_SELF_LOG")"
            if [[ "$code" -eq 0 && "$codex_self_observed" == "$codex_id" ]] && grep -q 'SELF-CODEX' "$COD_SELF_LOG"; then
                record_result "PASS" "self_resume_codex" "Codex resumed its own session" "$code" "$codex_id" "$codex_self_observed" "$COD_SELF_LOG"
            else
                record_result "FAIL" "self_resume_codex" "Codex did not resume its own session" "$code" "$codex_id" "$codex_self_observed" "$COD_SELF_LOG"
            fi
        fi

        if [[ -n "$claude_id" ]]; then
            code="$(run_cmd "self_resume_claude" "timeout 120 claude -r '$claude_id' -p --output-format json 'Respond with exactly SELF-CLAUDE.'")"
            local claude_self_observed claude_self_reply
            claude_self_observed="$(extract_json_field "$CLAUDE_SELF_LOG" '.session_id')"
            claude_self_reply="$(extract_json_field "$CLAUDE_SELF_LOG" '.result')"
            if [[ "$code" -eq 0 && "$claude_self_observed" == "$claude_id" && "$claude_self_reply" == SELF-CLAUDE* ]]; then
                record_result "PASS" "self_resume_claude" "Claude resumed its own session" "$code" "$claude_id" "$claude_self_observed" "$CLAUDE_SELF_LOG"
            else
                record_result "FAIL" "self_resume_claude" "Claude did not resume its own session" "$code" "$claude_id" "$claude_self_observed" "$CLAUDE_SELF_LOG"
            fi
        fi

        if [[ -n "$gemini_id" ]]; then
            code="$(run_cmd "self_resume_gemini" "timeout 120 gemini --resume '$gemini_id' -p 'Respond with exactly SELF-GEMINI.' --output-format json")"
            local gemini_self_observed gemini_self_reply
            gemini_self_observed="$(extract_json_field "$GEMINI_SELF_LOG" '.session_id')"
            gemini_self_reply="$(extract_json_field "$GEMINI_SELF_LOG" '.response')"
            if [[ "$code" -eq 0 && "$gemini_self_observed" == "$gemini_id" && "$gemini_self_reply" == "SELF-GEMINI" ]]; then
                record_result "PASS" "self_resume_gemini" "Gemini resumed its own session" "$code" "$gemini_id" "$gemini_self_observed" "$GEMINI_SELF_LOG"
            else
                record_result "FAIL" "self_resume_gemini" "Gemini did not resume its own session" "$code" "$gemini_id" "$gemini_self_observed" "$GEMINI_SELF_LOG"
            fi
        fi
    else
        record_result "SKIP" "self_resume_codex" "Self-resume baseline disabled (set GTBI_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
        record_result "SKIP" "self_resume_claude" "Self-resume baseline disabled (set GTBI_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
        record_result "SKIP" "self_resume_gemini" "Self-resume baseline disabled (set GTBI_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
    fi

    # Direct cross baseline (expected to fail/isolate without conversion).
    if [[ "$RUN_DIRECT_CROSS_BASELINE" == "true" ]]; then
        if [[ -n "$codex_id" ]]; then
            local cfc_log="$ARTIFACT_DIR/direct_cross_claude_from_codex.log"
            code="$(run_cmd "direct_cross_claude_from_codex" "timeout 120 claude -r '$codex_id' -p --output-format json 'Respond with exactly DIRECT-CLAUDE-FROM-CODEX.'")"
            evaluate_direct_cross_isolation "direct_cross_claude_from_codex" "claude" "codex" "$code" "$codex_id" "$(extract_json_field "$cfc_log" '.session_id')" "$cfc_log"

            local gfc_log="$ARTIFACT_DIR/direct_cross_gemini_from_codex.log"
            code="$(run_cmd "direct_cross_gemini_from_codex" "timeout 120 gemini --resume '$codex_id' -p 'Respond with exactly DIRECT-GEMINI-FROM-CODEX.' --output-format json")"
            evaluate_direct_cross_isolation "direct_cross_gemini_from_codex" "gemini" "codex" "$code" "$codex_id" "$(extract_json_field "$gfc_log" '.session_id')" "$gfc_log"
        fi

        if [[ -n "$claude_id" ]]; then
            local cdc_log="$ARTIFACT_DIR/direct_cross_codex_from_claude.log"
            code="$(run_cmd "direct_cross_codex_from_claude" "timeout 120 codex exec resume '$claude_id' 'Respond with exactly DIRECT-CODEX-FROM-CLAUDE.'")"
            evaluate_direct_cross_isolation "direct_cross_codex_from_claude" "codex" "claude" "$code" "$claude_id" "$(extract_codex_session_id "$cdc_log")" "$cdc_log"

            local gfc2_log="$ARTIFACT_DIR/direct_cross_gemini_from_claude.log"
            code="$(run_cmd "direct_cross_gemini_from_claude" "timeout 120 gemini --resume '$claude_id' -p 'Respond with exactly DIRECT-GEMINI-FROM-CLAUDE.' --output-format json")"
            evaluate_direct_cross_isolation "direct_cross_gemini_from_claude" "gemini" "claude" "$code" "$claude_id" "$(extract_json_field "$gfc2_log" '.session_id')" "$gfc2_log"
        fi

        if [[ -n "$gemini_id" ]]; then
            local cfg_log="$ARTIFACT_DIR/direct_cross_codex_from_gemini.log"
            code="$(run_cmd "direct_cross_codex_from_gemini" "timeout 120 codex exec resume '$gemini_id' 'Respond with exactly DIRECT-CODEX-FROM-GEMINI.'")"
            evaluate_direct_cross_isolation "direct_cross_codex_from_gemini" "codex" "gemini" "$code" "$gemini_id" "$(extract_codex_session_id "$cfg_log")" "$cfg_log"

            local clfg_log="$ARTIFACT_DIR/direct_cross_claude_from_gemini.log"
            code="$(run_cmd "direct_cross_claude_from_gemini" "timeout 120 claude -r '$gemini_id' -p --output-format json 'Respond with exactly DIRECT-CLAUDE-FROM-GEMINI.'")"
            evaluate_direct_cross_isolation "direct_cross_claude_from_gemini" "claude" "gemini" "$code" "$gemini_id" "$(extract_json_field "$clfg_log" '.session_id')" "$clfg_log"
        fi
    fi

    # Strict conversion matrix: all 6 directed pairs among {codex, claude, gemini}.
    run_conversion_pair "codex" "claude-code" "$codex_file" "convert_codex_to_claude"
    run_conversion_pair "codex" "gemini" "$codex_file" "convert_codex_to_gemini"
    run_conversion_pair "claude-code" "codex" "$claude_file" "convert_claude_to_codex"
    run_conversion_pair "claude-code" "gemini" "$claude_file" "convert_claude_to_gemini"
    run_conversion_pair "gemini" "codex" "$gemini_file" "convert_gemini_to_codex"
    run_conversion_pair "gemini" "claude-code" "$gemini_file" "convert_gemini_to_claude"

    write_json_report

    log "INFO" "summary" "Passed=$PASS_COUNT Failed=$FAIL_COUNT Skipped=$SKIP_COUNT"
    log "INFO" "summary" "Text log: $LOG_FILE"
    log "INFO" "summary" "JSON report: $JSON_FILE"
    log "INFO" "summary" "Artifacts: $ARTIFACT_DIR"

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
