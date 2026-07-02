# Clean-room test image for the code-intel plugin.
#
# Installs serena, CBM, and ast-grep using the EXACT commands from the plugin
# README ("Installing the underlying tools") — so a green build also proves the
# install guidance is correct on a fresh machine — then runs the plugin's test
# suite (test/run-tests.sh). No Claude Code account or API key is required: the
# MCP servers are driven directly over stdio by test/mcp-probe.mjs.
#
# Build (context = the plugin dir):
#   docker build -f external/code-intel/test/Dockerfile -t code-intel-test external/code-intel
# Run:
#   docker run --rm code-intel-test
FROM node:22-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# ast-grep — documented npm install
RUN npm install --global @ast-grep/cli

# CBM — documented npm install (binary only; no agent auto-config)
RUN npm install --global codebase-memory-mcp

# uv, then serena — documented install
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"
RUN uv tool install -p 3.13 serena-agent

# Claude CLI for the offline `plugin validate` step (best-effort; not required)
RUN npm install --global @anthropic-ai/claude-code || true

# The plugin under test
COPY . /opt/code-intel
RUN chmod +x /opt/code-intel/bin/* /opt/code-intel/scripts/*.sh /opt/code-intel/hooks/*.sh

ENV PLUGIN_DIR=/opt/code-intel
WORKDIR /opt/code-intel
ENTRYPOINT ["bash", "test/run-tests.sh"]
