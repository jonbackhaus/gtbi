# beads_rust (br)

Rust issue tracker with graph-aware dependencies for AI-assisted development workflows.

## What It Does

`br` (beads_rust) is a local-first issue tracker designed for AI coding agents. It manages tasks as "beads" with:
- Hierarchical parent-child relationships
- Dependency tracking (blocks/blocked-by)
- Priority scoring (P1-P5)
- Status lifecycle (open → in_progress → closed)
- JSONL persistence for version control compatibility

## Installation Verification

```bash
# Check br is installed
br --version

# Verify beads database works
br list --json 2>/dev/null
```

Expected output: version number and JSON array of beads (or empty array).

## Basic Usage

### List Beads

```bash
# List all open beads
br list

# List with specific status
br list --status open
br list --status in_progress

# JSON output for scripting
br list --json
```

### Show Bead Details

```bash
# Show a specific bead
br show bd-1abc

# Show with full description
br show bd-1abc --full
```

### Create Beads

```bash
# Create a new bead
br add "Fix authentication bug" --priority P2 --labels bug,auth

# Create as child of existing bead
br add "Write unit tests" --parent bd-1abc
```

### Update Beads

```bash
# Start working on a bead
br update bd-1abc --status in_progress

# Close a bead
br update bd-1abc --status closed

# Claim ownership
br update bd-1abc --owner "LavenderGate"
```

### Dependencies

```bash
# Add dependency (bd-1abc blocks bd-2def)
br link bd-1abc --blocks bd-2def

# View dependency graph
br graph
```

## Common Workflows

### Agent Task Selection

Use `bv` (beads viewer) for intelligent triage:

```bash
# Robot-friendly triage recommendations
bv --robot-triage

# Interactive TUI
bv  # human-only interactive TUI; agents avoid bare bv
```

### Sync with Git

Beads are stored in `.beads/issues.jsonl`:

```bash
# After making changes
git add .beads/issues.jsonl
git commit -m "Update beads: close bd-1abc"
```

### Filter by Labels

```bash
# Find documentation tasks
br list --labels docs

# Find high-priority bugs
br list --labels bug --priority P1
```

## Troubleshooting

### "No beads database found"

Initialize the beads directory:

```bash
mkdir -p .beads
touch .beads/issues.jsonl
```

### "Invalid bead ID"

Bead IDs follow the format `bd-XXXX` where XXXX is a base-36 identifier:

```bash
# Valid: bd-1abc, bd-2def
# Invalid: 1abc, bead-123
```

### Large JSONL File

The issues.jsonl file can grow large. Use JSON streaming tools:

```bash
# Count beads
wc -l .beads/issues.jsonl

# Search for specific bead
grep "bd-1abc" .beads/issues.jsonl | jq .
```

## Integration with AI Agents

Agents should:
1. Check `bv --robot-triage` for task recommendations
2. Claim beads before starting work (`br update ID --status in_progress --owner "AgentName"`)
3. Close beads when complete (`br update ID --status closed`)
4. Communicate via Agent Mail when coordinating on related beads

## Related Tools

- `bv` - Beads Viewer TUI for interactive task management
- `am` - Agent Mail for multi-agent coordination
- `gtbi doctor` - Verifies br installation
