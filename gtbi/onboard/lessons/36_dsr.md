# Lesson 36: Local Releases with DSR

skills:
  - dsr
  - release-management
  - ci-cd

---

# What is DSR?

Ever been blocked because GitHub Actions is throttled and you need to ship a release now? DSR is your escape hatch.

**DSR (Doodlestein Self-Releaser)** builds, tags, and publishes releases locally when CI/CD pipelines are unavailable or too slow. It handles cross-compilation, checksum generation, and GitHub release creation from your terminal.

---

# Checking Installation

Verify DSR is installed:

```bash
dsr --help
```

---

# Checking Release Readiness

Before releasing, verify everything is in order:

```bash
dsr check --all
```

This validates version tags, build prerequisites, and repository state.

---

# Building a Release

Build release binaries locally:

```bash
dsr build
```

This compiles for the current platform. For cross-platform releases, DSR coordinates with RCH to use remote workers.

---

# Why DSR Matters for Agents

GitHub Actions has rate limits and queue times. DSR provides:

- Immediate releases without waiting for CI queues
- Fallback infrastructure when Actions is throttled
- Local builds that bypass CI outages
- Consistent release artifacts with checksums

---

# Common Scenarios

```bash
# Check if repo is ready to release
dsr check --all

# Build release for current platform
dsr build

# Create a GitHub release with built artifacts
dsr release --tag v1.2.3
```

---

# Summary

You've learned:
1. **dsr check** - Verify release readiness
2. **dsr build** - Compile release binaries locally
3. **dsr release** - Publish to GitHub
4. How DSR provides CI/CD independence for urgent releases
