// ============================================================
// AUTO-GENERATED FROM gtbi.manifest.yaml — DO NOT EDIT
// Regenerate: bun run generate (from packages/manifest)
// ============================================================

export interface ManifestModuleMetadata {
  id: string;
  description: string;
  category: string;
  phase: number;
  dependencies: string[];
  tags: string[];
  enabledByDefault: boolean;
  optional: boolean;
}

export type ManifestSelectionProfileId = "full" | "safe" | "vibe" | "minimal" | "agents-only" | "cloud-only" | "stack-only";

export interface ManifestSelectionProfile {
  id: ManifestSelectionProfileId;
  label: string;
  mode?: "safe" | "vibe";
  onlyModules: string[];
  onlyPhases: string[];
}

export interface ManifestProvenanceMetadata {
  gtbiVersion: string;
  manifestSha256: string;
  checksumsYamlSha256: string;
}

export const manifestProvenance = {
  gtbiVersion: "0.7.0",
  manifestSha256: "987811463dbf8d49113ec3d94182cbf7850fe6fff7dfd35e3d028bc67f736088",
  checksumsYamlSha256: "25ce7e1583490766084d5f8535771f9866ce9f2d7262762b4a31d04ba85be6d7",
} as const satisfies ManifestProvenanceMetadata;

export const manifestModules: ManifestModuleMetadata[] = [
  {
    id: "base.system",
    description: "Base packages + sane defaults",
    category: "base",
    phase: 1,
    dependencies: [],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "users.ubuntu",
    description: "Ensure target user + passwordless sudo + ssh keys",
    category: "users",
    phase: 2,
    dependencies: [],
    tags: [
      "orchestration",
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "base.filesystem",
    description: "Create workspace and GTBI directories",
    category: "filesystem",
    phase: 3,
    dependencies: [
      "users.ubuntu",
    ],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "shell.zsh",
    description: "Zsh shell package",
    category: "shell",
    phase: 4,
    dependencies: [
      "base.system",
      "base.filesystem",
    ],
    tags: [
      "critical",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "shell.omz",
    description: "Oh My Zsh + Powerlevel10k + plugins + GTBI config",
    category: "shell",
    phase: 4,
    dependencies: [
      "shell.zsh",
    ],
    tags: [
      "critical",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "cli.modern",
    description: "Modern CLI tools referenced by the zshrc intent",
    category: "cli",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.lazygit",
    description: "Lazygit (apt or binary fallback)",
    category: "tools",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.lazydocker",
    description: "Lazydocker (binary install)",
    category: "tools",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "network.tailscale",
    description: "Zero-config mesh VPN for secure remote VPS access",
    category: "network",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "networking",
      "vpn",
      "security",
      "google-sso",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "network.ssh_keepalive",
    description: "Configure SSH server keepalive to prevent VPN/NAT disconnects",
    category: "network",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "networking",
      "remote-dev",
      "ssh",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "lang.bun",
    description: "Bun runtime for JS tooling and global CLIs",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.uv",
    description: "uv Python tooling (fast venvs)",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.rust",
    description: "Rust nightly + cargo",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.go",
    description: "Go toolchain",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.nvm",
    description: "nvm + latest Node.js",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.atuin",
    description: "Atuin shell history (Ctrl-R superpowers)",
    category: "tools",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.zoxide",
    description: "Zoxide (better cd)",
    category: "tools",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.ast_grep",
    description: "ast-grep (used by UBS for syntax-aware scanning)",
    category: "tools",
    phase: 6,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.claude",
    description: "Claude Code",
    category: "agents",
    phase: 7,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.codex",
    description: "OpenAI Codex CLI",
    category: "agents",
    phase: 7,
    dependencies: [
      "lang.bun",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.gemini",
    description: "Google Gemini CLI",
    category: "agents",
    phase: 7,
    dependencies: [
      "lang.bun",
      "lang.nvm",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.opencode",
    description: "OpenCode (multi-provider agent harness)",
    category: "agents",
    phase: 7,
    dependencies: [
      "base.system",
    ],
    tags: [
      "optional",
      "agent",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "stack.dolt",
    description: "Dolt version-control database (required by bd/beads)",
    category: "stack",
    phase: 9,
    dependencies: [],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.bd",
    description: "gastownhall beads (bd) - Dolt-backed local-first issue tracker for AI agents",
    category: "stack",
    phase: 9,
    dependencies: [
      "stack.dolt",
    ],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "gtbi.workspace",
    description: "Agent workspace with tmux session and project folder",
    category: "gtbi",
    phase: 10,
    dependencies: [
      "agents.claude",
      "agents.codex",
      "agents.gemini",
      "cli.modern",
    ],
    tags: [
      "workspace",
      "agents",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "gtbi.onboard",
    description: "Onboarding TUI tutorial",
    category: "gtbi",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "gtbi.update",
    description: "GTBI update command wrapper",
    category: "gtbi",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "gtbi.nightly",
    description: "Nightly auto-update timer (systemd)",
    category: "gtbi",
    phase: 10,
    dependencies: [
      "gtbi.update",
    ],
    tags: [
      "orchestration",
      "maintenance",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "gtbi.doctor",
    description: "GTBI doctor command for health checks",
    category: "gtbi",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
];

export const manifestSelectionProfiles: ManifestSelectionProfile[] = [
  {
    id: "full",
    label: "Full",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "safe",
    label: "Safe",
    mode: "safe",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "vibe",
    label: "Vibe",
    mode: "vibe",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "minimal",
    label: "Minimal",
    onlyModules: [
      "shell.omz",
      "cli.modern",
      "lang.bun",
      "lang.uv",
      "agents.claude",
      "agents.codex",
      "agents.gemini",
      "stack.ntm",
      "stack.mcp_agent_mail",
      "stack.ultimate_bug_scanner",
      "stack.beads_rust",
      "stack.beads_viewer",
      "stack.cass",
      "stack.cm",
      "stack.dcg",
      "stack.ru",
      "stack.rch",
      "gtbi.workspace",
      "gtbi.onboard",
      "gtbi.update",
      "gtbi.doctor",
    ],
    onlyPhases: [],
  },
  {
    id: "agents-only",
    label: "Agents only",
    onlyModules: [],
    onlyPhases: [
      "agents",
    ],
  },
  {
    id: "cloud-only",
    label: "Cloud only",
    onlyModules: [
      "cloud.wrangler",
      "cloud.supabase",
      "cloud.vercel",
    ],
    onlyPhases: [],
  },
  {
    id: "stack-only",
    label: "Stack only",
    onlyModules: [],
    onlyPhases: [
      "stack",
    ],
  },
];
