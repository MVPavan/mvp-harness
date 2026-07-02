#!/usr/bin/env node
// codex-adapter — a thin, dependency-free wrapper around `codex exec`.
//
// Why this is enough: `codex exec` boots an in-process Codex app-server over the
// shared `codex-core` engine, so it produces the exact same results as the full
// `codex app-server` protocol — without any of its broker/lock machinery. Each
// invocation is its own OS process, so you can run as many concurrently as you
// like. There is nothing to serialize and nothing to "bypass".

import { spawn } from "node:child_process";
import fs from "node:fs";
import process from "node:process";

const SANDBOX_MODES = new Set(["read-only", "workspace-write", "danger-full-access"]);
const EFFORT_LEVELS = new Set(["minimal", "low", "medium", "high", "xhigh"]);
const APPROVAL_POLICIES = new Set(["untrusted", "on-failure", "on-request", "never"]);
// Codex prints `session id: <uuid>` in its startup banner (on stderr). Match the
// UUID shape (8-4-4-4-12) specifically so stray hex elsewhere on the banner can't
// be mistaken for the id.
const SESSION_ID_RE =
  /session id:\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

const HELP = `codex-run — call OpenAI Codex (gpt-5.x) via \`codex exec\`.

Usage:
  codex-run [options] "<prompt>"
  echo "<prompt>" | codex-run [options]

Options:
  -m, --model <id>       Model id (default: account/config default).
  -e, --effort <level>   Reasoning effort: ${[...EFFORT_LEVELS].join(" | ")}.
  -C, --cd <dir>         Working root for Codex (default: current directory).
  -s, --sandbox <mode>   ${[...SANDBOX_MODES].join(" | ")} (default: read-only).
  -w, --writable         Shortcut for --sandbox workspace-write (lets Codex edit files).
  -a, --approval <pol>   Approval policy: ${[...APPROVAL_POLICIES].join(" | ")} (default: Codex's own).
      --resume <id>      Continue a prior Codex session by id.
      --role <name>      Apply a role preset from roles/<name>.md (prompt + sandbox/effort/config).
      --json             Stream raw JSONL events instead of just the final answer.
      --skip-git-check   Allow running outside a git repository.
  -h, --help             Show this help.

With no inline prompt, the prompt is read from piped stdin; an inline prompt takes
precedence and stdin is ignored. Codex streams progress to stderr and prints its
final answer to stdout. Each call is independent — run several in parallel safely.`;

function fail(msg) {
  process.stderr.write(`codex-run: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = {
    model: null,
    effort: null,
    cd: null,
    sandbox: null,
    approval: null,
    resume: null,
    role: null,
    json: false,
    skipGitCheck: false,
    promptParts: [],
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) fail(`missing value for ${arg}`);
      // A leading dash means the "value" is almost certainly the next option
      // (e.g. `-m --json`); treat that as a missing value rather than swallow it.
      if (value.startsWith("-") && value !== "-") {
        fail(`missing value for ${arg} (got option '${value}')`);
      }
      return value;
    };
    switch (arg) {
      case "-h":
      case "--help":
        process.stdout.write(`${HELP}\n`);
        process.exit(0);
        break;
      case "-m":
      case "--model":
        opts.model = next();
        break;
      case "-e":
      case "--effort":
        opts.effort = next();
        break;
      case "-C":
      case "--cd":
        opts.cd = next();
        break;
      case "-s":
      case "--sandbox":
        opts.sandbox = next();
        break;
      case "-w":
      case "--writable":
        opts.sandbox = "workspace-write";
        break;
      case "-a":
      case "--approval":
        opts.approval = next();
        break;
      case "--resume":
        opts.resume = next();
        break;
      case "--role":
        opts.role = next();
        break;
      case "--json":
        opts.json = true;
        break;
      case "--skip-git-check":
        opts.skipGitCheck = true;
        break;
      case "--":
        opts.promptParts.push(...argv.slice(i + 1));
        i = argv.length;
        break;
      default:
        if (arg.startsWith("-") && arg !== "-") fail(`unknown option: ${arg}`);
        opts.promptParts.push(arg);
    }
  }
  if (opts.sandbox !== null && !SANDBOX_MODES.has(opts.sandbox)) {
    fail(`invalid --sandbox '${opts.sandbox}' (expected: ${[...SANDBOX_MODES].join(", ")})`);
  }
  if (opts.effort && !EFFORT_LEVELS.has(opts.effort)) {
    fail(`invalid --effort '${opts.effort}' (expected: ${[...EFFORT_LEVELS].join(", ")})`);
  }
  if (opts.approval && !APPROVAL_POLICIES.has(opts.approval)) {
    fail(`invalid --approval '${opts.approval}' (expected: ${[...APPROVAL_POLICIES].join(", ")})`);
  }
  return opts;
}

function buildCodexArgs(opts, prompt, roleConfigs = []) {
  const args = ["exec"];
  // `resume <id>` puts the session id in the first positional slot; the prompt
  // stays the trailing positional, so the flags in between are unambiguous.
  if (opts.resume) args.push("resume", opts.resume);
  // Drive sandbox/approval/effort via `-c key=value`: these overrides are valid
  // on both `codex exec` and `codex exec resume`, whereas the `-s`/`-a`/`-C`
  // flags are not all accepted by the resume subcommand.
  args.push("-c", `sandbox_mode=${opts.sandbox}`);
  if (opts.approval) args.push("-c", `approval_policy=${opts.approval}`);
  if (opts.effort) args.push("-c", `model_reasoning_effort=${opts.effort}`);
  // Extra `-c` overrides contributed by a role (e.g. tools.web_search=true).
  for (const override of roleConfigs) args.push("-c", override);
  if (opts.model) args.push("-m", opts.model);
  // --cd only applies to a fresh session; a resumed session keeps its own cwd.
  if (opts.cd && !opts.resume) args.push("-C", opts.cd);
  if (opts.skipGitCheck) args.push("--skip-git-repo-check");
  if (opts.json) args.push("--json");
  // Only pass an inline prompt when we have one. With no inline prompt and piped
  // stdin, Codex reads the prompt from stdin itself.
  if (prompt) args.push(prompt);
  return args;
}

// Detect stdin that actually carries data (a pipe, redirected file, or socket) vs
// a TTY or an empty descriptor like /dev/null. `process.stdin.isTTY` is `undefined`
// (not `false`) for non-TTY fds, so we stat fd 0 directly rather than trust isTTY.
function stdinHasData() {
  if (process.stdin.isTTY) return false;
  try {
    const stat = fs.fstatSync(0);
    return stat.isFIFO() || stat.isFile() || stat.isSocket();
  } catch {
    return false;
  }
}

// Role name is restricted to a safe filename charset — this also blocks path
// traversal (no `/` or `.` segments) when resolving roles/<name>.md.
const ROLE_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9-]*$/;

function listRoles() {
  try {
    return fs
      .readdirSync(new URL("../roles/", import.meta.url))
      .filter((file) => file.endsWith(".md"))
      .map((file) => file.slice(0, -3))
      .sort()
      .join(", ");
  } catch {
    return "";
  }
}

// Load a role preset: minimal `key: value` front-matter between `---` fences,
// then a prompt body. `config` is repeatable; each value is a raw `key=value`
// passed straight through as a `-c` override.
function loadRole(name) {
  if (!ROLE_NAME_RE.test(name)) fail(`invalid role name '${name}'`);
  let text;
  try {
    text = fs.readFileSync(new URL(`../roles/${name}.md`, import.meta.url), "utf8");
  } catch {
    const available = listRoles();
    fail(`unknown role '${name}'${available ? ` (available: ${available})` : ""}`);
  }
  const role = { sandbox: null, effort: null, configs: [], prompt: text.trim() };
  const frontMatter = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (frontMatter) {
    role.prompt = frontMatter[2].trim();
    for (const line of frontMatter[1].split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const sep = trimmed.indexOf(":");
      if (sep === -1) continue;
      const key = trimmed.slice(0, sep).trim();
      const value = trimmed.slice(sep + 1).trim();
      if (key === "sandbox") role.sandbox = value;
      else if (key === "effort") role.effort = value;
      else if (key === "config") role.configs.push(value);
    }
  }
  if (!role.prompt) fail(`role '${name}' has an empty prompt body`);
  return role;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const role = opts.role ? loadRole(opts.role) : null;

  // A role contributes a prompt prefix; the user's args (if any) follow as the
  // task. Preserve text as written (no trim) so whitespace-significant prompts
  // survive; a trimmed copy only decides whether a prompt is present.
  const userPrompt = opts.promptParts.join(" ");
  const promptSegments = [];
  if (role) promptSegments.push(role.prompt);
  if (userPrompt.trim().length > 0) promptSegments.push(userPrompt);
  const inlinePrompt = promptSegments.join("\n\n");
  const hasInlinePrompt = inlinePrompt.trim().length > 0;
  const pipedStdin = stdinHasData();
  if (!hasInlinePrompt && !pipedStdin) {
    fail("no prompt provided (pass it as an argument, pipe it via stdin, or use --role)");
  }

  // Resolve sandbox/effort: an explicit flag wins, else the role's default, else
  // the global default. Validate the merged result.
  opts.sandbox = opts.sandbox ?? role?.sandbox ?? "read-only";
  if (!SANDBOX_MODES.has(opts.sandbox)) {
    fail(`invalid sandbox '${opts.sandbox}' (expected: ${[...SANDBOX_MODES].join(", ")})`);
  }
  opts.effort = opts.effort ?? role?.effort ?? null;
  if (opts.effort && !EFFORT_LEVELS.has(opts.effort)) {
    fail(`invalid effort '${opts.effort}' (expected: ${[...EFFORT_LEVELS].join(", ")})`);
  }

  // stdout stays clean (Codex's answer, or raw JSONL). stderr is piped so we can
  // pass progress through live AND scan the banner for the session id. Stdin is
  // forwarded to Codex only when it is the prompt source — no inline prompt and
  // real data on stdin (pipe/file/socket). An inline prompt takes precedence and
  // stdin is ignored, so Codex can never block on a held-open descriptor (e.g.
  // `tail -f | codex-run "..."`) and stray pipe data can't contaminate the prompt.
  const forwardStdin = !hasInlinePrompt && pipedStdin;
  const child = spawn("codex", buildCodexArgs(opts, hasInlinePrompt ? inlinePrompt : null, role?.configs ?? []), {
    stdio: [forwardStdin ? "inherit" : "ignore", "inherit", "pipe"],
  });

  let sessionId = null;
  let scanBuffer = "";
  child.stderr.on("data", (chunk) => {
    process.stderr.write(chunk);
    if (sessionId) return;
    scanBuffer += chunk.toString("utf8");
    const match = scanBuffer.match(SESSION_ID_RE);
    if (match) {
      sessionId = match[1];
      scanBuffer = "";
      return;
    }
    // Keep scanning indefinitely but bound memory: retain a rolling tail large
    // enough to span a banner line split across chunks.
    if (scanBuffer.length > 8192) scanBuffer = scanBuffer.slice(-1024);
  });

  child.on("error", (err) => {
    if (err.code === "ENOENT") {
      fail("`codex` not found on PATH. Install it with `npm i -g @openai/codex` and run `codex login`.");
    }
    fail(`failed to launch codex: ${err.message}`);
  });
  child.on("close", (code, signal) => {
    if (sessionId && !opts.json) {
      process.stderr.write(`\n[codex-adapter] session ${sessionId} — resume: --resume ${sessionId} "<next prompt>"\n`);
    }
    if (signal) {
      process.stderr.write(`codex-run: codex terminated by signal ${signal}\n`);
      process.exit(1);
    }
    process.exit(code ?? 0);
  });
}

main().catch((err) => fail(err?.stack || String(err)));
