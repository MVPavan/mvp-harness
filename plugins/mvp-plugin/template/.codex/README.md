# .codex

Repo-local Codex-facing assets for this project.

## Map

- [`config.toml`](config.toml) — trusted project-scoped Codex settings.
- [`hooks.json`](hooks.json) and [`hooks/`](hooks/) — Codex lifecycle hooks.
- [`rules/default.rules`](rules/default.rules) — Codex exec-policy rules for high-risk command prefixes.
- [`agents/`](agents/) — Codex custom agent roles migrated from Claude subagents.
- [`project/`](project/) — authoritative repo-specific facts and verification guidance.
- [`docs/`](docs/) — historical/reference docs copied from the prior harness. Treat these as legacy unless indexed as authoritative by `project/docs-index.md`.

## Skills

- [`skills/adopt/`](skills/adopt/) — adapt the Codex project overlay to a repository.
- [`skills/check-invariants/`](skills/check-invariants/) — run mechanically checkable project invariants.
- [`skills/codebase-architecture-research/`](skills/codebase-architecture-research/) — reusable workflow for studying an external codebase such as `external/<name>` and writing both agent-facing Markdown reports and human-review HTML under `docs/research/codebases/<slug>/`.
- [`skills/prepare-phases/`](skills/prepare-phases/) — create a Beads-backed workstream from docs or research.
- [`skills/run-phases/`](skills/run-phases/) — run incomplete workstream phases sequentially.
- [`skills/use-codex/`](skills/use-codex/) — choose Codex-native invocation surfaces.

The remaining folders under `skills/` are reusable workflows migrated from `.claude/skills/`.

Keep runtime state, credentials, and local Codex caches out of this directory.

The current local `codex-cli 0.139.0` was verified with `codex debug prompt-input` to load this repo's `.codex/skills` directory. The public Codex manual also documents `.agents/skills` as a repo skill location; if a future runtime stops loading `.codex/skills`, keep this directory as the tracked source of truth and add reviewed compatibility links or copies under the runtime-specific location.
