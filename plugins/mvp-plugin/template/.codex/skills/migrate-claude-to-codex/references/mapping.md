# Claude Code To Codex Migration Mapping

Use this reference when reviewing or extending `scripts/migrate_claude_to_codex.py`.

| Claude Code surface | Codex destination | Automation level |
| --- | --- | --- |
| `.claude/skills/<name>/SKILL.md` | `.codex/skills/<name>/SKILL.md` | Copy and path-normalize. |
| `.claude/skills/<name>/SKILL.MD` | `.codex/skills/<name>/SKILL.md` | Copy and normalize case. |
| `.claude/commands/**/*.md` | `.codex/skills/<command>/SKILL.md` | Convert each command document into a skill. |
| `.claude/agents/*.md` | `.codex/agents/*.toml` | Convert frontmatter/body into conservative Codex agent TOML. |
| `.claude/project/` | `.codex/project/` | Copy and path-normalize; review facts manually. |
| `.claude/docs/` | `.codex/docs/` | Copy as reference or historical docs. |
| `.claude/rules/**/*.md` | `.codex/rules/**/*.md` | Copy as guidance docs. Codex exec policy still needs `.rules`. |
| `.claude/hooks/` | `.codex/hooks/` | Copy scripts, but review JSON input expectations. |
| `.claude/settings.json` hooks | `.codex/hooks.json` | Best-effort path conversion only. |
| Claude slash command names | Codex skill names | Normalize path components to lowercase hyphen-case. |

## Caveats

- Codex custom prompts are not the preferred shared-workflow surface; migrate reusable command workflows to skills.
- Do not preserve Claude-only model IDs in Codex agent TOML unless current Codex docs confirm they are valid.
- Hook blocking semantics are similar enough to scaffold, but hook event payload shapes can differ. Test hook fixtures before trusting enforcement.
- Never remove `.claude/` its critical to project.
