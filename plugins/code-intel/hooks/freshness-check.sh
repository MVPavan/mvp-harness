#!/usr/bin/env bash
# code-intel SessionStart hook: nudge if this repo isn't indexed in CBM.
# NEVER blocks the session — always exits 0; failures stay silent by design.
#
# CBM identifies projects by a path-slug NAME and its query tools require an
# explicit `project` arg, so we can't ask "is <repo_path> indexed?" directly.
# Instead we list projects and check whether any project's root_path is this repo.
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

# `cli` writes its result to stderr; capture both. A non-zero exit means CBM is
# missing / timed out / errored -> stay silent (nothing actionable at startup).
out="$(timeout 8 "$PLUGIN_ROOT/bin/cbm" cli list_projects '{}' 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || exit 0

case "$out" in
  *"\"root_path\":\"$PROJECT\""*) ;;   # this repo is indexed -> stay silent
  *) printf '[code-intel] %s is not indexed for graph queries. Run /code-intel:index-repo to enable serena/CBM code intelligence (cuts tokens on large repos).\n' "$PROJECT" ;;
esac
exit 0
