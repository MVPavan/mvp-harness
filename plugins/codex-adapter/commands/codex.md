---
description: Delegate a task or question to OpenAI Codex (gpt-5.x) and relay its answer.
argument-hint: [prompt for Codex]
---

Delegate the following request to OpenAI Codex and report back.

Request: $ARGUMENTS

Do this:

1. Run the Codex adapter via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" -C "$(pwd)" "<the request above>"`
   - Runs **read-only** by default — Codex can read the repo and answer, but not edit.
   - If the request clearly asks Codex to **modify files**, add `--writable`.
   - To pin a model or effort, add `-m <model>` / `-e <high|medium|low|...>`.
   - The runner prints Codex's progress to stderr and its final answer to stdout.
2. Relay Codex's final answer back to me, clearly **attributed to Codex**.
   - If Codex made edits, summarize what changed — do not present them as your own work, and flag anything you disagree with.
   - If Codex is uncertain or failed, say so plainly; do not paper over it.
