# Lesson 11: Local Skill Management with ms

skills:
  - ms
  - agents
  - mcp

---

# What are Skills?

AI agents like Claude Code are powerful, but they don't know your specific project conventions or unique workflows out of the box.

**Skills** are reusable prompt templates that give agents new capabilities. They are like "plugins" for your AI.

We use **meta_skill (ms)** to manage these skills locally. It's a local-first knowledge management tool with hybrid semantic search (BM25 + hash embeddings) and Git-backed audit trails. Your skills live in your project repo, not in the cloud.

---

# Checking Installation

First, let's make sure `ms` is installed and healthy.

Run the version check:

```bash
ms --version
```

Then run the doctor check to verify everything is configured correctly:

```bash
ms doctor
```

---

# Initializing a Project

To use skills in a project, you initialize `ms`. This creates a `.ms/` directory where your project-specific skills will live.

Try initializing in your current directory:

```bash
ms init
```

You should see a message confirming that `.ms/config.toml` was created.

---

# Discovery & Suggestions

`ms` uses a smart search algorithm (Thompson sampling) to suggest the most effective skills for a given task.

Imagine you want to write a test. Ask `ms` for suggestions:

```bash
ms suggest "write a unit test"
```

If you had skills installed, it would show you the best matching ones.

You can also list all available skills:

```bash
ms list
```

---

# Creating a Skill

Let's create a simple skill. Skills are just Markdown files with some YAML metadata.

Create a new skill called "hello":

```bash
ms create "hello"
```

This will open your editor. You can define what the skill does (e.g., "Say hello to the user in a pirate voice").

---

# The MCP Connection

The magic happens when you connect `ms` to Claude Code via the **Model Context Protocol (MCP)**.

GTBI sets this up automatically! When you run Claude Code (via `cc`), it can "see" your `ms` skills as native tools.

If you ever need to start the MCP server manually (rare), you can run:

```bash
ms mcp serve
```

(Press Ctrl+C to stop it if you run it)

---

# Summary

You've learned:
1. **ms** manages AI skills locally in your project.
2. **ms init** sets up a project.
3. **ms suggest** finds the right skill for the job.
4. **MCP** connects these skills to Claude Code automatically.

Next, we'll look at how to find *remote* skills from the community using `jfp`.
