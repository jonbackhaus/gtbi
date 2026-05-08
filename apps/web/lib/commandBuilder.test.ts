import { describe, expect, test } from "bun:test";
import {
  buildCommands,
  buildHandoffRunbook,
  buildInstallCommand,
  buildShareURL,
  formatHandoffRunbookMarkdown,
  serializeHandoffRunbookJson,
} from "./commandBuilder";

describe("buildInstallCommand", () => {
  test("omits TARGET_USER for the default ubuntu user", () => {
    const command = buildInstallCommand("vibe", null, "ubuntu");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).toContain("--mode vibe");
  });

  test("includes TARGET_USER and --ref for a customized install", () => {
    const command = buildInstallCommand("safe", "v1.2.3", "admin");

    expect(command).toContain('TARGET_USER="admin"');
    expect(command).toContain('--ref "v1.2.3"');
    expect(command).toContain("/v1.2.3/install.sh");
    expect(command).toContain("--mode safe");
  });

  test("omits TARGET_USER when the username does not match the installer contract", () => {
    const command = buildInstallCommand("vibe", null, "Admin");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).not.toContain("Admin");
  });
});

describe("buildCommands", () => {
  test("propagates the customized username into installer and SSH commands", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "windows",
      username: "admin",
      mode: "safe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="admin"');
    expect(sshUser?.command).toContain("admin@10.20.30.40");
    expect(sshUser?.windowsCommand).toBe("ssh -i $HOME\\.ssh\\acfs_ed25519 admin@10.20.30.40");
  });

  test("falls back to ubuntu when the username input is invalid", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "mac",
      username: "bad user",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).not.toContain("TARGET_USER=");
    expect(sshUser?.label).toBe("SSH as ubuntu");
    expect(sshUser?.command).toContain("ubuntu@10.20.30.40");
  });

  test("accepts lowercase usernames with dots and hyphens", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "linux",
      username: "dev-user.1",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="dev-user.1"');
    expect(sshUser?.label).toBe("SSH as dev-user.1");
    expect(sshUser?.command).toContain("dev-user.1@10.20.30.40");
  });
});

describe("buildHandoffRunbook", () => {
  test("records the exact installer command while redacting the target host", () => {
    const runbook = buildHandoffRunbook({
      ip: "203.0.113.42",
      os: "mac",
      username: "dev-user",
      mode: "safe",
      ref: "v1.2.3",
    });

    const json = serializeHandoffRunbookJson(runbook);

    expect(runbook.schema).toBe("acfs.handoff-runbook.v1");
    expect(runbook.install.command).toContain('TARGET_USER="dev-user"');
    expect(runbook.install.command).toContain('--ref "v1.2.3"');
    expect(runbook.install.command).toContain("/v1.2.3/install.sh");
    expect(runbook.targetHost.kind).toBe("ipv4");
    expect(runbook.targetHost.value).toBe("<ipv4-target-host>");
    expect(runbook.privacy.rawTargetHostIncluded).toBe(false);
    expect(json).not.toContain("203.0.113.42");
    expect(json).toContain("<ipv4-target-host>");
  });

  test("uses a missing host placeholder when wizard state has no valid target", () => {
    const runbook = buildHandoffRunbook({
      ip: "",
      os: "windows",
      username: "bad user",
      mode: "vibe",
      ref: "bad ref",
    });

    expect(runbook.targetHost.kind).toBe("invalid_or_missing");
    expect(runbook.targetHost.value).toBe("<target-host>");
    expect(runbook.wizardSelections.targetUsername).toBe("ubuntu");
    expect(runbook.wizardSelections.sourceRef).toBe("main");
    expect(runbook.install.command).not.toContain("TARGET_USER=");
    expect(runbook.install.command).not.toContain("--ref");
  });

  test("renders a deterministic markdown handoff with support bundle references", () => {
    const runbook = buildHandoffRunbook({
      ip: "2001:db8::42",
      os: "linux",
      username: "ubuntu",
      mode: "vibe",
      ref: null,
    });

    const markdown = formatHandoffRunbookMarkdown(runbook);

    expect(markdown).toContain("# ACFS Wizard Handoff Runbook");
    expect(markdown).toContain("Schema: `acfs.handoff-runbook.v1`");
    expect(markdown).toContain("Host kind: ipv6");
    expect(markdown).toContain("ssh root@<ipv6-target-host>");
    expect(markdown).toContain("acfs support-bundle");
    expect(markdown).not.toContain("2001:db8::42");
  });
});

describe("buildShareURL", () => {
  test("drops unrelated query params from the current page URL", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding?utm_source=share",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "mac",
        username: "ubuntu",
        mode: "vibe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=mac&mode=vibe");
      expect(shareURL).not.toContain("utm_source=");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });

  test("drops usernames that the installer would reject", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "linux",
        username: "Admin",
        mode: "safe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=linux&mode=safe");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });
});
