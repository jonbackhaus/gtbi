# Lesson 13: Refining Plans with APR

skills:
  - apr
  - planning
  - ai-tools

---

# What is APR?

Complex specifications require multiple review cycles to identify architectural issues, edge cases, and security flaws. Instead of manually running 15-20 AI review rounds, APR automates the process.

**APR (Automated Plan Reviser Pro)** orchestrates iterative specification refinement using extended AI reasoning. Early rounds fix major issues, middle rounds refine structure, later rounds polish abstractions.

---

# Checking Installation

Verify APR is installed:

```bash
apr --version
```

And check available options:

```bash
apr --help
```

---

# The Basic Workflow

APR works with Markdown plan files. The typical flow looks like this:

1. Generate an initial plan (from Claude Code or write it yourself)
2. Run `apr refine` to improve it
3. Review the refined plan
4. Feed it back to Claude Code for implementation

---

# Refining a Plan

Let's say you have a plan file called `plan.md`. Refine it:

```bash
apr refine plan.md
```

APR analyzes the plan and outputs an improved version with:
- Clearer structure
- Identified dependencies
- Potential edge cases
- More actionable steps

---

# Saving to a Specific File

By default, APR outputs to stdout. Save to a specific file:

```bash
apr refine plan.md -o refined-plan.md
```

Now you have both versions to compare.

---

# Iterative Refinement

APR supports multiple passes. If the first refinement isn't thorough enough:

```bash
apr refine refined-plan.md -o final-plan.md
```

Each pass adds more detail and structure.

---

# A Practical Example

Here's a real workflow:

```bash
# 1. Claude Code generates initial plan
# (creates plan.md)

# 2. Refine with APR
apr refine plan.md -o refined-plan.md

# 3. Review the output
cat refined-plan.md

# 4. Give to Claude Code for implementation
# "Please implement according to refined-plan.md"
```

---

# Summary

You've learned:
1. **APR** turns rough plans into polished roadmaps
2. **apr refine <file>** processes a plan file
3. **-o** saves output to a specific file
4. Use APR iteratively for complex plans

APR is especially useful when you want Claude Code to follow a well-structured implementation plan.
