#!/usr/bin/env bash
# Deterministic half of /mvp-plugin:adopt: lay the self-contained harness into the
# target repo. Copies the reusable core (rules, skills, agents, commands, hooks,
# docs), preserves anything the repo owner customises (CLAUDE.md/AGENTS.md,
# settings/config, the per-repo overlay), drops overlay skeletons, initialises
# beads, and points beads sync at the repo's own remote.
#
# Idempotent and non-destructive: identical files are skipped, user-owned files
# are never clobbered, beads is never re-initialised, nothing is `git add`ed.
# The judgement half (filling the overlay) is the harness-adopt skill.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PLUGIN="$HP_PLUGIN_DIR"
TPL="$PLUGIN/template"
TARGET="$(hp_target)"
STAMP="$TARGET/.harness-manifest.txt"     # this repo's record of the last-installed payload hashes
NEW_MANIFEST="$TPL/harness-manifest.txt"  # the payload we are installing now

[ -d "$TPL/claude" ] || hp_die "template payload missing at $TPL — run scripts/build-template.sh"
[ -d "$TARGET" ]      || hp_die "target repo not found: $TARGET"

printf '#### Adopting harness into %s\n' "$TARGET"
git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || \
  hp_warn "target is not a git repo — changes will not be under version control; review carefully"

copied=0; overwritten=0; preserved=0; conflicts=0; retired=0

# Hash the target's last-installed version of a payload file (from the stamp), or
# empty if we have no record (fresh adopt, or adopted before manifests existed).
hp_base_hash() {
  [ -f "$STAMP" ] || return 0
  awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$STAMP" 2>/dev/null || true
}

# --- 1. Copy the payload (both harness trees + root instruction files). --------
# Three-way merge on re-run (/mvp-plugin:update) so a repo's local edits to core
# files are never silently overwritten: base = last-installed (stamp), local =
# what's in the repo now, new = the current template.
copy_one() {
  local rel="$1"                              # dot-less path within template/ (claude/…, codex/…)
  local src="$TPL/$rel"
  local drel; drel="$(hp_to_dotted "$rel")"   # dotted path the adopted repo needs (.claude/…)
  local dst="$TARGET/$drel"
  mkdir -p "$(dirname "$dst")"
  if [ ! -e "$dst" ]; then
    cp -p "$src" "$dst"; copied=$((copied+1)); return
  fi
  if hp_is_user_owned "$drel"; then hp_skip "$drel (exists, preserved)"; preserved=$((preserved+1)); return; fi
  local new_hash local_hash base_hash
  new_hash="$(hp_hash "$src")"
  local_hash="$(hp_hash "$dst")"
  if [ "$local_hash" = "$new_hash" ]; then return; fi                 # already up to date
  base_hash="$(hp_base_hash "$rel")"
  if [ -n "$base_hash" ] && [ "$local_hash" = "$base_hash" ]; then
    cp -p "$src" "$dst"; overwritten=$((overwritten+1)); return       # untouched locally -> update
  fi
  if [ -n "$base_hash" ] && [ "$new_hash" = "$base_hash" ]; then
    hp_skip "$drel (kept local edit; core unchanged)"; preserved=$((preserved+1)); return
  fi
  cp -p "$src" "$dst.template-new"                                     # local + core both changed
  hp_warn "$drel (local edit kept; new version at ${drel}.template-new)"
  conflicts=$((conflicts+1))
}
while IFS= read -r -d '' src; do
  copy_one "${src#"$TPL"/}"
done < <(find "$TPL" -type f -not -path "$TPL/beads/*" ! -name harness-manifest.txt -print0)

# Hook scripts must stay executable (settings.json invokes them directly).
for d in "$TARGET/.claude/hooks" "$TARGET/.codex/hooks"; do
  [ -d "$d" ] && find "$d" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
done

# --- 2. Overlay skeletons: structure now, facts filled by the adopt skill. -----
write_stub() {
  local rel="$1"
  local title="$2"
  local dst="$TARGET/$rel"
  [ -e "$dst" ] && { preserved=$((preserved+1)); return; }
  mkdir -p "$(dirname "$dst")"
  {
    printf '# %s\n\n' "$title"
    printf '> Skeleton created by /mvp-plugin:adopt. Replace with facts derived from THIS\n'
    printf '> repo (scan README, manifests, CI, source). Placeholder until then.\n\n'
    printf 'TODO: fill from repo reality.\n'
  } > "$dst"
  copied=$((copied+1))
}
OVERLAY=(
  "brief.md|Project Brief"
  "repo-map.md|Repository Map"
  "docs-index.md|Docs Index"
  "verification.md|Verification"
  "invariants.md|Invariants"
  "tools.md|Tools & Subagents"
  "tracking.md|Issue Tracking"
  "learnings.md|Learnings"
  "adoption-report.md|Adoption Report"
)
for harness in .claude .codex; do
  for entry in "${OVERLAY[@]}"; do
    write_stub "$harness/project/${entry%%|*}" "${entry##*|}"
  done
done
write_stub ".claude/project/code-intel.md" "Code Intelligence (code-intel plugin)"

# --- 3. Beads: init the store, ship the policy doc, point sync at this remote. -
ensure_yaml_key() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 0
  # awk passes the value as data (-v v), so a URL containing @ / $ / " is never
  # re-interpreted (perl treated "git@host" as an array and silently dropped @host).
  awk -v k="$key" -v v="$val" '
    index($0, k":") == 1 { print k": \"" v "\""; found=1; next }
    { print }
    END { if (!found) print k": \"" v "\"" }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
if command -v bd >/dev/null 2>&1; then
  if [ -f "$TARGET/.beads/metadata.json" ]; then
    hp_skip "beads already initialised (left as-is)"
  elif ( cd "$TARGET" && BD_NON_INTERACTIVE=1 bd init --non-interactive --skip-agents >/dev/null 2>&1 ); then
    hp_ok "bd init"
  else
    hp_warn "bd init failed — run 'bd init' in the repo manually"
  fi
  mkdir -p "$TARGET/.beads"; copy_one "beads/beads.md"   # three-way, never clobber local edits
  ( cd "$TARGET" && bd config set export.auto true >/dev/null 2>&1 ) || true
  url="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] && { ensure_yaml_key "$TARGET/.beads/config.yaml" "sync.remote" "git+$url"; hp_ok "beads sync.remote -> git+$url"; }
else
  hp_warn "bd not found — install: npm i -g @beads/bd (if the binary download 404s, pin a published release: npm i -g @beads/bd@1.0.4), then re-run /mvp-plugin:adopt"
fi

# --- 4. Gitignore: keep harness scratch/runtime artifacts out of git. ----------
GI="$TARGET/.gitignore"; MARKER="# --- mvp-plugin (added by /mvp-plugin:adopt) ---"
if grep -qF "$MARKER" "$GI" 2>/dev/null; then
  hp_skip ".gitignore already has harness block"
else
  { printf '\n%s\n' "$MARKER"; printf 'scratchpad/\n**/scratchpad/*\n.serena/\n.codebase-memory/\n'; } >> "$GI"
  hp_ok "appended harness block to .gitignore"
fi

# --- 4b. Retire files removed from the template, then stamp the new manifest. ---
# A file dropped from the payload should not linger in the adopted repo — but only
# delete it if it is unmodified (local hash == old base); otherwise keep it + warn,
# so a repo's own work is never destroyed. Stamp last so all three-way reads above
# saw the OLD base.
if [ -f "$STAMP" ] && [ -f "$NEW_MANIFEST" ]; then
  while IFS=$'\t' read -r orel ohash; do
    case "$orel" in ''|'#'*) continue ;; esac
    case "$orel" in /*|*..*) hp_warn "manifest path skipped (unsafe: $orel)"; continue ;; esac  # no escape from $TARGET
    odrel="$(hp_to_dotted "$orel")"
    hp_is_user_owned "$odrel" && continue                    # never retire a user-owned file
    awk -F'\t' -v k="$orel" '$1==k{f=1} END{exit !f}' "$NEW_MANIFEST" && continue
    odst="$TARGET/$odrel"
    [ -e "$odst" ] || continue
    if [ "$(hp_hash "$odst")" = "$ohash" ]; then
      rm -f "$odst"; retired=$((retired+1)); hp_ok "$odrel (retired; removed from harness)"
    else
      hp_warn "$odrel (removed from harness but locally modified — left in place)"
    fi
  done < "$STAMP"
fi
if [ -f "$NEW_MANIFEST" ]; then cp -p "$NEW_MANIFEST" "$STAMP"; fi

# --- 5. Summary. --------------------------------------------------------------
printf '#### install-harness done: %s new, %s core updated, %s preserved/kept, %s conflicts, %s retired\n' "$copied" "$overwritten" "$preserved" "$conflicts" "$retired"
if [ "$conflicts" -gt 0 ]; then
  printf 'NOTE: %s file(s) changed BOTH locally and upstream — your version was kept; review the *.template-new copies.\n' "$conflicts"
fi
printf 'NEXT: fill the project overlay (.claude/project/*, .codex/project/*) from repo reality — the harness-adopt skill does this.\n'
