# Testing code-intel in isolation

Two tiers. Start with Tier 1 — it needs no Claude Code account and catches almost
everything.

## Tier 1 — clean-room mechanics (Docker, no API key)

Builds a fresh image that installs serena, CBM, and ast-grep with the **exact
commands from the README**, then drives the plugin directly. A green run proves
both that the plugin works and that the install guidance is correct on a clean
machine.

```bash
# from the orchestrators repo root
docker build -f external/code-intel/test/Dockerfile -t code-intel-test external/code-intel
docker run --rm code-intel-test
```

What it checks (`test/run-tests.sh`):
- the three tools install and land on PATH;
- `scripts/discover.sh` finds them; the `bin/` shims resolve and **fail loud** (exit 127) when a tool is absent;
- `ast-grep` performs a real structural match;
- CBM **indexes a fixture repo and answers a `search_graph` query** (full end-to-end);
- the SessionStart freshness hook nudges on an unindexed repo and is silent on an indexed one;
- **serena and CBM each start as MCP servers and return `tools/list`** over stdio — exercised by `test/mcp-probe.mjs`, a ~70-line dependency-free MCP client (initialize → notifications/initialized → tools/list). No Claude Code needed.
- `claude plugin validate` (best-effort, if the CLI is present).

Exit code is non-zero if any check fails.

### Run the suite on the host (no Docker)
If serena/CBM/ast-grep are already installed (or reachable via `CODE_INTEL_*_BIN`):

```bash
PLUGIN_DIR=external/code-intel bash external/code-intel/test/run-tests.sh
```

This is less isolated (uses your real tool installs) but fast for iteration.

## Tier 2 — full end-to-end with Claude Code (needs an API key)

Tier 1 proves the machinery. Tier 2 proves Claude actually *uses* it. It requires
an authenticated Claude Code in the container, so pass a key at run time (never
bake secrets into the image):

Use the runner (handles the entrypoint override + pre-indexes the fixture):

```bash
ANTHROPIC_API_KEY=... bash external/code-intel/test/tier2.sh "Who calls greet()?"
```

Equivalent manual form (note `--entrypoint bash` — the image's default entrypoint
is the Tier-1 suite):

```bash
docker run --rm -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" --entrypoint bash code-intel-test \
  -lc 'cd /tmp/fixture && claude --plugin-dir /opt/code-intel \
       -p "Run /code-intel:doctor, then use the code graph to tell me who calls greet()." \
       --permission-mode acceptEdits'
```

What Tier 2 adds over Tier 1:
- the plugin actually **loads** in a real session (skill auto-loads, commands are namespaced `/code-intel:*`);
- `${CLAUDE_PROJECT_DIR}` / `${CLAUDE_PLUGIN_ROOT}` expansion in `.mcp.json` is exercised by Claude Code itself (the one thing Tier 1 can't cover);
- Claude routes a navigation question through the MCP tools rather than reading files.

Notes:
- Symbol-level serena queries (e.g. `find_referencing_symbols`) need the language
  server backend; for Python that means `pyright`/node, already present in the
  `node:22` base. Other languages need their LSP installed in the image.
- Keep `ANTHROPIC_API_KEY` in your shell env; do not commit it or pass it via
  `--build-arg`.

## Files
- `Dockerfile` — clean-room image (documented installs + plugin + suite).
- `run-tests.sh` — the Tier-1 suite (also runnable on the host via `PLUGIN_DIR=`).
- `mcp-probe.mjs` — minimal stdio MCP client for the `tools/list` handshake.
- `tier2.sh` — Tier-2 end-to-end runner (needs `ANTHROPIC_API_KEY`).
