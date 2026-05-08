/**
 * Command Builder
 *
 * Generates personalized SSH, installer, and post-install commands
 * based on user preferences (IP, OS, username, mode, ref).
 *
 * @see bd-31ps.4 for the full spec
 */

import type { OperatingSystem, InstallMode } from "./userPreferences";
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
): string {
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeInstallUsername(username);
  const installRef = safeRef ?? DEFAULT_INSTALL_REF;
  const userEnv = safeUsername ? `TARGET_USER="${safeUsername}" ` : "";
  const refArg = safeRef ? ` --ref "${safeRef}"` : "";
  const installerUrl = `${INSTALL_SCRIPT_BASE_URL}/${installRef}/install.sh`;

  return `curl -fsSL "${installerUrl}?$(date +%s)" | ${userEnv}bash -s -- --yes --mode ${mode}${refArg}`;
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
    command: buildInstallCommand(mode, ref, safeUsername),
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

export function buildHandoffRunbook(inputs: CommandBuilderInputs): HandoffRunbook {
  const safeRef = normalizeGitRef(inputs.ref);
  const sourceRef = safeRef ?? DEFAULT_INSTALL_REF;
  const targetUsername = normalizeCommandUsername(inputs.username);
  const redactedHost = redactedTargetHost(inputs.ip);
  const targetHostKind = classifyTargetHost(inputs.ip);
  const installCommand = buildInstallCommand(inputs.mode, safeRef, targetUsername);
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
