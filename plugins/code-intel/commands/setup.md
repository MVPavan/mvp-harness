---
description: One-time per-machine setup for the code-intel stack — auto-detect serena/CBM/ast-grep, wire up the CODE_INTEL_*_BIN env vars, and print install commands for anything missing.
---

Get the code-intel stack working on this machine with minimal effort. The three
binaries are located at runtime via `CODE_INTEL_*_BIN` env vars or PATH; this
command finds them and helps you set those vars (or tells you how to install what
is missing).

1. **Discover** what is already present (read-only):
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover.sh"`

2. **Interpret the output** for the user:
   - `ON PATH` → nothing to do for that tool.
   - `OK (env …)` → already wired via an override var.
   - `FOUND off PATH` → the binary exists but isn't on PATH; the script prints a
     ready-to-paste `export CODE_INTEL_*_BIN=…` line.
   - `MISSING` → not installed; the script prints the install command.

3. **Wire up found-off-PATH tools.** If the script emitted any `export` lines,
   offer the user two options and act only on their choice:
   - **(a) User shell profile** — tell them to paste the `export` lines into
     `~/.bashrc` / `~/.zshrc` (persists for all tools, not just Claude Code).
   - **(b) Claude-scoped (recommended for Claude Code only)** — add them to the
     `env` block of `~/.claude/settings.json` (user scope, never committed). If
     they confirm, do it safely: Read `~/.claude/settings.json`, merge the keys
     into a top-level `"env": { … }` object **without clobbering** existing keys,
     and write it back. Show the diff first. Example shape:
     ```json
     { "env": { "CODE_INTEL_SERENA_BIN": "/abs/path/to/serena" } }
     ```

4. **Install anything MISSING.** Relay the install command from the discovery
   output. Recommended per tool (do not run installs without the user asking):
   - serena: `uv tool install -p 3.13 serena-agent` (needs `uv`)
   - CBM: `npm i -g codebase-memory-mcp` (binary only — the plugin registers the
     MCP server itself, so do NOT let CBM auto-configure; if using its curl
     installer add `--skip-config`)
   - ast-grep: `npm install --global @ast-grep/cli` (or brew / cargo / pip)

5. **Verify** after wiring/installing: re-run step 1, then `/code-intel:doctor`.
   Note: env vars added to `~/.claude/settings.json` or a shell profile only take
   effect in a **new** Claude Code session.

Do not edit the repo or commit anything. The only file you may modify (with
confirmation) is the user-scoped `~/.claude/settings.json`.
