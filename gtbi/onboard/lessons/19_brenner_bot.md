# Brenner Bot: Research Orchestration for AI Agents

**Goal:** Use brenner_bot for structured research sessions with multi-agent AI workflows.

---

## What is Brenner Bot?

Brenner Bot is a research orchestration platform inspired by Nobel laureate Sydney Brenner's scientific methodology. It coordinates multi-agent AI research sessions with systematic problem formulation and rigorous constraint-based reasoning.

**Key Features:**
- Primary source corpus with stable citation anchors (§n format)
- Multi-model syntheses from Claude, GPT, and Gemini
- Searchable quote bank for pattern identification
- Multi-agent session management via Agent Mail
- Artifact compilation with 50+ validation rules

---

## Essential Commands

### System Health

```bash
# Check installation
brenner --version

# Run diagnostics
brenner doctor
```

### Corpus Search

```bash
# Search the transcript corpus
brenner corpus search "experimental design"

# Browse available sections
brenner corpus list
```

### Building Excerpts

```bash
# Compose cited passages from specific sections
brenner excerpt build --sections 42,43,44

# Export with citations
brenner excerpt build --sections 42-50 --format markdown
```

---

## Research Sessions

### Starting a Session

```bash
# Launch a multi-agent research workflow
brenner session start "hypothesis about X"

# Resume an existing session
brenner session resume <session_id>

# List active sessions
brenner session list
```

### Session Outputs

Research sessions produce structured artifacts:
- **Hypothesis slates**: Multiple competing explanations
- **Discriminative tests**: Experiments that distinguish hypotheses
- **Assumption ledgers**: Explicit premises with verification
- **Anomaly registers**: Unexplained observations
- **Adversarial critiques**: Challenges to the framing itself

---

## Integration with Flywheel

Brenner Bot coordinates with other tools:

| Tool | Integration |
|------|-------------|
| **Agent Mail** | Durable threads between agents in sessions |
| **NTM** | Spawns parallel agent sessions |
| **Beads** | Research tasks can become tracked issues |
| **CASS** | Session history is searchable |

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `brenner --version` | Check version |
| `brenner doctor` | Run diagnostics |
| `brenner corpus search "..."` | Search transcripts |
| `brenner corpus list` | List sections |
| `brenner excerpt build` | Build cited passages |
| `brenner session start` | Start research session |
| `brenner session list` | List active sessions |

---

## Research Methodology

Brenner Bot emphasizes:

1. **Problem Formulation**: Clear statement of what you're trying to understand
2. **Discriminative Design**: Experiments that distinguish between hypotheses
3. **Third Alternative**: Always consider "both hypotheses are wrong"
4. **Constraint-Based Reasoning**: What the data rules out, not just what it suggests
5. **Scale Physics**: Verify assumptions about orders of magnitude

---

## Web Interface

The web app at brennerbot.org provides:
- Corpus browsing with full-text search
- Excerpt composition from selected sections
- Session visualization

---

*Run `brenner session list` to see active research sessions!*
