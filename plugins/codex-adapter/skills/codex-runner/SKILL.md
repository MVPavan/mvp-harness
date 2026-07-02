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
- `-m, --model <id>`    Model id (omit to use the account default).
- `-e, --effort <l>`    Reasoning effort: `minimal|low|medium|high|xhigh`.
- `--resume <id>`       Continue a prior Codex session by id.
- `--role <name>`       Apply a role preset — see **Roles** below.
- `--json`              Stream raw JSONL events (progress + session id) instead of just the final answer.
- `--skip-git-check`    Allow running outside a git repository.

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
- Codex prints progress to stderr and its **final answer to stdout**. Relay that
  answer attributed to Codex; never present Codex's edits or claims as your own,
  and surface anything you disagree with.
- **Fan out for independent work:** launch multiple runners in parallel (one Bash
  message, several calls), then synthesize the results yourself. For a long run you
  don't need to block on, launch it with `run_in_background` and collect it later.
- If `codex` is missing, tell the user to run `npm i -g @openai/codex` and
  `codex login`.
