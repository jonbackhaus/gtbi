#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    SCRIPT_UNDER_TEST="$PROJECT_ROOT/apps/web/scripts/vercel-ignore-build.sh"
}

teardown() {
    common_teardown
}

init_vercel_fixture_repo() {
    local repo
    repo=$(create_temp_dir)

    mkdir -p "$repo/apps/web/scripts" "$repo/docs"
    cp "$SCRIPT_UNDER_TEST" "$repo/apps/web/scripts/vercel-ignore-build.sh"

    (
        cd "$repo" || exit 1
        git init -q
        git config user.email "test@example.invalid"
        git config user.name "GTBI Test"

        printf '{}\n' > package.json
        printf 'lock\n' > bun.lock
        printf '{"framework":"nextjs"}\n' > vercel.json
        printf 'core.*\n' > .vercelignore
        printf '{"name":"/web"}\n' > apps/web/package.json
        printf '{"framework":"nextjs"}\n' > apps/web/vercel.json
        printf 'notes\n' > docs/notes.md

        git add .
        git commit -q -m initial
    )

    printf '%s\n' "$repo"
}

commit_fixture_change() {
    local repo="$1"
    local file="$2"
    local content="$3"

    (
        cd "$repo" || exit 1
        printf '%s\n' "$content" > "$file"
        git add "$file"
        git commit -q -m "change $file"
    )
}

commit_many_unrelated_fixture_changes() {
    local repo="$1"
    local index

    (
        cd "$repo" || exit 1
        mkdir -p docs/many
        for index in $(seq 1 200); do
            printf 'doc %s\n' "$index" > "docs/many/file-${index}.md"
        done
        git add docs/many
        git commit -q -m "change many docs"
    )
}

run_ignore_script_for_head_range() {
    local repo="$1"
    local cwd="$2"

    (
        cd "$repo/$cwd" || exit 1
        VERCEL_GIT_PREVIOUS_SHA="$(git rev-parse HEAD~1)" \
            VERCEL_GIT_COMMIT_SHA="$(git rev-parse HEAD)" \
            VERCEL_GIT_COMMIT_REF="main" \
            bash scripts/vercel-ignore-build.sh
    )
}

@test "vercel ignore build proceeds for web app changes from app cwd" {
    repo=$(init_vercel_fixture_repo)
    commit_fixture_change "$repo" "apps/web/package.json" '{"name":"/web","changed":true}'

    run run_ignore_script_for_head_range "$repo" "apps/web"

    assert_failure
    assert_output --partial "Changes detected in: apps/web/"
}

@test "vercel ignore build proceeds for root Vercel config changes from app cwd" {
    repo=$(init_vercel_fixture_repo)
    commit_fixture_change "$repo" "vercel.json" '{"framework":"nextjs","buildCommand":"bun run build"}'

    run run_ignore_script_for_head_range "$repo" "apps/web"

    assert_failure
    assert_output --partial "Changes detected in: vercel.json"
}

@test "vercel ignore build skips unrelated documentation changes" {
    repo=$(init_vercel_fixture_repo)
    commit_fixture_change "$repo" "docs/notes.md" "updated notes"

    run run_ignore_script_for_head_range "$repo" "apps/web"

    assert_success
    assert_output --partial "No web app changes detected"
}

@test "vercel ignore build keeps skip exit with many unrelated changes" {
    repo=$(init_vercel_fixture_repo)
    commit_many_unrelated_fixture_changes "$repo"

    run run_ignore_script_for_head_range "$repo" "apps/web"

    assert_success
    assert_output --partial "No web app changes detected"
}
