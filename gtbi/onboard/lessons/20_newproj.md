# Starting Projects with GTBI

**Goal:** Create new projects with full GTBI tooling using `gtbi newproj`.

---

## Why Use `gtbi newproj`?

When you create a project with `ntm spawn`, you get a tmux session with agents.
But agents work better when they have:

- **AGENTS.md** - Project-specific guidance for AI agents
- **Beads (br)** - Local issue tracking for planning and progress
- **Claude settings** - Project-specific Claude Code configuration
- **Proper .gitignore** - Ignores build artifacts, secrets, etc.

`gtbi newproj` sets all of this up automatically.

---

## Quick Start

### Interactive Mode (Recommended)

```bash
gtbi newproj --interactive
```

Or the short form:

```bash
gtbi newproj -i
```

This launches a TUI wizard that guides you through setup.

### CLI Mode

```bash
gtbi newproj myproject
```

Creates `/data/projects/myproject` with full tooling.

---

## What Gets Created

```
myproject/
├── .git/              # Git repository initialized
├── .beads/            # Local issue tracking
├── .claude/           # Claude Code settings
├── AGENTS.md          # Instructions for AI agents
└── .gitignore         # Standard ignores
```

---

## Custom Directory

By default, projects go to `/data/projects/<name>`.

Specify a different location:

```bash
gtbi newproj myproject ~/code
```

Creates `~/code/myproject`.

---

## Options

| Flag | Effect |
|------|--------|
| `--interactive` | TUI wizard (recommended for first use) |
| `--no-br` | Skip beads initialization |
| `--no-claude` | Skip Claude settings |
| `--no-agents` | Skip AGENTS.md creation |

---

## The Full Workflow

1. **Create project:**
   ```bash
   gtbi newproj myapp -i
   ```

2. **Spawn agents:**
   ```bash
   ntm spawn myapp --cc=2
   ```

3. **Attach and work:**
   ```bash
   ntm attach myapp
   ```

The key insight: `gtbi newproj` prepares the project, `ntm spawn` starts agents.

---

## AGENTS.md

This file tells agents how to work in your project:

```markdown
# Project: myapp

## Language/Framework
- TypeScript with Bun

## Commands
- `bun dev` - Start dev server
- `bun test` - Run tests

## Conventions
- Use functional components
- Tests in __tests__ directories
```

Agents read this file and follow its instructions!

---

## Beads Integration

Projects created with `gtbi newproj` include beads (br) for issue tracking:

```bash
# Create an issue
br create "Set up authentication"

# List issues
br list

# See ready work (unblocked issues)
br ready
```

This integrates with `bv` (Beads Viewer) for visualization and graph analysis.

---

## Try It Now

```bash
# Create a test project
gtbi newproj test-project -i

# Explore what was created
ls -la /data/projects/test-project
cat /data/projects/test-project/AGENTS.md

# Archive it when done, instead of deleting it
mv /data/projects/test-project /data/projects/test-project.archived.$(date +%Y%m%d_%H%M%S)
```

---

## Next

Ready to spawn agents in your new project:

```bash
onboard 5
```
