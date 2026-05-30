#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

# ============================================================
# MANIFEST TESTS
# ============================================================

@test "gtbi.manifest.yaml contains stack.srps module" {
    run grep -q "^  - id: stack.srps" "$PROJECT_ROOT/gtbi.manifest.yaml"
    assert_success
}

@test "SRPS manifest entry has required fields" {
    local manifest="$PROJECT_ROOT/gtbi.manifest.yaml"
    local block

    block=$(awk '
        $0 ~ /^  - id: stack\.srps$/ {found=1; print; next}
        found && $0 ~ /^  - id: / {exit}
        found {print}
    ' "$manifest")

    [[ -n "$block" ]] || fail "stack.srps block not found"
    echo "$block" | grep -q "description:" || fail "Missing description field"
    echo "$block" | grep -q "installed_check:" || fail "Missing installed_check field"
    echo "$block" | grep -q "verified_installer:" || fail "Missing verified_installer field"
}

@test "SRPS installed_check command references sysmoni" {
    local manifest="$PROJECT_ROOT/gtbi.manifest.yaml"
    local check_cmd

    check_cmd=$(awk '
        $0 ~ /^  - id: stack\.srps$/ {found=1}
        found && $0 ~ /^  - id: / && $0 !~ /stack\.srps/ {exit}
        found && $0 ~ /command:/ {print; exit}
    ' "$manifest" | sed 's/.*command: *//; s/"//g')

    [[ -n "$check_cmd" ]] || fail "installed_check command not found"
    echo "$check_cmd" | grep -q "sysmoni" || fail "Missing sysmoni in installed_check"
}

# ============================================================
# CHECKSUMS TESTS
# ============================================================

@test "checksums.yaml contains SRPS entry" {
    run grep -q "^  srps:" "$PROJECT_ROOT/checksums.yaml"
    assert_success
}

@test "SRPS checksum has valid SHA256 format" {
    local sha256
    sha256=$(grep -A 2 "^  srps:" "$PROJECT_ROOT/checksums.yaml" | grep "sha256:" | sed 's/.*sha256: *//; s/"//g')

    [[ -n "$sha256" ]] || fail "SRPS sha256 not found"
    [[ "$sha256" =~ ^[a-f0-9]{64}$ ]] || fail "Invalid SHA256 format: $sha256"
}

@test "SRPS installer URL is reachable (optional)" {
    if [[ -z "${GTBI_TEST_ALLOW_NET:-}" ]]; then
        skip "Network checks disabled (set GTBI_TEST_ALLOW_NET=1 to enable)"
    fi

    local url
    url=$(grep -A 2 "^  srps:" "$PROJECT_ROOT/checksums.yaml" | grep "url:" | sed 's/.*url: *//; s/"//g')

    [[ -n "$url" ]] || fail "SRPS installer URL not found"

    run curl -sI -o /dev/null -w "%{http_code}" "$url"
    assert_success
    [[ "$output" == "200" ]] || fail "Installer URL returned HTTP $output"
}

# ============================================================
# GENERATED SCRIPTS TESTS
# ============================================================

@test "doctor_checks.sh contains SRPS check" {
    run grep -q "srps" "$PROJECT_ROOT/scripts/generated/doctor_checks.sh"
    assert_success
}

@test "install_stack.sh contains SRPS installation" {
    run grep -q "srps" "$PROJECT_ROOT/scripts/generated/install_stack.sh"
    assert_success
}

@test "manifest_index.sh contains SRPS metadata" {
    run grep -q "stack.srps" "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    assert_success
}

# ============================================================
# MANIFEST GENERATOR TESTS
# ============================================================

@test "Manifest generator validates successfully" {
    if ! command -v bun &>/dev/null; then
        skip "bun not available"
    fi

    run bash -lc "cd '$PROJECT_ROOT/packages/manifest' && bun run generate:validate"
    assert_success
}

@test "Manifest generate dry-run succeeds" {
    if ! command -v bun &>/dev/null; then
        skip "bun not available"
    fi

    run bash -lc "cd '$PROJECT_ROOT/packages/manifest' && bun run generate:dry"
    assert_success
}

# ============================================================
# DOCTOR COMMAND TESTS (optional)
# ============================================================

@test "Doctor command runs (optional)" {
    if [[ -z "${GTBI_RUN_DOCTOR_TESTS:-}" ]]; then
        skip "Doctor tests disabled (set GTBI_RUN_DOCTOR_TESTS=1 to enable)"
    fi

    run bash -lc "cd '$PROJECT_ROOT' && scripts/lib/doctor.sh --json"
    assert_success
}

@test "Doctor command output references SRPS (optional)" {
    if [[ -z "${GTBI_RUN_DOCTOR_TESTS:-}" ]]; then
        skip "Doctor tests disabled (set GTBI_RUN_DOCTOR_TESTS=1 to enable)"
    fi

    run bash -lc "cd '$PROJECT_ROOT' && scripts/lib/doctor.sh --json"
    assert_success
    assert_output --partial "srps"
}
