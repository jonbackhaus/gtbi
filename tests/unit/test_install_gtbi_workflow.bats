#!/usr/bin/env bats

setup() {
    TEST_WORKSPACE="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT_PATH="$PROJECT_ROOT/scripts/install-gtbi-workflow.sh"
    REPO_DIR="$TEST_WORKSPACE/repo"
    TEMPLATE_DIR="$TEST_WORKSPACE/templates"
    FAKE_BIN_DIR="$TEST_WORKSPACE/fake-bin"

    mkdir -p "$REPO_DIR/.git" "$TEMPLATE_DIR" "$FAKE_BIN_DIR"

    cat > "$TEMPLATE_DIR/notify.yml" <<'EOF'
env:
  TOOL_NAME: '{{ TOOL_NAME_PLACEHOLDER }}'
  INSTALLER_PATH: 'install.sh'
token: ${{ secrets.GTBI_REPO_DISPATCH_TOKEN }}
EOF

    cat > "$TEMPLATE_DIR/validate.yml" <<'EOF'
env:
  TOOL_NAME: '{{ TOOL_NAME_PLACEHOLDER }}'
  INSTALLER_PATH: 'install.sh'
secret: GTBI_REPO_DISPATCH_TOKEN
EOF

    local fake_tool
    for fake_tool in curl mkdir mktemp mv rm sha256sum; do
        cat > "$FAKE_BIN_DIR/$fake_tool" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$fake_tool" >> "$FAKE_BIN_DIR/invoked"
exit 99
EOF
        chmod +x "$FAKE_BIN_DIR/$fake_tool"
    done
}

teardown() {
    rm -rf "$TEST_WORKSPACE"
}

@test "install-gtbi-workflow escapes YAML values and ignores poisoned PATH tools" {
    local installer_path="scripts/install & fun's/install.sh"
    local tool_name="tool&with'quote"

    mkdir -p "$REPO_DIR/scripts/install & fun's"
    printf '#!/usr/bin/env bash\n' > "$REPO_DIR/$installer_path"

    run /bin/bash -c 'cd "$1" && shift && "$@"' bash "$REPO_DIR" \
        /usr/bin/env -i \
        HOME="${HOME:-/tmp}" \
        PATH="$FAKE_BIN_DIR:/usr/bin:/bin" \
        GTBI_TEMPLATE_URL="file://$TEMPLATE_DIR/notify.yml" \
        VALIDATE_TEMPLATE_URL="file://$TEMPLATE_DIR/validate.yml" \
        /bin/bash "$SCRIPT_PATH" "$tool_name" "$installer_path"

    [[ "$status" -eq 0 ]]
    [[ ! -e "$FAKE_BIN_DIR/invoked" ]]
    [[ -f "$REPO_DIR/.github/workflows/notify-gtbi.yml" ]]
    [[ -f "$REPO_DIR/.github/workflows/validate-gtbi.yml" ]]

    grep -F "TOOL_NAME: 'tool&with''quote'" "$REPO_DIR/.github/workflows/notify-gtbi.yml"
    grep -F "INSTALLER_PATH: 'scripts/install & fun''s/install.sh'" "$REPO_DIR/.github/workflows/notify-gtbi.yml"
    grep -F "GTBI_REPO_DISPATCH_TOKEN" "$REPO_DIR/.github/workflows/validate-gtbi.yml"
}

@test "install-gtbi-workflow rejects multiline template values before writing workflows" {
    printf '#!/usr/bin/env bash\n' > "$REPO_DIR/install.sh"

    run /bin/bash -c 'cd "$1" && shift && "$@"' bash "$REPO_DIR" \
        /usr/bin/env -i \
        HOME="${HOME:-/tmp}" \
        PATH="/usr/bin:/bin" \
        GTBI_TEMPLATE_URL="file://$TEMPLATE_DIR/notify.yml" \
        VALIDATE_TEMPLATE_URL="file://$TEMPLATE_DIR/validate.yml" \
        /bin/bash "$SCRIPT_PATH" $'bad\ntool' "install.sh"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"TOOL_NAME must be a single-line value"* ]]
    [[ ! -e "$REPO_DIR/.github/workflows/notify-gtbi.yml" ]]
}
