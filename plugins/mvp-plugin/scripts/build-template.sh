#!/usr/bin/env bash
# Regenerate the harness plugin's template/ payload from this repo's canonical
# harness. The orchestrators repo is the single source of truth: edit .claude/
# .codex/ here, then re-run this to refresh the portable payload the plugin
# copies into other repos via /mvp-plugin:adopt.
#
# What it does:
#   - mirrors .claude/ and .codex/ into template/, EXCLUDING the per-repo overlay
#     (*/project/*) and the two Bodha-flavoured python rule files;
#   - drops in genericised python coding-style.md / safety.md from scripts/overrides;
#   - copies CLAUDE.md / AGENTS.md / .beads/beads.md, genericising the few
#     project-specific lines (submodule names, "no first-party source tree");
#   - sweeps machine-local paths out of the payload;
#   - self-checks that no project/machine string survived, and fails loudly if one did.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$PLUGIN_DIR/template"
OVR="$SCRIPT_DIR/overrides"

note() { printf '  %s\n' "$1"; }
die()  { printf 'build-template FAIL: %s\n' "$1" >&2; exit 1; }

# Locate the SOURCE harness (the orchestrators checkout that owns .claude/.codex).
# This plugin is its own git repo, so we can't use its git-toplevel — search up
# from the plugin's parent for an ancestor that has the harness, or honour an
# explicit HARNESS_SRC override. A standalone clone of just this plugin has no
# source harness — that's fine; the shipped template/ is already built.
REPO="${HARNESS_SRC:-}"
if [ -z "$REPO" ]; then
  d="$(dirname "$PLUGIN_DIR")"
  while [ "$d" != "/" ]; do
    if [ -d "$d/.claude/rules" ] && [ -d "$d/.codex" ] && [ "$d" != "$PLUGIN_DIR" ]; then REPO="$d"; break; fi
    d="$(dirname "$d")"
  done
fi

command -v rsync >/dev/null 2>&1 || die "rsync is required"
[ -n "$REPO" ] && [ -d "$REPO/.claude/rules" ] || \
  die "source harness not found — run from a checkout of the orchestrators harness, or set HARNESS_SRC=/path/to/harness"

printf '#### Regenerating template/ from %s\n' "$REPO"
mkdir -p "$TPL"

# 1. Mirror the two harness trees, minus overlay + Bodha python rules.
for tree in .claude .codex; do
  [ -d "$REPO/$tree" ] || { note "skip $tree (absent)"; continue; }
  rsync -a --delete \
    --exclude '/project/' \
    --exclude '/rules/python/coding-style.md' \
    --exclude '/rules/python/safety.md' \
    "$REPO/$tree/" "$TPL/$tree/"
  note "mirrored $tree"
done

# 2. Genericised python rules into whichever harness trees ship them.
for tree in .claude .codex; do
  if [ -d "$TPL/$tree/rules/python" ]; then
    cp "$OVR/python/coding-style.md" "$TPL/$tree/rules/python/coding-style.md"
    cp "$OVR/python/safety.md"       "$TPL/$tree/rules/python/safety.md"
    note "generic python rules -> $tree"
  fi
done

# 3. Root instruction files + beads policy doc.
cp "$REPO/CLAUDE.md" "$TPL/CLAUDE.md"
cp "$REPO/AGENTS.md" "$TPL/AGENTS.md"
mkdir -p "$TPL/.beads"
cp "$REPO/.beads/beads.md" "$TPL/.beads/beads.md"
note "copied CLAUDE.md, AGENTS.md, .beads/beads.md"

# 4. Genericise the few project-specific lines in CLAUDE.md / AGENTS.md.
genericize() {
  local f="$1"
  perl -0pi -e 's/`external\/gascity` and `external\/gastown` are Git submodules\./External upstream projects, if any, are tracked as Git submodules under `external\/` (see `.gitmodules`)./g' "$f"
  perl -0pi -e 's/This repo currently has no first-party source tree or test suite\. Use the structural checks/Until the repo has real first-party code and CI, use the structural checks/g' "$f"
  perl -0pi -e 's/ until real code and CI exist\././g' "$f"
}
genericize "$TPL/CLAUDE.md"
genericize "$TPL/AGENTS.md"
note "genericised submodule + verification lines"

# 5. Sweep machine-local paths and project-specific EXAMPLE tokens out of the
#    payload (these appear as illustrative examples in reusable skills/docs).
while IFS= read -r -d '' f; do
  perl -pi -e '
    s{/home/pavanmv}{\$HOME}g;
    s{/data/codes/orchestrators}{<repo-root>}g;
    s/\bgastown\b/<name>/g;
    s/\bgascity\b/<name>/g;
    s/Bodha/the project/g;
  ' "$f"
done < <(find "$TPL" -type f \( -name '*.md' -o -name '*.py' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' -o -name '*.json' -o -name '*.sh' -o -name '*.mjs' -o -name '*.rules' -o -name '*.txt' \) -print0)
note "swept machine-local paths + example tokens"

# 6. Self-check: nothing project/machine-specific may survive in the payload.
fail=0
check() { # pattern human-label
  local hits
  hits="$(grep -rnI -- "$1" "$TPL" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf 'LEAK (%s):\n%s\n' "$2" "$hits" >&2
    fail=1
  fi
}
check 'Bodha'            'project name'
check 'gascity'          'submodule name'
check 'gastown'          'submodule name'
check '/home/pavanmv'    'machine path'
check '/data/codes'      'machine path'
[ "$fail" -eq 0 ] || die "project/machine-specific strings leaked into template/ (see LEAK lines above)"

# 7. Summary.
n_claude=$(find "$TPL/.claude" -type f 2>/dev/null | wc -l | tr -d ' ')
n_codex=$(find "$TPL/.codex" -type f 2>/dev/null | wc -l | tr -d ' ')
printf '#### template/ regenerated: %s files under .claude, %s under .codex, plus CLAUDE.md/AGENTS.md/.beads/beads.md\n' "$n_claude" "$n_codex"
printf 'OK: no project/machine-specific strings in payload.\n'
