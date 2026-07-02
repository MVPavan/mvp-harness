# mvp-harness

A single Claude Code plugin **marketplace** bundling PavanMV's agent-harness plugins.

## Plugins

| Plugin | Version | What it does |
| --- | --- | --- |
| `mvp-plugin` | 0.1.0 | Copy a self-contained agent harness into any repo — rules, skills, agents, hooks, `CLAUDE.md`/`AGENTS.md`, beads tracking. `adopt` installs, `doctor` verifies, `update` re-syncs. |
| `code-intel` | 0.1.0 | Graph-first code intelligence: serena & CBM MCP servers + ast-grep. Query the symbol graph before reading files to cut tokens on large repos. |
| `codex-adapter` | 1.0.1 | Call OpenAI Codex (gpt-5.x) from Claude Code via `codex exec` — roles, free-form delegation, true concurrency, no broker. |

## Layout

```
mvp-harness/
├── .claude-plugin/
│   └── marketplace.json   # the one catalog; lists all three plugins
└── plugins/
    ├── mvp-plugin/        └── .claude-plugin/plugin.json
    ├── code-intel/        └── .claude-plugin/plugin.json
    └── codex-adapter/     └── .claude-plugin/plugin.json
```

Each plugin is referenced in-tree via `"source": "./plugins/<name>"`.

## Install

Register the marketplace once (local path or, once published, the GitHub URL):

```
/plugin marketplace add <path-to>/mvp-harness
```

Then install any plugin by `name@marketplace`:

```
/plugin install mvp-plugin@mvp-harness
/plugin install code-intel@mvp-harness
/plugin install codex-adapter@mvp-harness
```

Adding the marketplace only makes the plugins available; it does not install them.
