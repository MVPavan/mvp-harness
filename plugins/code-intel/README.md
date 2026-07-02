# code-intel

A Claude Code **plugin + single-plugin marketplace** that packages the chosen
code-intelligence stack for token-cheap maintenance of large codebases:

| Tool | Role | Surfaced as |
|---|---|---|
| **serena** | LSP-exact navigation + symbol-level editing (rename / replace-body / safe-delete) | MCP server (`stdio`, `--context claude-code`) |
| **CBM** (codebase-memory-mcp) | Auto-sync knowledge graph + local semantic/NL search + diff impact | MCP server (`stdio`) |
| **ast-grep** | Structural search / rewrite / YAML lint-rules | `bin/ast-grep` on PATH (no MCP) |
| graph-first workflow | "query the graph before reading files; stop on bounded evidence" | model-invoked **skill** |

Design rationale and the evidence behind the tool choices live in
`docs/research/harness/tooling-decision-and-adoption-plan.md` (orchestrators repo).

## How binaries are located (no machine-local paths committed)

`bin/serena`, `bin/cbm`, `bin/ast-grep` are tiny resolver shims. Each finds the
real binary in this order: an explicit env var, then PATH, then **fails loud**
with an actionable message. The plugin never hardcodes an absolute path, so the
same committed plugin works on any machine.

If the tools are already on PATH under their canonical names (`serena`,
`codebase-memory-mcp`, `ast-grep`), **nothing to do** — they're auto-found.

Otherwise set the override env vars once per machine (shell profile, or the `env`
block of `~/.claude/settings.json` — user scope, never committed):

```sh
export CODE_INTEL_SERENA_BIN=/abs/path/to/.venv/bin/serena
export CODE_INTEL_CBM_BIN=/abs/path/to/codebase-memory-mcp
export CODE_INTEL_ASTGREP_BIN=/abs/path/to/ast-grep   # NOT the system `sg` (that's newgrp)
```

**Easiest:** run `/code-intel:setup` — it auto-detects the binaries in known
locations (including this repo's cloned `external/harness_repos/…`), offers to
write the env vars into `~/.claude/settings.json`, and prints install commands for
anything missing. `/code-intel:doctor` is the read-only diagnose version.

## Installing the underlying tools

You only need each binary on PATH (or pointed-to by its env var) — the plugin
handles all MCP wiring, so do **not** let a tool auto-configure Claude Code itself.

| Tool | Recommended | Alternatives | Notes |
|---|---|---|---|
| **serena** | `uv tool install -p 3.13 serena-agent` | `uvx -p 3.13 --from git+https://github.com/oraios/serena serena` (no install) | needs [`uv`](https://docs.astral.sh/uv/); Python 3.11–3.14. Lands at `~/.local/bin/serena`. |
| **CBM** | `npm i -g codebase-memory-mcp` | official `install.sh` run with `--skip-config` (see `/code-intel:setup`) · AUR `yay -S codebase-memory-mcp-bin` | zero runtime deps (static binary). npm / `--skip-config` install the **binary only** — the plugin registers the MCP server, so skip CBM's own agent auto-config to avoid a duplicate. |
| **ast-grep** | `npm install --global @ast-grep/cli` | `brew install ast-grep` · `cargo install ast-grep --locked` · `pip install ast-grep-cli` | installs `ast-grep` (+ an `sg` alias — ignore it; system `sg` is newgrp). |

## Enable it (per project)

This marketplace is enabled per-repo so projects that don't need code intelligence
pay nothing. In a repo's `.claude/settings.json` (or via `/plugin`):

```json
{
  "extraKnownMarketplaces": {
    "code-intel": { "source": { "source": "git", "...": "point at where this dir is hosted" } }
  },
  "enabledPlugins": { "code-intel@code-intel": true }
}
```

Opt a single repo out with `/code-intel:disable-for-project`.

### Why per-project (overhead)
serena + CBM mount ~35K of tool schema on the first turn. Current Claude Code
defers that via **MCP Tool Search** (auto-on when MCP schema exceeds ~10% of
context), so an enabled repo pays only a fraction up front. But starting the
serena LSP + CBM watcher still has process/index cost — so enable only where a
real codebase benefits. If you route Claude Code through a proxy/gateway that
disables Tool Search, per-project enablement keeps the schema tax contained.

## Index a repo (once)

```
/code-intel:index-repo
```

Runs CBM `index_repository` for the project and turns on `auto_index` (background
watcher keeps the graph fresh after edits). serena activates over LSP
automatically. A lightweight SessionStart hook nudges you if a repo is unindexed.

## Commands

- `/code-intel:setup` — one-time per-machine: auto-detect binaries, wire up the
  `CODE_INTEL_*_BIN` env vars, install what's missing.
- `/code-intel:index-repo` — build/refresh the CBM index for this repo.
- `/code-intel:doctor` — check binary resolution, index state, and Tool Search.
- `/code-intel:disable-for-project` — turn the stack off for this repo only.

## Layout

```
code-intel/
  .claude-plugin/{marketplace.json, plugin.json}
  .mcp.json              serena + CBM MCP servers (${CLAUDE_PLUGIN_ROOT}/bin/*)
  bin/{serena,cbm,ast-grep}   resolver shims (env -> PATH -> fail loud)
  lib/resolve.sh         shared resolution helper (sourced by shims)
  scripts/discover.sh    locate binaries across known install locations
  skills/graph-first/SKILL.md
  commands/{setup,index-repo,doctor,disable-for-project}.md
  hooks/{hooks.json, freshness-check.sh}
```
