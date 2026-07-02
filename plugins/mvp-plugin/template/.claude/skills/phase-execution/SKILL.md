---
name: phase-execution
description: Execute a development phase from a workstream roadmap, following the full cycle (plan, Codex critique, implement, verify, review) with beads as the work-state anchor.
---

# Phase Execution

Thin orchestrator that drives one complete phase of a workstream. Work-state lives in **beads** (epic =
phase, flat task = stage); the tracking files are bd-generated. Delegates planning and implementation to
specialized skills — does not reimplement them. Model: `.beads/beads.md` → *Workstream Mirrors*.

## Use It When

The user says "start phase N", "execute phase N", or "begin phase N".

## Inputs

- Phase number/name (e.g., `3`, `7a`, `R1.1`, `E`).
- **Roadmap path** — the workstream roadmap, passed as argument
  (e.g., `/phase-execution E --roadmap docs/workstreams/<name>/roadmap.md`).
- If no roadmap is given and it is ambiguous, ask which workstream.

## Workflow

### Step 1 — Load Context

1. Determine the workstream roadmap from `--roadmap` (a `docs/workstreams/<name>/roadmap.md`).
2. Read the roadmap — find the phase section: deliverables, spec references, exit criterion, risk.
3. Resolve the phase **epic** in bd: `bd list --spec <roadmap.md> --json` → the epic for this phase.
   Confirm it is **not closed** (`bd epic status --json` → its `.epic`). Never re-seed; the epic already
   exists from `/prepare-phases`.
4. Check dependencies: prerequisite stages/phases closed (`bd blocked`, `bd dep tree <epic>`).
5. Classify phase risk from the roadmap (each phase states its own; default `standard`).
6. Present the phase summary: deliverables, risk, and the ready stages
   (`bd ready --parent <epic> --json`, filtered to direct children `^<epic>\.[^.]+$`).

### Step 2 — Plan (deep phases only)

Skip for `standard` phases.

1. Invoke the **planning skill** with the phase deliverables + spec references.
   - Produces `docs/workstreams/<name>/plans/<phase>.md`. Handles Codex plan critique internally.
2. Invoke the **document-review skill** on the finalized plan (gaps, scope bloat, missing constraints,
   wrong spec refs, risky assumptions). Apply findings.
3. Present the plan for approval. Do **not** proceed without user approval.

### Step 3 — Execute Stages (drive off bd)

There is no hand-written checklist — the ready-front *is* `bd ready --parent <epic>`. Loop until no
ready stage remains:

1. **Select + claim atomically**: `bd ready --parent <epic> --claim --actor "cc:${CLAUDE_CODE_SESSION_ID:0:8}"`
   — returns one ready direct-child stage and flips it `in_progress` (non-skippable). If it returns a
   deeper descendant, filter to the direct child (`^<epic>\.[^.]+$`).
2. **Implement the stage:**
   - **deep** → invoke the **subagent-driven-development skill** with the plan (task packets, implementer
     dispatch, spec review, code review, Codex code review).
   - **standard** → implement directly from the roadmap's Spec Reference.
   - Marked **test-first** → invoke the **test-driven-development skill**.
   - Unexpected test failure → invoke the **systematic-debugging skill** before retrying.
3. **Close with evidence**: `bd close <stage-id> --reason "<verification evidence>" --actor "…"`. The
   reason is what renders into `progress.md` — if it's not in bd, it's not real.
4. **Discovered durable work** → `bd create --parent <epic> --deps discovered-from:<stage-id> --actor "…"`
   (becomes a new stage; do not let it vanish with the turn).
5. **Render if available**: if `scripts/bd-render-tracking.sh` exists, run
   `BD_RENDER=1 bash scripts/bd-render-tracking.sh <name>`. If it does not exist, leave generated
   mirrors absent and report the missing renderer. Confirm the stage to the user.

### Step 4 — Exit (the discipline gate)

1. **Gate** — a phase may close only when every stage is closed:
   `[ "$(bd list --parent <epic> --json | jq '[.[]|select(.status!="closed")]|length')" -eq 0 ]`.
   On failure, surface the unclosed stages
   (`bd list --parent <epic> --json | jq -r '.[]|select(.status!="closed")|.id+" "+.status'`) and **STOP** —
   the phase is not done.
2. Run the roadmap phase **exit criterion**.
3. Invoke the **verification-before-completion skill** to confirm the phase is genuinely done. If it
   fails: diagnose, fix, re-run. Do not skip.
4. Close the epic (`bd close <epic> --reason "<exit-criterion evidence>" --actor "…"`).

### Step 5 — Report

1. **Render if available**: if `scripts/bd-render-tracking.sh` exists, run
   `BD_RENDER=1 bash scripts/bd-render-tracking.sh <name>` (refreshes status/checklist/progress).
   If it does not exist, report that generated mirrors were not refreshed.
2. Run `git status` — report uncommitted changes (do not commit unless asked / running under `/run-phases`).
3. Summarize: what was built, test results, open items.

## What This Skill Owns

The phase lifecycle (load → plan → execute → gate → report), the bd work-state transitions, and the discipline gate.

## What This Skill Delegates

- **Plan creation + Codex plan critique** → planning skill
- **Plan quality gate** → document-review skill
- **Task dispatch + spec review + code review + Codex code review** → subagent-driven-development skill
- **Test-first execution** → test-driven-development skill
- **Unexpected failures** → systematic-debugging skill
- **Completion proof** → verification-before-completion skill
- **Brainstorming** → brainstorming skill (if requirements are unclear, return to brainstorm before planning)

## Rules

- Codex steps are expected when available, but remain best-effort under the capacity policy in `AGENTS.md`.
- Never mark a phase done without the **gate** (all stages closed) *and* the exit criterion.
- Never proceed past step 2 without user approval (deep phases).
- Never hand-edit the generated tracking files — update bd, then render.
- `--actor` on every bd write. If a stage is blocked or fails verification, stop and report.
- Do not edit submodule internals unless the task is explicitly submodule-local.
