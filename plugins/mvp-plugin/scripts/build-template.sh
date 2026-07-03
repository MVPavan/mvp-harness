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
EXCLUDE_FILE="$SCRIPT_DIR/template-exclude.txt"

note() { printf '  %s\n' "$1"; }
die()  { printf 'build-template FAIL: %s\n' "$1" >&2; exit 1; }
hashof() {  # portable sha256 (sha256sum on Linux, shasum on macOS)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

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

# 1. Mirror the two harness trees (dotted source -> dot-less payload), minus the
#    per-repo overlay, the project-flavoured python rules, and curation-only
#    harness-lifecycle tooling (template-exclude.txt) that must stay root-only so
#    the shipped template is a strict SUBSET of the root harness. The payload is
#    stored dot-less so the source harness's own Claude Code does not scan
#    template/.claude as project skills; install-harness.sh restores the dots.
[ -f "$EXCLUDE_FILE" ] || die "template exclude list not found: $EXCLUDE_FILE"
for tree in claude codex; do
  [ -d "$REPO/.$tree" ] || { note "skip .$tree (absent)"; continue; }
  rsync -a --delete \
    --exclude '/project/' \
    --exclude '/rules/python/coding-style.md' \
    --exclude '/rules/python/safety.md' \
    --exclude-from "$EXCLUDE_FILE" \
    "$REPO/.$tree/" "$TPL/$tree/"
  note "mirrored .$tree -> $tree"
done

# 2. Genericised python rules into whichever harness trees ship them.
for tree in claude codex; do
  if [ -d "$TPL/$tree/rules/python" ]; then
    cp "$OVR/python/coding-style.md" "$TPL/$tree/rules/python/coding-style.md"
    cp "$OVR/python/safety.md"       "$TPL/$tree/rules/python/safety.md"
    note "generic python rules -> $tree"
  fi
done

# 2b. Strip curation-only hooks (harness-*) from the template's settings.json so an
#     adopted repo never references a hook that was deliberately excluded from the
#     payload (see template-exclude.txt). Curation hooks stay root-only.
for tree in claude codex; do
  st="$TPL/$tree/settings.json"
  [ -f "$st" ] || continue
  python3 - "$st" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
hooks = data.get("hooks", {})
for event in list(hooks):
    kept = [g for g in hooks[event]
            if not any("harness-" in h.get("command", "") for h in g.get("hooks", []))]
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
  note "stripped curation hooks from $tree/settings.json"
done

# 3. Root instruction files + beads policy doc.
cp "$REPO/CLAUDE.md" "$TPL/CLAUDE.md"
cp "$REPO/AGENTS.md" "$TPL/AGENTS.md"
mkdir -p "$TPL/beads"
cp "$REPO/.beads/beads.md" "$TPL/beads/beads.md"
note "copied CLAUDE.md, AGENTS.md, beads/beads.md"

# 4. Genericise the few project-specific lines in CLAUDE.md / AGENTS.md.
genericize() {
  local f="$1"
  # Read-order line 6 + § External Submodules: the root harness describes its own
  # reference_harnesses/ + harness_learnings/ setup, which is meaningless in an
  # adopted repo. Neutralise both to the provider-agnostic external/ wording.
  perl -0pi -e 's{`reference_harnesses/<name>/` docs — only when the task is explicitly about that reference submodule}{`external/<name>/` docs — only when the task is explicitly about that submodule}g' "$f"
  perl -0pi -e 's{Third-party \*\*reference harness\*\* repos are tracked as Git submodules under `reference_harnesses/` \(see `\.gitmodules`\)\. The parent repo tracks their commit pointers only — they are read-only references, never copied into the local harness\. Do not edit submodule internals unless the task is explicitly submodule-local; for upstream sync, update and stage the submodule path\. Borrow only the smallest durable pattern \(see `harness_learnings/reference-harness-workflow\.md`\)\.}{External upstream projects, if any, are tracked as Git submodules under `external/` (see `.gitmodules`). The parent repo tracks their commit pointers only. Do not edit submodule internals unless the task is explicitly submodule-local; for upstream sync, update and stage the submodule path.}g' "$f"
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
    s/bodha-memory-eval/<eval-harness>/gi;
    s/bodha-chitta/<design-doc>/gi;
    s/\bgastown\b/<name>/g;
    s/\bgascity\b/<name>/g;
    s/\bBodha\b/the project/gi;
    s/\borchestrators\b/the parent repo/gi;
  ' "$f"
done < <(find "$TPL" -type f \( -name '*.md' -o -name '*.py' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' -o -name '*.json' -o -name '*.sh' -o -name '*.mjs' -o -name '*.rules' -o -name '*.txt' \) -print0)
note "swept machine-local paths + example tokens"

# 6. Self-check: nothing project/machine-specific may survive in the payload.
fail=0
check() { # pattern human-label (case-insensitive: catches Bodha/bodha alike)
  local hits
  hits="$(grep -rnIi -- "$1" "$TPL" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf 'LEAK (%s):\n%s\n' "$2" "$hits" >&2
    fail=1
  fi
}
check 'Bodha'            'project name'
check 'orchestrators'    'project name'
check 'gascity'          'submodule name'
check 'gastown'          'submodule name'
check '/home/pavanmv'    'machine path'
check '/data/codes'      'machine path'
check 'reference_harnesses' 'coding-ritual path (genericize rule drifted)'
check 'harness_learnings'   'coding-ritual path (genericize rule drifted)'
check 'harness-staleness'   'curation hook leaked into template settings.json'
[ "$fail" -eq 0 ] || die "project/machine-specific strings leaked into template/ (see LEAK lines above)"

# 6b. Payload manifest: per-file content hash so /mvp-plugin:update can three-way
#     merge and never clobber a repo's local edits (incl. .beads/beads.md).
#     Written atomically (temp + rename) so a hash failure can't leave it stale.
MANIFEST="$TPL/harness-manifest.txt"
{
  printf '# harness-manifest: <payload-path> <TAB> <sha256>. Generated by build-template.sh; do not edit.\n'
  find "$TPL" -type f ! -name harness-manifest.txt \
    | sort | while IFS= read -r f; do
        printf '%s\t%s\n' "${f#"$TPL"/}" "$(hashof "$f")"
      done
} > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"
note "payload manifest: $(grep -vc '^#' "$MANIFEST") files -> ${MANIFEST#"$PLUGIN_DIR"/}"

# 7. Summary.
n_claude=$(find "$TPL/claude" -type f 2>/dev/null | wc -l | tr -d ' ')
n_codex=$(find "$TPL/codex" -type f 2>/dev/null | wc -l | tr -d ' ')
printf '#### template/ regenerated: %s files under claude, %s under codex, plus CLAUDE.md/AGENTS.md/beads/beads.md\n' "$n_claude" "$n_codex"
printf 'OK: no project/machine-specific strings in payload.\n'

# 8. Advisory drift check between the two payload trees. Never fails the build —
#    it just surfaces shared files that have drifted apart since last accepted.
printf '\n'
if bash "$SCRIPT_DIR/check-sync.sh" check; then
  :
else
  printf 'WARN: shared .claude/.codex content has drifted (see above). Reconcile in the\n' >&2
  printf '      source harness, re-run build-template, then: bash scripts/check-sync.sh accept\n' >&2
fi
