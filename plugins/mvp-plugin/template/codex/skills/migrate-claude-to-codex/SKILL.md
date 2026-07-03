---
name: migrate-claude-to-codex
description: Migrate a Claude Code harness into Codex-native repo assets. Use when a repository has .claude agents, commands, skills, hooks, rules, docs, or project overlays that should become .codex skills, agents, hooks, rules, config, and project docs; also use when verifying whether Codex can discover the migrated harness.
---

# Migrate Claude To Codex

## Overview

Use this skill to perform a conservative Claude Code to Codex harness migration. Prefer the bundled script for mechanical inventory, copying, command-to-skill conversion, agent TOML generation, and structural verification; keep final project facts and behavior claims under human/agent review.

## Workflow

1. Read `AGENTS.md`, `.codex/project/docs-index.md` if present, and existing `.claude/` files.
2. Run a dry-run inventory:

```bash
python3 .codex/skills/migrate-claude-to-codex/scripts/migrate_claude_to_codex.py migrate --repo .
```

3. Review the planned actions. If the target repo already has `.codex/`, decide whether to keep existing files or use `--force` for selected reruns.
4. Apply the migration only after the dry-run looks right:

```bash
python3 .codex/skills/migrate-claude-to-codex/scripts/migrate_claude_to_codex.py migrate --repo . --apply
```

5. Manually review migrated content for provider-specific assumptions:
   - Claude model names in agent files should not be copied into Codex configs unless they are valid Codex model names.
   - Claude slash commands should become Codex skills; shared workflows should not stay only as custom prompts.
   - Claude hook scripts may need JSON-schema adjustments before they are safe as Codex hooks.
   - Project overlays should reference `.codex/project`, not `.claude/project`.
6. Verify the result:

```bash
python3 .codex/skills/migrate-claude-to-codex/scripts/migrate_claude_to_codex.py verify --repo .
```

7. If `codex` is installed, also verify real discovery:

```bash
codex debug prompt-input "verify codex harness discovery" | rg -n ".codex/skills|Available skills"
```

## What The Script Migrates

- `.claude/skills/*` to `.codex/skills/*`, normalizing `SKILL.MD` to `SKILL.md`.
- `.claude/commands/**/*.md` to `.codex/skills/<command-name>/SKILL.md`.
- `.claude/agents/*.md` to `.codex/agents/*.toml` using conservative Codex agent fields.
- `.claude/project`, `.claude/docs`, and `.claude/rules` to `.codex/project`, `.codex/docs`, and `.codex/rules`.
- `.claude/hooks` to `.codex/hooks` and `.claude/settings.json` hook registrations to `.codex/hooks.json` when safe to generate.
- A default `.codex/config.toml`, `.codex/rules/default.rules`, and `.codex/docs/codex-migration-notes.md` when missing.

The script never deletes `.claude/`, never stages or commits files, and does not overwrite existing targets unless `--force` is used.

## Review Rules

- Treat migration output as a scaffold, not proof of semantic equivalence.
- Prefer repo-relative paths in migrated docs.
- Preserve `.claude/` as a legacy/source harness until the user explicitly asks to remove it.
- Use official Codex docs or current local `codex` help when changing config, hooks, rules, skills, or agents.
- Run the target repo's documented verification checks before claiming the migration is complete.

## References

- Read `references/mapping.md` for the migration mapping and known caveats before changing the script's behavior.
