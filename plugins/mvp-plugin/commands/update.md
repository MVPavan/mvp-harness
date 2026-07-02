---
description: Re-sync the reusable harness core into this repo from the plugin, without touching the filled project overlay.
---

# /mvp-plugin:update

Refresh the reusable core (rules, skills, agents, commands, hooks, docs,
`CLAUDE.md`/`AGENTS.md`) from the plugin's current payload. The per-repo overlay
(`.claude/project/*`, `.codex/project/*`) and your own config are preserved.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-harness.sh"
```

This is the same deterministic installer `/mvp-plugin:adopt` uses: identical files
are skipped, core files are updated in place (review with `git status` /
`git diff`), and user-owned files are never clobbered. It does **not** re-run the
overlay adaptation — run `/mvp-plugin:adopt` if you also want to refresh repo facts.
