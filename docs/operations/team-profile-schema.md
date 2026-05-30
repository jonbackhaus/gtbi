# Redacted Team Profile Schema

This note defines the `bd-0aotl` design contract for portable GTBI team
profiles. A team profile is a shareable set of defaults for the web wizard,
installer, onboarding lessons, and future team-mode import flow. It must never
carry credentials, raw host addresses, private keys, or provider account data.

## Goals

- Let a maintainer publish safe defaults for repeated GTBI installs.
- Keep installer choices auditable before any mutation.
- Make required secret slots explicit without storing secret values.
- Support deterministic import diffs so users can review exactly what changes.
- Fail closed when a profile is incompatible with the current GTBI manifest or
  security policy.

## Non-Goals

- Profiles are not backups of a configured VPS.
- Profiles are not a credential vault.
- Profiles are not compatibility shims for deprecated installer flags.
- Profiles do not override `checksums.yaml` or verified-installer trust rules.

## File Layout

Recommended file name:

```text
gtbi-team-profile.json
```

The file is plain JSON. Future compressed bundles may include documentation,
but the profile JSON remains the trust boundary and must validate by itself.

## Schema

```json
{
  "schema": "gtbi.team-profile.v1",
  "schemaVersion": 1,
  "profileId": "example-team-vps",
  "displayName": "Example Team VPS",
  "description": "Shared GTBI defaults for the example team.",
  "generatedAt": "2026-05-08T00:00:00Z",
  "generatedBy": "gtbi wizard",
  "provenance": {
    "author": {
      "name": "Example Maintainer",
      "email": "maintainer@example.invalid"
    },
    "source": {
      "gtbiVersion": "0.0.0-dev",
      "gtbiRef": "main",
      "gtbiCommit": "0123456789abcdef0123456789abcdef01234567",
      "manifestSha256": "<sha256 of gtbi.manifest.yaml>",
      "checksumsYamlSha256": "<sha256 of checksums.yaml>"
    }
  },
  "compatibility": {
    "minAcfsVersion": "0.0.0-dev",
    "schemaVersions": [1],
    "targetUbuntuVersions": ["25.10"],
    "architectures": ["x86_64", "aarch64"],
    "installerRefPolicy": "prefer_pinned_ref",
    "checksumsRefPolicy": "current_gtbi_default"
  },
  "providerDefaults": {
    "provider": "contabo",
    "region": "us-east",
    "planClass": "standard-vps",
    "operatingSystem": "ubuntu-25.10",
    "architecture": "x86_64",
    "sshUser": "ubuntu",
    "sshPort": 22
  },
  "install": {
    "mode": "vibe",
    "profile": "full",
    "ref": {
      "type": "branch",
      "value": "main",
      "pinOnExport": true
    },
    "modules": {
      "only": [],
      "onlyPhases": [],
      "skip": [],
      "noDeps": false
    },
    "offlinePack": {
      "required": false,
      "pathHint": null
    }
  },
  "shellPreferences": {
    "loginShell": "zsh",
    "history": "atuin",
    "multiplexer": "tmux"
  },
  "lessonChoices": {
    "startLesson": "linux-basics",
    "requiredLessons": ["terminal-navigation", "agent-workflow"],
    "optionalLessons": ["cloud-provider-setup"]
  },
  "serviceAccounts": [
    {
      "id": "github",
      "required": true,
      "authMethod": "browser_login",
      "secretSlot": "secret://gtbi/team/github-token"
    },
    {
      "id": "cloudflare",
      "required": false,
      "authMethod": "api_token",
      "secretSlot": "secret://gtbi/team/cloudflare-api-token"
    }
  ],
  "redaction": {
    "allowSecretValues": false,
    "secretSlotsRequired": true,
    "forbiddenFields": [
      "token",
      "apiKey",
      "secret",
      "password",
      "privateKey",
      "cookie",
      "session"
    ]
  }
}
```

## Required Fields

Every v1 profile must include:

- `schema: "gtbi.team-profile.v1"` and `schemaVersion: 1`
- `profileId`, `displayName`, `generatedAt`, and `generatedBy`
- `provenance.source.gtbiRef`, `provenance.source.manifestSha256`, and
  `provenance.source.checksumsYamlSha256`
- `compatibility.targetUbuntuVersions`, `compatibility.architectures`,
  `compatibility.installerRefPolicy`, and `compatibility.checksumsRefPolicy`
- `providerDefaults.provider`, `providerDefaults.operatingSystem`,
  `providerDefaults.architecture`, and `providerDefaults.sshUser`
- `install.mode`, `install.ref`, and `install.modules`
- `redaction.allowSecretValues: false`
- `redaction.secretSlotsRequired: true`

Unknown top-level fields are allowed only under `extensions`. Unknown fields in
`providerDefaults`, `install`, `serviceAccounts`, or `redaction` must be ignored
by older consumers but must not weaken validation decisions.

## Safe Field Rules

Allowed values are defaults, choices, and identifiers:

- provider name, region, plan class, OS image, architecture, SSH username, and
  SSH port
- installer mode, selected module ids, skipped module ids, phase ids, and ref
  pinning policy
- shell and onboarding lesson preferences
- service account requirements and authentication method names
- secret-slot references that start with `secret://gtbi/team/`

Disallowed values include:

- raw provider hostnames or IP addresses
- passwords, OAuth refresh tokens, API tokens, session cookies, bearer tokens,
  private keys, recovery codes, database URLs, webhook secrets, or Vault tokens
- raw SSH public keys when they identify a private machine or person
- full local filesystem paths outside documented GTBI paths
- generated support-bundle contents, installer logs, or shell history

## Secret Slots

Secret slots describe future inputs without carrying the secret:

```json
{
  "id": "cloudflare",
  "required": true,
  "authMethod": "api_token",
  "secretSlot": "secret://gtbi/team/cloudflare-api-token"
}
```

Consumers must treat a missing required secret slot as an import warning or
blocked install step, not as permission to embed a credential. UI surfaces should
collect the value through the normal provider or CLI authentication flow at use
time.

## Forbidden Field And Value Checks

Profile validators must fail closed when any object key matches a forbidden
credential-like name outside `redaction.forbiddenFields` or documented
`secretSlot` metadata. The default forbidden key fragments are:

```text
token apiKey secret password privateKey private_key cookie session bearer
refreshToken accessToken clientSecret webhookSecret vaultToken
```

Profile validators must also reject values that look like:

- PEM or OpenSSH private-key blocks
- cloud or source-hosting access tokens
- bearer-token headers
- URL strings with embedded username/password
- long high-entropy opaque strings in non-secret fields
- raw IPv4 or IPv6 addresses in provider host fields

Examples in docs and tests must use placeholder text such as
`secret://gtbi/team/example-token`; they must not include realistic secret
samples.

## Compatibility Checks

Before applying an import, the consumer must compare the profile with the
current GTBI source:

1. `schema` and `schemaVersion` are supported.
2. `compatibility.targetUbuntuVersions` includes the requested target.
3. `compatibility.architectures` includes the target architecture.
4. `install.modules.only`, `install.modules.skip`, and `install.modules.onlyPhases`
   reference known modules or phases.
5. `install.modules.noDeps` is either absent or explicitly `false` unless the
   user enables expert mode during import.
6. `provenance.source.manifestSha256` matches the manifest used to build the
   selected plan, or the import diff marks the plan as stale.
7. `provenance.source.checksumsYamlSha256` matches the checksum metadata used by
   the installer, or the import diff marks checksum metadata as stale.
8. `install.ref.pinOnExport` is honored before commands are copied or executed.

Compatibility failures must stop automatic import. A user may still inspect the
profile in read-only mode.

## Import Diff Policy

Import must be dry-run first. The diff must be grouped into:

- `safeDefaults`: provider, shell, lesson, and module defaults that can be shown
  before mutation
- `installerCommand`: exact flags the profile would add or change
- `dependencyClosure`: modules added by resolver dependencies
- `skips`: requested skips and whether they are allowed
- `secretSlots`: required and optional secret-slot prompts
- `incompatibilities`: schema, manifest, checksum, Ubuntu, architecture, module,
  or ref-policy mismatches
- `refusals`: forbidden fields, secret-looking values, unsafe paths, or unknown
  critical fields

The import command must not write files, change shell configuration, start an
installer, or authenticate a service until the user confirms the reviewed diff.
No-TTY mode must print the diff and refuse mutation unless an explicit future
machine-readable confirmation flag is added.

## Export Policy

When exporting from the wizard or installer state:

- redact provider hostnames, raw IPs, account IDs, local paths, shell history,
  and log snippets
- convert credential requirements into `secretSlot` entries
- prefer pinned refs for repeatable installs
- record `manifestSha256` and `checksumsYamlSha256`
- sort module arrays deterministically
- include a warning if selected modules require live provider interaction

Export must never read private key files, token files, browser sessions, or
provider CLI credential stores.

## Error Codes

Future validators and import commands should use stable reason codes:

| Code | Meaning |
| --- | --- |
| `team_profile_missing_schema` | `schema` or `schemaVersion` is absent. |
| `team_profile_schema_unsupported` | Schema version is not supported. |
| `team_profile_secret_material_refused` | A field or value contains credential-like material. |
| `team_profile_forbidden_field` | A forbidden credential-like key is present. |
| `team_profile_unknown_module` | A module selector references an unknown module. |
| `team_profile_unknown_phase` | A phase selector references an unknown phase. |
| `team_profile_manifest_mismatch` | Profile manifest hash differs from the current resolver manifest. |
| `team_profile_checksums_mismatch` | Profile checksum hash differs from current checksum metadata. |
| `team_profile_arch_unsupported` | Target architecture is not listed. |
| `team_profile_ubuntu_unsupported` | Target Ubuntu version is not listed. |
| `team_profile_no_tty_confirmation_required` | Import needs confirmation but no TTY is available. |

## Test Plan

Implementation beads should add fixture tests for:

- valid minimal profile
- forbidden key names
- secret-looking values in safe fields
- unknown module and phase selectors
- manifest/checksum hash drift
- unsupported Ubuntu version and architecture
- no-TTY import refusal
- dry-run diff categories and deterministic module ordering
