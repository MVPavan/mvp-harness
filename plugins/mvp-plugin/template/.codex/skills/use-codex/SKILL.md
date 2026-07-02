---
name: use-codex
description: Choose and invoke the right Codex surface for project automation, reviews, rescue tasks, and cross-agent workflows. Use when asked how to run Codex from this repo, review local changes, launch noninteractive Codex work, or replace old Claude-plugin Codex commands with repo-native Codex CLI/app primitives.
---

# Use Codex

Use this skill to choose Codex-native surfaces. The old Claude Code Codex plugin command flow is legacy; this repo's default direction is direct Codex CLI/app usage.

## Source Order

1. Current official Codex manual or current `codex --help` output.
2. `docs/research/codex-usage-options.md`.
3. `.codex/project/tools.md`.
4. Legacy `.codex/docs/codex-usage-guide.md` only as historical context.

If sources disagree, prefer the current official manual and verified local CLI behavior.

## Default Choices

- **Implement or answer from the repo:** use the current Codex session.
- **Noninteractive task:** `codex exec "<prompt>"`.
- **Resume a noninteractive task:** `codex exec resume <session-id>` or `codex exec resume --last`.
- **Review local changes:** `codex review` or `codex exec review`, depending on the needed output path.
- **Cloud/offloaded work:** `codex cloud` after a cloud environment exists.
- **Cross-agent bridge:** consider `codex mcp-server` or the Codex SDK only when another runtime needs Codex as a callable tool.
- **Custom reusable workflow:** write a skill in `.codex/skills`.
- **Reusable shared distribution:** package skills and integrations as a plugin.

## Operational Rules

- Keep `agents.max_depth = 1` unless a task explicitly needs recursive delegation.
- Do not invoke multiple heavyweight Codex review/rescue jobs concurrently unless the user asks for parallelism and accepts the cost.
- Verify every Codex citation against live files before relying on it.
- For current docs/API/CLI uncertainty, use official docs or primary source lookup; do not invent flags or config keys.
- On capacity or auth failure, retry once when reasonable, then proceed without Codex and log the skip.
- Use repo-relative paths in prompts and artifacts.

## Review Prompt Pattern

For a review, make the scope explicit:

```text
codex review --base <ref>
```

or:

```text
codex exec review --base <ref>
```

When asking for adversarial critique, include the risk focus in the prompt and require file/line evidence.

## Migration Note

Codex custom prompts are deprecated. Old Claude slash-command workflows should become Codex skills unless they are one-off personal prompts in `~/.codex/prompts`.
