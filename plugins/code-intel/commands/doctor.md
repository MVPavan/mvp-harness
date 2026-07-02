---
description: Diagnose the code-intel stack — check that serena, CBM, and ast-grep resolve, whether this repo is indexed, and print fix-up exports if a binary is missing.
---

Diagnose the `code-intel` plugin and report a short status table. Run the checks
below via Bash and summarize results plus any fixes.

1. Binary resolution (each shim resolves env var -> PATH -> fails loud):
   - `"${CLAUDE_PLUGIN_ROOT}/bin/serena" --help >/dev/null 2>&1 && echo "serena: OK" || echo "serena: MISSING — set CODE_INTEL_SERENA_BIN"`
   - `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" --version 2>/dev/null && echo "cbm: OK" || echo "cbm: MISSING — set CODE_INTEL_CBM_BIN"`
   - `"${CLAUDE_PLUGIN_ROOT}/bin/ast-grep" --version 2>/dev/null && echo "ast-grep: OK" || echo "ast-grep: MISSING — set CODE_INTEL_ASTGREP_BIN"`

2. Index state for this repo. CBM keys projects by a path-slug **name** (not the
   path), and its `cli` prints to **stderr** (use `2>&1`). Check membership by
   `root_path`, and resolve the project name queries will need:
   - `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" cli list_projects "{}" 2>&1`  (find the entry whose `root_path` is `${CLAUDE_PROJECT_DIR}`)
   - `name="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cbm-project.sh" "${CLAUDE_PROJECT_DIR}")"; echo "project=${name:-<not indexed>}"`
   - If empty / not listed, tell the user to run `/code-intel:index-repo`.

3. Tool Search (controls whether the ~35K MCP schema is deferred):
   - Note whether `ENABLE_TOOL_SEARCH` is set and whether `ANTHROPIC_BASE_URL` is
     set (a proxy/gateway can disable Tool Search): `env | grep -E "ENABLE_TOOL_SEARCH|ANTHROPIC_BASE_URL" || echo "(neither set — relying on default Tool Search)"`

4. If any binary is MISSING, run discovery — it scans known install locations
   (incl. this repo's cloned harness) and prints ready-to-paste exports for found
   binaries, or the install command for missing ones:
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover.sh"`
   - Relay its `export CODE_INTEL_*_BIN=…` lines and/or install hints. To actually
     wire things up (incl. writing the env vars to user settings), point the user
     to `/code-intel:setup`. Reminder: system `sg` is newgrp, not ast-grep.

Report a compact table (tool | resolved? | path-or-fix) and the index state.
