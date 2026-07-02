---
name: run-phases
description: Execute all remaining phases of a Beads-backed workstream sequentially with context management. Use when the user explicitly asks to run every incomplete phase from a roadmap after workstream tracking is bootstrapped.
---

# Run All Remaining Phases

Execute every incomplete phase of a workstream in order, compacting context between phases to keep the workflow running continuously. Phase state is read from **Beads**; never rely on conversation memory or hand-maintained status files. Model: `.beads/beads.md` -> *Workstream Mirrors*.

Sequential execution is deliberate: one phase at a time, walking roadmap order even when dependencies would allow parallelism. For genuinely independent phases, run separate `$phase-execution` sessions.

## Inputs

- Roadmap path, for example: `$run-phases docs/workstreams/<name>/roadmap.md`.
- If none is given and it is ambiguous, ask which workstream.

## Workflow

1. Determine the workstream roadmap and read it for phase order.
2. Resolve phase epics with `bd list --spec <roadmap.md> --json` or `bd epic status --json` filtered to that `spec_id`.
3. Find the first phase epic in roadmap order that is not closed and whose dependencies are met.
4. Execute it with `$phase-execution <phase> --roadmap <roadmap.md>`. Within this workflow, auto-approve routine phase confirmations, but do not bypass safety approvals.
5. After the phase passes its discipline gate and exit criterion:
   - If `scripts/bd-render-tracking.sh` exists, run `BD_RENDER=1 bash scripts/bd-render-tracking.sh <name>`.
   - Refresh `.beads/issues.jsonl` with `bd export -o .beads/issues.jsonl`.
   - Commit only if the user or active workflow explicitly grants commit authority.
6. Compact context between phases when running interactively.
7. Re-query Beads after every compaction and before choosing the next phase.
8. Stop when every phase epic is closed or a phase fails its gate.

## Rules

- Phase order comes from the roadmap. Beads is authoritative for status.
- Generated workstream mirrors are never hand-edited.
- If a phase fails, stop and report the failed gate; do not continue.
- If tests fail, use `$systematic-debugging` before retrying.
- Subagent failures are handled by `$subagent-driven-development`.
- Do not push or sync remotes unless explicitly authorized.
