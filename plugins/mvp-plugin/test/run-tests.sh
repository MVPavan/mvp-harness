#!/usr/bin/env bash
# Tier-1 suite for the harness plugin. Drives the plugin directly (no Claude Code
# account needed): adopt into a fresh repo, verify everything landed and wired,
# check idempotency, and verify the non-destructive update. Exit non-zero on any fail.
#
# Host:      PLUGIN_DIR=external/mvp-plugin bash external/mvp-plugin/test/run-tests.sh
# Container: default ENTRYPOINT (PLUGIN_DIR=/opt/mvp-plugin).
set -u
PLUGIN="${PLUGIN_DIR:-/opt/mvp-plugin}"
FIX="${FIXTURE_DIR:-/tmp/harness-fixture}"
TPL="$PLUGIN/template"
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
chk(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }
hdr(){ printf '\n== %s ==\n' "$1"; }

[ -d "$TPL/claude" ] || { echo "FATAL: template payload missing at $TPL"; exit 2; }

hdr "fresh target repo"
rm -rf "$FIX"; mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" remote add origin https://github.com/example/harness-demo.git
printf '# Harness Demo\n' > "$FIX/README.md"
git -C "$FIX" add README.md && git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m init
ok "fixture repo created"

hdr "adopt (deterministic installer)"
CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/install-harness.sh" >/tmp/hp-install.log 2>&1; rc_install=$?
chk "install-harness.sh exit 0" '[ "$rc_install" -eq 0 ]'

hdr "payload landed"
chk ".claude tree"  '[ -d "$FIX/.claude/rules" ] && [ -d "$FIX/.claude/skills" ] && [ -d "$FIX/.claude/agents" ] && [ -d "$FIX/.claude/commands" ] && [ -d "$FIX/.claude/hooks" ]'
chk ".codex tree"   '[ -d "$FIX/.codex/rules" ] && [ -d "$FIX/.codex/skills" ] && [ -d "$FIX/.codex/agents" ]'
chk "CLAUDE.md + AGENTS.md" '[ -f "$FIX/CLAUDE.md" ] && [ -f "$FIX/AGENTS.md" ]'
chk "AGENTS.md == template (bd did not pollute it)" 'cmp -s "$FIX/AGENTS.md" "$TPL/AGENTS.md"'
chk "CLAUDE.md == template"                         'cmp -s "$FIX/CLAUDE.md" "$TPL/CLAUDE.md"'

hdr "hooks wired + executable"
chk "settings.json wires hooks" 'grep -q hooks "$FIX/.claude/settings.json"'
chk "hooks executable" '[ -x "$FIX/.claude/hooks/bd-prime.sh" ] && [ -x "$FIX/.claude/hooks/block-dangerous-commands.sh" ]'
chk "no machine-local path in settings.json" '! grep -qE "/home/|/Users/|/data/codes" "$FIX/.claude/settings.json"'

hdr "beads"
chk "bd on PATH" 'command -v bd >/dev/null 2>&1'
chk "beads initialised" '[ -f "$FIX/.beads/metadata.json" ]'
chk "beads.md policy doc present" '[ -f "$FIX/.beads/beads.md" ]'
chk "sync.remote points at origin" 'grep -q "git+https://github.com/example/harness-demo.git" "$FIX/.beads/config.yaml"'
chk "no stray .agents dir from bd" '[ ! -d "$FIX/.agents" ]'

hdr "overlay skeletons + gitignore"
chk "overlay skeletons present" '[ -f "$FIX/.claude/project/brief.md" ] && [ -f "$FIX/.codex/project/brief.md" ]'
chk ".gitignore harness block" 'grep -q "mvp-plugin (added by /mvp-plugin:adopt)" "$FIX/.gitignore"'

hdr "payload is generic (no project/machine strings)"
chk "no Bodha/gascity/gastown in adopted .claude+.codex" '! grep -rIqE "Bodha|gascity|gastown" "$FIX/.claude" "$FIX/.codex"'
chk "no /home/pavanmv or /data/codes in payload" '! grep -rIqE "/home/pavanmv|/data/codes" "$FIX/.claude" "$FIX/.codex" "$FIX/CLAUDE.md" "$FIX/AGENTS.md"'

hdr "non-destructive update (three-way merge)"
chk "payload manifest stamped in repo" '[ -f "$FIX/.harness-manifest.txt" ]'
UPDCORE="$FIX/.claude/rules/core/01-delegation.md"
echo "LOCAL-EDIT-KEPT" >> "$UPDCORE"
CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/install-harness.sh" >/tmp/hp-update.log 2>&1
chk "local edit to a core file survives re-adopt (update)" 'grep -q "LOCAL-EDIT-KEPT" "$UPDCORE"'
chk "update kept the local edit (0 core updated)" 'grep -q "0 core updated" /tmp/hp-update.log'

hdr "doctor"
CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/doctor.sh" >/tmp/hp-doctor.log 2>&1; rc_doctor=$?
chk "doctor exit 0 (no hard fail)" '[ "$rc_doctor" -eq 0 ]'
chk "doctor reports 0 fail" 'grep -q "0 fail" /tmp/hp-doctor.log'

hdr "idempotency (re-adopt)"
CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/install-harness.sh" >/tmp/hp-install2.log 2>&1
chk "second run copies 0 new, 0 updated" 'grep -q "0 new, 0 core updated" /tmp/hp-install2.log'

hdr "claude plugin validate (best-effort)"
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate "$PLUGIN" >/tmp/hp-validate.log 2>&1; then ok "plugin validate"; else no "plugin validate (see /tmp/hp-validate.log)"; fi
else
  printf '  SKIP  claude CLI not present\n'
fi

hdr "update-merge suite (three-way / orphan / conflict / core-file update)"
if PLUGIN_DIR="$PLUGIN" bash "$PLUGIN/test/update-merge-test.sh" >/tmp/hp-update-merge.log 2>&1; then
  ok "update-merge suite"
else
  no "update-merge suite FAILED (see /tmp/hp-update-merge.log)"; tail -5 /tmp/hp-update-merge.log
fi

printf '\n==== RESULT: %s passed, %s failed ====\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
