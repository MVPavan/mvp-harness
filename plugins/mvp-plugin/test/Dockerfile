# Clean-room image for the harness plugin's Tier-1 suite.
# Installs only what a fresh machine needs (git + beads), copies the plugin, and
# runs the suite. No Claude Code account required.
#   docker build -f external/mvp-plugin/test/Dockerfile -t mvp-plugin-test external/mvp-plugin
#   docker run --rm mvp-plugin-test
FROM node:22-bookworm

RUN apt-get update -qq \
 && apt-get install -y -qq git ca-certificates >/dev/null \
 && rm -rf /var/lib/apt/lists/*

# Beads — the one external tool /mvp-plugin:adopt needs. Pinned to @1.0.4 because
# npm's "latest" (1.0.5) currently points past the newest published GitHub
# release, so its postinstall binary download 404s on a clean machine. codex CLI
# is intentionally omitted: doctor only WARNs for it.
RUN npm install -g @beads/bd@1.0.4 >/dev/null 2>&1

ENV BD_NON_INTERACTIVE=1 \
    PLUGIN_DIR=/opt/mvp-plugin \
    FIXTURE_DIR=/tmp/harness-fixture

COPY . /opt/mvp-plugin
WORKDIR /tmp
ENTRYPOINT ["bash", "/opt/mvp-plugin/test/run-tests.sh"]
