# Testing the harness plugin in isolation

No Claude Code account needed — the suite drives the plugin's scripts directly.

## Tier-1 suite (Docker, clean image)

Builds an image that installs only what a fresh machine needs (`git` + beads,
installed exactly as the plugin recommends), copies the plugin, and runs the
suite against a throwaway target repo.

```bash
# from the orchestrators repo root
docker build -f external/mvp-plugin/test/Dockerfile -t mvp-plugin-test external/mvp-plugin
docker run --rm mvp-plugin-test
```

`run-tests.sh` adopts the harness into a fresh git repo and checks: both harness
trees + `CLAUDE.md`/`AGENTS.md` land; `bd init` does **not** pollute `AGENTS.md`;
hooks are wired and executable; `settings.json` has no machine-local path; beads
initialises with `sync.remote` pointed at the repo origin; no stray `.agents/`;
overlay skeletons + `.gitignore` block present; the payload carries **no**
project/machine strings; the vendored codex-adapter is intact and parseable; the
adopt is idempotent on re-run; and `claude plugin validate` passes (if the CLI is present).

## From-zero clean-room

Proves the bootstrap on a machine with **no beads installed**: the harness core
still copies and the installer guides the `bd` install, then after installing
beads the full suite goes green.

```bash
docker run --rm -v "$PWD/external/mvp-plugin:/opt/mvp-plugin:ro" \
  -e PLUGIN_DIR=/opt/mvp-plugin node:22-bookworm \
  bash /opt/mvp-plugin/test/from-zero.sh
```

## On the host (less isolated, fast)

Uses your real `bd`/`codex`/`claude`:

```bash
PLUGIN_DIR=external/mvp-plugin bash external/mvp-plugin/test/run-tests.sh
```

## Files

- `Dockerfile` — clean-room image (documented installs + plugin + suite).
- `run-tests.sh` — the Tier-1 suite (host-runnable via `PLUGIN_DIR=`).
- `from-zero.sh` — clean-room bootstrap (no bd → install → green).

## Note on the beads install pin

The image pins `@beads/bd@1.0.4`. npm's *latest* (1.0.5) currently points past
the newest published GitHub release, so its postinstall binary download 404s on a
clean machine. Pin a published release until upstream catches up.
