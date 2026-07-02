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

[ -d "$TPL/.claude" ] || hp_die "template payload missing at $TPL — run scripts/build-template.sh"
[ -d "$TARGET" ]      || hp_die "target repo not found: $TARGET"

printf '#### Adopting harness into %s\n' "$TARGET"
git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || \
  hp_warn "target is not a git repo — changes will not be under version control; review carefully"

copied=0; overwritten=0; preserved=0

# --- 1. Copy the payload (both harness trees + root instruction files). --------
copy_one() {
  local rel="$1"
  local src="$TPL/$rel"
  local dst="$TARGET/$rel"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ]; then
    if hp_is_user_owned "$rel"; then hp_skip "$rel (exists, preserved)"; preserved=$((preserved+1)); return; fi
    cmp -s "$src" "$dst" && return
    cp -p "$src" "$dst"; overwritten=$((overwritten+1)); return
  fi
  cp -p "$src" "$dst"; copied=$((copied+1))
}
while IFS= read -r -d '' src; do
  copy_one "${src#"$TPL"/}"
done < <(find "$TPL" -type f -not -path "$TPL/.beads/*" -print0)

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
  if grep -qE "^${key}:" "$file"; then
    perl -pi -e "s{^\Q${key}\E:.*}{${key}: \"${val}\"}g" "$file"
  else
    printf '\n%s: "%s"\n' "$key" "$val" >> "$file"
  fi
}
if command -v bd >/dev/null 2>&1; then
  if [ -f "$TARGET/.beads/metadata.json" ]; then
    hp_skip "beads already initialised (left as-is)"
  elif ( cd "$TARGET" && BD_NON_INTERACTIVE=1 bd init --non-interactive --skip-agents >/dev/null 2>&1 ); then
    hp_ok "bd init"
  else
    hp_warn "bd init failed — run 'bd init' in the repo manually"
  fi
  mkdir -p "$TARGET/.beads"; cp "$TPL/.beads/beads.md" "$TARGET/.beads/beads.md"
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

# --- 5. Summary. --------------------------------------------------------------
printf '#### install-harness done: %s new, %s core updated, %s user-owned preserved\n' "$copied" "$overwritten" "$preserved"
printf 'NEXT: fill the project overlay (.claude/project/*, .codex/project/*) from repo reality — the harness-adopt skill does this.\n'
