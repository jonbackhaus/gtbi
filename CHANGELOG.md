# Changelog

All notable changes to the [Agentic Coding Flywheel Setup (GTBI)](https://github.com/jonbackhaus/gtbi) project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each version links to its GitHub Release (where one exists) or to the tag comparison. Representative commits are linked for traceability.

---

## [v0.2.0](https://github.com/jonbackhaus/gtbi/releases/tag/v0.2.0) -- 2026-06-12

> Major expansion of the flywheel tool ecosystem, installer reliability, web application, and testing infrastructure since v0.1.0. [Compare with v0.1.0](https://github.com/jonbackhaus/gtbi/compare/v0.1.0...v0.2.0).

### Flywheel Tools

- **Destructive Command Guard (DCG)** -- Rust-based Claude Code `PreToolUse` hook that blocks dangerous git/fs commands with sub-millisecond latency; replaces the Python `git_safety_guard` ([`b770c9f`](https://github.com/jonbackhaus/gtbi/commit/b770c9fa))
- **Repo Updater (RU)** -- multi-repo sync with AI-driven commit automation ([`b770c9f`](https://github.com/jonbackhaus/gtbi/commit/b770c9fa))
- **giil** -- downloads cloud-hosted images for visual debugging in SSH/headless environments ([`b770c9f`](https://github.com/jonbackhaus/gtbi/commit/b770c9fa))
- **csctf** -- converts AI chat share links to Markdown/HTML archives ([`b770c9f`](https://github.com/jonbackhaus/gtbi/commit/b770c9fa))
- **APR, JFP, SRPS, Meta Skill (MS)** -- additional flywheel utilities ([`2ad1fe9`](https://github.com/jonbackhaus/gtbi/commit/2ad1fe96))
- **WezTerm Automata (WA), Brenner Bot** -- terminal automation and bot tooling with full lesson and test coverage ([`f746315`](https://github.com/jonbackhaus/gtbi/commit/f7463155))

### Installer & CLI

- **`gtbi services`** -- unified start/stop/restart for all GTBI background services ([`2d48c4b`](https://github.com/jonbackhaus/gtbi/commit/2d48c4b1))
- **`--only` and `--only-phase` flags** for selective tool or phase installation ([`da096a7`](https://github.com/jonbackhaus/gtbi/commit/da096a7c))
- **Verified installer framework** -- `install_asset_from_path` helper with SHA256 gating; 13 additional tool installers added ([`bcd4734`](https://github.com/jonbackhaus/gtbi/commit/bcd47348))
- **Autofix system** -- pre-flight warning detection and crash-safe change recording/undo ([`654c2d4`](https://github.com/jonbackhaus/gtbi/commit/654c2d43), [`8d28a12`](https://github.com/jonbackhaus/gtbi/commit/8d28a12d))
- **`--pin-ref` flag** for reproducible pinned installations ([`2cd7c72`](https://github.com/jonbackhaus/gtbi/commit/2cd7c72b))
- **GTBI self-update** as first operation in `gtbi update` ([`97f15b5`](https://github.com/jonbackhaus/gtbi/commit/97f15b56))
- **`loginctl enable-linger`** so user services survive SSH disconnects ([`fff5933`](https://github.com/jonbackhaus/gtbi/commit/fff59332))
- **Shell completions** for bash and zsh ([`f511fb6`](https://github.com/jonbackhaus/gtbi/commit/f511fb68))
- Curl timeouts, atomic file writes, batch cargo installs, and subprocess reduction throughout ([`46a1bb9`](https://github.com/jonbackhaus/gtbi/commit/46a1bb9c))

### Agent Mail

- **Systemd-managed service** replacing tmux-spawn; `LimitNOFILE=65536`, `Restart=always`, backend auto-detection ([`17d2fd4`](https://github.com/jonbackhaus/gtbi/commit/17d2fd47))
- Switched from Python to Rust binary installer ([`e9cdfb1`](https://github.com/jonbackhaus/gtbi/commit/e9cdfb1e))

### Web Application

- **Complete Guide rewrite** with narrative-post style and interactive visualizations ([`700b2c2`](https://github.com/jonbackhaus/gtbi/commit/700b2c20))
- **Core Flywheel page** (`/core-flywheel`) with 4 interactive visualizations and OG share images ([`478c56f`](https://github.com/jonbackhaus/gtbi/commit/478c56f6))
- **15+ lesson components** covering RCH, WezTerm, Brenner, GIIL, S2P, and utility tools ([`fd30a07`](https://github.com/jonbackhaus/gtbi/commit/fd30a07a))
- **Persistent wizard state** -- VPS checklist survives page reloads ([`df5b451`](https://github.com/jonbackhaus/gtbi/commit/df5b4515))
- **Personalized command builder panel** with pinned ref toggle ([`efd6338`](https://github.com/jonbackhaus/gtbi/commit/efd63384))
- **Dynamic OG/Twitter share images** across all sections ([`b720937`](https://github.com/jonbackhaus/gtbi/commit/b7209374))
- **Dark/light/system theme toggle** ([`5f19854`](https://github.com/jonbackhaus/gtbi/commit/5f198546))
- **Accessibility overhaul** -- focus states, ARIA labels, reduced motion, touch targets ([`f302394`](https://github.com/jonbackhaus/gtbi/commit/f3023941))
- **TanStack Query** for user preference hooks; Zod 4 migration ([`9bed651`](https://github.com/jonbackhaus/gtbi/commit/9bed6515))
- **Manifest-driven web generation** -- web metadata consumed directly from manifest ([`f20c6d2`](https://github.com/jonbackhaus/gtbi/commit/f20c6d2f))

### Shell & Onboarding

- **TUI project creation wizard** (`newproj --interactive`) -- 9-screen flow with smart AGENTS.md generation ([`540102a`](https://github.com/jonbackhaus/gtbi/commit/540102a2))
- **Dynamic lesson discovery** in onboard TUI; sparse lesson numbers supported ([`df66cea`](https://github.com/jonbackhaus/gtbi/commit/df66cea3))
- **6 new Oh-My-Zsh plugins**: python, pip, tmux, tmuxinator, systemd, rsync ([`387c825`](https://github.com/jonbackhaus/gtbi/commit/387c825d))
- **`fd` alias no longer shadows `find`**; `gmi` converted to auto-update+patch function ([`0b09aef`](https://github.com/jonbackhaus/gtbi/commit/0b09aef1))

### Doctor & Diagnostics

- **`gtbi doctor --fix` and `--dry-run`** for automatic remediation ([`c6238fa`](https://github.com/jonbackhaus/gtbi/commit/c6238fa0))
- **`gtbi status`** one-line health summary ([`9d13efcb`](https://github.com/jonbackhaus/gtbi/commit/9d13efcb))
- **`gtbi support-bundle`** diagnostic collection with redaction rules ([`77da131`](https://github.com/jonbackhaus/gtbi/commit/77da131e))
- Network health checks in `--deep` mode; per-module fix suggestions ([`bf772ea`](https://github.com/jonbackhaus/gtbi/commit/bf772ea0))

### Security & Manifest

- **Critical fix: command injection in `validate_directory()`** -- `eval echo "$dir"` replaced with safe pattern matching ([`6c6e899`](https://github.com/jonbackhaus/gtbi/commit/6c6e8996))
- **Internal script integrity verification** at install time ([`3fb952a`](https://github.com/jonbackhaus/gtbi/commit/3fb952ad))
- **`KNOWN_INSTALLERS` URLs synced from `checksums.yaml`** at load time ([`9c0b631`](https://github.com/jonbackhaus/gtbi/commit/9c0b6311))
- **Composite pre-commit hook** preventing manifest drift ([`513758a`](https://github.com/jonbackhaus/gtbi/commit/513758a7))
- **GitHub Actions hardened** against script injection and race conditions ([`3312d8b`](https://github.com/jonbackhaus/gtbi/commit/3312d8b9))

### Testing & CI

- **284 unit tests** via bats-core; **53 E2E tests** for `newproj` TUI ([`04f740e`](https://github.com/jonbackhaus/gtbi/commit/04f740ed), [`a28ebd1`](https://github.com/jonbackhaus/gtbi/commit/a28ebd13))
- **Playwright E2E** and functional smoke tests for flywheel tools ([`4e341c0`](https://github.com/jonbackhaus/gtbi/commit/4e341c07))
- **Strict canary + release checksum gate** CI workflow ([`15540a7`](https://github.com/jonbackhaus/gtbi/commit/15540a7d))
- Pipefail and TTY safety linters; POSIX-correct grep patterns throughout ([`b09a6fa`](https://github.com/jonbackhaus/gtbi/commit/b09a6fab))

### Infrastructure

- **Systemd timer** for daily unattended `gtbi-update` ([`18c52d8`](https://github.com/jonbackhaus/gtbi/commit/18c52d8d))
- **ntfy.sh push notifications** for agent task lifecycle ([`32c718e`](https://github.com/jonbackhaus/gtbi/commit/32c718e4))
- **Automated manifest drift detection** with auto-fix script ([`1e34eb6`](https://github.com/jonbackhaus/gtbi/commit/1e34eb69))
- MIT + OpenAI/Anthropic Rider license adopted ([`a6b3bbe`](https://github.com/jonbackhaus/gtbi/commit/a6b3bbe0))

---

## [v0.1.0](https://github.com/jonbackhaus/gtbi/releases/tag/v0.1.0) -- 2026-01-03

> Initial public release. 1,572 commits of foundational development.

### Core Infrastructure

- **One-liner installer** (`curl | bash`) that transforms a fresh Ubuntu VPS into a fully-configured agentic coding environment in ~30 minutes ([`aaf0a58`](https://github.com/jonbackhaus/gtbi/commit/aaf0a587))
- **Idempotent execution** -- interrupted installs resume automatically from the last completed phase
- **Manifest-driven architecture** -- `gtbi.manifest.yaml` as single source of truth with TypeScript parser (Zod) and code generation ([`31a5923`](https://github.com/jonbackhaus/gtbi/commit/31a59233), [`142eaff`](https://github.com/jonbackhaus/gtbi/commit/142eaff0))
- **Security verification** -- SHA256 checksum verification for all upstream installers with fail-closed semantics ([`bc41158`](https://github.com/jonbackhaus/gtbi/commit/bc41158b), [`9dba55f`](https://github.com/jonbackhaus/gtbi/commit/9dba55fc))

### Agent System

- **Three-tier agent support**: Claude Code, Codex CLI, and Gemini CLI ([`865d6e5`](https://github.com/jonbackhaus/gtbi/commit/865d6e5c))
- **Named Tmux Manager (NTM)** -- agent cockpit for managing coding sessions
- **Unified Session Search (CASS)** -- search across all agent session history
- **Procedural Memory (CM)** -- persistent context system for agents
- **Auth Switching (CAAM)** -- instant switching between API keys
- **Security Guardrails (SLB)** -- two-person rule enforcement for dangerous commands

### Shell Environment

- Modern shell setup: zsh + oh-my-zsh + powerlevel10k theme
- All language runtimes: bun, uv/Python, Rust, Go
- Cloud CLIs: Vault, Wrangler, Supabase, Vercel
- 20+ developer tools (ripgrep, fd, bat, delta, gh, etc.)
- Optimized tmux configuration with Catppuccin theme and vim-style copy mode

### Web Application

- **Wizard website** at [agent-flywheel.com](https://agent-flywheel.com) built with Next.js 16 + bun workspaces ([`2b320e0`](https://github.com/jonbackhaus/gtbi/commit/2b320e05))
- 10-step interactive wizard guiding beginners from laptop to running AI agents ([`6c0bbe3`](https://github.com/jonbackhaus/gtbi/commit/6c0bbe30) through [`aa9f043`](https://github.com/jonbackhaus/gtbi/commit/aa9f043a))
- Jargon tooltip component (desktop hover, mobile bottom sheet)
- CommandCard component with copy and checkbox state ([`fba5969`](https://github.com/jonbackhaus/gtbi/commit/fba59691))
- Stepper navigation component ([`33c3714`](https://github.com/jonbackhaus/gtbi/commit/33c37149))

### Diagnostics & Updates

- **`gtbi doctor`** -- self-healing diagnostic system with `--json` output ([`2fca17d`](https://github.com/jonbackhaus/gtbi/commit/2fca17de))
- **`gtbi update`** -- component update command ([`e6d310b`](https://github.com/jonbackhaus/gtbi/commit/e6d310bc))
- **Interactive onboarding TUI** with gum support and progress tracking ([`d96659e`](https://github.com/jonbackhaus/gtbi/commit/d96659ec))

### Installer Libraries

- Modular library scripts: `cli_tools.sh`, `languages.sh`, `agents.sh`, `stack.sh`, `cloud_db.sh` ([`43f59f0`](https://github.com/jonbackhaus/gtbi/commit/43f59f0b), [`d779651`](https://github.com/jonbackhaus/gtbi/commit/d7796510), [`865d6e5`](https://github.com/jonbackhaus/gtbi/commit/865d6e5c), [`f40adca`](https://github.com/jonbackhaus/gtbi/commit/f40adca1), [`7b14fbd`](https://github.com/jonbackhaus/gtbi/commit/7b14fbde))
- Cloud/database phase with Vault, Wrangler, Supabase CLI ([`47d6138`](https://github.com/jonbackhaus/gtbi/commit/47d61386))
- VPS provider setup guides for OVH, Contabo, Hetzner ([`8c725ed`](https://github.com/jonbackhaus/gtbi/commit/8c725edc))

### CI/CD

- Installer CI workflow with doctor integration ([`4664d79`](https://github.com/jonbackhaus/gtbi/commit/4664d79b))
- Docker integration test script ([`c0873bd`](https://github.com/jonbackhaus/gtbi/commit/c0873bdb))
- Fail-fast remote `curl|bash` subshells ([`fd677f7`](https://github.com/jonbackhaus/gtbi/commit/fd677f7a))
