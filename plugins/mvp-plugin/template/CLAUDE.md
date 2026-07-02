<!-- bd-doctor-divergence: ok -->
# Agent Operating Guide

Always-loaded entry point — every line here costs context. Detail lives in the pointed-to docs; keep it there.
Core harness is stable; repo-specific facts live in `.claude/project/`.

## Critical guidelines

- Prioritize factual accuracy over agreement with me.
- Point out errors and unchecked assumptions in my thinking.
- When I ask you to assess something, do so critically and avoid grade inflation.
- Distinguish certain knowledge from inference from speculation.
- If unsure, say so. Never fabricate citations, data, or examples.

## Read Order

1. `AGENTS.md`
2. `.claude/project/`: `brief.md`, `repo-map.md` (folder structure + how to orient), `docs-index.md`, `verification.md`, `invariants.md`
3. `docs/research/` — when working from prior research, runtime comparisons, or provider/tooling decisions
4. `docs/workstreams/<name>/roadmap.md` (active workstream plan) + generated workstream mirrors — when a workstream exists
5. Relevant rules under `.claude/rules/`
6. `external/<name>/` docs — only when the task is explicitly about that submodule

## Coding guideline

1. Follow `.claude/rules/core/03-ak-guidelines.md` — coding rules that reduce common LLM mistakes.
2. Use `html-artifact` only when the user asks for HTML, or when the deliverable is purely for human reading and richer structure clearly helps. Do not use it for agent prompts, README files, harness docs, or other Markdown-native repo files.

## Working Mode

Classify the task before acting.

- `small`: 1-2 files, low ambiguity, reversible. Execute directly, then self-check.
- `standard`: bounded feature, bug fix, or refactor. Short plan before coding.
- `deep`: cross-cutting, high-risk, or ambiguous. Brainstorm, plan, review, execute via subagents, capture learnings.

Lean by default. Match ceremony to scope and risk.

## Process Before Execution

- unclear or exploratory request: brainstorm first
- approved requirements plus multi-step code work: plan first
- newly written requirements or plan docs: review the document before execution
- risky behavior change or fragile legacy area: test-first or characterization-first
- bug, failure, or confusing behavior: systematic-debugging before proposing fixes
- approved plan with bounded tasks: subagent-driven development
- about to claim success: verify before completion

If the user already supplied a clear, approved plan, do not re-run brainstorming.

## Phase Execution

Explicit phase execution implementation work runs through `/phase-execution N` (full cycle: planning → subagent-dev → TDD → debugging → verification). Phase inventory: `docs/workstreams/<name>/roadmap.md`; work-state in Beads.

## Claude and Codex

Applies only when the Codex plugin is available. Codex is a **one-way, best-effort critic** — it reviews your completed output; no reverse loop. `small` tasks: skip Codex unless risk is unusual. For **any** invocation, follow [`.claude/commands/use-codex.md`](.claude/commands/use-codex.md) (authoritative — invocation path, operational rules, which command for what). Capacity errors: retry once, then proceed without it and log the skip. Detail: `.claude/project/tools.md`.

## Tools & Subagents

Unsure about a library/SDK/API/CLI (methods, signatures, config, versions)? Use official/reference docs via the **`docs-researcher`** subagent where available; never invent APIs. Use brainstorming for open-ended project research, tradeoffs, and requirements decisions. Tool routing details live in `.claude/project/tools.md`.

## Verification

No completion claims without fresh evidence.

1. Identify the command that proves the claim.
2. Run it.
3. Read the output and exit status.
4. Report the actual result.
5. Check `git status` before presenting completion.

Source of truth: `.claude/project/verification.md` and `.claude/project/invariants.md`.

Until the repo has real first-party code and CI, use the structural checks in `.claude/project/verification.md`.

## Learnings

Record verified, likely-to-recur patterns in `.claude/project/learnings.md` (format + rules in its header).

## Git Safety

- Stage explicit files only. No `git add .`, `git add -A`, `--no-verify`, force-push, `reset --hard`, `clean`, `restore`, or `checkout` rewrites without explicit approval.
- Small reversible commits. Do not amend unless the user asks.
- Do not overwrite unrelated user changes.
- Do not encode machine-local absolute paths in plans, prompts, docs, or rules.
- Use `scratchpad/` for throwaway work — gitignored, never commit it.

## External Submodules

External upstream projects, if any, are tracked as Git submodules under `external/` (see `.gitmodules`). The parent repo tracks their commit pointers only. Do not edit submodule internals unless the task is explicitly submodule-local; for upstream sync, update and stage the submodule path.

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Workflow, rules, agent context profiles, and the session-completion protocol live in **[`.beads/beads.md`](.beads/beads.md)**. Run `bd prime` for runtime context.
