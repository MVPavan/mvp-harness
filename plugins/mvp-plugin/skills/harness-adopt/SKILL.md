---
name: harness-adopt
description: Adapt the freshly-copied agent harness to the current repository. Use after /mvp-plugin:adopt has laid the files down, or when asked to fill the project overlay, refresh repo facts, or produce a harness adoption report. Fills .claude/project/* and .codex/project/* from repo reality and recommends repo-specific automations — without rewriting the reusable core.
---

# Harness adopt

The deterministic copy (`scripts/install-harness.sh`) has already laid the
self-contained harness into the repo and left the project overlay as skeletons.
Your job is the judgement half: replace those skeletons with facts derived from
**this** repo, and recommend automations that fit it. Keep the reusable core
(rules, skills, agents, commands, hooks) untouched.

## Goal

Turn the skeleton overlay into accurate repo facts, in **both** harness trees
(`.claude/project/*` and `.codex/project/*`), and append a report-only
recommendations section. Never auto-enable anything.

## Workflow

1. Read, in this order:
   - `AGENTS.md` and `CLAUDE.md` (the harness skeleton you just installed);
   - the skeleton overlay files under `.claude/project/` and `.codex/project/`.
2. Scan the target repo:
   - root instruction/config files, `README`, design docs;
   - manifests and lock files (`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `pom.xml`, …), CI (`.github/workflows`, etc.), and test config;
   - `.gitmodules` (real submodules — update the genericised "External Submodules" note in CLAUDE.md/AGENTS.md if the repo has any);
   - relevant source and test directories.
3. Authority order when facts conflict: **repo reality → current config/CI → maintained docs → older docs → explicit assumptions**. Verify claims against the repo; never copy unverifiable design-doc claims into project facts.
4. Fill these in **both** `.claude/project/` and `.codex/project/` (keep the two trees consistent; only path prefixes differ):
   - `brief.md` — what the repo is, stack, constraints, non-negotiables.
   - `repo-map.md` — top-level layout and how to navigate.
   - `docs-index.md` — authoritative docs and when to read them.
   - `verification.md` — the real commands that prove the repo is healthy (build/test/lint/CI). If there is no first-party code yet, keep the gate **structural** and say so — do not invent commands.
   - `invariants.md` — hard constraints derived from repo reality.
   - `tools.md` — runtimes, package managers, test/CI commands, subagent routing.
   - `tracking.md` — beads setup for this repo (prefix, sync remote).
   - `learnings.md` — start empty unless prior learnings exist.
   - `adoption-report.md` — inputs read, files updated, assumptions, conflicts/gaps, recommended next review step.
   - `.claude/project/code-intel.md` — whether the repo benefits from the `code-intel` plugin (serena+CBM+ast-grep), primary language/LSP, index state. Report-only.
5. Use repo-relative paths only. Never encode machine-local absolute paths.
6. **Recommend repo-specific automations (report-only).** Modeled on Anthropic's
   `claude-automation-recommender`: from the detected stack, surface the top 1–2
   per category in `adoption-report.md`. Do **not** create or enable anything —
   list them as opt-in suggestions.

   | Repo signal | Suggest (report-only) |
   |---|---|
   | Popular libraries/SDKs (React, FastAPI, Prisma, …) | `context7` MCP for live docs |
   | Frontend with UI/e2e needs | Playwright MCP |
   | Postgres/MySQL/Supabase | a database MCP |
   | Heavy GitHub / PR workflow | GitHub MCP + a `pr-check` skill |
   | Prettier/ESLint/Ruff configured | PostToolUse format/lint hook |
   | `.env`/lock files present | PreToolUse block-edit hook |
   | Large codebase (>500 files), navigation-heavy | the `code-intel` plugin |
   | Auth/payments/security code | a `security-reviewer` subagent |

   For each suggestion give a one-line **why** tied to a concrete repo signal,
   and the opt-in step. Note that the harness already ships generic hooks
   (dangerous-command block, generated-edit block, bd-prime) and core subagents,
   so only recommend what those don't already cover.
7. If Codex is available and the work is `standard` or `deep`, ask Codex to
   challenge the major assumptions (via `/codex-critique` or the `codex-runner`
   skill) before finalizing. Best-effort: one retry on capacity error, then proceed and log the skip.
8. Stop and present `adoption-report.md` for review. Do not commit; do not `git add`.

## Rules

- Do not rewrite core rules, agents, commands, skills, or hooks unless the user asks.
- Do not auto-enable plugins, MCP servers, or hooks — enablement is the user's trust decision.
- Keep `.claude/project/*` and `.codex/project/*` consistent with each other.
- If the repo's stack does not match a shipped rule set (e.g. it is not Python but `rules/python/` is present), say so in the report; recommend the user adapt or remove those rules rather than silently leaving a mismatch.
