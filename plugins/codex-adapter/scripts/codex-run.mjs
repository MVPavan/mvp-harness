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
// Codex spellings that change the sandbox or bypass approvals from the flag
// level, where they outrank the runner's validated `-c sandbox_mode` override:
// `--sandbox=<m>` / `-s<m>` / `-s=<m>` (native flag forms that dodge the exact-
// token cases below), plus `--full-auto`, `--yolo`, and `--dangerously-bypass-*`
// (hidden/dangerous aliases accepted by codex exec even though its --help
// doesn't list them all). None of these may ride the pass-through lane.
const SANDBOX_BYPASS_RE = /^(-s|--sandbox\b|--yolo\b|--full-auto\b|--dangerously-bypass)/;
// Config keys that select or reshape the sandbox: the legacy `sandbox_mode` key
// plus the permission-profile keys (`default_permissions`, `permissions.*`) that
// supersede it in Codex's config resolver. Anchored form for --config / role
// `config:` values; unanchored form for pass-through tokens, whose key can sit
// after any flag spelling (`--config=...`, `-c...`).
const SANDBOX_CONFIG_KEY_RE = /^\s*"?(sandbox_mode|default_permissions|permissions)"?\s*[.=[]/;
const SANDBOX_CONFIG_TOKEN_RE = /"?(sandbox_mode|default_permissions|permissions)"?\s*[.=[]/;
// Effort/approval values the current CLI documents. Unknown values warn but are
// still forwarded: Codex silently ignores unrecognized config values, so hard-
// failing here would block every new level the CLI ships (as happened when
// gpt-5.6 added `max`/`ultra`), while forwarding silently would hide typos.
const KNOWN_EFFORTS = new Set(["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]);
const KNOWN_APPROVALS = new Set(["untrusted", "on-failure", "on-request", "never"]);
// Codex prints `session id: <uuid>` in its startup banner (on stderr). Match the
// UUID shape (8-4-4-4-12) specifically so stray hex elsewhere on the banner can't
// be mistaken for the id.
const SESSION_ID_RE =
  /session id:\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;
// Banner lines used to enrich the session footer with an audit trail of what
// actually ran (`model: gpt-...`, `sandbox: read-only [...]`).
const BANNER_MODEL_RE = /^model:\s*(\S+)/m;
const BANNER_SANDBOX_RE = /^sandbox:\s*([^\n[]+)/m;
// How much transcript to keep for failure diagnostics in quiet mode.
const TRANSCRIPT_TAIL_LINES = 60;

const HELP = `codex-run — call OpenAI Codex (gpt-5.x) via \`codex exec\`.

Usage:
  codex-run [options] "<prompt>"
  echo "<prompt>" | codex-run [options]

Options:
  -m, --model <id>       Model id (default: account/config default).
  -e, --effort <level>   Reasoning effort: ${[...KNOWN_EFFORTS].join(" | ")}
                         (model-dependent; unknown values warn and are forwarded).
  -C, --cd <dir>         Working root for Codex (default: current directory).
  -s, --sandbox <mode>   ${[...SANDBOX_MODES].join(" | ")} (default: read-only).
  -w, --writable         Shortcut for --sandbox workspace-write (lets Codex edit files).
  -a, --approval <pol>   Approval policy: ${[...KNOWN_APPROVALS].join(" | ")} (default: Codex's own).
  -c, --config <k=v>     Extra Codex config override (repeatable; passed through as -c).
      --review           Run Codex's native code-review harness (\`codex exec review\`).
                         Target the diff via forwarded flags: --uncommitted, --base=<branch>, --commit=<sha>.
      --resume <id>      Continue a prior Codex session by id.
      --role <name>      Apply a role preset from roles/<name>.md (prompt + sandbox/effort/config).
      --json             Stream raw JSONL events instead of just the final answer.
      --progress         Stream Codex's progress transcript live (default when stderr is a TTY).
      --quiet            Suppress the transcript; print only the answer and a one-line session
                         footer (default when stderr is NOT a TTY, e.g. under an agent). On
                         failure, the last ${TRANSCRIPT_TAIL_LINES} transcript lines are still shown.
      --skip-git-check   Allow running outside a git repository.
  -h, --help             Show this help.

Options the runner doesn't recognize are forwarded verbatim to \`codex exec\`
(e.g. --output-schema=schema.json, -o=answer.txt, --ephemeral, --add-dir=<dir>).
Use the --flag=value form for forwarded flags that take a value — a space-separated
value would be read as prompt text. Forwarded flags land after the subcommand, so
flags that exist only on plain \`codex exec\` (e.g. --add-dir) don't combine with
--review/--resume.

With no inline prompt, the prompt is read from piped stdin; an inline prompt takes
precedence and stdin is ignored. Codex prints its final answer to stdout; progress
goes to stderr only when streaming (see --progress/--quiet). Each call is
independent — run several in parallel safely.`;

function fail(msg) {
  process.stderr.write(`codex-run: ${msg}\n`);
  process.exit(2);
}

function warn(msg) {
  process.stderr.write(`codex-run: ${msg}\n`);
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
    review: false,
    json: false,
    progress: null,
    skipGitCheck: false,
    configs: [],
    passthrough: [],
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
      case "-c":
      case "--config": {
        const override = next();
        if (!override.includes("=")) fail(`--config expects key=value (got '${override}')`);
        // A -c placed after the runner's own sandbox override would win inside
        // Codex, silently defeating the validated fail-closed sandbox — via the
        // legacy key or the permission-profile keys that supersede it. Route all
        // sandbox choices through -s/-w instead.
        if (SANDBOX_CONFIG_KEY_RE.test(override)) {
          fail(`sandbox/permission config must go through -s/--sandbox (or -w), not --config '${override}'`);
        }
        opts.configs.push(override);
        break;
      }
      case "--review":
        opts.review = true;
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
      case "--progress":
        opts.progress = true;
        break;
      case "--quiet":
        opts.progress = false;
        break;
      case "--skip-git-check":
        opts.skipGitCheck = true;
        break;
      case "--":
        opts.promptParts.push(...argv.slice(i + 1));
        i = argv.length;
        break;
      default:
        if (arg.startsWith("-") && arg !== "-") {
          // Not a runner option — forward it verbatim so new `codex exec` flags
          // work without an adapter release. Single-token forwarding only:
          // valued flags must use the --flag=value form, because a space-
          // separated value would land in the prompt instead.
          //
          // Exception: any spelling that smuggles a sandbox or approvals
          // escalation — a native flag form (see SANDBOX_BYPASS_RE) or a
          // sandbox-shaping config override (`--config=sandbox_mode=...`,
          // `-cdefault_permissions=...`) — would land after the runner's
          // validated sandbox -c, or outrank it at the flag level, and win
          // inside Codex.
          if (SANDBOX_BYPASS_RE.test(arg) || SANDBOX_CONFIG_TOKEN_RE.test(arg)) {
            fail(`use -s/--sandbox (or -w) to set the sandbox, not '${arg}'`);
          }
          warn(`forwarding unrecognized option '${arg}' to codex exec`);
          opts.passthrough.push(arg);
          break;
        }
        opts.promptParts.push(arg);
    }
  }
  return opts;
}

function buildCodexArgs(opts, prompt, roleConfigs = []) {
  const args = ["exec"];
  // `review` runs Codex's native code-review harness; `resume <id>` continues a
  // prior session. Both occupy the subcommand slot right after `exec`; the prompt
  // stays the trailing positional, so the flags in between are unambiguous.
  if (opts.review) args.push("review");
  else if (opts.resume) args.push("resume", opts.resume);
  // Sandbox is enforced on two levels. The native `-s` flag is the strongest:
  // it outranks every config override, including permission-profile keys
  // (`default_permissions`) that supersede `sandbox_mode` in the config
  // resolver — but only plain `codex exec` accepts it (`exec resume` /
  // `exec review` don't). The `-c sandbox_mode=` override below is valid on
  // all three and covers the subcommands.
  if (!opts.resume && !opts.review) args.push("-s", opts.sandbox);
  // Drive approval/effort via `-c key=value`: these overrides are valid on
  // `codex exec` and its subcommands, whereas flags like `-a`/`-C` are not all
  // accepted by `exec resume` / `exec review`.
  args.push("-c", `sandbox_mode=${opts.sandbox}`);
  if (opts.approval) args.push("-c", `approval_policy=${opts.approval}`);
  if (opts.effort) args.push("-c", `model_reasoning_effort=${opts.effort}`);
  // Extra `-c` overrides: the role's first, then explicit --config flags, so a
  // caller can override a role default (for the same key, the later -c wins).
  for (const override of roleConfigs) args.push("-c", override);
  for (const override of opts.configs) args.push("-c", override);
  if (opts.model) args.push("-m", opts.model);
  // --cd only applies to a fresh plain session: a resumed session keeps its own
  // cwd, and `exec review` has no -C flag (the runner spawns in opts.cd instead).
  if (opts.cd && !opts.resume && !opts.review) args.push("-C", opts.cd);
  if (opts.skipGitCheck) args.push("--skip-git-repo-check");
  if (opts.json) args.push("--json");
  // Options the runner didn't recognize, forwarded verbatim (--flag=value form).
  args.push(...opts.passthrough);
  // Only pass an inline prompt when we have one. With no inline prompt and piped
  // stdin, plain `codex exec` reads the prompt from stdin itself — but
  // `exec review` only reads stdin when the positional is an explicit `-`.
  // The `--` guarantees Codex parses the prompt as a positional: without it, a
  // prompt starting with a dash (e.g. via the runner's own `--` delimiter)
  // would be parsed as a Codex flag — an escalation vector.
  if (prompt) args.push("--", prompt);
  else if (opts.review && opts.forwardStdin) args.push("--", "-");
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
      else if (key === "config") {
        // Role configs are emitted after the runner's validated sandbox -c and
        // would win inside Codex — via the legacy key or the permission-profile
        // keys. The `sandbox:` front-matter key is the legitimate channel (an
        // explicit -s/-w flag still overrides it).
        if (SANDBOX_CONFIG_KEY_RE.test(value)) {
          fail(`role '${name}': set the sandbox via the 'sandbox:' front-matter key, not 'config: ${value}'`);
        }
        role.configs.push(value);
      }
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
  // `--review` may run bare: Codex's native review harness has its own default
  // instructions; an inline prompt (or role) becomes custom review instructions.
  if (!hasInlinePrompt && !pipedStdin && !opts.review) {
    fail("no prompt provided (pass it as an argument, pipe it via stdin, or use --role)");
  }
  if (opts.review && opts.resume) {
    fail("--review starts a fresh review turn and cannot be combined with --resume");
  }

  // Resolve sandbox/effort: an explicit flag wins, else the role's default, else
  // the global default. Validate the merged result.
  opts.sandbox = opts.sandbox ?? role?.sandbox ?? "read-only";
  // Sandbox stays hard-validated: Codex silently ignores unrecognized config
  // values, so a typo here would fall back to the user's config.toml default —
  // which may be workspace-write. Fail closed.
  if (!SANDBOX_MODES.has(opts.sandbox)) {
    fail(`invalid sandbox '${opts.sandbox}' (expected: ${[...SANDBOX_MODES].join(", ")})`);
  }
  opts.effort = opts.effort ?? role?.effort ?? null;
  // Effort/approval are warn-and-forward (see KNOWN_EFFORTS note above): unknown
  // values still reach Codex, but Codex swallows bad ones silently, so the
  // warning is the only signal a typo gets.
  if (opts.effort && !KNOWN_EFFORTS.has(opts.effort)) {
    warn(`effort '${opts.effort}' is not a known level (${[...KNOWN_EFFORTS].join(", ")}); forwarding as-is`);
  }
  if (opts.approval && !KNOWN_APPROVALS.has(opts.approval)) {
    warn(`approval '${opts.approval}' is not a known policy (${[...KNOWN_APPROVALS].join(", ")}); forwarding as-is`);
  }

  // stdout stays clean (Codex's answer, or raw JSONL). stderr is piped so we can
  // pass progress through live AND scan the banner for the session id. Stdin is
  // forwarded to Codex only when it is the prompt source — no inline prompt and
  // real data on stdin (pipe/file/socket). An inline prompt takes precedence and
  // stdin is ignored, so Codex can never block on a held-open descriptor (e.g.
  // `tail -f | codex-run "..."`) and stray pipe data can't contaminate the prompt.
  const forwardStdin = !hasInlinePrompt && pipedStdin;
  opts.forwardStdin = forwardStdin;
  // Note: an inline prompt (or role) wins over piped stdin by design (see HELP).
  // No warning here — agent harnesses routinely run commands with a pipe-like
  // stdin that carries no data, which would make it fire on every call.

  // Stream the progress transcript only when a human is watching (stderr is a
  // TTY). Under an agent the transcript is pure context cost — suppress it and
  // report a one-line audit footer instead, keeping a bounded tail for failure
  // diagnostics. `--progress`/`--quiet` force either mode.
  const streamProgress = opts.progress ?? process.stderr.isTTY === true;
  // A bad cwd makes spawn throw ENOENT before the executable is even resolved,
  // which the error handler below would misread as "codex not on PATH".
  if (opts.review && opts.cd && !fs.existsSync(opts.cd)) {
    fail(`--cd directory not found: ${opts.cd}`);
  }
  const child = spawn("codex", buildCodexArgs(opts, hasInlinePrompt ? inlinePrompt : null, role?.configs ?? []), {
    stdio: [forwardStdin ? "inherit" : "ignore", "inherit", "pipe"],
    // `exec review` has no -C flag; honor --cd there by spawning in that directory.
    ...(opts.review && opts.cd ? { cwd: opts.cd } : {}),
  });

  let sessionId = null;
  let bannerModel = null;
  let bannerSandbox = null;
  let scanBuffer = "";
  let scanDone = false;
  // Quiet mode keeps a bounded transcript tail for failure diagnostics.
  let tailBuffer = "";
  child.stderr.on("data", (chunk) => {
    const text = chunk.toString("utf8");
    if (streamProgress) {
      process.stderr.write(chunk);
    } else {
      tailBuffer += text;
      if (tailBuffer.length > 65536) tailBuffer = tailBuffer.slice(-32768);
    }
    if (scanDone) return;
    scanBuffer += text;
    if (!sessionId) sessionId = scanBuffer.match(SESSION_ID_RE)?.[1] ?? null;
    if (!bannerModel) bannerModel = scanBuffer.match(BANNER_MODEL_RE)?.[1] ?? null;
    if (!bannerSandbox) bannerSandbox = scanBuffer.match(BANNER_SANDBOX_RE)?.[1]?.trim() ?? null;
    if (sessionId && bannerModel && bannerSandbox) {
      scanDone = true;
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
    const failed = signal !== null || (code !== null && code !== 0);
    // In quiet mode the transcript was withheld; on failure it is the evidence.
    if (!streamProgress && failed && tailBuffer.length > 0) {
      const tail = tailBuffer.replace(/\n+$/, "").split("\n").slice(-TRANSCRIPT_TAIL_LINES).join("\n");
      process.stderr.write(
        `\n[codex-adapter] codex exited ${signal ? `on signal ${signal}` : `with code ${code}`}; transcript tail:\n${tail}\n`,
      );
    }
    if (sessionId && !opts.json) {
      const meta = [bannerModel && `model ${bannerModel}`, bannerSandbox].filter(Boolean).join(", ");
      process.stderr.write(
        `\n[codex-adapter] session ${sessionId}${meta ? ` (${meta})` : ""} — resume: --resume ${sessionId} "<next prompt>"\n`,
      );
    }
    if (signal) {
      process.stderr.write(`codex-run: codex terminated by signal ${signal}\n`);
      process.exit(1);
    }
    process.exit(code ?? 0);
  });
}

main().catch((err) => fail(err?.stack || String(err)));
