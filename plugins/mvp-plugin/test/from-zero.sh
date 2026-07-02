#!/usr/bin/env bash
# FROM-ZERO clean-room test. Proves the lifecycle on a machine that starts with
# NO beads installed:
#   phase 1  clean state -> the harness core still copies; installer tells you to install bd
#   phase 2  install bd  -> via the exact command the installer recommends
#   phase 3  verify wired -> the full Tier-1 suite goes green
# Container-only (a host normally already has bd). Run with the plugin mounted RO:
#   docker run --rm -v "$PWD/external/mvp-plugin:/opt/mvp-plugin:ro" \
#     -e PLUGIN_DIR=/opt/mvp-plugin node:22-bookworm bash /opt/mvp-plugin/test/from-zero.sh
set -u
PLUGIN="${PLUGIN_DIR:-/opt/mvp-plugin}"
FIX=/tmp/fz-fixture
fail(){ echo "FROM-ZERO FAIL: $1"; exit 1; }
hdr(){ printf '\n#### %s\n' "$1"; }

hdr "phase 0: prereqs (git)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq git ca-certificates >/dev/null 2>&1 || fail "apt prereqs"

hdr "phase 1: CLEAN STATE (no bd) — core copies; installer guides bd install"
command -v bd >/dev/null 2>&1 && fail "expected a clean machine WITHOUT bd"
rm -rf "$FIX"; mkdir -p "$FIX"; git -C "$FIX" init -q
git -C "$FIX" remote add origin https://github.com/example/fz.git
printf '# fz\n' > "$FIX/README.md"
git -C "$FIX" add README.md && git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m init
out="$(CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$FIX" bash "$PLUGIN/scripts/install-harness.sh" 2>&1)"; echo "$out"
[ -d "$FIX/.claude/rules" ] && [ -f "$FIX/AGENTS.md" ] || fail "harness core should copy even without bd"
echo "$out" | grep -q "bd not found" || fail "installer should warn that bd is missing with install guidance"
echo "OK: harness core copied on a clean machine; bd-install guidance shown"

hdr "phase 2: INSTALL bd via the documented command"
# Pinned to a published release — npm 'latest' (1.0.5) currently 404s its binary.
npm install -g @beads/bd@1.0.4 >/dev/null 2>&1 || fail "npm install -g @beads/bd@1.0.4"
command -v bd >/dev/null 2>&1 || fail "bd still not on PATH after install"
echo "OK installed: $(bd version 2>&1 | head -1)"

hdr "phase 3: VERIFY everything wired (full Tier-1 suite)"
PLUGIN_DIR="$PLUGIN" FIXTURE_DIR=/tmp/fz-suite bash "$PLUGIN/test/run-tests.sh"
