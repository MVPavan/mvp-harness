# Codex Migration Notes

Date: 2026-06-13

## Sources Checked

- Official Codex manual fetched with `openai-docs` helper: `https://developers.openai.com/codex/codex-manual.md`.
- Codex CLI local version: `codex-cli 0.139.0`.
- OpenAI Codex repository: `https://github.com/openai/codex`.
- OpenAI Skills catalog: `https://github.com/openai/skills`.
- Codex hook source for `PreToolUse` and hook schemas:
  - `https://raw.githubusercontent.com/openai/codex/main/codex-rs/hooks/src/events/pre_tool_use.rs`
  - `https://raw.githubusercontent.com/openai/codex/main/codex-rs/hooks/src/schema.rs`

## Mapping Decisions

| Claude surface | Codex destination | Rationale |
| --- | --- | --- |
| `.claude/project/` | `.codex/project/` | Codex project facts should be first-class and referenced by `AGENTS.md`. |
| `.claude/skills/` | `.codex/skills/` | Local `codex debug prompt-input` verified this repo's `.codex/skills` are loaded by the current CLI. |
| `.claude/commands/*.md` | `.codex/skills/<command>/SKILL.md` | Current Codex docs mark custom prompts as deprecated for shared workflows and migration maps slash commands to skills. |
| `.claude/agents/*.md` | `.codex/agents/*.toml` | Current Codex docs define project custom agents as TOML files under `.codex/agents/`. |
| `.claude/hooks/*` and `.claude/settings.json` | `.codex/hooks.json` plus `.codex/hooks/` | Codex hooks use `hooks.json` or inline TOML next to active config layers. |
| Claude safety hook patterns | `.codex/hooks/` plus `.codex/rules/default.rules` | Hooks inspect full tool input; rules guard high-risk outside-sandbox command prefixes. |
| `.claude/rules/*.md` | `.codex/rules/*.md` plus `.codex/rules/default.rules` | Guidance docs remain useful; `.rules` is the Codex exec-policy format. |

## Important Caveat

The public manual documents `.agents/skills` as a repo skill location, while the current local CLI in this repo rendered `.codex/skills/codebase-architecture-research/SKILL.md` in `codex debug prompt-input`. This migration keeps `.codex/skills` as the tracked active source for this repository. If a future Codex runtime stops loading `.codex/skills`, add reviewed compatibility links or copies under the runtime-supported location rather than moving the source of truth blindly.
