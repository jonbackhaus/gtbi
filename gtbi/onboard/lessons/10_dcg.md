# DCG: Destructive Command Guard

**Goal:** Block dangerous commands before they execute.

---

## Why DCG Matters

AI agents sometimes propose destructive commands like hard resets or recursive deletes.
DCG stops those commands *before* they run and suggests safer alternatives.

---

## Essential Commands

### Test a Command

```bash
dcg test "git reset --hard" --explain
```

### Register the Hook

```bash
dcg install
```

### Check Health

```bash
dcg doctor
```

---

## Protection Packs

Enable only the packs you need:

```bash
# ~/.config/dcg/config.toml
[packs]
enabled = ["git", "filesystem", "database.postgresql"]
```

---

## Allow-Once Workflow

If you *must* run a blocked command:

```bash
dcg allow-once <code>
```

Use this sparingly and only when you understand the risk.

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `dcg test "<cmd>"` | Check if a command is dangerous |
| `dcg test "<cmd>" --explain` | Explain why it was blocked |
| `dcg packs` | List protection packs |
| `dcg install` | Register Claude Code hook |
| `dcg allow-once <code>` | Bypass a single command |
| `dcg doctor` | Health check |

---

## Integration with Other Tools

- **SLB**: Two-person rule after DCG pre-check
- **UBS**: Quality checks before commits
- **Mail**: Coordinate on safety decisions

---

## Congratulations!

You've completed the GTBI onboarding.

You now have:
- A fully configured development VPS
- Three powerful coding agents
- A complete coordination toolstack
- The knowledge to use it all

**Go build something amazing!**

---

*Run `gtbi doctor` to verify your setup, then start your first project with `cc`!*
