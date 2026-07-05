#!/usr/bin/env bash
# Update-path coverage for /mvp-plugin:update (the three-way merge). Copies the
# plugin to a scratch dir so the template can be mutated between adopt and update,
# then exercises every merge branch, beads/SSH handling, orphan retirement, path
# containment, and the core-file update gap (S1). Standalone; no Claude account.
#
#   PLUGIN_DIR=mvp-harness/plugins/mvp-plugin bash <that>/test/update-merge-test.sh
set -u
SRC="${PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$(cd "$SRC" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PC="$WORK/plugin"; FIX="$WORK/fixture"
cp -r "$SRC" "$PC"
mkdir -p "$FIX"; git -C "$FIX" init -q; git -C "$FIX" remote add origin git@github.com:acme/app.git
printf '# demo\n' > "$FIX/README.md"
git -C "$FIX" add README.md && git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m init
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
regen(){ local T="$PC/template"; { printf '# m\n'; find "$T" -type f ! -name harness-manifest.txt | sort \
  | while IFS= read -r f; do printf '%s\t%s\n' "${f#"$T"/}" "$(sha256sum "$f"|cut -d' ' -f1)"; done; } > "$T/harness-manifest.txt"; }
adopt(){ CLAUDE_PLUGIN_ROOT="$PC" CLAUDE_PROJECT_DIR="$FIX" bash "$PC/scripts/install-harness.sh" >"$WORK/log" 2>&1; }
tpl_claude="$PC/template/claude"

printf '\n== adopt ==\n'; adopt
[ -f "$FIX/.harness-manifest.txt" ] && ok "manifest stamped" || no "manifest missing"
grep -q 'git+git@github.com:acme/app.git' "$FIX/.beads/config.yaml" && ok "H3: SSH remote preserved" || no "H3: SSH remote corrupted"

R="$FIX/.claude/rules/core/01-delegation.md"; TR="$tpl_claude/rules/core/01-delegation.md"
printf '\n== three-way: untouched local + upstream change -> UPDATE ==\n'
echo "UPSTREAM-1" >> "$TR"; regen; adopt
grep -q 'UPSTREAM-1' "$R" && ok "untouched core file updated" || no "untouched core NOT updated"

printf '\n== three-way: local edit + no upstream change -> KEEP ==\n'
echo "LOCAL-1" >> "$R"; adopt
grep -q 'LOCAL-1' "$R" && ok "local edit kept" || no "local edit clobbered"

printf '\n== three-way: local edit + upstream change -> CONFLICT (.template-new) ==\n'
echo "UPSTREAM-2" >> "$TR"; regen; adopt
grep -q 'LOCAL-1' "$R" && [ -f "$R.template-new" ] && grep -q 'UPSTREAM-2' "$R.template-new" \
  && ok "conflict: local kept + .template-new has upstream" || no "conflict handling wrong"

printf '\n== S1: CLAUDE.md (was always-preserved) now three-way merges ==\n'
echo "UPSTREAM-CLAUDE" >> "$PC/template/CLAUDE.md"; regen; adopt
grep -q 'UPSTREAM-CLAUDE' "$FIX/CLAUDE.md" && ok "untouched CLAUDE.md received upstream update" || no "CLAUDE.md still not updated (S1)"
echo "LOCAL-CLAUDE" >> "$FIX/CLAUDE.md"; echo "UPSTREAM-CLAUDE2" >> "$PC/template/CLAUDE.md"; regen; adopt
grep -q 'LOCAL-CLAUDE' "$FIX/CLAUDE.md" && [ -f "$FIX/CLAUDE.md.template-new" ] \
  && ok "edited CLAUDE.md kept + .template-new offered" || no "edited CLAUDE.md mishandled"

printf '\n== overlay stays user-owned (never touched) ==\n'
echo "MY-BRIEF" >> "$FIX/.claude/project/brief.md"; adopt
grep -q 'MY-BRIEF' "$FIX/.claude/project/brief.md" && ok "overlay preserved" || no "overlay clobbered"

printf '\n== C3: local edit to .beads/beads.md survives ==\n'
echo "LOCAL-BEADS" >> "$FIX/.beads/beads.md"; adopt
grep -q 'LOCAL-BEADS' "$FIX/.beads/beads.md" && ok "beads.md local edit kept" || no "beads.md clobbered"

printf '\n== H4: orphan retire (unmodified removed) + safety (modified kept) ==\n'
rm -f "$tpl_claude/skills/ak-guide/SKILL.md"; regen; adopt
[ ! -e "$FIX/.claude/skills/ak-guide/SKILL.md" ] && ok "unmodified orphan retired" || no "orphan not retired"
G="$FIX/.claude/skills/grill-me/SKILL.md"; echo "LOCAL-G" >> "$G"
rm -f "$tpl_claude/skills/grill-me/SKILL.md"; regen; adopt
[ -f "$G" ] && grep -q 'LOCAL-G' "$G" && ok "modified orphan kept" || no "modified orphan destroyed"

printf '\n== N4: path-traversal manifest entry refused ==\n'
echo SECRET > "$WORK/VICTIM.txt"
printf '../VICTIM.txt\t%s\n' "$(sha256sum "$WORK/VICTIM.txt"|cut -d' ' -f1)" >> "$FIX/.harness-manifest.txt"
adopt
[ -f "$WORK/VICTIM.txt" ] && ok "traversal blocked (VICTIM survives)" || no "traversal deleted VICTIM"

printf '\n== idempotency ==\n'; adopt
grep -q '0 new, 0 core updated' "$WORK/log" && ok "idempotent re-run" || no "not idempotent"

printf '\n==== update-merge: %s passed, %s failed ====\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
