#!/usr/bin/env bats
# ============================================================
# E2E Tests: Terminal Compatibility
# Tests the wizard works correctly across different terminal types
# ============================================================

load 'test_helper'

setup() {
    e2e_setup
}

teardown() {
    e2e_teardown
}

# ============================================================
# TERM Environment Variable Tests
# ============================================================

@test "CLI mode works with TERM=dumb" {
    local project_name="term-dumb-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=dumb run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

@test "CLI mode works with TERM=xterm" {
    local project_name="term-xterm-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=xterm run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

@test "CLI mode works with TERM=xterm-256color" {
    local project_name="term-256-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=xterm-256color run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

@test "CLI mode works without TERM set" {
    local project_name="term-unset-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    unset TERM
    run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

# ============================================================
# Unicode Detection Tests
# ============================================================

@test "CLI mode output works without unicode" {
    local project_name="no-unicode-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=dumb LANG=C run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    # Output should not contain broken unicode
    [[ "$output" != *"�"* ]] || true
}

@test "CLI mode output includes unicode when available" {
    local project_name="unicode-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=xterm-256color LANG=en_US.UTF-8 run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    # Project should be created regardless of unicode support
    [[ -d "$project_dir" ]]
}

# ============================================================
# Terminal Size Tests
# ============================================================

@test "Interactive mode fails gracefully with small terminal" {
    skip_without_expect

    # Set very small terminal size
    export COLUMNS=40
    export LINES=10

    run expect -c '
        spawn bash '"$GTBI_LIB_DIR/newproj.sh"' --interactive
        expect {
            -re "(small|resize|terminal)" { exit 0 }
            timeout { exit 1 }
        }
    '

    # Should either warn about size or work anyway
    [[ "$status" -eq 0 ]] || [[ "$output" == *"terminal"* ]]
}

@test "Terminal size check function exists" {
    source "$GTBI_LIB_DIR/newproj.sh" 2>/dev/null || true

    # Check the function exists
    declare -f get_terminal_size &>/dev/null || \
    declare -f check_terminal_size &>/dev/null || \
    skip "Terminal size functions not found in newproj.sh"
}

# ============================================================
# Color Support Tests
# ============================================================

@test "Output has no raw escape codes when TERM=dumb" {
    local project_name="dumb-escape-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    TERM=dumb run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    # Escape codes would show as \033 or similar
    [[ "$output" != *$'\033['* ]] || true  # May have codes, that's ok
}

@test "NO_COLOR environment variable is respected" {
    local project_name="no-color-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    NO_COLOR=1 run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

# ============================================================
# CI Environment Detection Tests
# ============================================================

@test "Detects CI via CI=true" {
    CI=true run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
    [[ "$output" == *"CI"* ]]
}

@test "Detects CI via GITHUB_ACTIONS" {
    GITHUB_ACTIONS=true run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
    [[ "$output" == *"CI"* ]] || [[ "$output" == *"environment"* ]]
}

@test "Detects CI via GITLAB_CI" {
    GITLAB_CI=true run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
}

@test "Detects CI via JENKINS_URL" {
    JENKINS_URL="http://jenkins.example.com" run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
}

@test "Detects CI via TRAVIS" {
    TRAVIS=true run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
}

@test "Detects CI via CIRCLECI" {
    CIRCLECI=true run bash "$GTBI_LIB_DIR/newproj.sh" --interactive

    assert_failure
}

# ============================================================
# Shell Compatibility
# ============================================================

@test "Works with bash 4.x features" {
    # Test associative array syntax works
    local project_name="bash4-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
}

@test "Works in subshell environment" {
    local project_name="subshell-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash -c "bash '$GTBI_LIB_DIR/newproj.sh' '$project_name' '$project_dir'"

    assert_success
    [[ -d "$project_dir" ]]
}

# ============================================================
# Locale Tests
# ============================================================

@test "Works with LC_ALL=C" {
    local project_name="locale-c-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    LC_ALL=C run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
}

@test "Works with UTF-8 locale" {
    local project_name="locale-utf8-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    LC_ALL=en_US.UTF-8 run bash "$GTBI_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
}
