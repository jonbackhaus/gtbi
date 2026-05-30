#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "install_helpers"
    
    # Mock manifest data
    export GTBI_MANIFEST_INDEX_LOADED=true
    
    # We must unset arrays first to avoid "cannot assign to element of array" if re-declaring types?
    unset GTBI_MODULES_IN_ORDER GTBI_MODULE_PHASE GTBI_MODULE_DEFAULT GTBI_MODULE_CATEGORY GTBI_MODULE_DEPS GTBI_MODULE_TAGS
    
    GTBI_MODULES_IN_ORDER=("mod1" "mod2" "mod3")
    declare -gA GTBI_MODULE_PHASE=( ["mod1"]="1" ["mod2"]="2" ["mod3"]="3" )
    declare -gA GTBI_MODULE_DEFAULT=( ["mod1"]="1" ["mod2"]="1" ["mod3"]="0" )
    declare -gA GTBI_MODULE_CATEGORY=( ["mod1"]="base" ["mod2"]="lang" ["mod3"]="tools" )
    declare -gA GTBI_MODULE_DEPS=()
    declare -gA GTBI_MODULE_TAGS=()
    
    # Selection globals (reset)
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    SKIP_TAGS=()
    SKIP_CATEGORIES=()
    
    # Stub sudo for run_as_target
    stub_command "sudo" "" 0
}

teardown() {
    common_teardown
}

use_spy_sudo() {
    spy_command "sudo"
    export GTBI_TEST_SUDO_BIN="$STUB_DIR/sudo"

    _gtbi_system_binary_path() {
        local name="${1:-}"
        local candidate=""

        [[ -n "$name" ]] || return 1

        if [[ "$name" == "sudo" && -n "${GTBI_TEST_SUDO_BIN:-}" && -x "$GTBI_TEST_SUDO_BIN" ]]; then
            printf '%s\n' "$GTBI_TEST_SUDO_BIN"
            return 0
        fi

        for candidate in \
            "/usr/bin/$name" \
            "/bin/$name" \
            "/usr/local/bin/$name" \
            "/usr/local/sbin/$name" \
            "/usr/sbin/$name" \
            "/sbin/$name"
        do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done

        return 1
    }
}

@test "gtbi_flag_bool: parses boolean values" {
    export TEST_VAR="true"
    run gtbi_flag_bool "TEST_VAR"
    assert_output "1"
    
    export TEST_VAR="False"
    run gtbi_flag_bool "TEST_VAR"
    assert_output "0"
    
    export TEST_VAR="1"
    run gtbi_flag_bool "TEST_VAR"
    assert_output "1"
    
    export TEST_VAR="invalid"
    run gtbi_flag_bool "TEST_VAR"
    # Output contains warning
    assert_output --partial "Ignoring invalid"
}

@test "gtbi_resolve_selection: default selection" {
    gtbi_resolve_selection
    
    # mod1 (default=1) should be selected
    if [[ -z "${GTBI_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 not selected"; fi
    # mod3 (default=0) should NOT be selected
    if [[ -n "${GTBI_EFFECTIVE_RUN[mod3]}" ]]; then fail "mod3 selected"; fi
}

@test "gtbi_resolve_selection: --only module" {
    ONLY_MODULES=("mod3")
    gtbi_resolve_selection
    
    if [[ -z "${GTBI_EFFECTIVE_RUN[mod3]}" ]]; then fail "mod3 not selected"; fi
    if [[ -n "${GTBI_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 selected"; fi
}

@test "gtbi_resolve_selection: --skip module" {
    SKIP_MODULES=("mod1")
    gtbi_resolve_selection
    
    if [[ -n "${GTBI_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 selected"; fi
    if [[ -z "${GTBI_EFFECTIVE_RUN[mod2]}" ]]; then fail "mod2 not selected"; fi
}

@test "gtbi_resolve_selection: --only and --skip same module fails" {
    ONLY_MODULES=("mod1")
    SKIP_MODULES=("mod1")

    if gtbi_resolve_selection 2>/dev/null; then
        fail "selection should fail when a directly requested module is also skipped"
    fi
}

@test "gtbi_resolve_selection: --only-phase can skip a selected module" {
    ONLY_PHASES=("1")
    SKIP_MODULES=("mod1")

    gtbi_resolve_selection

    if [[ -n "${GTBI_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 selected"; fi
}

@test "run_as_current_shell: executes command" {
    run run_as_current_shell "echo 'hello world'"
    assert_success
    assert_output "hello world"
}

@test "run_as_target_shell: calls run_as_target" {
    # Override function
    run_as_target() {
        echo "run_as_target called with: $*"
    }
    
    local out
    out=$(run_as_target_shell "echo test")
    
    # Check key parts instead of exact string to avoid expansion hell.
    # The shell source must be a fixed wrapper; command data is passed as $1.
    if [[ "$out" != *"run_as_target called with: "* ]]; then
        fail "Did not call run_as_target with env-backed bash path"
    fi
    if [[ "$out" != *" GTBI_BASH_BIN="* ]]; then
        fail "Did not pass bash path as env data"
    fi
    if [[ "$out" != *"/bash -c "* ]]; then
        fail "Did not call bash -c"
    fi
    if [[ "$out" != *'_gtbi_primary_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"'* ]]; then
        fail "Did not compute primary bin from runtime HOME"
    fi
    if [[ "$out" != *'export PATH="${_gtbi_primary_bin}:$HOME/.local/bin:$HOME/.gtbi/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:$PATH"'* ]]; then
        fail "Did not export user tool PATH"
    fi
    if [[ "$out" != *'eval "$1" _ echo test'* ]]; then
        fail "Did not pass command as argv data"
    fi
}

@test "run_as_current_shell: treats GTBI_BIN_DIR as inert PATH data" {
    local marker="$BATS_TEST_TMPDIR/current-shell-path-injection"
    export GTBI_BIN_DIR="\$(printf pwn > '$marker')"

    run run_as_current_shell "printf 'ok\n'"
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "GTBI_BIN_DIR command substitution executed"
}

@test "run_as_current_shell: resolves HOME-relative tool paths" {
    export HOME="$BATS_TEST_TMPDIR/home"
    export PATH="/usr/bin:/bin"
    mkdir -p "$HOME/.cargo/bin"
    cat > "$HOME/.cargo/bin/gtbi-home-path-tool" <<'EOF'
#!/usr/bin/env bash
printf 'home-path-ok\n'
EOF
    chmod +x "$HOME/.cargo/bin/gtbi-home-path-tool"

    run run_as_current_shell "gtbi-home-path-tool"
    assert_success
    assert_output "home-path-ok"
}

@test "run_as_current_shell stdin mode treats GTBI_BIN_DIR as inert PATH data" {
    local marker="$BATS_TEST_TMPDIR/current-shell-stdin-path-injection"
    local out
    export GTBI_BIN_DIR="\$(printf pwn > '$marker')"

    out="$(printf "printf 'ok\\n'\n" | run_as_current_shell)"
    [[ "$out" == "ok" ]] || fail "Expected ok, got: $out"
    [[ ! -e "$marker" ]] || fail "GTBI_BIN_DIR command substitution executed"
}

@test "run_as_target_shell: treats GTBI_BIN_DIR as inert PATH data" {
    local marker="$BATS_TEST_TMPDIR/target-shell-path-injection"
    export GTBI_BIN_DIR="\$(printf pwn > '$marker')"

    run_as_target() {
        "$@"
    }

    run run_as_target_shell "printf 'ok\n'"
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "GTBI_BIN_DIR command substitution executed"
}

@test "run_as_root_shell: sudo path passes command as argv and keeps GTBI_BIN_DIR inert" {
    [[ "$EUID" -ne 0 ]] || skip "sudo path is bypassed when tests run as root"

    local marker="$BATS_TEST_TMPDIR/root-shell-path-injection"
    local fake_sudo="$BATS_TEST_TMPDIR/fake-sudo"
    export CAPTURE_FILE="$BATS_TEST_TMPDIR/root-shell-sudo-argv.txt"
    export GTBI_BIN_DIR="\$(printf pwn > '$marker')"
    export SUDO="$fake_sudo"

    cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE_FILE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
exec "$@"
EOF
    chmod +x "$fake_sudo"

    run run_as_root_shell "printf 'root-ok\n'"
    assert_success
    assert_output "root-ok"
    [[ ! -e "$marker" ]] || fail "GTBI_BIN_DIR command substitution executed"

    local -a argv=()
    mapfile -t argv < "$CAPTURE_FILE"
    local wrapper=""
    local command_arg=""
    local idx
    [[ "${argv[0]:-}" == "-n" ]] || fail "Expected noninteractive sudo (-n), got: ${argv[*]}"
    for idx in "${!argv[@]}"; do
        if [[ "${argv[$idx]}" == "-c" ]]; then
            wrapper="${argv[$((idx + 1))]:-}"
            command_arg="${argv[$((idx + 3))]:-}"
            break
        fi
    done

    [[ "$wrapper" == *'eval "$1"'* ]] || fail "Expected sudo shell wrapper to eval argv command, got: $wrapper"
    [[ "$wrapper" != *"root-ok"* ]] || fail "Command was embedded in sudo shell wrapper: $wrapper"
    [[ "$command_arg" == "printf 'root-ok\n'" ]] || fail "Expected command as argv data, got: $command_arg"
}

@test "run_as_root_shell: sudo stdin path is noninteractive" {
    [[ "$EUID" -ne 0 ]] || skip "sudo path is bypassed when tests run as root"

    local fake_sudo="$BATS_TEST_TMPDIR/fake-sudo-stdin"
    local out
    export CAPTURE_FILE="$BATS_TEST_TMPDIR/root-shell-sudo-stdin-argv.txt"
    export SUDO="$fake_sudo"

    cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE_FILE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
exec "$@"
EOF
    chmod +x "$fake_sudo"

    out="$(printf "printf 'stdin-ok\\n'\n" | run_as_root_shell)"
    [[ "$out" == "stdin-ok" ]] || fail "Expected stdin-ok, got: $out"

    local -a argv=()
    mapfile -t argv < "$CAPTURE_FILE"
    [[ "${argv[0]:-}" == "-n" ]] || fail "Expected noninteractive sudo (-n), got: ${argv[*]}"
}

@test "run_as_root_shell: discovered sudo path is noninteractive" {
    [[ "$EUID" -ne 0 ]] || skip "sudo path is bypassed when tests run as root"

    local fake_sudo="$BATS_TEST_TMPDIR/fake-discovered-sudo"
    export CAPTURE_FILE="$BATS_TEST_TMPDIR/root-shell-discovered-sudo-argv.txt"
    export FAKE_DISCOVERED_SUDO="$fake_sudo"
    unset SUDO

    cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE_FILE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
exec "$@"
EOF
    chmod +x "$fake_sudo"

    _gtbi_system_binary_path() {
        case "${1:-}" in
            sudo) printf '%s\n' "$FAKE_DISCOVERED_SUDO" ;;
            env) printf '/usr/bin/env\n' ;;
            bash) printf '/usr/bin/bash\n' ;;
            *) return 1 ;;
        esac
    }

    run run_as_root_shell "printf 'discovered-ok\n'"
    assert_success
    assert_output "discovered-ok"

    local -a argv=()
    mapfile -t argv < "$CAPTURE_FILE"
    [[ "${argv[0]:-}" == "-n" ]] || fail "Expected noninteractive sudo (-n), got: ${argv[*]}"
}

@test "run_as_target_shell stdin mode treats GTBI_BIN_DIR as inert PATH data" {
    local marker="$BATS_TEST_TMPDIR/target-shell-stdin-path-injection"
    local out
    export GTBI_BIN_DIR="\$(printf pwn > '$marker')"

    run_as_target() {
        "$@"
    }

    out="$(printf "printf 'ok\\n'\n" | run_as_target_shell)"
    [[ "$out" == "ok" ]] || fail "Expected ok, got: $out"
    [[ ! -e "$marker" ]] || fail "GTBI_BIN_DIR command substitution executed"
}

@test "run_as_target: extends PATH for target-user non-login shells" {
    export TARGET_USER="testuser"
    export TARGET_HOME="/home/testuser"
    export GTBI_BIN_DIR="/home/testuser/.local/bin"

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "testuser" ]]; then
            printf 'testuser:x:1000:1000::/home/testuser:/bin/bash\n'
            return 0
        fi
        return 1
    }

    use_spy_sudo

    run run_as_target env
    assert_success

    local captured
    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *"PATH=/home/testuser/.local/bin:/home/testuser/.local/bin:/home/testuser/.gtbi/bin:/home/testuser/.cargo/bin:/home/testuser/.bun/bin:/home/testuser/.atuin/bin:/home/testuser/go/bin:"* ]] \
        || fail "Expected run_as_target to extend PATH for target-user bins, got: $captured"
}

@test "installer target-user runners use noninteractive sudo" {
    local helpers="$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F '"$sudo_bin" -n -u "$user" "$env_bin" "${env_args[@]}" "$sh_bin"' "$helpers"
    assert_success

    run grep -F '"$sudo_bin" -n -u "$user" "$env_bin" "${env_args[@]}" "$sh_bin"' "$installer"
    assert_success

    run grep -F 'postgres_runner=("$postgres_sudo_bin" -n -u postgres -H)' "$installer"
    assert_success
}

@test "installer upgrade setup uses noninteractive sudo fallbacks" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F '"$sudo_bin" -n "$apt_get_bin" update -qq && "$sudo_bin" -n "$apt_get_bin" install -y jq' "$installer"
    assert_success

    run grep -F '"$sudo_bin" -n "$mkdir_bin" -p "${GTBI_RESUME_DIR:-/var/lib/gtbi}"' "$installer"
    assert_success

    run grep -F '"$sudo_bin" -n "$chown_bin" "$("$id_bin" -u):$("$id_bin" -g)" "${GTBI_RESUME_DIR:-/var/lib/gtbi}"' "$installer"
    assert_success
}

@test "run_as_target: passwd home overrides stale TARGET_HOME and home-scoped bin dir" {
    local target_home
    local stale_home
    local captured

    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    mkdir -p "$target_home/.local/bin" "$target_home/.gtbi" "$stale_home/.local/bin" "$stale_home/.gtbi"

    export TARGET_USER="gtbitestuser"
    export TARGET_HOME="$stale_home"
    export GTBI_BIN_DIR="$stale_home/.local/bin"
    export GTBI_HOME="$stale_home/.gtbi"

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "gtbitestuser" ]]; then
            printf 'gtbitestuser:x:1000:1000::%s:/bin/bash\n' "$target_home"
            return 0
        fi
        return 1
    }

    use_spy_sudo

    run run_as_target env
    assert_success

    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *"HOME=$target_home"* ]] || fail "Expected passwd target HOME, got: $captured"
    [[ "$captured" == *"TARGET_HOME=$target_home"* ]] || fail "Expected passwd TARGET_HOME, got: $captured"
    [[ "$captured" == *"GTBI_BIN_DIR=$target_home/.local/bin"* ]] || fail "Expected repaired GTBI_BIN_DIR, got: $captured"
    [[ "$captured" == *"GTBI_HOME=$target_home/.gtbi"* ]] || fail "Expected repaired GTBI_HOME, got: $captured"
    [[ "$captured" != *"$stale_home"* ]] || fail "Stale home leaked into target environment: $captured"
}

@test "run_as_target: slash TARGET_HOME is not used as a stale-home rewrite prefix" {
    local target_home
    local captured

    target_home="$(create_temp_dir)"
    mkdir -p "$target_home/.local/bin" "$target_home/.gtbi"

    export TARGET_USER="gtbitestuser"
    export TARGET_HOME="/"
    export GTBI_BIN_DIR="/usr/local/bin"
    export GTBI_HOME="/opt/gtbi"

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "gtbitestuser" ]]; then
            printf 'gtbitestuser:x:1000:1000::%s:/bin/bash\n' "$target_home"
            return 0
        fi
        return 1
    }

    use_spy_sudo

    run run_as_target env
    assert_success

    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *"HOME=$target_home"* ]] || fail "Expected passwd target HOME, got: $captured"
    [[ "$captured" == *"TARGET_HOME=$target_home"* ]] || fail "Expected passwd TARGET_HOME, got: $captured"
    [[ "$captured" == *"GTBI_BIN_DIR=/usr/local/bin"* ]] || fail "Slash TARGET_HOME rewrote GTBI_BIN_DIR: $captured"
    [[ "$captured" == *"GTBI_HOME=/opt/gtbi"* ]] || fail "Slash TARGET_HOME rewrote GTBI_HOME: $captured"
}

@test "primary bin helpers fail clearly without HOME or GTBI_BIN_DIR" {
    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; gtbi_link_primary_bin_command /tmp/source cmd' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    assert_failure
    assert_output --partial "GTBI_BIN_DIR must be an absolute path"
    refute_output --partial "unbound variable"

    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; gtbi_install_executable_into_primary_bin /tmp/source cmd' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    assert_failure
    assert_output --partial "GTBI_BIN_DIR must be an absolute path"
    refute_output --partial "unbound variable"
}

@test "run_as_target: preserves GTBI bootstrap context for generated child shells" {
    export TARGET_USER="testuser"
    export TARGET_HOME="/home/testuser"
    export GTBI_HOME="/home/testuser/.gtbi"
    export GTBI_BIN_DIR="/home/testuser/.local/bin"
    export GTBI_BOOTSTRAP_DIR="/tmp/gtbi-bootstrap"
    export GTBI_LIB_DIR="/tmp/gtbi-bootstrap/scripts/lib"
    export GTBI_GENERATED_DIR="/tmp/gtbi-bootstrap/scripts/generated"
    export GTBI_ASSETS_DIR="/tmp/gtbi-bootstrap/gtbi"
    export GTBI_CHECKSUMS_YAML="/tmp/gtbi-bootstrap/checksums.yaml"
    export GTBI_MANIFEST_YAML="/tmp/gtbi-bootstrap/gtbi.manifest.yaml"
    export CHECKSUMS_FILE="/tmp/gtbi-bootstrap/checksums.yaml"
    export GTBI_REF="main"

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "testuser" ]]; then
            printf 'testuser:x:1000:1000::/home/testuser:/bin/bash\n'
            return 0
        fi
        return 1
    }

    use_spy_sudo

    run run_as_target env
    assert_success

    local captured
    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *"GTBI_BOOTSTRAP_DIR=/tmp/gtbi-bootstrap"* ]] || fail "Missing GTBI_BOOTSTRAP_DIR: $captured"
    [[ "$captured" == *"GTBI_LIB_DIR=/tmp/gtbi-bootstrap/scripts/lib"* ]] || fail "Missing GTBI_LIB_DIR: $captured"
    [[ "$captured" == *"GTBI_GENERATED_DIR=/tmp/gtbi-bootstrap/scripts/generated"* ]] || fail "Missing GTBI_GENERATED_DIR: $captured"
    [[ "$captured" == *"GTBI_ASSETS_DIR=/tmp/gtbi-bootstrap/gtbi"* ]] || fail "Missing GTBI_ASSETS_DIR: $captured"
    [[ "$captured" == *"GTBI_CHECKSUMS_YAML=/tmp/gtbi-bootstrap/checksums.yaml"* ]] || fail "Missing GTBI_CHECKSUMS_YAML: $captured"
    [[ "$captured" == *"GTBI_MANIFEST_YAML=/tmp/gtbi-bootstrap/gtbi.manifest.yaml"* ]] || fail "Missing GTBI_MANIFEST_YAML: $captured"
    [[ "$captured" == *"CHECKSUMS_FILE=/tmp/gtbi-bootstrap/checksums.yaml"* ]] || fail "Missing CHECKSUMS_FILE: $captured"
    [[ "$captured" == *"GTBI_REF=main"* ]] || fail "Missing GTBI_REF: $captured"
}

@test "_gtbi_resolve_target_home: fails closed when NSS cannot resolve another user" {
    stub_command "getent" "" 2
    export HOME="$BATS_TEST_TMPDIR/current-home"

    run _gtbi_resolve_target_home "missinguser"
    assert_failure
    assert_output ""
}

@test "_gtbi_resolve_target_home: ignores slash passwd homes and falls back to current HOME" {
    local current_user
    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    export HOME="$BATS_TEST_TMPDIR/current-home"
    mkdir -p "$HOME"

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "$current_user" ]]; then
            printf '%s\n' "$current_user:x:1000:1000::/:/bin/bash"
            return 0
        fi
        return 2
    }

    run _gtbi_resolve_target_home "$current_user"
    assert_success
    assert_output "$HOME"
}

@test "_gtbi_resolve_target_home: current HOME fallback cannot override explicit target home" {
    local current_user
    local current_home
    local target_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    export HOME="$current_home"

    _gtbi_getent_passwd_entry() {
        return 2
    }

    run _gtbi_resolve_target_home "$current_user" "$target_home"
    assert_failure
    assert_output ""

    run _gtbi_resolve_target_home "$current_user" "$current_home"
    assert_success
    assert_output "$current_home"
}

@test "_gtbi_resolve_target_home: rejects slash HOME for current user when passwd resolution is unavailable" {
    local current_user
    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    export HOME="/"

    _gtbi_getent_passwd_entry() {
        return 2
    }

    run _gtbi_resolve_target_home "$current_user"
    assert_failure
    assert_output ""
}

@test "run_as_target: fails closed when target home cannot be resolved" {
    export TARGET_USER="missinguser"
    unset TARGET_HOME GTBI_BIN_DIR GTBI_HOME
    stub_command "getent" "" 2
    use_spy_sudo

    run run_as_target env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "run_as_target should not invoke sudo when TARGET_HOME cannot be resolved"
    fi
}

@test "run_as_target: rejects slash TARGET_HOME override" {
    export TARGET_USER="testuser"
    export TARGET_HOME="/"
    use_spy_sudo

    run run_as_target env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'testuser': /"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "run_as_target should not invoke sudo when TARGET_HOME is '/'"
    fi
}

@test "run_as_target: rejects invalid TARGET_USER before sudo" {
    export TARGET_USER="../bad user"
    export TARGET_HOME="/home/testuser"
    use_spy_sudo

    run run_as_target env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "run_as_target should not invoke sudo for invalid TARGET_USER"
    fi
}

@test "_gtbi_resolve_target_home: ignores function-poisoned passwd and identity shims" {
    local current_user=""
    local current_home=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    [[ -n "$current_user" ]] || skip "Could not resolve current user"
    [[ "$current_user" != "root" ]] || skip "Test requires a non-root current user"

    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" ]] || skip "Could not resolve current home from passwd"
    export HOME="$current_home"

    getent() {
        printf '%s\n' 'poisoned:x:0:0::/tmp/poisoned:/bin/bash'
    }
    id() {
        printf '%s\n' 'poisoned'
    }
    whoami() {
        printf '%s\n' 'poisoned'
    }

    run _gtbi_resolve_target_home "$current_user"
    assert_success
    assert_output "$current_home"
}

@test "run_as_target: ignores function-poisoned whoami on same-user fast path" {
    local current_user=""
    local current_home=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    [[ -n "$current_user" ]] || skip "Could not resolve current user"
    [[ "$current_user" != "root" ]] || skip "Test requires a non-root current user"

    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" ]] || skip "Could not resolve current home from passwd"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$current_home"
    unset GTBI_BIN_DIR GTBI_HOME

    whoami() {
        printf '%s\n' 'poisoned'
    }

    use_spy_sudo

    run run_as_target env
    assert_success
    assert_output --partial "HOME=$current_home"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "run_as_target should not invoke sudo on the same-user fast path"
    fi
}

@test "run_as_target: same-user fast path preserves caller directory" {
    local caller_dir="$BATS_TEST_TMPDIR/caller"
    local target_home="$BATS_TEST_TMPDIR/target home"
    local after_pwd=""
    local status=0

    mkdir -p "$caller_dir" "$target_home"

    export TARGET_USER="testuser"
    export TARGET_HOME="$target_home"
    unset GTBI_BIN_DIR GTBI_HOME

    _gtbi_resolve_current_user() {
        printf 'testuser\n'
    }

    _gtbi_getent_passwd_entry() {
        if [[ "${1:-}" == "testuser" ]]; then
            printf 'testuser:x:1000:1000::%s:/bin/bash\n' "$target_home"
            return 0
        fi
        return 1
    }

    cd "$caller_dir" || fail "failed to enter caller dir"
    run_as_target true || status=$?
    after_pwd="$(pwd -P)"
    cd "$PROJECT_ROOT" || true

    [[ "$status" -eq 0 ]] || fail "run_as_target failed with status $status"
    [[ "$after_pwd" == "$caller_dir" ]] || fail "run_as_target leaked cwd: $after_pwd"
}

@test "gtbi_ensure_primary_bin_dir: rejects invalid GTBI_BIN_DIR before mkdir" {
    export TARGET_USER="testuser"
    export TARGET_HOME="/home/testuser"
    export GTBI_BIN_DIR="relative/bin"
    use_spy_sudo

    run_as_target() {
        echo "run_as_target invoked"
        return 0
    }

    run gtbi_ensure_primary_bin_dir
    assert_failure
    assert_output --partial "GTBI_BIN_DIR must be an absolute path and cannot be '/'"
    refute_output --partial "run_as_target invoked"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "gtbi_ensure_primary_bin_dir should not invoke sudo for invalid GTBI_BIN_DIR"
    fi
}

@test "gtbi_ensure_primary_bin_dir: does not use current HOME when TARGET_HOME is unresolved" {
    export TARGET_USER="missinguser"
    unset TARGET_HOME
    export HOME="$(create_temp_dir)"
    export GTBI_BIN_DIR="/usr/local/bin"

    use_spy_sudo
    stub_command "getent" "" 2
    stub_command "id" "otheruser" 0
    stub_command "whoami" "otheruser" 0

    run gtbi_ensure_primary_bin_dir
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser'"

    if [[ -f "$STUB_DIR/sudo.log" ]] && [[ -s "$STUB_DIR/sudo.log" ]]; then
        fail "gtbi_ensure_primary_bin_dir should not invoke sudo when TARGET_HOME cannot be resolved"
    fi
}

@test "_gtbi_run_root_bin_command: rejects bare command names" {
    run _gtbi_run_root_bin_command mkdir -p "$BATS_TEST_TMPDIR/root-bin"

    assert_failure
    assert_output --partial "Root primary bin command must be an absolute trusted path"
}

@test "primary bin helpers resolve trusted coreutils before root-owned writes" {
    local calls_file="$BATS_TEST_TMPDIR/primary-bin-root-calls.log"

    export TARGET_USER="testuser"
    export TARGET_HOME="/home/testuser"
    export GTBI_BIN_DIR="/usr/local/bin"

    _gtbi_system_binary_path() {
        case "${1:-}" in
            mkdir|ln|install)
                printf '/trusted/%s\n' "$1"
                return 0
                ;;
        esac
        return 1
    }

    _gtbi_run_root_bin_command() {
        printf '%s\n' "$*" >> "$calls_file"
        return 0
    }

    run gtbi_link_primary_bin_command /tmp/source-tool tool
    assert_success

    run gtbi_install_executable_into_primary_bin /tmp/source-tool installed-tool
    assert_success

    local calls
    calls="$(cat "$calls_file")"
    [[ "$calls" == *"/trusted/mkdir -p /usr/local/bin"* ]] || fail "mkdir was not trusted: $calls"
    [[ "$calls" == *"/trusted/ln -sf /tmp/source-tool /usr/local/bin/tool"* ]] || fail "ln was not trusted: $calls"
    [[ "$calls" == *"/trusted/install -m 0755 /tmp/source-tool /usr/local/bin/installed-tool"* ]] || fail "install was not trusted: $calls"
    [[ "$calls" != *$'\n'"mkdir "* ]] || fail "bare mkdir leaked into root helper: $calls"
    [[ "$calls" != *$'\n'"ln "* ]] || fail "bare ln leaked into root helper: $calls"
    [[ "$calls" != *$'\n'"install "* ]] || fail "bare install leaked into root helper: $calls"
}

@test "_gtbi_force_reinstall_enabled: returns 0 when true" {
    export GTBI_FORCE_REINSTALL="true"
    run _gtbi_force_reinstall_enabled
    assert_success
}

@test "_gtbi_force_reinstall_enabled: returns 1 when false" {
    export GTBI_FORCE_REINSTALL="false"
    run _gtbi_force_reinstall_enabled
    assert_failure
}

# -------------------------------------------------
# Skip-if-installed tests (bd-1eop)
# -------------------------------------------------

@test "gtbi_module_is_installed: returns false when no check defined" {
    # Clear installed_check arrays
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=()
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=()

    run gtbi_module_is_installed "mod1"
    assert_failure
}

@test "gtbi_module_is_installed: returns true when check succeeds" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )

    run gtbi_module_is_installed "mod1"
    assert_success
}

@test "gtbi_module_is_installed: returns false when check fails" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="false" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )

    run gtbi_module_is_installed "mod1"
    assert_failure
}

@test "gtbi_should_skip_module: skips installed modules" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )
    export GTBI_FORCE_REINSTALL=false

    run gtbi_should_skip_module "mod1"
    assert_success  # 0 means should skip
}

@test "gtbi_should_skip_module: does not skip when force reinstall" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )
    export GTBI_FORCE_REINSTALL=true

    run gtbi_should_skip_module "mod1"
    assert_failure  # 1 means do not skip (install)
}

@test "gtbi_module_is_installed: respects run_as target_user" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="target_user" )

    # Mock run_as_target to just pass through to bash
    # Note: We need to export the function for subshells
    run_as_target() {
        "$@"
    }
    export -f run_as_target

    run gtbi_module_is_installed "mod1"
    assert_success
}

@test "gtbi_module_is_installed: target_user checks include GTBI user PATH prefix" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="command -v br" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="target_user" )

    export CAPTURE_FILE="$BATS_TEST_TMPDIR/run_as_target_args.txt"
    run_as_target() {
        printf '%s\n' "$*" > "$CAPTURE_FILE"
        return 0
    }
    export -f run_as_target

    run gtbi_module_is_installed "mod1"
    assert_success

    local captured
    captured="$(cat "$CAPTURE_FILE")"
    [[ "$captured" == *'_gtbi_primary_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"'* ]] \
        || fail "Expected target-user installed check to compute runtime primary bin, got: $captured"
    [[ "$captured" == *'export PATH="${_gtbi_primary_bin}:$HOME/.local/bin:$HOME/.gtbi/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:$PATH"'* ]] \
        || fail "Expected target-user installed check to extend PATH, got: $captured"
    [[ "$captured" == *'eval "$1" _ command -v br'* ]] \
        || fail "Expected target-user installed check to extend PATH, got: $captured"
}

@test "gtbi_module_is_installed: target_user checks fail closed without run_as_target" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="command -v false-positive-tool" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="target_user" )

    export TARGET_USER="ubuntu"
    export TARGET_HOME="$BATS_TEST_TMPDIR/target-home"
    export GTBI_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$GTBI_BIN_DIR" "$BATS_TEST_TMPDIR/global-bin"

    cat > "$BATS_TEST_TMPDIR/global-bin/false-positive-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/global-bin/false-positive-tool"
    export PATH="$BATS_TEST_TMPDIR/global-bin:/usr/bin:/bin"

    unset -f run_as_target

    run gtbi_module_is_installed "mod1"
    assert_failure
}

@test "gtbi_module_is_installed: root checks fail closed without sudo" {
    unset GTBI_MODULE_INSTALLED_CHECK GTBI_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA GTBI_MODULE_INSTALLED_CHECK=( ["mod1"]="command -v false-positive-root-tool" )
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="root" )
    local original_path="$PATH"

    mkdir -p "$BATS_TEST_TMPDIR/global-bin"
    cat > "$BATS_TEST_TMPDIR/global-bin/bash" <<'EOF'
#!/usr/bin/env bash
exec /bin/bash "$@"
EOF
    chmod +x "$BATS_TEST_TMPDIR/global-bin/bash"

    cat > "$BATS_TEST_TMPDIR/global-bin/false-positive-root-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/global-bin/false-positive-root-tool"
    export PATH="$BATS_TEST_TMPDIR/global-bin"

    run gtbi_module_is_installed "mod1"
    export PATH="$original_path"
    assert_failure
}
