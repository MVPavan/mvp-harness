---
name: beads
description: Use when working in a repository that uses bd or Beads for durable project task tracking, issue dependencies, blocker management, multi-session handoff, or shared work memory. Trigger when the user asks to find ready work, claim or close tasks, create follow-up work, inspect blockers, or recover project context; also when starting a new task or implementation, choosing what to work on next, or wrapping up a work session.
---

# Beads

Shared, durable task system for this repo — the source of truth for project work, not markdown TODO files. `bd` is the interface and the table below is self-sufficient for everyday work. Recover context (and the session-close protocol) with `bd prime`; if it prints nothing, check the workspace with `bd where`. Project policy lives in `.beads/beads.md`.

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
| Stats / health | `bd stats` (quick summary) · `bd lint` · `bd stale` · `bd orphans` · `bd gc` / `bd prune` |

Priority is `0..4` (0=critical), not high/med/low. Never `bd edit` (opens $EDITOR — use `bd update` flags). Add `--json` to parse output. Close only when the work is actually done.

Maintenance — on-demand, not per session: use the stats/health row above. Run `bd preflight --check` only when its checks match this repo's current toolchain; this CLI version includes some Go-specific checks.

## Conventions

- **Actor (mandatory, every write):** pass `--actor "<runtime>:<session-or-purpose>"` on *all* `bd create` / `update` / `close` / `dep` / `label`. Examples: `codex:setup`, `cc:${CLAUDE_CODE_SESSION_ID:0:8}`, `gemini:<session>`. Stamps `created_by` + each change event; `owner` stays the human.
- **Casing:** label names are filter-case-sensitive (`-l idea` ≠ `-l Idea`) — all-lowercase, kebab-case for multi-word (`relationship-graph`), never Capitalized/PascalCase.
- **idea** (raw, untriaged): `bd create "…" -l idea --defer 2099-01-01 -q`; triage with `bd list -l idea`.
- **backlog** (vetted, not now): `bd create "…" -l backlog -t <type> -p <prio> --defer … -q`, or promote an idea — `bd label add <id> backlog; bd label remove <id> idea`.
- **Epic → spec-id (mandatory check):** never create an epic without first checking for a spec, plan, or design doc. If the user named one, attach it (`--spec-id <path>`). If no such document exists, proceed without one only when the issue description captures the reason. `spec_id` does not inherit to children; filter epics by spec with `bd list --spec <prefix>`.
- **Issue shape:** keep child tasks flat as practical. Add dependencies only when work genuinely depends on another issue's output; do not chain tasks only because they appear in sequence.

## Overrides (these beat `bd prime`'s defaults)

- **Granularity:** one bd issue per work-item, never per step — TodoWrite handles this turn's steps. Durable work found mid-task → `bd create … --deps discovered-from:<id>` before the turn ends.
- **Memory:** durable knowledge (facts, decisions, preferences) → `MEMORY.md`, not `bd remember`. Do **NOT** use `bd remember` / `bd memories`, and ignore `bd prime` guidance to avoid `MEMORY.md`. bd holds work items only.
- **Git:** conservative — no commit / push / `bd dolt push` unless asked. At session close, if issues changed, refresh the mirror: `bd export -o .beads/issues.jsonl`.

Deep policy (git profiles, sync & durability mechanics, convention rationale, epic-spec nuances): `.beads/beads.md`.
