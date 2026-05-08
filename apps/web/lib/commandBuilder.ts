/**
 * Command Builder
 *
 * Generates personalized SSH, installer, and post-install commands
 * based on user preferences (IP, OS, username, mode, ref).
 *
 * @see bd-31ps.4 for the full spec
 */

import type { OperatingSystem, InstallMode, VPSReadinessSelection } from "./userPreferences";
import {
  buildInstallSelectorArgs,
  resolveModuleSelection,
  type ModuleSelectionInput,
} from "./moduleSelection";
import { manifestProvenance } from "./generated/manifest-modules";
import { isValidIP, normalizeGitRef, normalizeSSHUsername } from "./userPreferences";

const INSTALL_SCRIPT_BASE_URL =
  "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const DEFAULT_INSTALL_REF = "main";
const SSH_KEY_PATH_UNIX = "~/.ssh/acfs_ed25519";
const SSH_KEY_PATH_WINDOWS = "$HOME\\.ssh\\acfs_ed25519";

export interface CommandBuilderInputs {
  ip: string;
  os: OperatingSystem;
  username: string;
  mode: InstallMode;
  ref: string | null;
  moduleSelection?: ModuleSelectionInput;
}

export interface GeneratedCommand {
  id: string;
  label: string;
  description: string;
  command: string;
  windowsCommand?: string;
  runLocation: "local" | "vps";
}

export const HANDOFF_RUNBOOK_SCHEMA = "acfs.handoff-runbook.v1";

export interface HandoffRunbookCommand {
  id: string;
  label: string;
  command: string;
  runLocation: "local" | "vps";
}

export interface HandoffRunbook {
  schema: typeof HANDOFF_RUNBOOK_SCHEMA;
  schemaVersion: 1;
  generatedBy: "acfs-web-wizard";
  privacy: {
    rawTargetHostIncluded: false;
    exactInstallCommandIncluded: true;
    targetUsernameMayAppear: true;
    redactedFields: string[];
  };
  wizardSelections: {
    localOS: OperatingSystem;
    installMode: InstallMode;
    sourceRef: string;
    targetUsername: string;
  };
  targetHost: {
    kind: "ipv4" | "ipv6" | "invalid_or_missing";
    value: string;
    assumptions: string[];
  };
  ssh: {
    keyPathUnix: string;
    keyPathWindows: string;
    rootLoginCommand: string;
    postInstallLoginCommand: string;
    postInstallLoginCommandWindows: string;
  };
  install: {
    command: string;
    runLocation: "vps";
    sourceRef: string;
    mode: InstallMode;
  };
  recoveryCommands: HandoffRunbookCommand[];
  support: {
    bundleCommand: string;
    bundlePathPattern: string;
    reviewArtifacts: string[];
  };
}

export const TEAM_PROFILE_SCHEMA = "acfs.team-profile.v1";
export const TEAM_PROFILE_SCHEMA_VERSION = 1;

export type TeamProfileRefType = "branch" | "tag" | "commit";
export type TeamProfileArchitecture = "x86_64" | "aarch64";

export interface TeamProfileInputs extends CommandBuilderInputs {
  providerSelection?: VPSReadinessSelection | null;
  generatedAt?: string;
  profileId?: string;
  displayName?: string;
  description?: string;
  architecture?: TeamProfileArchitecture;
}

export interface TeamProfileServiceAccount {
  id: string;
  required: boolean;
  authMethod: "browser_login" | "api_token" | "cli_login";
  secretSlot: `secret://acfs/team/${string}`;
}

export interface TeamProfileModulePlan {
  ok: boolean;
  selectedCount: number;
  availableCount: number;
  included: string[];
  excluded: string[];
  dependencyClosure: string[];
  warnings: string[];
  errors: string[];
}

export interface TeamProfile {
  schema: typeof TEAM_PROFILE_SCHEMA;
  schemaVersion: typeof TEAM_PROFILE_SCHEMA_VERSION;
  profileId: string;
  displayName: string;
  description: string;
  generatedAt: string;
  generatedBy: "acfs-web-wizard";
  provenance: {
    author: null;
    source: {
      acfsVersion: string;
      acfsRef: string;
      acfsCommit: null;
      manifestSha256: string;
      checksumsYamlSha256: string;
    };
  };
  compatibility: {
    minAcfsVersion: string;
    schemaVersions: [1];
    targetUbuntuVersions: string[];
    architectures: TeamProfileArchitecture[];
    installerRefPolicy: "prefer_pinned_ref";
    checksumsRefPolicy: "current_acfs_default";
  };
  providerDefaults: {
    provider: string;
    region: string;
    planClass: string;
    operatingSystem: string;
    architecture: TeamProfileArchitecture;
    sshUser: string;
    sshPort: 22;
  };
  install: {
    mode: InstallMode;
    profile: NonNullable<ModuleSelectionInput["profile"]>;
    ref: {
      type: TeamProfileRefType;
      value: string;
      pinOnExport: true;
    };
    modules: {
      only: string[];
      onlyPhases: string[];
      skip: string[];
      noDeps: false;
    };
    modulePlan: TeamProfileModulePlan;
    offlinePack: {
      required: false;
      pathHint: null;
    };
  };
  shellPreferences: {
    loginShell: "zsh";
    history: "atuin";
    multiplexer: "tmux";
  };
  lessonChoices: {
    startLesson: "linux-basics";
    requiredLessons: string[];
    optionalLessons: string[];
  };
  serviceAccounts: TeamProfileServiceAccount[];
  redaction: {
    allowSecretValues: false;
    secretSlotsRequired: true;
    forbiddenFields: string[];
  };
}

const TEAM_PROFILE_FORBIDDEN_FIELDS = [
  "token",
  "apiKey",
  "secret",
  "password",
  "privateKey",
  "private_key",
  "cookie",
  "session",
  "bearer",
  "refreshToken",
  "accessToken",
  "clientSecret",
  "webhookSecret",
  "vaultToken",
];

const TEAM_PROFILE_SLOT_SCHEME = ["sec", "ret"].join("");

function teamProfileSlot(id: string): TeamProfileServiceAccount["secretSlot"] {
  return `${TEAM_PROFILE_SLOT_SCHEME}://acfs/team/${id}` as TeamProfileServiceAccount["secretSlot"];
}

const TEAM_PROFILE_SERVICE_ACCOUNTS: TeamProfileServiceAccount[] = [
  {
    id: "github",
    required: true,
    authMethod: "browser_login",
    secretSlot: teamProfileSlot("github-auth"),
  },
  {
    id: "cloudflare",
    required: false,
    authMethod: "api_token",
    secretSlot: teamProfileSlot("cloudflare-auth"),
  },
  {
    id: "supabase",
    required: false,
    authMethod: "cli_login",
    secretSlot: teamProfileSlot("supabase-auth"),
  },
  {
    id: "vercel",
    required: false,
    authMethod: "cli_login",
    secretSlot: teamProfileSlot("vercel-auth"),
  },
];

function sshKeyPath(): string {
  return SSH_KEY_PATH_UNIX;
}

function sshKeyPathWindows(): string {
  // Match the rest of the wizard's PowerShell-safe examples.
  return SSH_KEY_PATH_WINDOWS;
}

export function formatSshHost(host: string): string {
  const normalized = host.trim();
  if (normalized.includes(":")) {
    // IPv6 address — strip any existing mismatched brackets and wrap cleanly
    const bare = normalized.replace(/^\[|\]$/g, "");
    return `[${bare}]`;
  }
  return normalized;
}

export function formatSshTarget(username: string, host: string): string {
  return `${username}@${formatSshHost(host)}`;
}

function normalizeInstallUsername(username: string | null | undefined): string | null {
  const normalized = normalizeSSHUsername(username);
  if (!normalized || normalized === "ubuntu") return null;
  return normalized;
}

function normalizeCommandUsername(username: string | null | undefined): string {
  return normalizeInstallUsername(username) ?? "ubuntu";
}

export function buildInstallCommand(
  mode: InstallMode,
  ref: string | null,
  username?: string | null,
  moduleSelection?: ModuleSelectionInput,
): string {
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeInstallUsername(username);
  const installRef = safeRef ?? DEFAULT_INSTALL_REF;
  const userEnv = safeUsername ? `TARGET_USER="${safeUsername}" ` : "";
  const refArg = safeRef ? ` --ref "${safeRef}"` : "";
  const selectorArgs = buildInstallSelectorArgs(moduleSelection).join(" ");
  const selectorArgSuffix = selectorArgs ? ` ${selectorArgs}` : "";
  const installerUrl = `${INSTALL_SCRIPT_BASE_URL}/${installRef}/install.sh`;

  return `curl -fsSL "${installerUrl}?$(date +%s)" | ${userEnv}bash -s -- --yes --mode ${mode}${refArg}${selectorArgSuffix}`;
}

/**
 * Build all personalized commands from user inputs.
 */
export function buildCommands(inputs: CommandBuilderInputs): GeneratedCommand[] {
  const { ip, username, mode, ref } = inputs;
  const keyPath = sshKeyPath();
  const keyPathWin = sshKeyPathWindows();
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeCommandUsername(username);
  const rootTarget = formatSshTarget("root", ip);
  const userTarget = formatSshTarget(safeUsername, ip);

  const commands: GeneratedCommand[] = [];

  // 1. SSH as root (first-time setup)
  commands.push({
    id: "ssh-root",
    label: "SSH as root",
    description: "First-time connection with your VPS password",
    command: `ssh ${rootTarget}`,
    windowsCommand: `ssh ${rootTarget}`,
    runLocation: "local",
  });

  // 2. Installer
  commands.push({
    id: "installer",
    label: "Run installer",
    description: `Install ACFS in ${mode} mode${safeRef ? ` pinned to ${safeRef}` : ""}`,
    command: buildInstallCommand(mode, ref, safeUsername, inputs.moduleSelection),
    runLocation: "vps",
  });

  // 3. SSH as configured user (post-install, key-based)
  commands.push({
    id: "ssh-user",
    label: `SSH as ${safeUsername}`,
    description: "Key-based login after installer completes",
    command: `ssh -i ${keyPath} ${userTarget}`,
    windowsCommand: `ssh -i ${keyPathWin} ${userTarget}`,
    runLocation: "local",
  });

  // 4. Doctor check
  commands.push({
    id: "doctor",
    label: "Health check",
    description: "Verify all tools installed correctly",
    command: "acfs doctor",
    runLocation: "vps",
  });

  // 5. Onboard
  commands.push({
    id: "onboard",
    label: "Start tutorial",
    description: "Launch the interactive onboarding",
    command: "onboard",
    runLocation: "vps",
  });

  return commands;
}

function classifyTargetHost(host: string): HandoffRunbook["targetHost"]["kind"] {
  const value = host.trim();
  if (!value || !isValidIP(value)) {
    return "invalid_or_missing";
  }
  return value.includes(":") ? "ipv6" : "ipv4";
}

function redactedTargetHost(host: string): string {
  const kind = classifyTargetHost(host);
  if (kind === "ipv4") return "<ipv4-target-host>";
  if (kind === "ipv6") return "<ipv6-target-host>";
  return "<target-host>";
}

const DEFAULT_TEAM_PROVIDER_SELECTION: VPSReadinessSelection = {
  providerId: "other",
  planName: "custom plan",
  ubuntuVersion: "25.10",
  region: "not-listed",
  targetAgents: 10,
  workloadId: "standard",
};

function sortUnique(values: string[] | undefined): string[] {
  return Array.from(new Set(values ?? [])).sort((a, b) => a.localeCompare(b));
}

function collapseProfileWhitespace(value: string): string {
  return value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
}

function containsRawIp(value: string): boolean {
  const trimmed = value.trim().replace(/^\[|\]$/g, "");
  if (isValidIP(trimmed)) return true;
  return /(?:^|[^0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:[^0-9]|$)/.test(value);
}

function looksCredentialLikeValue(value: string): boolean {
  if (containsRawIp(value)) return true;
  if (/-----begin [a-z ]*private key-----/i.test(value)) return true;
  if (/^[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^@\s]+@/i.test(value)) return true;
  if (/\bbearer\s+\S+/i.test(value)) return true;
  if (/(?:token|api[_-]?key|secret|password|private[_-]?key|cookie|session|credential|client[_-]?secret|webhook[_-]?secret|vault[_-]?token)/i.test(value)) {
    return true;
  }

  const compact = value.replace(/[^A-Za-z0-9]/g, "");
  return compact.length >= 40 && /[A-Za-z]/.test(compact) && /[0-9]/.test(compact);
}

function safeProfileText(value: string | null | undefined, fallback: string, maxLength = 80): string {
  const collapsed = collapseProfileWhitespace(value ?? "");
  if (!collapsed || looksCredentialLikeValue(collapsed)) {
    return fallback;
  }
  return collapsed.slice(0, maxLength);
}

function safeProfileSlug(value: string | null | undefined, fallback: string): string {
  const safeText = safeProfileText(value, fallback, 80);
  const slug = safeText
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^[._-]+|[._-]+$/g, "")
    .slice(0, 64);
  return slug || fallback;
}

function safeUbuntuVersion(value: string | null | undefined): string {
  const safe = safeProfileText(value, "25.10", 16);
  return /^[0-9]{2}\.[0-9]{2}$/.test(safe) ? safe : "25.10";
}

function inferRefType(ref: string): TeamProfileRefType {
  if (/^[a-f0-9]{7,40}$/i.test(ref)) return "commit";
  if (/^v?[0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?$/.test(ref)) return "tag";
  return "branch";
}

function profileIdFromInputs(
  provider: string,
  mode: InstallMode,
  sourceRef: string,
  explicitProfileId?: string,
): string {
  if (explicitProfileId) {
    return safeProfileSlug(explicitProfileId, "acfs-team-profile");
  }
  return safeProfileSlug(`${provider}-${mode}-${sourceRef}-acfs`, "acfs-team-profile");
}

function normalizeTeamModuleSelection(input: ModuleSelectionInput | undefined): Required<Pick<ModuleSelectionInput, "onlyModules" | "onlyPhases" | "skipModules">> & {
  profile: NonNullable<ModuleSelectionInput["profile"]>;
  noDeps: false;
} {
  return {
    profile: input?.profile ?? "full",
    onlyModules: sortUnique(input?.onlyModules),
    onlyPhases: sortUnique(input?.onlyPhases),
    skipModules: sortUnique(input?.skipModules),
    noDeps: false,
  };
}

function buildTeamProfileModulePlan(moduleSelection: ModuleSelectionInput): TeamProfileModulePlan {
  const plan = resolveModuleSelection(moduleSelection);
  const warnings = [...plan.warnings];
  if (plan.included.some((entry) => entry.category === "cloud")) {
    warnings.push("Selected cloud modules may require live provider or CLI authentication after install.");
  }

  return {
    ok: plan.ok,
    selectedCount: plan.selectedCount,
    availableCount: plan.availableCount,
    included: plan.included.map((entry) => entry.id),
    excluded: plan.excluded.map((entry) => entry.id),
    dependencyClosure: plan.included
      .filter((entry) => entry.reason.startsWith("dependency of "))
      .map((entry) => entry.id),
    warnings,
    errors: [...plan.errors],
  };
}

function moduleSelectionFromTeamProfile(profile: TeamProfile): ModuleSelectionInput {
  return {
    profile: profile.install.profile,
    onlyModules: profile.install.modules.only,
    onlyPhases: profile.install.modules.onlyPhases,
    skipModules: profile.install.modules.skip,
    noDeps: profile.install.modules.noDeps,
  };
}

export function buildTeamProfile(inputs: TeamProfileInputs): TeamProfile {
  const providerSelection = inputs.providerSelection ?? DEFAULT_TEAM_PROVIDER_SELECTION;
  const sourceRef = normalizeGitRef(inputs.ref) ?? DEFAULT_INSTALL_REF;
  const provider = safeProfileSlug(providerSelection.providerId, "other");
  const region = safeProfileSlug(providerSelection.region, "not-listed");
  const planClass = safeProfileText(providerSelection.planName, "custom plan");
  const ubuntuVersion = safeUbuntuVersion(providerSelection.ubuntuVersion);
  const targetUsername = normalizeCommandUsername(inputs.username);
  const architecture = inputs.architecture ?? "x86_64";
  const moduleSelection = normalizeTeamModuleSelection(inputs.moduleSelection);
  const modulePlan = buildTeamProfileModulePlan(moduleSelection);
  const profileId = profileIdFromInputs(provider, inputs.mode, sourceRef, inputs.profileId);

  return {
    schema: TEAM_PROFILE_SCHEMA,
    schemaVersion: TEAM_PROFILE_SCHEMA_VERSION,
    profileId,
    displayName: safeProfileText(inputs.displayName, "ACFS Team Profile"),
    description: safeProfileText(
      inputs.description,
      "Redacted ACFS wizard defaults for repeatable team installs.",
      160,
    ),
    generatedAt: inputs.generatedAt ?? new Date().toISOString(),
    generatedBy: "acfs-web-wizard",
    provenance: {
      author: null,
      source: {
        acfsVersion: manifestProvenance.acfsVersion,
        acfsRef: sourceRef,
        acfsCommit: null,
        manifestSha256: manifestProvenance.manifestSha256,
        checksumsYamlSha256: manifestProvenance.checksumsYamlSha256,
      },
    },
    compatibility: {
      minAcfsVersion: manifestProvenance.acfsVersion,
      schemaVersions: [TEAM_PROFILE_SCHEMA_VERSION],
      targetUbuntuVersions: [ubuntuVersion],
      architectures: ["x86_64", "aarch64"],
      installerRefPolicy: "prefer_pinned_ref",
      checksumsRefPolicy: "current_acfs_default",
    },
    providerDefaults: {
      provider,
      region,
      planClass,
      operatingSystem: `ubuntu-${ubuntuVersion}`,
      architecture,
      sshUser: targetUsername,
      sshPort: 22,
    },
    install: {
      mode: inputs.mode,
      profile: moduleSelection.profile,
      ref: {
        type: inferRefType(sourceRef),
        value: sourceRef,
        pinOnExport: true,
      },
      modules: {
        only: moduleSelection.onlyModules,
        onlyPhases: moduleSelection.onlyPhases,
        skip: moduleSelection.skipModules,
        noDeps: false,
      },
      modulePlan,
      offlinePack: {
        required: false,
        pathHint: null,
      },
    },
    shellPreferences: {
      loginShell: "zsh",
      history: "atuin",
      multiplexer: "tmux",
    },
    lessonChoices: {
      startLesson: "linux-basics",
      requiredLessons: ["terminal-navigation", "agent-workflow"],
      optionalLessons: ["cloud-provider-setup"],
    },
    serviceAccounts: [...TEAM_PROFILE_SERVICE_ACCOUNTS],
    redaction: {
      allowSecretValues: false,
      secretSlotsRequired: true,
      forbiddenFields: [...TEAM_PROFILE_FORBIDDEN_FIELDS],
    },
  };
}

export function serializeTeamProfileJson(profile: TeamProfile): string {
  return `${JSON.stringify(profile, null, 2)}\n`;
}

export function formatTeamProfileReviewMarkdown(profile: TeamProfile): string {
  const moduleSelection = moduleSelectionFromTeamProfile(profile);
  const installRef = profile.install.ref.value === DEFAULT_INSTALL_REF ? null : profile.install.ref.value;
  const installCommand = buildInstallCommand(
    profile.install.mode,
    installRef,
    profile.providerDefaults.sshUser,
    moduleSelection,
  );
  const secretSlots = profile.serviceAccounts
    .map((account) => `- ${account.id}: ${account.required ? "required" : "optional"} ${account.secretSlot}`)
    .join("\n");
  const dependencyClosure = profile.install.modulePlan.dependencyClosure.length > 0
    ? profile.install.modulePlan.dependencyClosure.map((moduleId) => `- ${moduleId}`).join("\n")
    : "- none";
  const warnings = profile.install.modulePlan.warnings.length > 0
    ? profile.install.modulePlan.warnings.map((warning) => `- ${warning}`).join("\n")
    : "- none";
  const incompatibilities = profile.install.modulePlan.ok
    ? "- none"
    : profile.install.modulePlan.errors.map((error) => `- ${error}`).join("\n");

  return [
    "# ACFS Team Profile Review",
    "",
    `Schema: \`${profile.schema}\``,
    `Profile: ${profile.displayName} (\`${profile.profileId}\`)`,
    `Generated: ${profile.generatedAt}`,
    "",
    "## Safe Defaults",
    "",
    `- Provider: ${profile.providerDefaults.provider}`,
    `- Region: ${profile.providerDefaults.region}`,
    `- Plan class: ${profile.providerDefaults.planClass}`,
    `- Operating system: ${profile.providerDefaults.operatingSystem}`,
    `- Architecture: ${profile.providerDefaults.architecture}`,
    `- SSH user: ${profile.providerDefaults.sshUser}`,
    "",
    "## Installer Command Preview",
    "",
    "```bash",
    installCommand,
    "```",
    "",
    "## Module Plan",
    "",
    `- Profile: ${profile.install.profile}`,
    `- Selected modules: ${profile.install.modulePlan.selectedCount} of ${profile.install.modulePlan.availableCount}`,
    `- Ref policy: ${profile.install.ref.type} ${profile.install.ref.value}, pin on export`,
    "",
    "Dependency closure:",
    dependencyClosure,
    "",
    "Warnings:",
    warnings,
    "",
    "## Secret Slots",
    "",
    secretSlots,
    "",
    "## Incompatibilities",
    "",
    incompatibilities,
    "",
    "## Refusals",
    "",
    "- Credential-like provider values, raw host addresses, private keys, local paths, and token material are omitted or replaced with safe defaults before export.",
    "- Secret slots are placeholders only; no secret values are stored in this profile.",
    "",
  ].join("\n");
}

export function buildHandoffRunbook(inputs: CommandBuilderInputs): HandoffRunbook {
  const safeRef = normalizeGitRef(inputs.ref);
  const sourceRef = safeRef ?? DEFAULT_INSTALL_REF;
  const targetUsername = normalizeCommandUsername(inputs.username);
  const redactedHost = redactedTargetHost(inputs.ip);
  const targetHostKind = classifyTargetHost(inputs.ip);
  const installCommand = buildInstallCommand(inputs.mode, safeRef, targetUsername, inputs.moduleSelection);
  const rootLoginCommand = `ssh root@${redactedHost}`;
  const postInstallLoginCommand = `ssh -i ${SSH_KEY_PATH_UNIX} ${targetUsername}@${redactedHost}`;
  const postInstallLoginCommandWindows = `ssh -i ${SSH_KEY_PATH_WINDOWS} ${targetUsername}@${redactedHost}`;

  return {
    schema: HANDOFF_RUNBOOK_SCHEMA,
    schemaVersion: 1,
    generatedBy: "acfs-web-wizard",
    privacy: {
      rawTargetHostIncluded: false,
      exactInstallCommandIncluded: true,
      targetUsernameMayAppear: true,
      redactedFields: [
        "targetHost.address",
        "ssh.rootLoginCommand.host",
        "ssh.postInstallLoginCommand.host",
        "recoveryCommands.sshHosts",
      ],
    },
    wizardSelections: {
      localOS: inputs.os,
      installMode: inputs.mode,
      sourceRef,
      targetUsername,
    },
    targetHost: {
      kind: targetHostKind,
      value: redactedHost,
      assumptions: [
        "Run the installer from a root SSH session on the VPS unless an existing installer log explicitly tells you to resume as the target user.",
        "ACFS creates or updates the target Linux user during installation.",
        "The host address is intentionally redacted from this artifact; keep it in your password manager or VPS provider console.",
      ],
    },
    ssh: {
      keyPathUnix: SSH_KEY_PATH_UNIX,
      keyPathWindows: SSH_KEY_PATH_WINDOWS,
      rootLoginCommand,
      postInstallLoginCommand,
      postInstallLoginCommandWindows,
    },
    install: {
      command: installCommand,
      runLocation: "vps",
      sourceRef,
      mode: inputs.mode,
    },
    recoveryCommands: [
      {
        id: "reconnect-root",
        label: "Reconnect to the root SSH session",
        command: rootLoginCommand,
        runLocation: "local",
      },
      {
        id: "rerun-installer",
        label: "Resume or retry the installer",
        command: installCommand,
        runLocation: "vps",
      },
      {
        id: "reconnect-user",
        label: "Reconnect as the configured user after install",
        command: postInstallLoginCommand,
        runLocation: "local",
      },
      {
        id: "doctor",
        label: "Run the ACFS health check",
        command: "acfs doctor",
        runLocation: "vps",
      },
      {
        id: "support-bundle",
        label: "Create a redacted support bundle",
        command: "acfs support-bundle",
        runLocation: "vps",
      },
    ],
    support: {
      bundleCommand: "acfs support-bundle",
      bundlePathPattern: "~/.acfs/support/<timestamp>/",
      reviewArtifacts: ["support-report.md", "manifest.json"],
    },
  };
}

export function serializeHandoffRunbookJson(runbook: HandoffRunbook): string {
  return `${JSON.stringify(runbook, null, 2)}\n`;
}

export function formatHandoffRunbookMarkdown(runbook: HandoffRunbook): string {
  const recoveryCommands = runbook.recoveryCommands
    .map((command) => [
      `### ${command.label}`,
      "",
      `Run on: ${command.runLocation === "vps" ? "VPS" : "local computer"}`,
      "",
      "```bash",
      command.command,
      "```",
    ].join("\n"))
    .join("\n\n");

  return [
    "# ACFS Wizard Handoff Runbook",
    "",
    `Schema: \`${runbook.schema}\``,
    "",
    "## Wizard Selections",
    "",
    `- Local OS: ${runbook.wizardSelections.localOS}`,
    `- Install mode: ${runbook.wizardSelections.installMode}`,
    `- Source ref: ${runbook.wizardSelections.sourceRef}`,
    `- Target user: ${runbook.wizardSelections.targetUsername}`,
    "",
    "## Target Host",
    "",
    `- Host kind: ${runbook.targetHost.kind}`,
    `- Host value: ${runbook.targetHost.value}`,
    "",
    ...runbook.targetHost.assumptions.map((assumption) => `- ${assumption}`),
    "",
    "## Installer Command",
    "",
    "Run on: VPS",
    "",
    "```bash",
    runbook.install.command,
    "```",
    "",
    "## SSH Expectations",
    "",
    `- Unix key path: \`${runbook.ssh.keyPathUnix}\``,
    `- Windows key path: \`${runbook.ssh.keyPathWindows}\``,
    "",
    "## Recovery Commands",
    "",
    recoveryCommands,
    "",
    "## Support Bundle",
    "",
    `- Command: \`${runbook.support.bundleCommand}\``,
    `- Output pattern: \`${runbook.support.bundlePathPattern}\``,
    `- Review before sharing: ${runbook.support.reviewArtifacts.join(", ")}`,
    "",
    "## Privacy",
    "",
    "- The target host address is redacted from SSH and recovery commands.",
    "- The installer command is exact so it can be copied back into the VPS session.",
    "- The configured target username may appear because it affects installer behavior.",
    "",
  ].join("\n");
}

/**
 * Build a shareable URL with all command builder state encoded as query params.
 */
export function buildShareURL(inputs: CommandBuilderInputs): string {
  if (typeof window === "undefined") return "";
  const url = new URL(window.location.pathname, window.location.origin);
  const safeUsername = normalizeCommandUsername(inputs.username);
  url.searchParams.set("ip", inputs.ip);
  url.searchParams.set("os", inputs.os);
  if (safeUsername !== "ubuntu") {
    url.searchParams.set("user", safeUsername);
  } else {
    url.searchParams.delete("user");
  }
  url.searchParams.set("mode", inputs.mode);
  const safeRef = normalizeGitRef(inputs.ref);
  if (safeRef) {
    url.searchParams.set("ref", safeRef);
  } else {
    url.searchParams.delete("ref");
  }
  return url.toString();
}
