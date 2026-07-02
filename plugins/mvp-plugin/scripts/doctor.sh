#!/usr/bin/env bash
# /mvp-plugin:doctor — verify a repo's harness is correctly installed and wired.
# PASS/WARN/FAIL per check. Exit non-zero only on a hard FAIL (missing core);
# missing optional tools (bd, codex) are WARNs with install hints.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

TARGET="$(hp_target)"
pass=0; warn=0; fail=0
P(){ printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
W(){ printf '  WARN  %s\n' "$1"; warn=$((warn+1)); }
F(){ printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

printf '#### mvp-plugin doctor — %s\n' "$TARGET"

# 1. Core payload present.
for d in .claude/rules .claude/skills .claude/agents .claude/commands .claude/hooks \
         .codex/rules .codex/skills .codex/agents; do
  [ -d "$TARGET/$d" ] && P "present: $d" || F "missing: $d (run /mvp-plugin:adopt)"
done
for f in CLAUDE.md AGENTS.md; do
  [ -f "$TARGET/$f" ] && P "present: $f" || F "missing: $f"
done

# 2. Hooks wired + executable.
if [ -f "$TARGET/.claude/settings.json" ]; then
  grep -q 'hooks' "$TARGET/.claude/settings.json" && P "settings.json wires hooks" || W "settings.json has no hooks block"
else
  W ".claude/settings.json absent — hooks not wired (a pre-existing settings.json is preserved; merge the harness hooks in)"
fi
for h in "$TARGET/.claude/hooks"/*.sh; do
  [ -e "$h" ] || continue
  [ -x "$h" ] && P "executable: ${h#"$TARGET"/}" || F "not executable: ${h#"$TARGET"/} (chmod +x)"
done

# 3. No machine-local absolute paths in wiring (portability).
if [ -f "$TARGET/.claude/settings.json" ]; then
  if grep -qE '/home/|/Users/|/data/codes' "$TARGET/.claude/settings.json"; then
    F "settings.json contains a machine-local absolute path"
  else
    P "settings.json paths are portable (\$CLAUDE_PROJECT_DIR / relative)"
  fi
fi

# 4. Beads.
if command -v bd >/dev/null 2>&1; then
  P "bd on PATH ($(bd version 2>/dev/null | head -1))"
  if [ -f "$TARGET/.beads/metadata.json" ]; then
    P "beads initialised (.beads/metadata.json)"
  else
    W "beads not initialised — run /mvp-plugin:adopt or 'bd init'"
  fi
  [ -f "$TARGET/.beads/config.yaml" ] && grep -q '^sync.remote:' "$TARGET/.beads/config.yaml" \
    && P "beads sync.remote set" || W "beads sync.remote not set (no git origin?)"
else
  W "bd not found — install: npm i -g @beads/bd (if its binary download 404s, pin a published release: npm i -g @beads/bd@1.0.4)"
fi

# 5. Overlay filled (not still skeleton).
skeletons=0
for f in "$TARGET/.claude/project"/*.md "$TARGET/.codex/project"/*.md; do
  [ -e "$f" ] || continue
  grep -q 'TODO: fill from repo reality' "$f" 2>/dev/null && skeletons=$((skeletons+1))
done
if [ "$skeletons" -eq 0 ]; then
  P "project overlay filled (no skeletons left)"
else
  W "$skeletons overlay file(s) still skeletons — run the harness-adopt skill to fill them"
fi

# 6. codex-adapter dependency (bundled co-plugin).
if command -v codex >/dev/null 2>&1; then
  P "codex CLI on PATH (codex-adapter ready)"
else
  W "codex CLI not found — for the bundled codex-adapter: npm i -g @openai/codex && codex login"
fi

printf '#### doctor: %s pass, %s warn, %s fail\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
