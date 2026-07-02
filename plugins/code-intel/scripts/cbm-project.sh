#!/usr/bin/env bash
# Print the CBM project NAME whose root_path == <repo>. CBM's query tools
# (search_graph, index_status, trace_path, detect_changes, …) all REQUIRE an
# explicit `project` arg, and the name is a path-slug — so look it up via
# list_projects rather than deriving it. Prints nothing if the repo isn't indexed
# or on any error (callers should treat empty as "not indexed / unknown").
# Usage: cbm-project.sh [repo-path]   (defaults to $CLAUDE_PROJECT_DIR or $PWD)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBM="$SELF_DIR/../bin/cbm"
REPO="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"

out="$("$CBM" cli list_projects '{}' 2>&1)" || exit 0
command -v node >/dev/null 2>&1 || exit 0   # name extraction needs a JSON parser

printf '%s' "$out" | node -e '
let s="";
process.stdin.on("data", d => s += d).on("end", () => {
  const repo = process.argv[1];
  const line = s.split("\n").map(x => x.trim()).filter(Boolean).reverse().find(l => l.startsWith("{"));
  if (!line) return;
  try {
    const j = JSON.parse(line);
    const p = (j.projects || []).find(p => p.root_path === repo);
    if (p && p.name) process.stdout.write(p.name);
  } catch {}
});' "$REPO"
