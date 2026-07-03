# Adoption Runbook — Beads (bd) Issue Tracking

**Purpose.** Hand this file to an agent in **any** repo and it can reproduce the exact issue-tracking
setup: the **bd (Beads)** tracker wired in with low instruction-pollution — a triggerable skill + a policy
doc + a SessionStart hook + git-native durability — plus the conventions that make coding agents use it
correctly (the TodoWrite/bd split, mandatory `--actor` attribution, idea/backlog capture, epic→spec,
conservative git). Fill in the placeholders and
follow top to bottom.

## 0. Placeholders (substitute throughout)

| Placeholder | Meaning | Example |
|---|---|---|
| `{{PREFIX}}` | short, distinctive issue-ID prefix (2–4 chars, starts with a letter) | `bo` |
| `{{GIT_REMOTE}}` | the repo's git remote URL (for bd's Dolt sync) | `https://github.com/you/repo.git` |
| `{{KNOWLEDGE_STORE}}` | the project's durable-knowledge store, if any (else "none") | `MEMORY.md auto-memory` / `none` |

## 1. The model you are reproducing (don't collapse these)

Three layers that coexist:

- **bd = durable work items** — tasks, bugs, features, epics, dependencies, blockers; anything that must
  survive thread reset / compaction / handoff, or that another person or agent should resume.
- **TodoWrite = the agent's in-turn execution checklist** — the steps of the one task being done *now*
  (ephemeral). One bd issue per *unit of work*, never per step.
- **`{{KNOWLEDGE_STORE}}` = durable knowledge** — facts, decisions, preferences. (If the project has no
  such store, `bd remember` fills this role; if it does, knowledge stays there — see the policy.)

Litmus: *"if my session died right now, would I want this to still exist as project state?"* → yes = bd,
no = TodoWrite.

## 2. Prerequisites

- Install **bd** (Beads). It is a single binary (Dolt-backed, embedded mode). Install however your
  environment provides it (e.g. via npm/nvm, a release binary, or a package manager) and confirm:
  ```bash
  bd version    # pin/record the version; the CLI has breaking-change velocity
  ```
- A git repo (`git init` if needed). bd does **not** require a GitHub remote to function locally.

## 3. Initialize + configure

```bash
bd init                      # see "what bd init creates" below
bd rename-prefix {{PREFIX}}- # short, distinctive prefix → issues like {{PREFIX}}-x7q (must end with '-')
```

**What `bd init` creates automatically (do not hand-write these):**

- `.beads/` containing the Dolt binary store (gitignored) plus **committed** files: `config.yaml`,
  `metadata.json` (project id / Dolt mode), `README.md`, `.gitignore`, and **five git-hook shims** under
  `.beads/hooks/` — `pre-commit`, `pre-push`, `post-checkout`, `post-merge`, `prepare-commit-msg`.
- It sets git's **`core.hooksPath` → `.beads/hooks`** in `.git/config`. That config is **per-clone and
  machine-local (an absolute path, NOT committed)**: the hook *shims* are committed, but their
  *activation* is per-clone — **re-run `bd init` / `bd setup` on every fresh clone** to re-activate them.
- It adds beads runtime ignores to the **root `.gitignore`** — `.dolt/`, `*.db`, `.beads/proxieddb/`, and
  `.beads-credential-key` (the federation encryption key, which **must never be committed**).

You only hand-author three things on top of what `bd init` generates: the `config.yaml` edits (below),
the `.beads/beads.md` policy (§4), and the `.claude/` skill + hook (§5–§6).

Then set `./.beads/config.yaml` to enable git-native durability (key lines — leave the rest of the
bd-generated file as is):

```yaml
# Short, distinctive issue prefix. New issues: {{PREFIX}}-x7q; epics {{PREFIX}}-a9f; children {{PREFIX}}-a9f.1
issue-prefix: {{PREFIX}}

# Cross-machine operational sync (Dolt over the repo remote).
sync.remote: "git+{{GIT_REMOTE}}"

# JSONL plaintext mirror for git-native durability (issues.jsonl is COMMITTED; see .beads/beads.md).
# auto: best-effort live mirror; in embedded mode it can lag, so it is NOT trusted alone — a manual
#       `bd export -o .beads/issues.jsonl` at session close refreshes the committed snapshot.
# git-add: stays false — bd never auto-stages; staging/commit is explicit (conservative git).
export.auto: true
export.git-add: false
```

**`.beads/.gitignore`** — `bd init` writes it (it ignores the Dolt binary store, runtime locks, the
ephemeral SQLite, etc.). Verify **`issues.jsonl` is NOT ignored** (it is the committed durability
mirror); recent `bd init` already appends the tracked-mirror note below, so add it only if missing:

```gitignore
# issues.jsonl is intentionally TRACKED (git-native durability mirror — see
# .beads/beads.md "Source of truth, durability & sync"). Do NOT re-ignore it;
# it is refreshed via a manual `bd export` at session close and committed explicitly.
```

> **Why:** the Dolt binary store is the source of truth but can't be diffed/merged by git and bloats
> `.git`; the JSONL export is a readable, recoverable plaintext mirror. Recover on a fresh clone with
> `bd import .beads/issues.jsonl`.

## 4. Policy doc — `.beads/beads.md`

Create this file (it carries the durable, project-specific policy that `bd prime` does not own; keeps
`AGENTS.md`/`CLAUDE.md` clean):

````markdown
# Beads Issue Tracker — policy

This project uses **bd (beads)** for durable issue tracking. The command reference and the live
session-close protocol come from `bd prime` (run it for the authoritative workflow). This file holds only
**policy** that `bd prime` does not own.

## Repo-specific rules

- **Memory.** This project keeps durable knowledge in `{{KNOWLEDGE_STORE}}`. Do **NOT** use `bd remember`,
  and ignore any bd guidance that says to avoid that store. Division of responsibility: **bd = work
  items**; **`{{KNOWLEDGE_STORE}}` = durable knowledge**. *(If `{{KNOWLEDGE_STORE}}` is "none", delete this
  bullet and use `bd remember` / `bd memories` for cross-session knowledge instead.)*
- **Conservative git authority (default).** Use bd for tracking, but do **NOT** run git commits, pushes,
  or `bd dolt push` / Dolt remote sync unless the user explicitly asks. At handoff, report changed files,
  validation, and the proposed commands. A current "do not commit / do not push" instruction always wins.
- **Source of truth, durability & sync.** The local Dolt DB under `.beads/` (gitignored binary) is the
  **source of truth**. `.beads/issues.jsonl` is a **committed plaintext mirror** for git-native
  durability — recoverable on a fresh clone via `bd import .beads/issues.jsonl`. Auto-export
  (`export.auto: true`) is **best-effort**; in embedded mode it can lag, so **do not trust it alone**. At
  session close, refresh with `bd export -o .beads/issues.jsonl`, then commit it (subject to the
  conservative-git rule — never auto-staged; `export.git-add: false`). Cross-machine *operational* sync
  stays `bd dolt push/pull` (`sync.remote` in `.beads/config.yaml`).
- **Hygiene cadence (on-demand, not per session).** In **embedded mode** `bd doctor` is a no-op (it
  prints *"not yet supported in embedded mode"*) — use `bd stats` / `bd lint` / `bd stale` / `bd orphans`
  for health and `bd preflight --check` before a PR. Reclaim space with `bd gc` (decay + compact) or
  `bd prune` (drop old closed beads). *(In non-embedded / Dolt-server setups `bd doctor` does work — it
  health/sync/hook-checks, with `bd doctor --fix` to repair.)*
- **Epic → spec link (ask first).** Before creating an **epic**, ask the user for a spec/plan doc to link,
  and set it with `--spec-id <path>`. Ask first by default; only skip if the user already declined for
  this epic. `spec_id` does **not** inherit to children; it labels the epic (enables `bd list --spec` and
  a visible link in `bd show`).
- **TodoWrite vs bd (overrides `bd prime`).** `bd prime` says "do NOT use TodoWrite" and "create a bead
  before writing code" — **ignore that here**. TodoWrite is the right tool for the *current turn's
  execution steps*; keep using it. bd owns **work items** — one issue per unit of work, **never per
  step**. Make a bd issue when work is durable / multi-session / has dependencies; TodoWrite-only is fine
  for a small task finished this turn. Any *durable* work discovered mid-task must be promoted into bd
  (`--deps discovered-from:<id>`) before the turn ends. Don't keep markdown TODO files as project state.

## Idea & backlog capture

Two parked-work labels, distinguished by **commitment level**. Both are deferred so they stay out of
`bd ready`; never capture either as a shell alias, markdown note, or TODO file. Never use
`--ephemeral` / wisps for them — those are TTL-compacted and can vanish before triage.

**`idea` — raw, unvetted** ("is this even worth doing?"). A thought / follow-up not yet decided on:

    bd create "the idea in one line" -l idea --defer 2099-01-01 -q

`-l idea` tags it for the pile; `--defer` keeps it out of `bd ready`. If tied to the issue in progress,
add `--deps discovered-from:<current-id>`. Triage with `bd list -l idea` → do now / move to backlog /
discard (`bd close`) / leave parked.

**`backlog` — vetted, accepted, but not now** ("yes, just later"). Already carries a real `type` and
`priority`; it is committed-someday, not a maybe:

    bd create "the work item" -l backlog -t <type> -p <prio> --defer <date|2099-01-01> -q

Promote a surviving idea: `bd update <id> --type … --priority …; bd label add <id> backlog;
bd label remove <id> idea`. Review with `bd list -l backlog`; **schedule** by clearing the defer /
raising priority and dropping the `backlog` label.

> **Label casing:** label names are filter-case-sensitive (`-l idea` ≠ `-l Idea`) — always all-lowercase,
> kebab-case for multi-word (`relationship-graph`).

See `bd prime` for the full command catalogue and the session-completion checklist.
````

## 5. Skill — `.claude/skills/beads/SKILL.md`

> **Location matters — install agent config under `.claude/`, never `.agents/`.** Claude Code discovers
> skills from `.claude/skills/`, hooks from `.claude/hooks/`, and hook registration from
> `.claude/settings.json`. Put the beads skill at **`.claude/skills/beads/SKILL.md`** (one folder per
> skill). Do **NOT** create it under `.agents/`, `agents/`, or a repo-root location, and if `bd setup` /
> `bd quickstart` offers to install "agent instructions" elsewhere, **decline or redirect** — the
> canonical skill lives under `.claude/skills/`. (Some repos keep an `.agents/` placeholder that only
> documents that everything real lives in `.claude/`; do not put skills there.)

Create this triggerable skill (auto-discovered from `.claude/skills/`):

````markdown
---
name: beads
description: Use when working in a repository that uses bd or Beads for durable project task tracking, issue dependencies, blocker management, multi-session handoff, or shared work memory. Trigger when the user asks to find ready work, claim or close tasks, create follow-up work, inspect blockers, or recover project context; also when starting a new task or implementation, choosing what to work on next, or wrapping up a work session.
---

# Beads

Shared, durable task system for this repo — the source of truth for project work, not markdown TODO
files. `bd` is the interface and the table below is self-sufficient for everyday work. Recover context
(and the session-close protocol) with `bd prime`; if it prints nothing, check the workspace with
`bd where`. For project policy (memory, git authority, sync) see `.beads/beads.md`.

## Cheat-sheet

| Goal | Command |
|------|---------|
| Recover context / session-close protocol | `bd prime` |
| Ready (unblocked) work | `bd ready` |
| List by status | `bd list --status=open\|in_progress\|closed` |
| Inspect one issue | `bd show <id>` |
| Search text | `bd search "<query>"` |
| Create | `bd create "title" --description="why + what" -t task\|bug\|feature\|epic\|chore\|decision -p 0..4` |
| Claim | `bd update <id> --claim` |
| Edit fields | `bd update <id> --title/--description/--notes/--design/--priority/--status` |
| Close (one or many) | `bd close <id> [<id>…] [--reason="…"]` |
| Dependencies | `bd dep add <id> <depends-on>` · `bd dep tree <id>` · `bd blocked` |
| Labels | `bd label add\|remove <id> <label>` · `bd list -l <label>` · `bd label list-all` |
| Lifecycle | `bd defer <id> --until=<date>` · `bd supersede <id> --with=<id>` · `bd stale` · `bd orphans` |
| Epics | create: `-t epic [--spec-id <path>]` · child: `bd create … --parent <epic-id>` · `bd epic status` · `bd epic close-eligible` · children: `bd list --parent <id>` · by spec: `bd list --spec <prefix>` |
| Stats / health | `bd stats` · `bd lint` · `bd stale` · `bd orphans` · `bd gc` / `bd prune` |

Priority is `0..4` (0=critical), not high/med/low. Never `bd edit` (opens $EDITOR — use `bd update`
flags). Add `--json` to parse output. Close only when the work is actually done. `bd doctor` may be a
no-op in embedded mode — use the stats/health row, and `bd preflight --check` before a PR.

## Conventions

- **Actor (mandatory, every write):** pass `--actor "cc:${CLAUDE_CODE_SESSION_ID:0:8}"` on *all*
  `bd create` / `update` / `close` / `dep` / `label`. Stamps `created_by` + each change event; `owner`
  stays the human. *(`cc:` + a short session id is just a stable agent tag — adapt the prefix to your
  agent runtime; the goal is that every write is attributable.)*
- **Casing:** label names are filter-case-sensitive (`-l idea` ≠ `-l Idea`) — all-lowercase, kebab-case
  for multi-word (`relationship-graph`), never Capitalized/PascalCase.
- **idea** (raw, untriaged): `bd create "…" -l idea --defer 2099-01-01 -q`; triage with `bd list -l idea`.
- **backlog** (vetted, not now): `bd create "…" -l backlog -t <type> -p <prio> --defer … -q`, or promote
  an idea — `bd label add <id> backlog; bd label remove <id> idea`.
- **Epic → spec-id (mandatory check):** never create an epic without first checking for a spec. If the
  user named one, attach it (`--spec-id <path>`); if not, ask whether it belongs to a spec — proceed
  without one only after they decline. `spec_id` does not inherit to children; filter with
  `bd list --spec <prefix>`.

## Overrides (these beat `bd prime`'s defaults)

- **Granularity:** one bd issue per work-item, never per step — TodoWrite handles this turn's steps.
  Durable work found mid-task → `bd create … --deps discovered-from:<id>` before the turn ends.
- **Memory:** durable knowledge → `{{KNOWLEDGE_STORE}}`, not `bd remember`. bd holds work items only.
  *(If the project has no such store, use `bd remember` / `bd memories` instead.)*
- **Git:** conservative — no commit / push / `bd dolt push` unless asked. At session close, if issues
  changed, refresh the mirror: `bd export -o .beads/issues.jsonl`.

Deep policy (git profiles, sync & durability mechanics, convention rationale, epic-spec nuances):
`.beads/beads.md`.
````

## 6. SessionStart hook — auto-prime each session

Create `.claude/hooks/bd-prime.sh` (self-locates `bd`; degrades to a silent no-op if absent — it must
never fail the session):

```bash
#!/usr/bin/env bash
# SessionStart hook: prime the agent with Beads workflow context (`bd prime --hook-json`).
# `bd` may live under nvm and not be on the hook's PATH; this self-locates it with no machine-local path.

if ! command -v bd >/dev/null 2>&1; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
    nvm use --silent default >/dev/null 2>&1 || nvm use --silent node >/dev/null 2>&1
  fi
fi
if ! command -v bd >/dev/null 2>&1; then
  for d in "$HOME"/.nvm/versions/node/*/bin; do
    [ -x "$d/bd" ] && PATH="$d:$PATH" && break
  done
fi

command -v bd >/dev/null 2>&1 && bd prime --hook-json
exit 0
```

```bash
chmod +x .claude/hooks/bd-prime.sh
```

Register it in `.claude/settings.json`. If the file already exists, **merge** this `SessionStart` entry
into its `hooks` object rather than overwriting — other hooks (e.g. a `PreToolUse` git guard) may already
be present:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/bd-prime.sh" }
        ]
      }
    ]
  }
}
```

> bd also installs **git hooks** at init (`core.hooksPath=.beads/hooks`) — these are committed shims and
> are per-clone; re-run `bd init`/setup on a fresh clone to activate them. They do not auto-export or
> auto-stage `issues.jsonl`.

## 7. Discoverability pointer (keep top-level files clean)

Add a short pointer to `AGENTS.md` (and/or `CLAUDE.md`) — do **not** paste the workflow there:

```markdown
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Workflow, rules, and the session-completion protocol
live in **[`.beads/beads.md`](.beads/beads.md)**. Run `bd prime` for runtime context.
```

## 8. Session-close protocol (the durable handoff)

Before saying "done": **close completed issues** (`bd close <id> …`) → **run quality gates** → **refresh
the mirror** (`bd export -o .beads/issues.jsonl` if issues changed) → **`git status`** → **report
handoff** (changed files, validation, proposed commands). Commit/push only with explicit authority
(conservative default). The `bd prime` output includes the live version of this checklist.

## 9. Verification (acceptance)

```bash
bd prime                 # prints workflow context (or a hint if the workspace is fresh)
bd create "smoke: adoption check" --type=task --priority=3 --actor "cc:${CLAUDE_CODE_SESSION_ID:0:8}" -q
bd ready                 # the new issue appears
bd export -o .beads/issues.jsonl && git diff --stat .beads/issues.jsonl   # mirror refreshes
bd stats                 # issue counts look sane  (bd doctor is a no-op in embedded mode)
bd preflight --check     # PR-readiness checks run
bd close <id> --reason="adoption verified" --actor "cc:${CLAUDE_CODE_SESSION_ID:0:8}"
```

Then confirm: a SessionStart prints `bd prime` context; the agent uses **TodoWrite for in-turn steps** and
a **single bd issue per work item** (not per step); ideas go to `-l idea` (promote to `-l backlog`); and nothing is committed/pushed
without an explicit ask.

## 10. Notes captured from the original adoption

- **Pick a short, distinctive prefix early** — rename while the store is empty (zero migration cost);
  `bd rename-prefix` requires a trailing `-`.
- The override of `bd prime`'s "never TodoWrite / never your-memory-store" stance is deliberate and was
  A/B-verified to produce better agent behaviour (1 issue + TodoWrite-for-steps, ideas deferred to `-l idea`,
  discovered work promoted with `discovered-from`) versus raw `bd prime` (issues-per-step, cluttered
  `bd ready`).
- **Don't commit the Dolt binary store** — git can't diff/merge it and `.git` bloats fast. Commit the
  JSONL export instead (best-effort auto-export + a manual `bd export` at close).
- **bd worktree gotcha:** `bd init` inside a git *worktree* writes its store into the **main** repo
  (shared `.git`). Run bd from the real repo root.
