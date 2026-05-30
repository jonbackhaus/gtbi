#!/usr/bin/env bash
# ============================================================
# GTBI newproj TUI Wizard - Tech Stack Detection
# Automatically detects project tech stack from config files
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_GTBI_NEWPROJ_DETECT_SH_LOADED:-}" ]]; then
    return 0
fi
_GTBI_NEWPROJ_DETECT_SH_LOADED=1

# ============================================================
# Tech Stack Detection
# ============================================================

# Detect project tech stack by scanning for config files
# Usage: detected=($(detect_tech_stack "/path/to/project"))
# Returns: space-separated list of detected technologies
detect_tech_stack() {
    local dir="${1:-.}"
    local detected=()

    # Resolve to absolute path
    if ! dir="$(cd "$dir" 2>/dev/null && pwd)"; then
        log_error "Cannot access directory: $dir" 2>/dev/null || true
        return 1
    fi

    # Check if directory is readable
    if [[ ! -r "$dir" ]]; then
        log_warn "Cannot read directory: $dir" 2>/dev/null || true
        return 1
    fi

    log_debug "Scanning for tech stack in: $dir" 2>/dev/null || true

    # ========================================
    # Primary Language/Runtime Detection
    # ========================================

    # Node.js / JavaScript
    if [[ -f "$dir/package.json" ]]; then
        detected+=("nodejs")
        log_tech_detect "nodejs" "package.json" "high" 2>/dev/null || true
    fi

    # TypeScript
    if [[ -f "$dir/tsconfig.json" ]]; then
        detected+=("typescript")
        log_tech_detect "typescript" "tsconfig.json" "high" 2>/dev/null || true
    fi

    # Python (modern)
    if [[ -f "$dir/pyproject.toml" ]]; then
        detected+=("python")
        log_tech_detect "python" "pyproject.toml" "high" 2>/dev/null || true
    # Python (legacy) - only if no pyproject.toml
    elif [[ -f "$dir/requirements.txt" ]]; then
        detected+=("python-legacy")
        log_tech_detect "python-legacy" "requirements.txt" "medium" 2>/dev/null || true
    fi

    # Rust
    if [[ -f "$dir/Cargo.toml" ]]; then
        detected+=("rust")
        log_tech_detect "rust" "Cargo.toml" "high" 2>/dev/null || true
    fi

    # Go
    if [[ -f "$dir/go.mod" ]]; then
        detected+=("go")
        log_tech_detect "go" "go.mod" "high" 2>/dev/null || true
    fi

    # Ruby
    if [[ -f "$dir/Gemfile" ]]; then
        detected+=("ruby")
        log_tech_detect "ruby" "Gemfile" "high" 2>/dev/null || true
    fi

    # Java/Maven
    if [[ -f "$dir/pom.xml" ]]; then
        detected+=("java-maven")
        log_tech_detect "java-maven" "pom.xml" "high" 2>/dev/null || true
    fi

    # Java/Gradle
    if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]]; then
        detected+=("java-gradle")
        local gradle_file="build.gradle"
        [[ -f "$dir/build.gradle.kts" ]] && gradle_file="build.gradle.kts"
        log_tech_detect "java-gradle" "$gradle_file" "high" 2>/dev/null || true
    fi

    # PHP
    if [[ -f "$dir/composer.json" ]]; then
        detected+=("php")
        log_tech_detect "php" "composer.json" "high" 2>/dev/null || true
    fi

    # Elixir
    if [[ -f "$dir/mix.exs" ]]; then
        detected+=("elixir")
        log_tech_detect "elixir" "mix.exs" "high" 2>/dev/null || true
    fi

    # ========================================
    # Framework Detection (secondary)
    # ========================================

    # Next.js
    if [[ -d "$dir/.next" || -f "$dir/next.config.js" || -f "$dir/next.config.mjs" || -f "$dir/next.config.ts" ]]; then
        detected+=("nextjs")
        local next_indicator=".next"
        [[ -f "$dir/next.config.js" ]] && next_indicator="next.config.js"
        [[ -f "$dir/next.config.mjs" ]] && next_indicator="next.config.mjs"
        [[ -f "$dir/next.config.ts" ]] && next_indicator="next.config.ts"
        log_tech_detect "nextjs" "$next_indicator" "high" 2>/dev/null || true
    fi

    # Nuxt.js
    if [[ -f "$dir/nuxt.config.js" || -f "$dir/nuxt.config.ts" ]]; then
        detected+=("nuxt")
        local nuxt_file="nuxt.config.js"
        [[ -f "$dir/nuxt.config.ts" ]] && nuxt_file="nuxt.config.ts"
        log_tech_detect "nuxt" "$nuxt_file" "high" 2>/dev/null || true
    fi

    # SvelteKit
    if [[ -f "$dir/svelte.config.js" ]]; then
        detected+=("svelte")
        log_tech_detect "svelte" "svelte.config.js" "high" 2>/dev/null || true
    fi

    # Astro
    if [[ -f "$dir/astro.config.mjs" || -f "$dir/astro.config.ts" ]]; then
        detected+=("astro")
        local astro_file="astro.config.mjs"
        [[ -f "$dir/astro.config.ts" ]] && astro_file="astro.config.ts"
        log_tech_detect "astro" "$astro_file" "high" 2>/dev/null || true
    fi

    # Remix
    if [[ -f "$dir/remix.config.js" ]]; then
        detected+=("remix")
        log_tech_detect "remix" "remix.config.js" "high" 2>/dev/null || true
    fi

    # Vite
    if [[ -f "$dir/vite.config.js" || -f "$dir/vite.config.ts" ]]; then
        detected+=("vite")
        local vite_file="vite.config.js"
        [[ -f "$dir/vite.config.ts" ]] && vite_file="vite.config.ts"
        log_tech_detect "vite" "$vite_file" "medium" 2>/dev/null || true
    fi

    # ========================================
    # Build Tools / Infrastructure
    # ========================================

    # Make
    if [[ -f "$dir/Makefile" || -f "$dir/makefile" || -f "$dir/GNUmakefile" ]]; then
        detected+=("make")
        log_tech_detect "make" "Makefile" "medium" 2>/dev/null || true
    fi

    # CMake
    if [[ -f "$dir/CMakeLists.txt" ]]; then
        detected+=("cmake")
        log_tech_detect "cmake" "CMakeLists.txt" "high" 2>/dev/null || true
    fi

    # Docker
    if [[ -f "$dir/Dockerfile" ]]; then
        detected+=("docker")
        log_tech_detect "docker" "Dockerfile" "high" 2>/dev/null || true
    fi

    # Docker Compose
    if [[ -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" || -f "$dir/compose.yml" || -f "$dir/compose.yaml" ]]; then
        detected+=("docker-compose")
        local compose_file="docker-compose.yml"
        [[ -f "$dir/docker-compose.yaml" ]] && compose_file="docker-compose.yaml"
        [[ -f "$dir/compose.yml" ]] && compose_file="compose.yml"
        [[ -f "$dir/compose.yaml" ]] && compose_file="compose.yaml"
        log_tech_detect "docker-compose" "$compose_file" "high" 2>/dev/null || true
    fi

    # Terraform
    if [[ -f "$dir/main.tf" || -f "$dir/terraform.tf" ]]; then
        detected+=("terraform")
        log_tech_detect "terraform" "*.tf" "high" 2>/dev/null || true
    fi

    # ========================================
    # Return Results
    # ========================================

    if [[ ${#detected[@]} -eq 0 ]]; then
        log_info "No tech stack detected in: $dir" 2>/dev/null || true
    else
        log_info "Detected tech stack: ${detected[*]}" 2>/dev/null || true
    fi

    echo "${detected[@]}"
}

# ============================================================
# Monorepo Detection
# ============================================================

# Detect tech stack in monorepo (checks one level deep)
# Usage: detected=($(detect_tech_stack_monorepo "/path/to/monorepo"))
detect_tech_stack_monorepo() {
    local dir="${1:-.}"
    local detected=()
    local seen=()

    # Resolve to absolute path
    if ! dir="$(cd "$dir" 2>/dev/null && pwd)"; then
        return 1
    fi

    log_debug "Scanning monorepo for tech stack: $dir" 2>/dev/null || true

    # Check root level first
    local root_stack
    root_stack=$(detect_tech_stack "$dir")
    for tech in $root_stack; do
        if [[ " ${seen[*]} " != *" ${tech} "* ]]; then
            detected+=("$tech")
            seen+=("$tech")
        fi
    done

    # Check common monorepo patterns
    local subdirs=()

    # packages/* pattern (npm workspaces, lerna)
    if [[ -d "$dir/packages" ]]; then
        for subdir in "$dir"/packages/*/; do
            [[ -d "$subdir" ]] && subdirs+=("$subdir")
        done
    fi

    # apps/* pattern (turborepo, nx)
    if [[ -d "$dir/apps" ]]; then
        for subdir in "$dir"/apps/*/; do
            [[ -d "$subdir" ]] && subdirs+=("$subdir")
        done
    fi

    # services/* pattern (microservices)
    if [[ -d "$dir/services" ]]; then
        for subdir in "$dir"/services/*/; do
            [[ -d "$subdir" ]] && subdirs+=("$subdir")
        done
    fi

    # libs/* pattern (nx)
    if [[ -d "$dir/libs" ]]; then
        for subdir in "$dir"/libs/*/; do
            [[ -d "$subdir" ]] && subdirs+=("$subdir")
        done
    fi

    # Scan subdirectories
    for subdir in "${subdirs[@]}"; do
        local sub_stack
        sub_stack=$(detect_tech_stack "$subdir")
        for tech in $sub_stack; do
            if [[ " ${seen[*]} " != *" ${tech} "* ]]; then
                detected+=("$tech")
                seen+=("$tech")
            fi
        done
    done

    echo "${detected[@]}"
}

# ============================================================
# AGENTS.md Section Mapping
# ============================================================

# Map detected tech stack to AGENTS.md sections
# Usage: sections=$(get_agents_sections_for_stack nodejs typescript docker)
get_agents_sections_for_stack() {
    local stack=("$@")
    local sections=()
    local seen=()

    for tech in "${stack[@]}"; do
        local section=""
        case "$tech" in
            nodejs|typescript)
                section="nodejs_toolchain"
                ;;
            python|python-legacy)
                section="python_toolchain"
                ;;
            rust)
                section="rust_toolchain"
                ;;
            go)
                section="go_toolchain"
                ;;
            ruby)
                section="ruby_toolchain"
                ;;
            java|java-maven|java-gradle)
                section="java_toolchain"
                ;;
            php)
                section="php_toolchain"
                ;;
            elixir)
                section="elixir_toolchain"
                ;;
            nextjs)
                section="nextjs_framework"
                ;;
            nuxt)
                section="nuxt_framework"
                ;;
            svelte)
                section="svelte_framework"
                ;;
            astro)
                section="astro_framework"
                ;;
            remix)
                section="remix_framework"
                ;;
            vite)
                section="vite_build"
                ;;
            docker|docker-compose)
                section="docker_workflow"
                ;;
            make|cmake)
                section="build_system"
                ;;
            terraform)
                section="infrastructure"
                ;;
        esac

        # Add section if not already seen
        if [[ -n "$section" ]] && [[ " ${seen[*]} " != *" ${section} "* ]]; then
            sections+=("$section")
            seen+=("$section")
        fi
    done

    echo "${sections[@]}"
}

# ============================================================
# Tech Stack Display Names
# ============================================================

# Get human-readable name for a tech stack item
# Usage: name=$(get_tech_display_name "nodejs")
get_tech_display_name() {
    local tech="$1"
    case "$tech" in
        nodejs) echo "Node.js" ;;
        typescript) echo "TypeScript" ;;
        python) echo "Python (modern)" ;;
        python-legacy) echo "Python (legacy)" ;;
        rust) echo "Rust" ;;
        go) echo "Go" ;;
        ruby) echo "Ruby" ;;
        java) echo "Java (Maven/Gradle)" ;;
        java-maven) echo "Java (Maven)" ;;
        java-gradle) echo "Java (Gradle)" ;;
        php) echo "PHP" ;;
        elixir) echo "Elixir" ;;
        nextjs) echo "Next.js" ;;
        nuxt) echo "Nuxt.js" ;;
        svelte) echo "SvelteKit" ;;
        astro) echo "Astro" ;;
        remix) echo "Remix" ;;
        vite) echo "Vite" ;;
        docker) echo "Docker" ;;
        docker-compose) echo "Docker Compose" ;;
        make) echo "Make" ;;
        cmake) echo "CMake" ;;
        terraform) echo "Terraform" ;;
        *) echo "$tech" ;;
    esac
}

# Get all detected tech as display strings
# Usage: display_list=$(get_tech_display_list nodejs typescript)
get_tech_display_list() {
    local stack=("$@")
    local display=()

    for tech in "${stack[@]}"; do
        display+=("$(get_tech_display_name "$tech")")
    done

    # Join with commas
    local IFS=', '
    echo "${display[*]}"
}

# ============================================================
# Stack Priority
# ============================================================

# Get priority level for a tech stack item
# Returns: 1=primary, 2=framework/tool, 3=legacy
get_tech_priority() {
    local tech="$1"
    case "$tech" in
        nodejs|python|rust|go|ruby|java|java-maven|java-gradle|php|elixir)
            echo "1"
            ;;
        typescript|nextjs|nuxt|svelte|astro|remix|docker|cmake|terraform)
            echo "2"
            ;;
        python-legacy|make|vite|docker-compose)
            echo "3"
            ;;
        *)
            echo "2"
            ;;
    esac
}

# Sort tech stack by priority (primary first)
# Usage: sorted=$(sort_tech_by_priority nodejs docker python-legacy typescript)
sort_tech_by_priority() {
    local stack=("$@")
    local primary=()
    local secondary=()
    local tertiary=()

    for tech in "${stack[@]}"; do
        local priority
        priority=$(get_tech_priority "$tech")
        case "$priority" in
            1) primary+=("$tech") ;;
            2) secondary+=("$tech") ;;
            3) tertiary+=("$tech") ;;
        esac
    done

    echo "${primary[*]} ${secondary[*]} ${tertiary[*]}"
}

# ============================================================
# Detection Summary
# ============================================================

# Generate a summary of detected tech stack for display
# Usage: summary=$(get_detection_summary nodejs typescript docker)
get_detection_summary() {
    local stack=("$@")

    if [[ ${#stack[@]} -eq 0 ]]; then
        echo "No tech stack detected"
        return
    fi

    local sorted
    sorted=$(sort_tech_by_priority "${stack[@]}")

    local display
    local -a sorted_array=()
    read -ra sorted_array <<< "$sorted"
    display=$(get_tech_display_list "${sorted_array[@]}")

    local count=${#stack[@]}
    if [[ $count -eq 1 ]]; then
        echo "$display"
    else
        echo "$display ($count technologies)"
    fi
}
