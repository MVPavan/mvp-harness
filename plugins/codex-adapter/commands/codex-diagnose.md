---
description: Have Codex root-cause a failure without changing files (read-only).
argument-hint: "<describe the failure or symptom>"
---

Have OpenAI Codex diagnose the failure described and relay its root-cause analysis.

Failure: $ARGUMENTS

Do this:

1. Run the `diagnose` role via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" --role diagnose -C "$(pwd)" "$ARGUMENTS"`
   - **Read-only** — Codex investigates and explains; it does not edit.
2. Relay Codex's diagnosis **attributed to Codex**. If it proposes a fix, present it as Codex's suggestion; flag anything you disagree with.
