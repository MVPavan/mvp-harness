---
description: Canonical invocation rules for calling OpenAI Codex (via the codex-adapter plugin) from this repo. Subagents and the main thread must follow this for review, diagnosis, implementation, research, and critique.
---

# How to use Codex

Authoritative for this repo. On disagreement, this command wins. Codex runs **GPT-5.x**
(a different model family from Claude) and is a one-way, best-effort critic — no reverse loop.

Codex is reached through the installed **codex-adapter** plugin. Each call is an independent,
stateless `codex exec` process, so you can run as many concurrently as you need.

## Entry points

- **`codex-runner` skill** — the full-control path. Invoke it for any run that needs a role,
  a model/effort/sandbox override, backgrounding, or fan-out. It builds and runs
  `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" [options] "<prompt>"` against the
  installed plugin (resolves the plugin path for you).
- **Slash commands** — one role each, for the common shapes: `/codex` (free-form),
  `/codex-review`, `/codex-diagnose`, `/codex-implement`, `/codex-research`, `/codex-critique`.
- **`/codex-check`** — readiness. If `codex` is missing: `npm i -g @openai/codex` then `codex login`.

Runner options (via the skill): `--role <name>` · `-s read-only|workspace-write|danger-full-access`
· `-w` (= workspace-write) · `-m <model>` · `-e minimal|low|medium|high|xhigh` · `--resume <session-id>`
· `--json` · `--skip-git-check`. Progress → **stderr**; final answer → **stdout**, then a
`[codex-adapter] session <id> — resume:` footer. Relay the stdout answer attributed to Codex.

## Roles (pick by output shape)

| Want | Role / command | Sandbox / effort |
|---|---|---|
| Adversarial review of the current diff | `review` / `/codex-review` | read-only / high |
| Root-cause a failure, no edits | `diagnose` / `/codex-diagnose` | read-only / xhigh |
| Make a bounded change + verify | `implement` / `/codex-implement` | workspace-write / high |
| Investigate with web search, cited | `research` / `/codex-research` | read-only / xhigh |
| Second opinion on a decision/design/plan | `critique` / `/codex-critique` | read-only / xhigh |
| Free-form, no preset | *(no role)* / `/codex` | read-only / default |

Explicit flags override a role's defaults (e.g. `--role implement -s read-only`, `--role critique -e high`).
`review` and `critique` return **prose**, not structured JSON.

## Invocation paths

| Need | Path |
|---|---|
| Standard role run | The matching `/codex*` slash command, or the `codex-runner` skill with `--role`. |
| Flag override (model / effort / sandbox) | The `codex-runner` skill — slash commands don't expose flags. |
| Long / noisy run you needn't block on | The `codex-runner` skill, launched with **`run_in_background: true`**; collect later via BashOutput. |
| Keep a very verbose run out of the main thread | Optional: brief a `general-purpose` subagent to invoke the skill and return only the distilled result. There is **no dedicated Codex subagent**. |

## Rules

1. **Read-only by default.** Only `--role implement` or `-w` may edit the tree — and say so to the user.
2. **`--effort` floor `low`.** `minimal` rejects `web_search` → 400. `low` small · `medium`/`high` investigation · `xhigh` deep root-cause.
3. **Fan out freely.** Independent work → several runs in one message (or background). The real ceiling is the API rate limit.
4. **Verify every Codex citation.** GPT-5.x confidently cites lines that don't match current code — grep before acting.
5. **Pick by role.** Reach for `-m`/`-e`/`-s` only to override a role default, with reason.
6. **Iterate 2–5 rounds** for non-trivial work. Don't ship on "DO NOT SHIP" without fixing the finding or recording why it's out of scope.
7. **Best-effort.** On capacity/auth error: retry once, then proceed without Codex and log the skip. `small` tasks skip Codex unless risk is unusual.
8. **Resume** a prior thread with `--resume <session-id>` from the footer; otherwise each call is fresh.

## Pointers

- Deep docs ship inside the installed plugin and are directly readable: `${CLAUDE_PLUGIN_ROOT}/` (`README.md`, `docs/writing-roles.md`, `roles/`, `skills/codex-runner/`) from any `/codex*` command or the `codex-runner` skill, or under `~/.claude/plugins/cache/codex-adapter/codex-adapter/<version>/` (latest dir) for a direct read.
- Repo pointers: [`AGENTS.md`](../../AGENTS.md) § Codex And Claude · [`CLAUDE.md`](../../CLAUDE.md) § Claude and Codex.
