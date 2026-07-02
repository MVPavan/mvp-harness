#!/usr/bin/env bash
# Tier-2 end-to-end: run the plugin inside the test image with a REAL Claude Code
# session, so the model actually loads + uses the MCP tools. Requires the
# code-intel-test image (build it first) and ANTHROPIC_API_KEY in your env.
# The key is passed at run time only — never bake it into the image.
#
# Usage: ANTHROPIC_API_KEY=... bash external/code-intel/test/tier2.sh ["prompt"]
#
# NOTE: best-effort. Headless `claude -p` with --plugin-dir may require additional
# trust/permission flags depending on your Claude Code version; adjust as needed.
set -euo pipefail
: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY in your environment first}"
IMAGE="${IMAGE:-code-intel-test}"
PROMPT="${1:-Run /code-intel:doctor, then use the code graph (CBM/serena) to tell me who calls greet(). Remember CBM tools need the project arg from list_projects.}"

docker run --rm \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e CI_PROMPT="$PROMPT" \
  --entrypoint bash \
  "$IMAGE" -lc '
    cd /tmp/fixture
    codebase-memory-mcp cli index_repository "{\"repo_path\":\"/tmp/fixture\"}" >/dev/null 2>&1 || true
    claude --plugin-dir /opt/code-intel -p "$CI_PROMPT" --permission-mode acceptEdits
  '
