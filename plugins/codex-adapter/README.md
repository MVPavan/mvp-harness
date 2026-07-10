# codex-adapter

Call **OpenAI Codex** (gpt-5.x) from **Claude Code** — a clean, dependency-free
plugin built around a single primitive: `codex exec`.

It exists because the official [`codex-plugin-cc`](https://github.com/openai/codex-plugin-cc)
wraps the experimental `codex app-server` protocol behind a broker that
serializes calls to **one Codex at a time**. This rebuild drops all of that.

## Why `codex exec` is enough

Codex has one shared engine (`codex-core`). Every surface is a facade over it:

```text
@openai/codex-sdk ──spawns──> codex exec ──boots──> in-process app-server ──> codex-core
codex (TUI) ─────────────────────────────────────> in-process app-server ──> codex-core
codex app-server ────────────────────────────────> codex-core   (the full protocol, lid off)
codex mcp-server ────────────────────────────────> codex-core   (parallel, exposes 2 tools)
```

So `codex exec` runs on the **same `codex-core` engine** as `codex app-server` —
it's the stable, documented non-interactive surface over that engine, not a
reduced one. `app-server` is the richer *protocol*: it adds **token-level
streaming**, **mid-turn interactive approvals**, **steer/interrupt**, and
**thread fork/rollback/compact**. Those are *interaction* features, not a
different result — for one-shot delegation `exec` produces the same turn outcome
with none of the ceremony.

And because each `codex exec` is its own OS process, **concurrency is free** —
run as many as you want at once. There is no lock to bypass.

## Requirements

- [Codex CLI](https://developers.openai.com/codex) on your `PATH`
  (`npm i -g @openai/codex`), authenticated via `codex login`.
- Node.js ≥ 18.

## Install as a Claude Code plugin

Two commands, on any machine:

```text
/plugin marketplace add MVPavan/codex-adapter
/plugin install codex-adapter@codex-adapter
```

Run `/plugin update codex-adapter@codex-adapter` to pick up new versions.

**Prerequisite:** the [Codex CLI](https://developers.openai.com/codex) must be on
your `PATH` (`npm i -g @openai/codex`) and authenticated (`codex login`). The
runner exits with a clear message if it isn't — the plugin can't install it for you.

You then get:

- **`/codex <prompt>`** — delegate a free-form task or question to Codex.
- **`/codex-review`**, **`/codex-diagnose`**, **`/codex-implement`**,
  **`/codex-research`**, **`/codex-critique`** — the role presets (see [Roles](#roles)).
- **`/codex-check`** — verify the Codex CLI is installed and authenticated.
- The **`codex-runner`** skill lets Claude delegate to Codex on its own,
  including running several instances in parallel.

For local development, skip the marketplace and load the repo directly:
`claude --plugin-dir /path/to/codex-adapter`.

## Use the runner directly

```bash
# Ask Codex a question about the current repo (read-only)
node scripts/codex-run.mjs "Explain how auth is wired in this repo"

# Let Codex make changes
node scripts/codex-run.mjs --writable "Fix the failing test in tests/auth_test.py"

# Pick a model and effort; pipe the prompt in
echo "Review this diff for bugs" | node scripts/codex-run.mjs -m gpt-5.6-luna -e high

# Continue a previous Codex session.
# Every run prints a resume hint to stderr, e.g.:
#   [codex-adapter] session 019ec... — resume: --resume 019ec... "<next prompt>"
node scripts/codex-run.mjs --resume <session-id> "Now add tests for that fix"

# Raw event stream (JSONL) for progress / capturing the session id
node scripts/codex-run.mjs --json "Summarize the README"
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-m, --model <id>` | account default | Model id |
| `-e, --effort <level>` | — | `low\|medium\|high\|xhigh\|max\|ultra` (model-dependent; unknown values warn and are forwarded) |
| `-C, --cd <dir>` | cwd | Working root for Codex |
| `-s, --sandbox <mode>` | `read-only` | `read-only\|workspace-write\|danger-full-access` |
| `-w, --writable` | — | Shortcut for `--sandbox workspace-write` |
| `-a, --approval <pol>` | Codex default | `untrusted\|on-failure\|on-request\|never` |
| `-c, --config <k=v>` | — | Extra Codex config override, repeatable (passed through as `-c`) |
| `--review` | — | Run Codex's native code-review harness (see [Native code review](#native-code-review)) |
| `--resume <id>` | — | Continue a prior session by id |
| `--role <name>` | — | Apply a role preset (see [Roles](#roles)) |
| `--json` | — | Stream raw JSONL events |
| `--skip-git-check` | — | Allow running outside a git repo |

**Pass-through:** any option the runner doesn't recognize is forwarded verbatim to
`codex exec` — e.g. `--output-schema=schema.json`, `-o=answer.txt`, `--ephemeral`,
`--add-dir=<dir>` — so new CLI flags work without an adapter release. Use the
`--flag=value` form for forwarded flags that take a value (a space-separated value
would be read as prompt text). The runner warns on stderr when it forwards, so
typos stay visible. With `--review`/`--resume`, forwarded flags land after the
subcommand — flags that exist only on plain `codex exec` (e.g. `--add-dir`) don't
combine with those modes. Sandbox values remain strictly validated: Codex silently
ignores unrecognized config values, and a typo'd sandbox would otherwise fall back
to your `config.toml` default — which may be `workspace-write`.

**Sandbox enforcement:** there are exactly two legitimate escalation channels —
an explicit `-s`/`-w` flag, and a role's `sandbox:` front-matter (the curated
presets, e.g. `implement`; an explicit flag still overrides). The validated sandbox is applied on two levels — plain
`codex exec` gets the native `-s <mode>` flag (which outranks every config
override, including the permission-profile keys that supersede `sandbox_mode` in
Codex's config resolver), and all modes get `-c sandbox_mode=<mode>` (the only
form `exec resume`/`exec review` accept). Spellings that would smuggle an
escalation past it are rejected outright: native sandbox/approval flags
(`--sandbox=...`, `-s<mode>`, `--yolo`, `--full-auto`, `--dangerously-bypass-*`)
and sandbox-shaping config keys (`sandbox_mode`, `default_permissions`,
`permissions.*`) in `--config`, role `config:` lines, or pass-through tokens.
This is mistake-proofing for the common paths, not a security boundary: a caller
who fully controls the command line or `$CODEX_HOME` can still escalate (e.g. a
forwarded `--profile=<name>` whose profile reshapes permissions on
`--review`/`--resume`, where the native `-s` flag doesn't exist). Treat the
runner's invoker as trusted.

### Reading the output

The two streams are kept strictly separate:

- **stdout** — Codex's final answer, and nothing else.
- **stderr** — the startup banner (including the `session id`), the live
  progress transcript, tool-call traces, and the `[codex-adapter]` resume hint.

Pick the stream you want:

| You want… | Do this |
|-----------|---------|
| Just the answer | read **stdout**, discard stderr: `node scripts/codex-run.mjs "…" 2>/dev/null` |
| Answer + live progress (human) | run normally — progress on stderr, answer on stdout |
| A machine-readable event stream | add `--json` and parse the final agent-message event |

**Why the answer can look doubled:** in human mode `codex exec` echoes the agent
message in its stderr transcript (`codex\n<answer>`) *and* prints the final
answer on stdout. If you merge the streams — a terminal, `2>&1`, or a tool that
captures both — you see it twice. Keep the streams separate (or read stdout
only) and the answer appears exactly once.

## Roles

A **role** is a reusable preset — a curated prompt plus default sandbox/effort and
optional config — stored as `roles/<name>.md`. Pass `--role <name>` to apply one;
the role's prompt is prepended to whatever task you give (built-in roles write theirs as XML-tagged blocks tuned for GPT-5.x). Roles are opt-in: with no
`--role`, the runner behaves exactly as the free-form examples above.

Built-in roles:

| Role | Sandbox | Effort | Purpose |
|------|---------|--------|---------|
| `review` | read-only | high | adversarial code review — find bugs/risks in the diff |
| `diagnose` | read-only | xhigh | root-cause a failure without changing files |
| `implement` | workspace-write | high | make a bounded change and verify it |
| `research` | read-only | xhigh | investigate with web search; gather + cite + synthesize |
| `critique` | read-only | xhigh | critique a decision/design/plan — independent, anti-sycophancy, web search |

```bash
# Review the current diff
node scripts/codex-run.mjs --role review

# Root-cause a failure
node scripts/codex-run.mjs --role diagnose "the login test flakes intermittently"

# Implement a bounded change (writable)
node scripts/codex-run.mjs --role implement "add a --version flag to the CLI"

# Research with web search
node scripts/codex-run.mjs --role research "current best practices for rate-limiting"

# Critique a decision or design — an independent second opinion (reads files for context; web search on)
node scripts/codex-run.mjs --role critique "should we keep the adapter stateless instead of a daemon? <your reasoning>"
```

**Precedence:** an explicit flag always overrides a role default, which overrides
the global default. So `--role implement -s read-only` stays read-only, and
`--role research -e high` bumps the effort. Roles never change the safe default
unless you name one.

## Native code review

`--review` runs Codex's purpose-built review harness (`codex exec review`) instead
of a plain exec turn. Unlike the `review` role — a curated adversarial prompt over
the working tree — the native harness can target a precise diff. Point it with
forwarded flags:

```bash
# Review the uncommitted changes (staged + unstaged + untracked)
node scripts/codex-run.mjs --review --uncommitted

# Review against a base branch, or a single commit
node scripts/codex-run.mjs --review --base=main
node scripts/codex-run.mjs --review --commit=<sha>

# Custom review instructions — only WITHOUT a target flag (Codex rejects the
# combination); name the target in the instructions instead
node scripts/codex-run.mjs --review "Review the uncommitted changes; focus on concurrency"
```

A bare `--review` needs no prompt (the harness has its own default instructions).
Target flags and custom instructions are mutually exclusive in Codex itself, so
`--role review --review` also works only without a target flag. `--resume` doesn't
combine with `--review` — a review is always a fresh turn.

**Adding a role:** drop a `roles/<name>.md` file with optional front-matter (see
[docs/writing-roles.md](docs/writing-roles.md) for how to write a good role prompt):

```markdown
---
sandbox: read-only               # optional; explicit -s/-w still overrides
effort: high                     # optional; explicit -e still overrides
config: tools.web_search=true    # optional, repeatable; passed through as `-c key=value`
---
<the role's prompt prefix>
```

> `research` enables web search via `tools.web_search=true`, which requires a
> non-minimal effort (Codex rejects `web_search` with `effort=minimal`).

## Design notes

- **Safe by default:** read-only sandbox; opt into writes explicitly.
- **No state, no daemon:** the runner spawns `codex exec` and exits. Session
  continuity is delegated to Codex's own `resume`.
- **Roadmap:** if live streaming / interactive approvals / cancel become
  needed, that's the one reason to build a thin `codex app-server` client —
  layered on top, never a broker.

## License

MIT
