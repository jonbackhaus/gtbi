# GTBI Workflow Templates

Ready-to-use GitHub Actions workflow templates for GTBI-owned tool repositories.

## Available Templates

| Template | Use Case |
|----------|----------|
| `notify-gtbi-workflow.yml` | Full repository-dispatch workflow with checksum comparison and dry-run support |
| `validate-gtbi-workflow.yml` | Validation workflow for checking a tool repo's GTBI integration |
| `notify-gtbi-root.yml` | Repos with `install.sh` at repository root |
| `notify-gtbi-scripts.yml` | Repos with `install.sh` in `scripts/` directory |

## Quick Setup

1. **Create PAT**: Generate a Personal Access Token with `contents:read` on the `gastown_batteries_included` repo

2. **Add Secret**: In your tool repo, create a secret named `GTBI_REPO_DISPATCH_TOKEN` with the PAT value

3. **Copy Template**: Copy the appropriate template to `.github/workflows/notify-gtbi.yml`

4. **Test**: Trigger the workflow manually or push a change to your install script

## Which Template to Use

Check your `checksums.yaml` entry to see the installer path:

```yaml
# Root install.sh → use notify-gtbi-root.yml
ntm:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"

# scripts/install.sh → use notify-gtbi-scripts.yml
mcp_agent_mail:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/refs/heads/main/install.sh"
```

## Full Documentation

See `gtbi/docs/repo-dispatch-setup.md` for complete setup instructions, troubleshooting, and security considerations.
