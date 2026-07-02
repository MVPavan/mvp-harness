---
description: Index the current repo into CBM (and confirm serena activation) so graph queries work. Run once per repo; CBM auto-syncs after.
---

Build the code-intelligence index for this project so serena/CBM graph queries
return results instead of `project not found or not indexed`.

Run these via Bash, using the plugin's resolver shim (no machine paths needed).
CBM's `cli` prints its JSON result to **stderr**, so append `2>&1` to capture it:

1. Index the repo into CBM (ms-fast; out-of-band, ~0 agent tokens):
   `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" cli index_repository "{\"repo_path\":\"${CLAUDE_PROJECT_DIR}\"}" 2>&1`

2. Enable the background watcher so the graph stays fresh after edits:
   `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" config set auto_index true 2>&1`

3. Verify it took. CBM keys projects by a path-slug **name** (not the path), so
   confirm via `list_projects` — look for an entry whose `root_path` is
   `${CLAUDE_PROJECT_DIR}` and note its `name`:
   `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" cli list_projects "{}" 2>&1`

4. Resolve that project name (every CBM query needs it) and show fresh status:
   `name="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cbm-project.sh" "${CLAUDE_PROJECT_DIR}")"; echo "project=$name"`
   `"${CLAUDE_PLUGIN_ROOT}/bin/cbm" cli index_status "{\"project\":\"$name\"}" 2>&1`

Then report: node/edge counts, `auto_index` on, and the project name `$name` —
**all CBM query tools (`search_graph`, `trace_path`, `detect_changes`, …) take it
as their required `project` argument.** serena needs no explicit indexing — it
activates this project over LSP when its MCP server starts. If any `bin/cbm` call
reports the binary is missing, run `/code-intel:doctor`.

Do NOT read large parts of the repo to "warm" anything — indexing is the tool's
job, not yours.
