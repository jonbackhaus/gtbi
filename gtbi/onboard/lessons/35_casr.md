# Lesson 35: Cross-Agent Session Resumption with CASR

skills:
  - casr
  - multi-agent
  - session-management

---

# What is CASR?

Ever started a task with Claude, hit a rate limit, and wanted to continue with Gemini without losing context? CASR handles that.

**CASR (Cross-Agent Session Resumer)** captures session state from one AI coding agent and generates a structured handoff prompt for another. It preserves file context, conversation history, and task progress across provider boundaries.

---

# Checking Installation

Verify CASR is installed:

```bash
casr --help
```

---

# Listing Available Providers

See which AI agents CASR can hand off between:

```bash
casr providers
```

This shows supported agents (Claude Code, Codex CLI, Gemini CLI) and their session formats.

---

# Creating a Handoff

When you need to switch agents mid-task:

```bash
casr capture --from claude-code --session-dir .
```

This captures the current session state and generates a resume prompt.

---

# Why CASR Matters for Agents

In multi-agent workflows, rate limits and context windows force agent switches. CASR ensures:

- No lost context when switching providers
- Task continuity across Claude, Codex, and Gemini
- Structured handoff prompts that preserve intent
- Reduced ramp-up time for the receiving agent

---

# Common Scenarios

```bash
# Capture current Claude session for Gemini handoff
casr capture --from claude-code

# Resume a captured session in Codex
casr resume --to codex-cli --session latest

# List recent session captures
casr list
```

---

# Summary

You've learned:
1. **casr providers** - List supported agents
2. **casr capture** - Save session state for handoff
3. **casr resume** - Continue work in a different agent
4. How cross-agent handoffs maintain task continuity
