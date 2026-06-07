# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Git Workflow

**MANDATORY:** Never commit directly to `main`. All work goes on a feature branch.

- **Feature branches**: `git checkout -b fix/<topic>` or `feat/<topic>` before any code changes
- **Worktrees for sub-agents**: Use `git worktree add` to give each sub-agent an isolated copy of the repo — prevents concurrent edits from colliding on the same working tree
- **Commit often**: Small, atomic commits are easier to bisect and revert; don't batch unrelated changes
- **Push when complete**: Work is not done until `git push` succeeds (see Session Completion above)

```bash
# Start work
git checkout -b fix/<topic>

# Isolated sub-agent worktree
git worktree add /tmp/gtbi-<topic> -b fix/<topic>-agent

# Commit often, push at end
git add <files> && git commit -m "..."
git push -u origin fix/<topic>
```

## Build & Test

```bash
# Generate scripts after any manifest or lib change
export PATH="$HOME/.bun/bin:$PATH"
bun run --cwd packages/manifest generate

# Run Docker integration test (Ubuntu 25.10 greenfield install)
./tests/docker/run.sh install

# Test artifacts written to:
# tests/artifacts/install.log
```

## Architecture Overview

- `gtbi.manifest.yaml` — single source of truth: all install modules, phases, checksums
- `packages/manifest/` — TypeScript generator; `bun run generate` compiles manifest → shell scripts
- `scripts/generated/` — **do not edit directly**; always edit manifest and regenerate
- `scripts/lib/` — shared shell helpers (`install_helpers.sh`, `state.sh`, `security.sh`, etc.)
- `install.sh` — top-level orchestrator; calls generated phase scripts
- `checksums.yaml` — SHA256 of every external installer (uv, dolt, claude, bun, …)
- `tests/docker/` — hermetic Docker integration tests

## Conventions & Patterns

- **Manifest → generate → scripts**: Any change to `gtbi.manifest.yaml` or `scripts/lib/*.sh` requires `bun run generate` before committing. Generated files live in `scripts/generated/` and `apps/web/lib/generated/`.
- **Checksums must stay fresh**: If an external installer URL serves new content, update `checksums.yaml` and rerun generate to update `internal_checksums.sh`.
- **`run_as` in manifest**: `target_user` runs as the ubuntu user; `root` runs as root. Installers that require root (e.g. dolt) must use `run_as: root`.
- **Docker-safe installs**: Avoid bare `systemctl enable/start` — use `|| true`; no systemd in Docker.
