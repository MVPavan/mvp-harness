---
name: check-invariants
description: Run mechanically checkable invariants from the Codex project overlay and report pass or fail. Use when asked to check project invariants, validate repo structure, or audit whether documented constraints still match the working tree.
---

# Check Invariants

Read `.codex/project/invariants.md` and run each listed check.

## Rules

- Only run invariants with explicit commands.
- Report pass or fail per invariant.
- If an invariant is aspirational rather than mechanically checkable, say so and skip it.
- Use repo-relative paths only when presenting results.
