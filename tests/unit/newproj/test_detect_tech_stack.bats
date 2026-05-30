#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_detect.sh - Tech Stack Detection
# ============================================================

load '../test_helper'

setup() {
    common_setup

    # Create temp directory for testing
    TEST_DIR=$(create_temp_dir)
    export TEST_DIR

    # Set up logging
    export GTBI_LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$GTBI_LOG_DIR"
    export GTBI_LOG_LEVEL=0

    # Source dependencies
    source_lib "newproj_logging"
    init_logging

    # Source the detection module
    source_lib "newproj_detect"

    # Create temp project directory
    TEMP_PROJECT=$(create_temp_dir)
}

teardown() {
    common_teardown
}

# ============================================================
# Basic Detection Tests
# ============================================================

@test "detect_tech_stack returns empty for empty directory" {
    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ -z "$output" ]]
}

@test "detect_tech_stack returns nodejs for package.json" {
    echo '{"name":"test"}' > "$TEMP_PROJECT/package.json"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
}

@test "detect_tech_stack returns typescript when tsconfig.json present" {
    echo '{}' > "$TEMP_PROJECT/tsconfig.json"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"typescript"* ]]
}

@test "detect_tech_stack returns python for pyproject.toml" {
    echo '[project]' > "$TEMP_PROJECT/pyproject.toml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"python"* ]]
}

@test "detect_tech_stack returns rust for Cargo.toml" {
    echo '[package]' > "$TEMP_PROJECT/Cargo.toml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"rust"* ]]
}

@test "detect_tech_stack returns go for go.mod" {
    echo 'module test' > "$TEMP_PROJECT/go.mod"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"go"* ]]
}

@test "detect_tech_stack returns ruby for Gemfile" {
    echo 'source "https://rubygems.org"' > "$TEMP_PROJECT/Gemfile"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"ruby"* ]]
}

@test "detect_tech_stack returns java-maven for pom.xml" {
    echo '<project></project>' > "$TEMP_PROJECT/pom.xml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"java-maven"* ]]
}

@test "detect_tech_stack returns java-gradle for build.gradle" {
    echo 'plugins {}' > "$TEMP_PROJECT/build.gradle"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"java-gradle"* ]]
}

@test "detect_tech_stack returns php for composer.json" {
    echo '{}' > "$TEMP_PROJECT/composer.json"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"php"* ]]
}

@test "detect_tech_stack returns elixir for mix.exs" {
    echo 'defmodule Test.MixProject do' > "$TEMP_PROJECT/mix.exs"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"elixir"* ]]
}

# ============================================================
# Framework Detection Tests
# ============================================================

@test "detect_tech_stack detects nextjs from .next directory" {
    mkdir "$TEMP_PROJECT/.next"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nextjs"* ]]
}

@test "detect_tech_stack detects nextjs from next.config.js" {
    echo 'module.exports = {}' > "$TEMP_PROJECT/next.config.js"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nextjs"* ]]
}

@test "detect_tech_stack detects nuxt from nuxt.config.ts" {
    echo 'export default {}' > "$TEMP_PROJECT/nuxt.config.ts"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nuxt"* ]]
}

@test "detect_tech_stack detects svelte from svelte.config.js" {
    echo 'export default {}' > "$TEMP_PROJECT/svelte.config.js"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"svelte"* ]]
}

@test "detect_tech_stack detects astro from astro.config.mjs" {
    echo 'export default {}' > "$TEMP_PROJECT/astro.config.mjs"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"astro"* ]]
}

@test "detect_tech_stack detects vite from vite.config.ts" {
    echo 'export default {}' > "$TEMP_PROJECT/vite.config.ts"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"vite"* ]]
}

# ============================================================
# Build Tool Detection Tests
# ============================================================

@test "detect_tech_stack detects docker from Dockerfile" {
    echo 'FROM alpine' > "$TEMP_PROJECT/Dockerfile"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"docker"* ]]
}

@test "detect_tech_stack detects docker-compose from docker-compose.yml" {
    echo 'version: "3"' > "$TEMP_PROJECT/docker-compose.yml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"docker-compose"* ]]
}

@test "detect_tech_stack detects docker-compose from compose.yaml" {
    echo 'version: "3"' > "$TEMP_PROJECT/compose.yaml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"docker-compose"* ]]
}

@test "detect_tech_stack detects make from Makefile" {
    echo 'all:' > "$TEMP_PROJECT/Makefile"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"make"* ]]
}

@test "detect_tech_stack detects cmake from CMakeLists.txt" {
    echo 'cmake_minimum_required(VERSION 3.0)' > "$TEMP_PROJECT/CMakeLists.txt"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"cmake"* ]]
}

@test "detect_tech_stack detects terraform from main.tf" {
    echo 'resource "aws_instance" "example" {}' > "$TEMP_PROJECT/main.tf"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"terraform"* ]]
}

# ============================================================
# Multiple Stack Detection Tests
# ============================================================

@test "detect_tech_stack detects multiple stacks" {
    echo '{}' > "$TEMP_PROJECT/package.json"
    echo '[project]' > "$TEMP_PROJECT/pyproject.toml"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
    [[ "$output" == *"python"* ]]
}

@test "detect_tech_stack detects nodejs + typescript" {
    echo '{}' > "$TEMP_PROJECT/package.json"
    echo '{}' > "$TEMP_PROJECT/tsconfig.json"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
    [[ "$output" == *"typescript"* ]]
}

@test "detect_tech_stack detects nodejs + nextjs + typescript" {
    echo '{}' > "$TEMP_PROJECT/package.json"
    echo '{}' > "$TEMP_PROJECT/tsconfig.json"
    mkdir "$TEMP_PROJECT/.next"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
    [[ "$output" == *"typescript"* ]]
    [[ "$output" == *"nextjs"* ]]
}

# ============================================================
# Edge Case Tests
# ============================================================

@test "detect_tech_stack prefers pyproject.toml over requirements.txt" {
    echo '[project]' > "$TEMP_PROJECT/pyproject.toml"
    echo 'flask' > "$TEMP_PROJECT/requirements.txt"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"python"* ]]
    [[ "$output" != *"python-legacy"* ]]
}

@test "detect_tech_stack returns python-legacy for requirements.txt alone" {
    echo 'flask' > "$TEMP_PROJECT/requirements.txt"

    run detect_tech_stack "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"python-legacy"* ]]
}

@test "detect_tech_stack handles non-existent directory" {
    run detect_tech_stack "/nonexistent/path/12345"
    assert_failure
}

@test "detect_tech_stack handles current directory" {
    cd "$TEMP_PROJECT"
    echo '{}' > "package.json"

    run detect_tech_stack "."
    assert_success

    [[ "$output" == *"nodejs"* ]]
}

# ============================================================
# Monorepo Detection Tests
# ============================================================

@test "detect_tech_stack_monorepo scans packages directory" {
    mkdir -p "$TEMP_PROJECT/packages/frontend"
    mkdir -p "$TEMP_PROJECT/packages/backend"
    echo '{}' > "$TEMP_PROJECT/packages/frontend/package.json"
    echo '[project]' > "$TEMP_PROJECT/packages/backend/pyproject.toml"

    run detect_tech_stack_monorepo "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
    [[ "$output" == *"python"* ]]
}

@test "detect_tech_stack_monorepo scans apps directory" {
    mkdir -p "$TEMP_PROJECT/apps/web"
    echo '{}' > "$TEMP_PROJECT/apps/web/package.json"
    echo '{}' > "$TEMP_PROJECT/apps/web/next.config.js"

    run detect_tech_stack_monorepo "$TEMP_PROJECT"
    assert_success

    [[ "$output" == *"nodejs"* ]]
    [[ "$output" == *"nextjs"* ]]
}

@test "detect_tech_stack_monorepo deduplicates results" {
    mkdir -p "$TEMP_PROJECT/packages/pkg1"
    mkdir -p "$TEMP_PROJECT/packages/pkg2"
    echo '{}' > "$TEMP_PROJECT/packages/pkg1/package.json"
    echo '{}' > "$TEMP_PROJECT/packages/pkg2/package.json"

    run detect_tech_stack_monorepo "$TEMP_PROJECT"
    assert_success

    # Count occurrences of nodejs - should be 1
    local count
    count=$(echo "$output" | grep -o "nodejs" | wc -l)
    [[ "$count" -eq 1 ]]
}

# ============================================================
# Section Mapping Tests
# ============================================================

@test "get_agents_sections_for_stack maps nodejs correctly" {
    run get_agents_sections_for_stack "nodejs"
    assert_success

    [[ "$output" == *"nodejs_toolchain"* ]]
}

@test "get_agents_sections_for_stack maps python correctly" {
    run get_agents_sections_for_stack "python"
    assert_success

    [[ "$output" == *"python_toolchain"* ]]
}

@test "get_agents_sections_for_stack maps docker correctly" {
    run get_agents_sections_for_stack "docker"
    assert_success

    [[ "$output" == *"docker_workflow"* ]]
}

@test "get_agents_sections_for_stack maps java correctly" {
    run get_agents_sections_for_stack "java"
    assert_success

    [[ "$output" == *"java_toolchain"* ]]
}

@test "get_agents_sections_for_stack deduplicates sections" {
    run get_agents_sections_for_stack "nodejs" "typescript"

    # Both map to nodejs_toolchain, should only appear once
    local count
    count=$(echo "$output" | grep -o "nodejs_toolchain" | wc -l)
    [[ "$count" -eq 1 ]]
}

@test "get_agents_sections_for_stack handles multiple stacks" {
    run get_agents_sections_for_stack "nodejs" "python" "docker"
    assert_success

    [[ "$output" == *"nodejs_toolchain"* ]]
    [[ "$output" == *"python_toolchain"* ]]
    [[ "$output" == *"docker_workflow"* ]]
}

# ============================================================
# Display Name Tests
# ============================================================

@test "get_tech_display_name returns correct name for nodejs" {
    run get_tech_display_name "nodejs"
    assert_success

    [[ "$output" == "Node.js" ]]
}

@test "get_tech_display_name returns correct name for typescript" {
    run get_tech_display_name "typescript"
    assert_success

    [[ "$output" == "TypeScript" ]]
}

@test "get_tech_display_name returns correct name for java" {
    run get_tech_display_name "java"
    assert_success

    [[ "$output" == "Java (Maven/Gradle)" ]]
}

@test "get_tech_display_name returns correct name for python-legacy" {
    run get_tech_display_name "python-legacy"
    assert_success

    [[ "$output" == "Python (legacy)" ]]
}

@test "get_tech_display_name returns input for unknown tech" {
    run get_tech_display_name "unknown-tech"
    assert_success

    [[ "$output" == "unknown-tech" ]]
}

# ============================================================
# Priority Tests
# ============================================================

@test "get_tech_priority returns 1 for primary languages" {
    run get_tech_priority "nodejs"
    [[ "$output" == "1" ]]

    run get_tech_priority "python"
    [[ "$output" == "1" ]]

    run get_tech_priority "rust"
    [[ "$output" == "1" ]]
}

@test "get_tech_priority returns 2 for frameworks" {
    run get_tech_priority "nextjs"
    [[ "$output" == "2" ]]

    run get_tech_priority "docker"
    [[ "$output" == "2" ]]
}

@test "get_tech_priority returns 3 for legacy/secondary" {
    run get_tech_priority "python-legacy"
    [[ "$output" == "3" ]]

    run get_tech_priority "make"
    [[ "$output" == "3" ]]
}

@test "sort_tech_by_priority orders correctly" {
    run sort_tech_by_priority "docker" "python-legacy" "nodejs"
    assert_success

    # nodejs (priority 1) should come before docker (priority 2)
    # docker (priority 2) should come before python-legacy (priority 3)
    local output_array=()
    read -r -a output_array <<< "$output"
    [[ "${output_array[0]}" == "nodejs" ]]
}

# ============================================================
# Summary Tests
# ============================================================

@test "get_detection_summary returns 'No tech stack detected' for empty" {
    run get_detection_summary
    assert_success

    [[ "$output" == "No tech stack detected" ]]
}

@test "get_detection_summary formats single tech correctly" {
    run get_detection_summary "nodejs"
    assert_success

    [[ "$output" == "Node.js" ]]
}

@test "get_detection_summary formats multiple techs with count" {
    run get_detection_summary "nodejs" "typescript" "docker"
    assert_success

    [[ "$output" == *"(3 technologies)"* ]]
}
