---
description: Have Codex make a bounded code change and verify it (edits the working tree).
argument-hint: "<what to implement>"
---

Have OpenAI Codex implement the change described. **This edits files in the working tree.**

Task: $ARGUMENTS

Do this:

1. Run the `implement` role via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" --role implement -C "$(pwd)" "$ARGUMENTS"`
   - **Writable** (workspace-write) — Codex may edit files in the current repo. It does not commit or push.
2. Summarize exactly what Codex changed and what it ran to verify, **attributed to Codex** — do not present its edits as your own work, and flag anything you disagree with. Review the diff before relying on it.
