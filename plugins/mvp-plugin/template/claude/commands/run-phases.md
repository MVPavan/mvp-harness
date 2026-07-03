---
description: Execute all remaining phases of a workstream sequentially with auto-approval and context management, driven off beads.
---

# Run All Remaining Phases

Execute every incomplete phase of a workstream in order, compacting context between phases to keep the
workflow running continuously. Phase state is read from **beads** (epic = phase), never from conversation
memory or a hand-maintained status file. Model: `.beads/beads.md` → *Phase & workstream integration*.

> **Sequential by design.** A deliberately *sequential* runner — one phase at a time, `/compact` between, for
> context economy — walking phases in roadmap order even when deps would allow parallelism. For genuinely-
> independent phases, run separate `/phase-execution` sessions; sequencing comes from the **declared deps**,
> never from this runner. (Independent *stages within* a phase can still run together at the DD layer,
> file-conflict bounded.)

## Inputs

- **Roadmap path** — the workstream roadmap, e.g. `/run-phases docs/workstreams/<name>/roadmap.md`.
- If none is given and it is ambiguous, ask which workstream.

## How It Works

1. Determine the workstream roadmap (`docs/workstreams/<name>/roadmap.md`) and read it for **phase order**.
2. Resolve the workstream's phase epics: `bd list --spec <roadmap.md> --json` (or `bd epic status --json`
   filtered to that `spec_id`).
3. Find the **first phase epic in roadmap order that is not closed** and whose dependencies are met
   (`bd blocked`). That is the next phase.
4. Execute it: `/phase-execution <phase> --roadmap <roadmap.md>`. Within it, auto-approve confirmation
   prompts (plan approval, etc.) — do not pause for input.
5. After the phase passes its **discipline gate + exit criterion** (enforced inside `/phase-execution`):
   - `BD_RENDER=1 bash scripts/bd-render-tracking.sh <name>` — refresh the tracking trio + board.
   - Refresh the durable mirror + commit: `bd export -o .beads/issues.jsonl`, then stage it together with
     the phase's changed files and the regenerated tracking, and commit. (Invoking `/run-phases` is the
     explicit opt-in for per-phase commits; otherwise conservative-git — no push / `bd dolt push`.)
6. Run `/compact` to summarize context and free space.
7. **Re-query bd** (file/bd state is the source of truth, not conversation memory): `bd epic status` +
   `bd ready` → the next incomplete phase. Re-render if needed.
8. Continue from step 4 with the next phase.
9. Stop when every phase epic is closed, or a phase fails its gate / exit criterion.

## Phase Order

Read the execution order from the roadmap file itself — do not hardcode phase sequences. The roadmap is
authoritative for order; bd is authoritative for *status*.

## Auto-Approval Rules

For this workflow, treat the following as auto-approved:

- Plan approval for deep phases (phase-execution Step 2) — approve immediately.
- Per-phase commit — commit after each phase passes its gate (see step 5).
- Codex critique — run if available, follow the capacity policy in `AGENTS.md`.

## Context Management

**Use `/compact` between phases** so the workflow continues uninterrupted. `/clear` would terminate the
session. After compaction, conversation details are lossy — that's fine, because all persistent state
lives in **beads** (+ its generated views):

- `bd epic status --json` — which phases are done / eligible to close (re-query after every compact).
- `bd ready --parent <epic> --json` — the current phase's remaining stages (the live checklist).
- `bd list --parent <epic> --status closed --json` — completed stages + their `close --reason` evidence.
- `docs/workstreams/<name>/plans/` — approved plans for deep phases.

**Critical rule:** after every `/compact`, re-query `bd epic status` / `bd ready` and re-render before continuing.

**Within a phase:** use `/compact` between stages if context grows large (deep phases with many stages).

## Failure Handling

- If a phase fails its gate or exit criterion: stop, report what failed, do **not** continue.
- If Codex is at capacity: follow the Codex capacity policy in `AGENTS.md`.
- If a test fails: invoke systematic-debugging before retrying. If it fails twice, stop and report.
- Subagent failures (529, timeouts): handled by the subagent-driven-development skill's own recovery rules.
