---
description: Get an independent Codex critique / second opinion on a decision, design, or plan (read-only).
argument-hint: "<decision/design + context>"
---

Have OpenAI Codex give an independent second opinion on the decision or design below.

Proposal: $ARGUMENTS

Do this:

1. Run the `critique` role via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" --role critique -C "$(pwd)" "$ARGUMENTS"`
   - **Read-only**, **web search enabled** — the role steelmans both sides, ranks objections, and ends with a recommendation + confidence.
2. Relay Codex's critique **attributed to Codex**, including its bottom-line recommendation and what would change its mind. Don't soften its disagreements — surface them.
