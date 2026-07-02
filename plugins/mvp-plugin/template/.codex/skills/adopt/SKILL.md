---
name: adopt
description: Adopt this reusable agent setup to a repository by refreshing only the Codex project overlay files. Use when asked to adapt the harness to the current repo, update repo facts, or produce an adoption report without rewriting reusable core skills, agents, hooks, or rules.
---

# Adopt This Setup

Use this after the setup has been copied into a target repository root.

## Goal

Keep the core harness stable. Update only `.codex/project/*` with facts derived from the current repo.

## Workflow

1. Read:
   - `AGENTS.md`
   - this skill
   - `.codex/project/*.md`
2. Scan the target repo in this order:
   - root instruction files
   - README and design docs
   - manifests, lock files, CI, and test config
   - relevant source and test directories
3. Use this authority order:
   - repo reality
   - current config and CI
   - maintained docs
   - older docs
   - explicit assumptions
4. Verify claims against the actual repo when possible.
5. Update only:
   - `.codex/project/brief.md`
   - `.codex/project/repo-map.md`
   - `.codex/project/verification.md`
   - `.codex/project/invariants.md`
   - `.codex/project/docs-index.md`
   - `.codex/project/tools.md`
   - `.codex/project/tracking.md`
   - `.codex/project/learnings.md`
   - `.codex/project/adoption-report.md`
6. Use repo-relative paths only.
7. For standard or deep adoption work, get an independent Codex review or subagent critique when capacity and tooling permit.
8. Stop and present the adoption report for review.

## Rules

- Do not rewrite core rules, agents, hooks, or skills unless the user asks.
- Do not copy unverifiable design-doc claims into project facts.
- Do not invent verification commands. If local commands are unclear, say so in `verification.md` and keep the completion gate structural until real code, manifests, or CI exist.
- If the repo has a language-specific stack, document the observed commands and any mismatch with `.codex/rules/` in the adoption report.
