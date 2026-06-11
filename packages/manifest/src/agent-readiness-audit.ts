#!/usr/bin/env bun
/**
 * Safe local readiness audit for agent CLIs.
 */

import { accessSync, constants, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export type ReadinessStatus = 'pass' | 'warn' | 'fail' | 'unknown';

export interface PathStatResult {
  kind: 'missing' | 'file' | 'directory' | 'other' | 'unreadable';
  executable?: boolean;
  detail?: string;
}

export interface DirectoryEntryResult {
  name: string;
  kind: 'file' | 'directory' | 'other';
}

export interface ReadFileResult {
  kind: 'ok' | 'missing' | 'unreadable';
  content?: string;
  detail?: string;
}

export interface ReadDirResult {
  kind: 'ok' | 'missing' | 'unreadable';
  entries?: DirectoryEntryResult[];
  detail?: string;
}

export interface AgentReadinessFileSystem {
  stat(path: string): PathStatResult;
  readFile(path: string): ReadFileResult;
  readDir(path: string): ReadDirResult;
}

export interface CommandRunResult {
  status: number | null;
  stdout: string;
  stderr: string;
  error?: string;
}

export interface AgentReadinessCommandRunner {
  run(commandPath: string, args: string[], timeoutMs: number): CommandRunResult;
}

export interface CliCheckResult {
  status: ReadinessStatus;
  command: string;
  path?: string;
  aliases: Record<string, string | undefined>;
  version?: string;
  detail: string;
}

export interface ComponentResult {
  status: ReadinessStatus;
  detail: string;
  paths: string[];
}

export interface AgentToolReport {
  id: 'claude' | 'codex' | 'gemini';
  displayName: string;
  status: ReadinessStatus;
  docsUrl: string;
  command: string;
  aliases: string[];
  cli: CliCheckResult;
  auth?: ComponentResult;
  config?: ComponentResult;
  nextActions: string[];
}

export interface AgentReadinessReport {
  ok: boolean;
  generatedAt: string;
  home: string;
  summary: Record<ReadinessStatus, number>;
  tools: AgentToolReport[];
  redaction: {
    secretValuesIncluded: false;
    note: string;
  };
}

export interface BuildAgentReadinessOptions {
  home: string;
  env?: Record<string, string | undefined>;
  pathEntries?: string[];
  gtbiBinDir?: string;
  fileSystem?: AgentReadinessFileSystem;
  commandRunner?: AgentReadinessCommandRunner;
  collectVersions?: boolean;
  generatedAt?: string;
}

interface AuthFileCandidate {
  label: string;
  path: string;
  json: boolean;
}

interface ProviderDefinition {
  id: 'claude' | 'codex' | 'gemini';
  displayName: string;
  command: string;
  aliases: string[];
  docsUrl: string;
  authFiles: (context: PathContext) => AuthFileCandidate[];
  configFiles: (context: PathContext) => AuthFileCandidate[];
  envCredentials: string[];
  nextActions: string[];
}

interface PathContext {
  home: string;
  env: Record<string, string | undefined>;
}

interface JsonProbe {
  status: ReadinessStatus;
  path: string;
  detail: string;
  exists: boolean;
}

interface CliOptions {
  home: string;
  pathEntries?: string[];
  json: boolean;
  quiet: boolean;
  collectVersions: boolean;
}

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');
const STATUS_RANK: Record<ReadinessStatus, number> = {
  pass: 0,
  warn: 1,
  unknown: 2,
  fail: 3,
};

class NodeReadinessFileSystem implements AgentReadinessFileSystem {
  stat(path: string): PathStatResult {
    try {
      const stat = statSync(path);
      const kind = stat.isFile() ? 'file' : stat.isDirectory() ? 'directory' : 'other';
      let executable = false;
      if (kind === 'file') {
        try {
          accessSync(path, constants.X_OK);
          executable = true;
        } catch {
          executable = false;
        }
      }
      return { kind, executable };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }

  readFile(path: string): ReadFileResult {
    try {
      return { kind: 'ok', content: readFileSync(path, 'utf8') };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }

  readDir(path: string): ReadDirResult {
    try {
      const entries = readdirSync(path, { withFileTypes: true }).map((entry) => ({
        name: entry.name,
        kind: entry.isDirectory() ? 'directory' as const : entry.isFile() ? 'file' as const : 'other' as const,
      }));
      return { kind: 'ok', entries };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }
}

class SpawnCommandRunner implements AgentReadinessCommandRunner {
  run(commandPath: string, args: string[], timeoutMs: number): CommandRunResult {
    const result = spawnSync(commandPath, args, {
      encoding: 'utf8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024,
    });
    return {
      status: result.status,
      stdout: result.stdout ?? '',
      stderr: result.stderr ?? '',
      error: result.error?.message,
    };
  }
}

function errorCode(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null && 'code' in error
    ? String((error as { code?: unknown }).code)
    : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function statusMax(statuses: ReadinessStatus[]): ReadinessStatus {
  return statuses.reduce<ReadinessStatus>(
    (max, status) => (STATUS_RANK[status] > STATUS_RANK[max] ? status : max),
    'pass'
  );
}

function statusRank(status: ReadinessStatus): number {
  return STATUS_RANK[status];
}

function isStatus(status: ReadinessStatus, expected: ReadinessStatus): boolean {
  return statusRank(status) - statusRank(expected) === 0;
}

function unique(values: Array<string | undefined>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    if (!value) continue;
    if (seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }
  return result;
}

function redactPath(path: string, home: string): string {
  const normalizedHome = resolve(home);
  const normalizedPath = resolve(path);
  if (normalizedPath === normalizedHome) return '$HOME';
  if (normalizedPath.startsWith(`${normalizedHome}/`)) {
    return `$HOME/${normalizedPath.slice(normalizedHome.length + 1)}`;
  }
  return normalizedPath;
}

function pathContext(home: string, env: Record<string, string | undefined>): PathContext {
  return { home: resolve(home), env };
}

function xdgConfigHome(context: PathContext): string {
  return context.env.XDG_CONFIG_HOME ? resolve(context.env.XDG_CONFIG_HOME) : join(context.home, '.config');
}


function credentialEnvPresent(env: Record<string, string | undefined>, names: string[]): string[] {
  return names.filter((name) => Boolean(env[name]?.trim()));
}

function providerDefinitions(): ProviderDefinition[] {
  return [
    {
      id: 'claude',
      displayName: 'Claude Code',
      command: 'claude',
      aliases: ['cc'],
      docsUrl: 'https://code.claude.com/docs/en/authentication',
      authFiles: (context) => {
        const claudeConfigDir = context.env.CLAUDE_CONFIG_DIR
          ? resolve(context.env.CLAUDE_CONFIG_DIR)
          : join(xdgConfigHome(context), 'claude-code');
        return [
          { label: 'Claude OAuth credentials', path: join(context.home, '.claude', '.credentials.json'), json: true },
          { label: 'Claude Code auth file', path: join(claudeConfigDir, 'auth.json'), json: true },
        ];
      },
      configFiles: (context) => [
        { label: 'Claude session state', path: join(context.home, '.claude.json'), json: true },
        { label: 'Claude user settings', path: join(context.home, '.claude', 'settings.json'), json: true },
        { label: 'Claude config settings', path: join(xdgConfigHome(context), 'claude', 'settings.json'), json: true },
        { label: 'Claude Code config settings', path: join(xdgConfigHome(context), 'claude-code', 'settings.json'), json: true },
      ],
      envCredentials: ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN'],
      nextActions: [
        'Run `claude` and complete browser sign-in; use `/login` inside Claude Code to switch accounts.',
        'For headless environments, run `claude setup-token` and set `CLAUDE_CODE_OAUTH_TOKEN`.',
      ],
    },
    {
      id: 'codex',
      displayName: 'Codex CLI',
      command: 'codex',
      aliases: ['cod'],
      docsUrl: 'https://developers.openai.com/codex/cli',
      authFiles: (context) => {
        const codexHome = context.env.CODEX_HOME ? resolve(context.env.CODEX_HOME) : join(context.home, '.codex');
        return [
          { label: 'Codex auth file', path: join(codexHome, 'auth.json'), json: true },
        ];
      },
      configFiles: (context) => {
        const codexHome = context.env.CODEX_HOME ? resolve(context.env.CODEX_HOME) : join(context.home, '.codex');
        return [
          { label: 'Codex auth file', path: join(codexHome, 'auth.json'), json: true },
        ];
      },
      envCredentials: ['OPENAI_API_KEY'],
      nextActions: [
        'Run `codex` and complete the first-run sign-in prompt with a ChatGPT account or API key.',
        'Upgrade with `bun install -g @openai/codex@latest` if the installed CLI is stale.',
      ],
    },
    {
      id: 'gemini',
      displayName: 'Gemini CLI',
      command: 'gemini',
      aliases: ['gmi'],
      docsUrl: 'https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html',
      authFiles: (context) => {
        const geminiHome = context.env.GEMINI_HOME ? resolve(context.env.GEMINI_HOME) : join(context.home, '.gemini');
        return [
          { label: 'Gemini settings and OAuth state', path: join(geminiHome, 'settings.json'), json: true },
          { label: 'Gemini OAuth credentials cache', path: join(geminiHome, 'oauth_creds.json'), json: true },
        ];
      },
      configFiles: (context) => {
        const geminiHome = context.env.GEMINI_HOME ? resolve(context.env.GEMINI_HOME) : join(context.home, '.gemini');
        return [
          { label: 'Gemini settings', path: join(geminiHome, 'settings.json'), json: true },
        ];
      },
      envCredentials: ['GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS'],
      nextActions: [
        'Run `gemini` and choose an authentication method, or use `/auth` inside Gemini CLI to change methods.',
        'Use the Google account tied to a Google AI Pro or Ultra subscription when using Login with Google.',
      ],
    },
  ];
}

function executableSearchDirs(home: string, options: BuildAgentReadinessOptions): string[] {
  return unique([
    ...managedExecutableDirs(home, options),
    ...pathSearchDirs(options),
  ]).map(resolveLookupRoot);
}

function managedExecutableDirs(home: string, options: BuildAgentReadinessOptions): string[] {
  const env = options.env ?? process.env;
  return unique([
    options.gtbiBinDir,
    env.GTBI_BIN_DIR,
    join(home, '.local', 'bin'),
    join(home, '.bun', 'bin'),
    join(home, '.cargo', 'bin'),
  ]);
}

function pathSearchDirs(options: BuildAgentReadinessOptions): string[] {
  const env = options.env ?? process.env;
  return options.pathEntries ?? (env.PATH ?? '').split(':').filter(Boolean);
}

function resolveLookupRoot(path: string): string {
  return resolve(path);
}

function findExecutable(
  command: string,
  aliases: string[],
  options: BuildAgentReadinessOptions,
  fs: AgentReadinessFileSystem
): CliCheckResult {
  const dirs = executableSearchDirs(options.home, options);
  const aliasDirs = managedExecutableDirs(options.home, options).map(resolveLookupRoot);
  const aliasesFound: Record<string, string | undefined> = {};
  let commandPath: string | undefined;

  for (const candidate of [command, ...aliases]) {
    const searchDirs = candidate === command ? dirs : aliasDirs;
    for (const dir of searchDirs) {
      const path = join(dir, candidate);
      const stat = fs.stat(path);
      if (stat.kind === 'file' && stat.executable) {
        if (candidate === command && !commandPath) {
          commandPath = path;
        } else if (candidate !== command && !aliasesFound[candidate]) {
          aliasesFound[candidate] = path;
        }
        break;
      }
    }
  }

  if (!commandPath) {
    return {
      status: 'fail',
      command,
      aliases: aliasesFound,
      detail: `${command} was not found in GTBI or PATH bin directories`,
    };
  }

  return {
    status: 'pass',
    command,
    path: commandPath,
    aliases: aliasesFound,
    detail: `${command} is executable at ${commandPath}`,
  };
}

function attachVersion(
  cli: CliCheckResult,
  runner: AgentReadinessCommandRunner,
  collectVersions: boolean
): CliCheckResult {
  if (!collectVersions || !cli.path) return cli;
  const result = runner.run(cli.path, ['--version'], 4000);
  if (result.status === 0) {
    const version = firstOutputLine(result.stdout || result.stderr);
    return {
      ...cli,
      version,
      detail: version ? `${cli.detail}; version: ${version}` : `${cli.detail}; version command returned no output`,
    };
  }
  return {
    ...cli,
    detail: `${cli.detail}; version unavailable${result.error ? `: ${result.error}` : ''}`,
  };
}

function firstOutputLine(output: string): string | undefined {
  const line = output.split(/\r?\n/).map((part) => part.trim()).find(Boolean);
  return line ? line.slice(0, 160) : undefined;
}

function parseJsonProbe(candidate: AuthFileCandidate, fs: AgentReadinessFileSystem, home: string): JsonProbe {
  const read = fs.readFile(candidate.path);
  if (read.kind === 'missing') {
    return {
      status: 'warn',
      path: candidate.path,
      detail: `${candidate.label} is missing at ${redactPath(candidate.path, home)}`,
      exists: false,
    };
  }
  if (read.kind === 'unreadable') {
    return {
      status: 'unknown',
      path: candidate.path,
      detail: `${candidate.label} could not be read at ${redactPath(candidate.path, home)}: ${read.detail ?? 'permission denied'}`,
      exists: true,
    };
  }
  if (candidate.json) {
    try {
      JSON.parse(read.content ?? '');
    } catch (error) {
      return {
        status: 'fail',
        path: candidate.path,
        detail: `${candidate.label} is malformed JSON at ${redactPath(candidate.path, home)}: ${errorMessage(error)}`,
        exists: true,
      };
    }
  }
  return {
    status: 'pass',
    path: candidate.path,
    detail: `${candidate.label} is present and parseable at ${redactPath(candidate.path, home)}`,
    exists: true,
  };
}

function evaluateAuth(
  definition: ProviderDefinition,
  context: PathContext,
  fs: AgentReadinessFileSystem
): ComponentResult {
  const envCreds = credentialEnvPresent(context.env, definition.envCredentials);
  const probes = definition.authFiles(context).map((candidate) => parseJsonProbe(candidate, fs, context.home));
  const presentProbe = probes.find((probe) => isStatus(probe.status, 'pass'));
  const failedProbe = probes.find((probe) => isStatus(probe.status, 'fail'));
  const unreadableProbe = probes.find((probe) => isStatus(probe.status, 'unknown'));
  const paths = probes.map((probe) => probe.path);

  if (failedProbe) {
    return {
      status: 'fail',
      detail: failedProbe.detail,
      paths,
    };
  }
  if (envCreds.length > 0) {
    return {
      status: 'pass',
      detail: `credential environment variable is set (${envCreds.join(', ')}); value not inspected`,
      paths,
    };
  }
  if (presentProbe) {
    return {
      status: 'pass',
      detail: presentProbe.detail,
      paths,
    };
  }
  if (unreadableProbe) {
    return {
      status: 'unknown',
      detail: unreadableProbe.detail,
      paths,
    };
  }
  return {
    status: 'warn',
    detail: `no ${definition.displayName} auth artifact was found`,
    paths,
  };
}

function evaluateConfig(
  definition: ProviderDefinition,
  context: PathContext,
  fs: AgentReadinessFileSystem
): ComponentResult {
  const probes = definition.configFiles(context).map((candidate) => parseJsonProbe(candidate, fs, context.home));
  const failedProbe = probes.find((probe) => isStatus(probe.status, 'fail'));
  const unreadableProbe = probes.find((probe) => isStatus(probe.status, 'unknown'));
  const presentCount = probes.filter((probe) => probe.exists && isStatus(probe.status, 'pass')).length;

  if (failedProbe) {
    return {
      status: 'fail',
      detail: failedProbe.detail,
      paths: probes.map((probe) => probe.path),
    };
  }
  if (unreadableProbe) {
    return {
      status: 'unknown',
      detail: unreadableProbe.detail,
      paths: probes.map((probe) => probe.path),
    };
  }
  return {
    status: 'pass',
    detail: presentCount > 0
      ? `${presentCount} config/auth JSON file(s) are parseable`
      : 'no malformed JSON config files detected',
    paths: probes.map((probe) => probe.path),
  };
}

function evaluateProvider(
  definition: ProviderDefinition,
  context: PathContext,
  options: BuildAgentReadinessOptions,
  fs: AgentReadinessFileSystem,
  runner: AgentReadinessCommandRunner
): AgentToolReport {
  const cli = attachVersion(
    findExecutable(definition.command, definition.aliases, options, fs),
    runner,
    options.collectVersions ?? true
  );
  const auth = evaluateAuth(definition, context, fs);
  const config = evaluateConfig(definition, context, fs);
  const status = statusMax([cli.status, auth.status, config.status]);
  const nextActions = isStatus(status, 'pass') ? [] : definition.nextActions;

  return {
    id: definition.id,
    displayName: definition.displayName,
    status,
    docsUrl: definition.docsUrl,
    command: definition.command,
    aliases: definition.aliases,
    cli,
    auth,
    config,
    nextActions,
  };
}

function summarize(tools: AgentToolReport[]): Record<ReadinessStatus, number> {
  const summary: Record<ReadinessStatus, number> = {
    pass: 0,
    warn: 0,
    fail: 0,
    unknown: 0,
  };
  for (const tool of tools) {
    summary[tool.status] += 1;
  }
  return summary;
}

export function buildAgentReadinessReport(options: BuildAgentReadinessOptions): AgentReadinessReport {
  const home = resolve(options.home);
  const env = options.env ?? process.env;
  const context = pathContext(home, env);
  const fs = options.fileSystem ?? new NodeReadinessFileSystem();
  const runner = options.commandRunner ?? new SpawnCommandRunner();
  const providerReports = providerDefinitions().map((definition) =>
    evaluateProvider(definition, context, { ...options, home }, fs, runner)
  );
  const tools = [...providerReports];
  const summary = summarize(tools);

  return {
    ok: summary.fail === 0,
    generatedAt: options.generatedAt ?? new Date().toISOString(),
    home,
    summary,
    tools,
    redaction: {
      secretValuesIncluded: false,
      note: 'The audit reports file existence, parseability, and environment variable names only; secret values and file contents are never included.',
    },
  };
}

function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = {
    home: process.env.HOME ? resolve(process.env.HOME) : process.cwd(),
    json: false,
    quiet: false,
    collectVersions: true,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    switch (arg) {
      case '--json':
        options.json = true;
        break;
      case '--quiet':
        options.quiet = true;
        break;
      case '--no-version':
        options.collectVersions = false;
        break;
      case '--home':
        i += 1;
        options.home = resolve(args[i] ?? '');
        break;
      case '--path':
        i += 1;
        options.pathEntries = (args[i] ?? '').split(':').filter(Boolean);
        break;
      case '--help':
      case '-h':
        printUsage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function printUsage(): void {
  console.log(`Usage: scripts/agent-readiness-audit.sh [--json] [--quiet] [--no-version] [--home PATH] [--path PATH]

Audits Claude Code, Codex CLI, and Gemini CLI readiness without
printing token values or auth file contents.

Options:
  --json        Emit machine-readable JSON.
  --quiet       Suppress human output.
  --no-version  Skip CLI --version probes.
  --home PATH   Audit a specific home directory.
  --path PATH   Override executable search PATH entries.
  --help, -h    Show this help.`);
}

function printHumanReport(report: AgentReadinessReport, quiet: boolean): void {
  if (quiet) return;
  console.log('GTBI agent readiness audit');
  console.log(`Home: ${report.home}`);
  console.log(`Summary: pass=${report.summary.pass} warn=${report.summary.warn} unknown=${report.summary.unknown} fail=${report.summary.fail}`);
  console.log('');

  for (const tool of report.tools) {
    console.log(`[${tool.status.toUpperCase()}] ${tool.displayName} (${tool.command})`);
    console.log(`  cli: [${tool.cli.status}] ${tool.cli.detail}`);
    if (tool.auth) {
      console.log(`  auth: [${tool.auth.status}] ${tool.auth.detail}`);
    }
    if (tool.config) {
      console.log(`  config: [${tool.config.status}] ${tool.config.detail}`);
    }
    for (const action of tool.nextActions) {
      console.log(`  next: ${action}`);
    }
    console.log(`  docs: ${tool.docsUrl}`);
  }
}

async function runCli(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const report = buildAgentReadinessReport({
    home: options.home,
    pathEntries: options.pathEntries,
    env: process.env,
    collectVersions: options.collectVersions,
    gtbiBinDir: process.env.GTBI_BIN_DIR ?? join(DEFAULT_ROOT, 'bin'),
  });

  if (options.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printHumanReport(report, options.quiet);
  }

  if (!report.ok) {
    process.exit(1);
  }
}

if (import.meta.main) {
  runCli().catch((error: unknown) => {
    console.error(errorMessage(error));
    process.exit(2);
  });
}
