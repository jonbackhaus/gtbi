# Lesson 33: Hybrid Search with FSFS

skills:
  - fsfs
  - search
  - code-navigation

---

# What is FSFS?

Ever wished `grep` understood what you meant, not just what you typed? FSFS bridges that gap.

**FSFS (FrankenSearch)** is a hybrid search engine that combines BM25 lexical matching with semantic vector search. It indexes local files and delivers results progressively, so you see fast keyword hits immediately while deeper semantic matches arrive moments later.

---

# Checking Installation

Verify FSFS is installed:

```bash
fsfs --help
```

---

# Indexing a Directory

Before searching, build an index:

```bash
fsfs index .
```

This scans files in the current directory and creates both lexical and semantic indexes.

---

# Searching

Run a search query:

```bash
fsfs search "database connection pooling"
```

Results are ranked by a combined score of keyword relevance and semantic similarity.

---

# Why FSFS Matters for Agents

AI agents frequently need to find relevant code across large repos. FSFS handles:

- Finding conceptually related code, not just exact string matches
- Locating implementations by describing what they do
- Navigating unfamiliar codebases quickly

---

# Common Scenarios

```bash
# Find code related to error handling
fsfs search "error handling retry logic"

# Search only Rust files
fsfs search "async runtime" --glob "*.rs"

# Rebuild index after major changes
fsfs index --rebuild .
```

---

# Summary

You've learned:
1. **fsfs index** - Build search indexes
2. **fsfs search** - Hybrid lexical + semantic search
3. Progressive delivery for fast results
4. Why hybrid search outperforms plain grep for code navigation
