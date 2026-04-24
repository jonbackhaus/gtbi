#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "security"
    
    # Create dummy checksums file
    export CHECKSUMS_FILE=$(create_temp_file)
}

teardown() {
    common_teardown
}

@test "enforce_https: allows https" {
    run enforce_https "https://example.com"
    assert_success
}

@test "enforce_https: blocks http" {
    run enforce_https "http://example.com"
    assert_failure
}

@test "verify_checksum: passes on match" {
    local content="verified content"
    local sha
    if command -v sha256sum &>/dev/null; then
        sha=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
    else
        sha=$(echo -n "$content" | shasum -a 256 | cut -d' ' -f1)
    fi

    # Stub curl to return content (handles -o flag)
    stub_curl "$content" 0

    run verify_checksum "https://example.com" "$sha" "test"
    assert_success
    assert_output --partial "$content"
    assert_output --partial "Verified: test"
}

@test "verify_checksum: clears RETURN cleanup trap after success" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        sha="$(printf "%s" "verified content" | sha256sum | cut -d" " -f1)"
        verify_checksum "https://example.com" "$sha" "test" >/dev/null 2>&1
        trap -p RETURN
    ' _ "$security_lib"
    assert_success
    assert_output ""
}

@test "fetch_checksum: clears RETURN cleanup trap after success" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        fetch_checksum "https://example.com" >/dev/null
        trap -p RETURN
    ' _ "$security_lib"
    assert_success
    assert_output ""
}

@test "verify_checksum: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        sha="$(printf "%s" "verified content" | sha256sum | cut -d" " -f1)"
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            verify_checksum "https://example.com" "$sha" "test" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "fetch_checksum: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            fetch_checksum "https://example.com" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "fetch_and_run_with_recovery: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "printf ok" > "$2"
        }
        bash() {
            return 0
        }
        sha="$(printf "%s" "printf ok" | sha256sum | cut -d" " -f1)"
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            fetch_and_run_with_recovery "https://example.com/install.sh" "$sha" "test" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "verify_checksum: fails on mismatch" {
    local content="malicious content"
    local sha="0000000000000000000000000000000000000000000000000000000000000000"

    stub_curl "$content" 0
    
    run verify_checksum "https://example.com" "$sha" "test"
    assert_failure
    assert_output --partial "Checksum mismatch"
}

@test "verify_checksum: rejects trusted-owner mismatch without refreshed checksum" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        source "$1"
        acfs_download_to_file() {
            printf "%s" "changed trusted content" > "$2"
        }
        acfs_refresh_loaded_checksums_from_remote() {
            return 1
        }
        verify_checksum \
            "https://raw.githubusercontent.com/Dicklesworthstone/example/main/install.sh" \
            "0000000000000000000000000000000000000000000000000000000000000000" \
            "trusted_tool"
    ' _ "$security_lib"

    assert_failure
    assert_output --partial "Checksum mismatch"
    refute_output --partial "Trusted-tool auto-accept"
}

@test "load_checksums: parses yaml" {
    # Need full 64-char sha256 for regex
    local sha1="1111111111111111111111111111111111111111111111111111111111111111"
    local sha2="2222222222222222222222222222222222222222222222222222222222222222"

    cat > "$CHECKSUMS_FILE" <<EOF
installers:
  tool1:
    url: "https://example.com/1"
    sha256: "$sha1"
  tool2:
    url: "https://example.com/2"
    sha256: "$sha2"
EOF

    echo "DEBUG: CHECKSUMS_FILE=$CHECKSUMS_FILE" >&2
    cat "$CHECKSUMS_FILE" >&2

    # load_checksums populates global LOADED_CHECKSUMS
    # Since we use 'run', variables are lost.
    # We must call it directly to test state.
    
    load_checksums
    assert_equal "$?" "0"
    
    # Use get_checksum accessor
    local val1
    val1=$(get_checksum "tool1")
    echo "DEBUG: val1='$val1'" >&2
    assert_equal "$val1" "$sha1"
    
    local val2
    val2=$(get_checksum "tool2")
    assert_equal "$val2" "$sha2"
}
