---
name: codex-runner
description: Use to delegate a coding, analysis or research task to OpenAI Codex (gpt-5.x) from Claude Code — for a critique, an independent implementation or diagnosis pass, or to parallelize work across multiple Codex instances. Trigger when the user asks to "run Codex", "ask Codex", "use Codex", get a Codex review, or hand a task to Codex.
---

# Codex runner

Invoke OpenAI Codex through the bundled runner. Each call is an independent
`codex exec` process driving the same `codex-core` engine as the full Codex
app-server — so you may run **several concurrently** (multiple Bash calls in one
message). There is no shared broker and no single-instance lock to work around.

## Invoke

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" [options] "<prompt>"
```

The prompt may be an argument or piped via stdin.

Options:
- `-C, --cd <dir>`      Working root for Codex. Usually pass the repo root.
- `-s, --sandbox <m>`   `read-only` (default) | `workspace-write` | `danger-full-access`.
- `-w, --writable`      Shortcut for `--sandbox workspace-write` (Codex may edit files in the working dir).
- `-m, --model <id>`    Model id (omit to use the account default) — see **Models** below.
- `-e, --effort <l>`    Reasoning effort: `low|medium|high|xhigh|max|ultra` (model-dependent; unknown values warn and forward).
- `-c, --config <k=v>`  Extra Codex config override (repeatable).
- `--review`            Native code-review harness (`codex exec review`). Target the diff with `--uncommitted`, `--base=<branch>`, or `--commit=<sha>` — or give custom instructions as the prompt instead (Codex rejects a prompt combined with a target flag).
- `--resume <id>`       Continue a prior Codex session by id (not combinable with `--review`).
- `--role <name>`       Apply a role preset — see **Roles** below.
- `--json`              Stream raw JSONL events (progress + session id) instead of just the final answer.
- `--progress` / `--quiet`  Force the progress transcript on/off. Default is automatic: streamed for a human (stderr TTY), suppressed for an agent — so **do not** redirect stderr with `2>/dev/null`; on success you get the answer plus one `[codex-adapter] session ... (model ..., sandbox)` footer, and on failure the last 60 transcript lines.
- `--skip-git-check`    Allow running outside a git repository.

Any option the runner doesn't recognize is forwarded verbatim to `codex exec`
(e.g. `--output-schema=schema.json`, `-o=answer.txt`, `--ephemeral`,
`--add-dir=<dir>`). Use the `--flag=value` form for forwarded flags that take a
value — a space-separated value would be read as prompt text. Forwarded flags land
after the subcommand, so flags that exist only on plain `codex exec` (e.g.
`--add-dir`) don't combine with `--review`/`--resume`.

## Models

Do **not** probe the CLI to discover models — pick from this catalog. When the
user names a model informally ("sol", "terra", "luna", "5.5", "mini"), map it to
the slug here.

| Slug | When to pick it | Efforts |
|------|-----------------|---------|
| `gpt-5.6-sol` | **Default — omit `-m` entirely** (account default). Frontier agentic coding. | low–ultra |
| `gpt-5.6-terra` | Large or long implementations: multi-file features, big refactors, sustained agentic work. | low–ultra |
| `gpt-5.6-luna` | Quick, small, cheap tasks — mechanical edits, lookups, high-volume fan-out. | low–max |
| `gpt-5.5` | Prior frontier; only when the user asks for it. | low–xhigh |
| `gpt-5.4` / `gpt-5.4-mini` | Legacy everyday / small; only on request. | low–xhigh |
| `gpt-5.3-codex-spark` | **Not usable here** (`supported_in_api: false` — TUI only). | — |

Catalog as of 2026-07-10 (codex-cli 0.144.x). If a slug is rejected or you need
the live list: `jq -r '.models[] | "\(.slug) \(.visibility)"' "${CODEX_HOME:-$HOME/.codex}/models_cache.json`.

## Roles

Prefer a role for common shapes of work — it applies a tuned prompt plus sensible
sandbox/effort defaults. Pass `--role <name>`; your text becomes the specific task.

- `review` — adversarial code review of the current diff (read-only).
- `diagnose` — root-cause a failure without editing (read-only).
- `implement` — make a bounded change and verify it (writable working tree).
- `research` — investigate with web search, cited (read-only).
- `critique` — independent second opinion on a decision/design/plan (read-only).

Explicit flags override a role's defaults (e.g. `--role implement -s read-only`,
`--role critique -e high`). With no `--role`, the runner is plain free-form.

## Rules

- **Default to read-only** for analysis, review, and diagnosis. Only add
  `--writable` when the task is explicitly to change files, and tell the user
  Codex will be editing their working tree.
- Codex prints its **final answer to stdout** (stderr carries the session footer,
  and — only when streaming or on failure — the progress transcript). Relay that
  answer attributed to Codex; never present Codex's edits or claims as your own,
  and surface anything you disagree with.
- **Fan out for independent work:** launch multiple runners in parallel (one Bash
  message, several calls), then synthesize the results yourself. For a long run you
  don't need to block on, launch it with `run_in_background` and collect it later.
- If `codex` is missing, tell the user to run `npm i -g @openai/codex` and
  `codex login`.
