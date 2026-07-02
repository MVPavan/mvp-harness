#!/usr/bin/env bash
# code-intel plugin test suite. Runs inside the test container (Dockerfile) or on
# any host where serena, codebase-memory-mcp, and ast-grep are installed.
# Exercises: tool presence, discovery, shim resolution + fail-loud, ast-grep,
# CBM index+query (end-to-end), the freshness hook, and live MCP tools/list
# handshakes for both serena and CBM. No Claude Code / API key required.
set -u
PLUGIN="${PLUGIN_DIR:-/opt/code-intel}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
hdr() { printf '\n== %s ==\n' "$1"; }

# defensive: ensure scripts are executable (COPY usually preserves this)
chmod +x "$PLUGIN"/bin/* "$PLUGIN"/scripts/*.sh "$PLUGIN"/hooks/*.sh 2>/dev/null || true

# ---- fixture repo to index/search ----
FIX=/tmp/fixture; mkdir -p "$FIX"
cat > "$FIX/app.py" <<'PY'
def greet(name):
    return "hi " + name

def main():
    print(greet("world"))
PY
cat > "$FIX/util.py" <<'PY'
import os
def risky():
    x = None
    if x == None:            # ast-grep structural target
        return os.environ["X"]
PY

hdr "tool presence"
command -v serena              >/dev/null && ok "serena on PATH"   || bad "serena on PATH"
command -v codebase-memory-mcp >/dev/null && ok "cbm on PATH"      || bad "cbm on PATH"
command -v ast-grep            >/dev/null && ok "ast-grep on PATH" || bad "ast-grep on PATH"

hdr "discover.sh (clean machine -> expect ON PATH)"
CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/discover.sh" | tee /tmp/disc.txt
grep -q "serena:.*ON PATH"   /tmp/disc.txt && ok "serena discovered"   || bad "serena discovered"
grep -q "cbm:.*ON PATH"      /tmp/disc.txt && ok "cbm discovered"      || bad "cbm discovered"
grep -q "ast-grep:.*ON PATH" /tmp/disc.txt && ok "ast-grep discovered" || bad "ast-grep discovered"

hdr "shim resolution"
"$PLUGIN/bin/ast-grep" --version >/dev/null 2>&1 && ok "bin/ast-grep" || bad "bin/ast-grep"
"$PLUGIN/bin/cbm" --version      >/dev/null 2>&1 && ok "bin/cbm"      || bad "bin/cbm"
"$PLUGIN/bin/serena" --help      >/dev/null 2>&1 && ok "bin/serena"   || bad "bin/serena"

hdr "shim fail-loud (tool absent)"
out="$(env -u CODE_INTEL_ASTGREP_BIN PATH=/usr/bin:/bin "$PLUGIN/bin/ast-grep" --version 2>&1)"; rc=$?
{ [ "$rc" -eq 127 ] && printf '%s' "$out" | grep -q "not found"; } && ok "exit 127 + message" || bad "fail-loud (rc=$rc)"

hdr "ast-grep structural search"
m="$("$PLUGIN/bin/ast-grep" run -p '$X == None' -l python "$FIX" 2>/dev/null)"
printf '%s' "$m" | grep -q "x == None" && ok 'matched $X == None' || bad "ast-grep structural match"

hdr "CBM index + query (end-to-end)"
"$PLUGIN/bin/cbm" cli index_repository "{\"repo_path\":\"$FIX\"}" >/tmp/idx.txt 2>&1
PNAME="$(bash "$PLUGIN/scripts/cbm-project.sh" "$FIX")"
[ -n "$PNAME" ] && ok "cbm-project.sh resolved name" || bad "cbm-project.sh lookup (idx: $(tail -1 /tmp/idx.txt))"
sg="$("$PLUGIN/bin/cbm" cli search_graph "{\"project\":\"$PNAME\",\"name_pattern\":\"greet\"}" 2>&1)"
printf '%s' "$sg" | grep -qi "greet" && ok "search_graph(project=$PNAME) found greet" \
  || bad "cbm search_graph (sg: $(printf '%s' "$sg" | tail -1))"

hdr "freshness hook"
NEW=/tmp/fresh; mkdir -p "$NEW"; echo "def a(): pass" > "$NEW/a.py"
n="$(CLAUDE_PROJECT_DIR="$NEW" bash "$PLUGIN/hooks/freshness-check.sh" 2>&1)"
printf '%s' "$n" | grep -q "not indexed" && ok "nudges on unindexed repo" || bad "hook nudge"
s="$(CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/hooks/freshness-check.sh" 2>&1)"
[ -z "$s" ] && ok "silent on indexed repo" || bad "hook silent (got: $s)"

hdr "MCP handshakes (tools/list over stdio)"
ct="$(node "$PLUGIN/test/mcp-probe.mjs" --timeout 60 -- "$PLUGIN/bin/cbm" 2>/tmp/cbm.err)"
case "$ct" in TOOLS=*) c=${ct#TOOLS=}; [ "$c" -ge 10 ] && ok "CBM listed $c tools" || bad "CBM tools=$c (<10)";;
  *) bad "CBM probe ($(tail -1 /tmp/cbm.err 2>/dev/null))";; esac
SER_ARGS="start-mcp-server --transport stdio --context claude-code --project $FIX --enable-web-dashboard false --open-web-dashboard false --enable-gui-log-window false"
st="$(node "$PLUGIN/test/mcp-probe.mjs" --timeout 120 -- "$PLUGIN/bin/serena" $SER_ARGS 2>/tmp/ser.err)"
case "$st" in TOOLS=*) c=${st#TOOLS=}; [ "$c" -ge 1 ] && ok "serena listed $c tools" || bad "serena tools=$c";;
  *) bad "serena probe ($(tail -1 /tmp/ser.err 2>/dev/null))";; esac

hdr "claude plugin validate (best-effort)"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$PLUGIN" >/tmp/val.txt 2>&1 && ok "plugin validate" || bad "plugin validate ($(tail -1 /tmp/val.txt))"
else
  printf '  SKIP  claude CLI not present\n'
fi

printf '\n==== RESULT: %d passed, %d failed ====\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
