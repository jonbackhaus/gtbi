#!/usr/bin/env bash
# ============================================================
# GTBI Swarm Assign - role-aware Beads allocation planner
#
# Reads ready Beads plus optional bv triage JSON, then emits advisory-only
# per-agent assignment suggestions. This script never marks Beads, sends
# Agent Mail, claims reservations, launches agents, or mutates RCH/NTM state.
# ============================================================

set -euo pipefail

SWARM_ASSIGN_JSON=false
SWARM_ASSIGN_AGENTS=""
SWARM_ASSIGN_ROLES=""
SWARM_ASSIGN_PROFILE="balanced"
SWARM_ASSIGN_READY_FILE=""
SWARM_ASSIGN_TRIAGE_FILE=""

swarm_assign_usage() {
    cat <<'EOF'
Usage: gtbi swarm assign [OPTIONS]

Options:
  --json              Emit machine-readable JSON
  --markdown          Emit Markdown output (default)
  --agents N          Requested agent count when --roles is omitted
  --roles SPEC        Role mix, e.g. implementation:2,review:1,testing,docs
  --profile NAME      balanced, codex-heavy, review-heavy, or docs-heavy
                      (default: balanced)
  --ready-file FILE   Read br ready --json output from a fixture/file
  --triage-file FILE  Read bv --robot-triage output from a fixture/file
  --help, -h          Show this help

The command is advisory-only. It prints Bead IDs, suggested roles, reservation
surfaces, and Agent Mail thread IDs, but it does not claim work or send mail.
EOF
}

swarm_assign_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_ASSIGN_JSON=true
                shift
                ;;
            --markdown)
                SWARM_ASSIGN_JSON=false
                shift
                ;;
            --agents)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agents requires a positive integer" >&2
                    return 2
                fi
                SWARM_ASSIGN_AGENTS="$2"
                shift 2
                ;;
            --roles)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --roles requires a role specification" >&2
                    return 2
                fi
                SWARM_ASSIGN_ROLES="$2"
                shift 2
                ;;
            --profile)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --profile requires a value" >&2
                    return 2
                fi
                SWARM_ASSIGN_PROFILE="$2"
                shift 2
                ;;
            --ready-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --ready-file requires a path" >&2
                    return 2
                fi
                SWARM_ASSIGN_READY_FILE="$2"
                shift 2
                ;;
            --triage-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --triage-file requires a path" >&2
                    return 2
                fi
                SWARM_ASSIGN_TRIAGE_FILE="$2"
                shift 2
                ;;
            --help|-h)
                swarm_assign_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'gtbi swarm assign --help' for usage." >&2
                return 2
                ;;
        esac
    done

    case "$SWARM_ASSIGN_PROFILE" in
        balanced|codex-heavy|review-heavy|docs-heavy) ;;
        *)
            echo "Error: unsupported profile: $SWARM_ASSIGN_PROFILE" >&2
            return 2
            ;;
    esac

    if [[ -n "$SWARM_ASSIGN_AGENTS" ]] && { [[ ! "$SWARM_ASSIGN_AGENTS" =~ ^[0-9]+$ ]] || (( SWARM_ASSIGN_AGENTS < 1 )); }; then
        echo "Error: --agents requires a positive integer" >&2
        return 2
    fi

    if [[ -z "$SWARM_ASSIGN_ROLES" && -z "$SWARM_ASSIGN_AGENTS" ]]; then
        echo "Error: provide --agents or --roles" >&2
        return 2
    fi
}

swarm_assign_binary_path() {
    local name="${1:-}"
    local path_value=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$path_value" && -x "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

swarm_assign_normalize_role() {
    local role="$1"

    role="${role,,}"
    role="${role//_/-}"
    case "$role" in
        impl|implement|implementation|code|coding|feature)
            printf 'implementation\n'
            ;;
        review|reviewer|audit|qa)
            printf 'review\n'
            ;;
        test|tests|testing|tester)
            printf 'testing\n'
            ;;
        doc|docs|documentation|writer)
            printf 'documentation\n'
            ;;
        *)
            echo "Error: unsupported role: $role" >&2
            return 2
            ;;
    esac
}

swarm_assign_roles_from_spec() {
    local spec="$1"
    local part=""
    local role=""
    local count=""
    local normalized=""
    local i=0

    IFS=',' read -r -a parts <<< "$spec"
    for part in "${parts[@]}"; do
        part="${part//[[:space:]]/}"
        [[ -n "$part" ]] || continue
        if [[ "$part" =~ ^([A-Za-z_-]+):([0-9]+)$ ]]; then
            role="${BASH_REMATCH[1]}"
            count="${BASH_REMATCH[2]}"
        else
            role="$part"
            count=1
        fi
        normalized="$(swarm_assign_normalize_role "$role")" || return $?
        (( count > 0 )) || {
            echo "Error: role count must be positive: $part" >&2
            return 2
        }
        for ((i = 0; i < count; i++)); do
            printf '%s\n' "$normalized"
        done
    done
}

swarm_assign_roles_from_profile() {
    local agents="$1"
    local profile="$2"
    local i=0
    local role=""

    for ((i = 1; i <= agents; i++)); do
        case "$profile" in
            review-heavy)
                case $(( (i - 1) % 4 )) in
                    0|1) role="review" ;;
                    2) role="implementation" ;;
                    *) role="testing" ;;
                esac
                ;;
            docs-heavy)
                case $(( (i - 1) % 4 )) in
                    0|1) role="documentation" ;;
                    2) role="implementation" ;;
                    *) role="testing" ;;
                esac
                ;;
            codex-heavy)
                case $(( (i - 1) % 5 )) in
                    0|1|2) role="implementation" ;;
                    3) role="testing" ;;
                    *) role="review" ;;
                esac
                ;;
            *)
                case $(( (i - 1) % 5 )) in
                    0|1) role="implementation" ;;
                    2) role="review" ;;
                    3) role="testing" ;;
                    *) role="documentation" ;;
                esac
                ;;
        esac
        printf '%s\n' "$role"
    done
}

swarm_assign_roles_json() {
    local jq_bin="$1"
    local roles_text=""

    if [[ -n "$SWARM_ASSIGN_ROLES" ]]; then
        roles_text="$(swarm_assign_roles_from_spec "$SWARM_ASSIGN_ROLES")" || return $?
    else
        roles_text="$(swarm_assign_roles_from_profile "$SWARM_ASSIGN_AGENTS" "$SWARM_ASSIGN_PROFILE")"
    fi

    printf '%s\n' "$roles_text" \
        | "$jq_bin" -R -s '
            split("\n")
            | map(select(length > 0))
            | to_entries
            | map({slot: (.key + 1), agent: ("agent-" + ((.key + 1) | tostring)), role: .value})
        '
}

swarm_assign_collect_ready_json() {
    local br_bin=""

    if [[ -n "$SWARM_ASSIGN_READY_FILE" ]]; then
        if [[ ! -f "$SWARM_ASSIGN_READY_FILE" ]]; then
            echo "Error: ready file not found: $SWARM_ASSIGN_READY_FILE" >&2
            return 2
        fi
        cat "$SWARM_ASSIGN_READY_FILE"
        return 0
    fi

    br_bin="$(swarm_assign_binary_path br 2>/dev/null || true)"
    if [[ -z "$br_bin" ]]; then
        echo "Error: br is required unless --ready-file is provided" >&2
        return 2
    fi
    "$br_bin" ready --json
}

swarm_assign_collect_triage_json() {
    local bv_bin=""

    if [[ -n "$SWARM_ASSIGN_TRIAGE_FILE" ]]; then
        if [[ ! -f "$SWARM_ASSIGN_TRIAGE_FILE" ]]; then
            echo "Error: triage file not found: $SWARM_ASSIGN_TRIAGE_FILE" >&2
            return 2
        fi
        cat "$SWARM_ASSIGN_TRIAGE_FILE"
        return 0
    fi

    bv_bin="$(swarm_assign_binary_path bv 2>/dev/null || true)"
    if [[ -z "$bv_bin" ]]; then
        printf '{}\n'
        return 0
    fi
    "$bv_bin" --robot-triage 2>/dev/null || printf '{}\n'
}

swarm_assign_jq_filter() {
    cat <<'JQ'
def arr($v): if $v == null then [] elif ($v | type) == "array" then $v else [] end;
def text($v): ($v // "" | tostring | ascii_downcase);
def n($v): if ($v | type) == "number" then $v elif (($v | type) == "string" and ($v | test("^[0-9]+$"))) then ($v | tonumber) else 0 end;
def triage_recommendations:
  arr($triage.triage.recommendations // $triage.recommendations);

def triage_for($id):
  first(triage_recommendations[]? | select(.id == $id)) // {};

def display_labels($i):
  if (arr($i.labels) | length) > 0 then arr($i.labels) else arr((triage_for($i.id)).labels) end;
def labels($i): display_labels($i) | map(tostring | ascii_downcase);
def issue_title($i): ($i.title // (triage_for($i.id)).title // "");
def issue_type($i): ($i.issue_type // (triage_for($i.id)).type // (triage_for($i.id)).issue_type // null);
def priority($i): n($i.priority // (triage_for($i.id)).priority // 9);
def estimate($i): if ($i.estimated_minutes // null) == null then 999999 else n($i.estimated_minutes) end;
def has_label($ls; $re): any($ls[]?; test($re));
def has_text($i; $re): (text(issue_title($i)) | test($re));

def is_ready_issue($i):
  (($i.status // "open") == "open")
  and (($i.blocked // false) != true)
  and ((arr($i.blocked_by) | length) == 0);

def role_fit($i; $role):
  (labels($i)) as $ls
  | (text(issue_type($i))) as $type
  | if $role == "documentation" then
      (if has_label($ls; "docs|documentation|content|lesson|onboard|readme|website") or has_text($i; "doc|readme|lesson|copy|content") then 80 else 5 end)
    elif $role == "testing" then
      (if has_label($ls; "test|tests|qa|coverage|harness") or has_text($i; "test|fixture|harness|coverage|repro") then 80 else 10 end)
    elif $role == "review" then
      (if has_label($ls; "review|audit|quality|security|performance|bug") or has_text($i; "audit|review|bug|regression|security|perf") or $type == "bug" then 80 else 20 end)
    else
      (if $type == "feature" or $type == "task" or has_label($ls; "backend|cli|swarm|capacity|inventory|support|coordination") then 70 else 25 end)
    end;

def rank($i):
  (triage_for($i.id)) as $t
  | ((10 - priority($i)) * 10)
    + (n($t.score) * 1000)
    + (n($t.unblocks) * 5)
    - (estimate($i) / 10000);

def dependency_position($i):
  (triage_for($i.id)) as $t
  | {
      score: ($t.score // null),
      blocked_by: arr($t.blocked_by),
      unblocks: n($t.unblocks),
      action: ($t.action // "Start work on this issue")
    };

def reservation_surfaces($i):
  (labels($i)) as $ls
  | ([ ".beads/issues.jsonl" ]
     + (if has_label($ls; "swarm|coordination|bv|beads|capacity|inventory|support") then ["scripts/lib/swarm_*.sh", "tests/unit/test_swarm_*.sh"] else [] end)
     + (if has_label($ls; "capacity") then ["scripts/lib/capacity.sh", "tests/unit/test_capacity.sh"] else [] end)
     + (if has_label($ls; "support") then ["scripts/lib/support.sh", "tests/**/test_support*.sh"] else [] end)
     + (if has_label($ls; "inventory") then ["scripts/lib/swarm_inventory.sh", "tests/unit/test_swarm_inventory.sh"] else [] end)
     + (if has_label($ls; "docs|documentation|content|lesson|onboard|readme") then ["README.md", "docs/**", "gtbi/onboard/**"] else [] end)
     + (if has_label($ls; "test|tests|qa|harness") or has_text($i; "test|fixture|harness") then ["tests/**"] else [] end))
    | unique
    | .[:8];

def rationale($i; $role):
  (labels($i)) as $ls
  | if $role == "documentation" and (has_label($ls; "docs|documentation|content|lesson|onboard|readme") or has_text($i; "doc|readme|lesson|copy|content")) then
      "documentation role matches docs/content signals"
    elif $role == "testing" and (has_label($ls; "test|tests|qa|coverage|harness") or has_text($i; "test|fixture|harness|coverage|repro")) then
      "testing role matches test/fixture signals"
    elif $role == "review" and (has_label($ls; "review|audit|quality|security|performance|bug") or has_text($i; "audit|review|bug|regression|security|perf") or text($i.issue_type) == "bug") then
      "review role matches audit/bug/quality signals"
    elif $role == "implementation" then
      "implementation role takes the highest-ranked ready implementation slice"
    else
      "fallback assignment from ready queue ranking"
    end;

def assignment($slot; $i):
  {
    slot: $slot.slot,
    agent: $slot.agent,
    role: $slot.role,
    bead_id: $i.id,
    title: issue_title($i),
    issue_type: issue_type($i),
    priority: (if priority($i) == 9 and (($i.priority // (triage_for($i.id)).priority // null) == null) then null else priority($i) end),
    estimated_minutes: ($i.estimated_minutes // null),
    labels: display_labels($i),
    dependency_position: dependency_position($i),
    reservation_surfaces: reservation_surfaces($i),
    agent_mail_thread_id: $i.id,
    suggested_subject: ("[" + $i.id + "] Start: " + ($i.title // "")),
    rationale: rationale($i; $slot.role)
  };

($ready | if type == "array" then . else [] end) as $raw_ready
| ($raw_ready | map(select(is_ready_issue(.)))) as $ready_issues
| reduce $roles[] as $slot
    ({assignments: [], remaining: ($ready_issues | sort_by(priority(.), estimate(.), .id)), idle: []};
      ([
        .remaining[]
        | . as $issue
        | {
            issue: $issue,
            fit: role_fit($issue; $slot.role),
            rank: rank($issue)
          }
        ] | sort_by(-.fit, -.rank, priority(.issue), estimate(.issue), .issue.id) | .[0]? ) as $choice
      | if $choice == null then
          .idle += [$slot + {reason: "no-ready-bead"}]
        else
          .assignments += [assignment($slot; $choice.issue)]
          | .remaining = [.remaining[] | select(.id != $choice.issue.id)]
        end
    ) as $planned
| {
    schema_version: 1,
    status: "pass",
    advisory_only: true,
    mutations: {
      marks_beads: false,
      sends_agent_mail: false,
      claims_reservations: false,
      launches_agents: false
    },
    inputs: {
      ready_source: $ready_source,
      triage_source: $triage_source,
      profile: $profile,
      requested_agents: ($roles | length),
      requested_roles: $roles
    },
    summary: {
      ready_count: ($ready_issues | length),
      assigned_count: ($planned.assignments | length),
      idle_count: ($planned.idle | length),
      unassigned_ready_count: ($planned.remaining | length),
      excluded_count: ($raw_ready | map(select(is_ready_issue(.) | not)) | length)
    },
    assignments: $planned.assignments,
    idle_agents: $planned.idle,
    unassigned_ready_beads: ($planned.remaining | map({
      bead_id: .id,
      title: issue_title(.),
      priority: (if priority(.) == 9 and ((.priority // (triage_for(.id)).priority // null) == null) then null else priority(.) end),
      issue_type: issue_type(.),
      labels: display_labels(.),
      agent_mail_thread_id: .id
    })),
    excluded_beads: ($raw_ready | map(select(is_ready_issue(.) | not) | {
      bead_id: .id,
      title: issue_title(.),
      status: (.status // null),
      reason: (if (.blocked // false) == true or ((arr(.blocked_by) | length) > 0) then "blocked" else "not-ready-status" end)
    }))
  }
JQ
}

swarm_assign_build_report() {
    local jq_bin="$1"
    local ready_json="$2"
    local triage_json="$3"
    local roles_json="$4"
    local ready_source="live-br-ready"
    local triage_source="live-bv-triage"

    [[ -n "$SWARM_ASSIGN_READY_FILE" ]] && ready_source="file"
    [[ -n "$SWARM_ASSIGN_TRIAGE_FILE" ]] && triage_source="file"
    [[ "$triage_json" == "{}" ]] && triage_source="unavailable"

    "$jq_bin" -n \
        --argjson ready "$ready_json" \
        --argjson triage "$triage_json" \
        --argjson roles "$roles_json" \
        --arg ready_source "$ready_source" \
        --arg triage_source "$triage_source" \
        --arg profile "$SWARM_ASSIGN_PROFILE" \
        "$(swarm_assign_jq_filter)"
}

swarm_assign_emit_markdown() {
    local report="$1"
    local jq_bin="$2"

    printf '# GTBI Swarm Assignment Plan\n\n'
    printf 'Advisory only: this command did not mark Beads, send Agent Mail, claim reservations, launch agents, or change RCH/NTM state.\n\n'

    "$jq_bin" -r '
        "## Summary\n",
        "- Ready Beads considered: `\(.summary.ready_count)`",
        "- Assignments: `\(.summary.assigned_count)`",
        "- Idle agents: `\(.summary.idle_count)`",
        "- Unassigned ready Beads: `\(.summary.unassigned_ready_count)`",
        "- Excluded non-ready/blocked Beads: `\(.summary.excluded_count)`",
        "",
        "## Assignments\n",
        "| Agent | Role | Bead | Priority | Reservation Surfaces | Thread |",
        "| --- | --- | --- | --- | --- | --- |",
        (if (.assignments | length) == 0 then
          "| - | - | No ready Beads | - | - | - |"
        else
          (.assignments[] | "| \(.agent) | \(.role) | `\(.bead_id)` \(.title) | P\(.priority // "-") | \((.reservation_surfaces | join("<br>"))) | `\(.agent_mail_thread_id)` |")
        end),
        "",
        "## Idle Agents\n",
        (if (.idle_agents | length) == 0 then
          "- None"
        else
          (.idle_agents[] | "- `\(.agent)` (`\(.role)`): \(.reason)")
        end),
        "",
        "## Unassigned Ready Beads\n",
        (if (.unassigned_ready_beads | length) == 0 then
          "- None"
        else
          (.unassigned_ready_beads[] | "- `\(.bead_id)` P\(.priority // "-") \(.title)")
        end)
    ' <<< "$report"
}

swarm_assign_main() {
    local parse_status=0
    local jq_bin=""
    local ready_json=""
    local triage_json=""
    local roles_json=""
    local report=""

    swarm_assign_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        100) return 0 ;;
        *) return "$parse_status" ;;
    esac

    jq_bin="$(swarm_assign_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for swarm assignment planning" >&2
        return 2
    fi

    roles_json="$(swarm_assign_roles_json "$jq_bin")" || return $?
    ready_json="$(swarm_assign_collect_ready_json)" || return $?
    triage_json="$(swarm_assign_collect_triage_json)" || return $?

    if ! "$jq_bin" . >/dev/null 2>&1 <<< "$ready_json"; then
        echo "Error: ready input is not valid JSON" >&2
        return 2
    fi
    if ! "$jq_bin" . >/dev/null 2>&1 <<< "$triage_json"; then
        triage_json="{}"
    fi

    report="$(swarm_assign_build_report "$jq_bin" "$ready_json" "$triage_json" "$roles_json")"
    if [[ "$SWARM_ASSIGN_JSON" == "true" ]]; then
        printf '%s\n' "$report"
    else
        swarm_assign_emit_markdown "$report" "$jq_bin"
    fi
}

swarm_assign_main "$@"
