---
description: Have Codex research a question using web search, with citations (read-only).
argument-hint: "<research question>"
---

Have OpenAI Codex research the question and relay a cited synthesis.

Question: $ARGUMENTS

Do this:

1. Run the `research` role via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" --role research -C "$(pwd)" "$ARGUMENTS"`
   - **Read-only**, **web search enabled** (the role sets a non-minimal effort, required for web search).
2. Relay Codex's answer **attributed to Codex**, preserving its source citations (URLs). Flag any claims it left uncertain.
