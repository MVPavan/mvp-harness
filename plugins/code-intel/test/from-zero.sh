#!/usr/bin/env bash
# FROM-ZERO bootstrap test. Starts on a clean OS with NO code-intel tools and
# proves the full lifecycle:
#   phase 1  clean state    -> discover reports all MISSING; shims fail loud (127)
#   phase 2  install        -> run the EXACT commands the plugin recommends
#   phase 3  verify wired   -> the full Tier-1 suite goes green
# Run in a clean base image with the plugin mounted read-only at /opt/code-intel:
#   docker run --rm -v "$PWD/external/code-intel:/opt/code-intel:ro" \
#     -e PLUGIN_DIR=/opt/code-intel node:22-bookworm bash /opt/code-intel/test/from-zero.sh
set -u
PLUGIN="${PLUGIN_DIR:-/opt/code-intel}"
fail() { echo "FROM-ZERO FAIL: $1"; exit 1; }
hdr()  { printf '\n#### %s\n' "$1"; }

hdr "phase 0: prereqs (curl/git)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl ca-certificates git >/dev/null 2>&1 || fail "apt prereqs"

hdr "phase 1: CLEAN STATE — expect all MISSING + fail-loud"
d="$(CLAUDE_PROJECT_DIR=/tmp bash "$PLUGIN/scripts/discover.sh")"; echo "$d"
echo "$d" | grep -q "serena:.*MISSING"   || fail "serena should be MISSING on a clean machine"
echo "$d" | grep -q "cbm:.*MISSING"      || fail "cbm should be MISSING on a clean machine"
echo "$d" | grep -q "ast-grep:.*MISSING" || fail "ast-grep should be MISSING on a clean machine"
out="$(env -u CODE_INTEL_ASTGREP_BIN "$PLUGIN/bin/ast-grep" --version 2>&1)"; rc=$?
{ [ "$rc" -eq 127 ] && printf '%s' "$out" | grep -q "not found"; } || fail "shim should fail loud (rc=$rc): $out"
echo "OK: clean state handled (all MISSING with install hints; shim fail-loud 127)"

hdr "phase 2: INSTALL via the plugin's documented commands"
npm install --global @ast-grep/cli codebase-memory-mcp >/dev/null 2>&1 || fail "npm install (ast-grep + cbm)"
curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || fail "uv install"
export PATH="$HOME/.local/bin:$PATH"
uv tool install -p 3.13 serena-agent >/dev/null 2>&1 || fail "uv tool install serena-agent"
echo "OK installed: $(serena --version 2>&1 | head -1) | $(codebase-memory-mcp --version 2>&1 | tail -1) | $(ast-grep --version 2>&1 | head -1)"

hdr "phase 3: VERIFY everything wired (full Tier-1 suite)"
PLUGIN_DIR="$PLUGIN" bash "$PLUGIN/test/run-tests.sh"
