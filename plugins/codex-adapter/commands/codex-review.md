---
description: Run an adversarial Codex code review of the current changes (read-only).
argument-hint: "[optional focus area]"
---

Have OpenAI Codex review the current code changes and relay its findings.

Optional focus: $ARGUMENTS

Do this:

1. Run the `review` role via Bash:
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.mjs" --role review -C "$(pwd)" "$ARGUMENTS"`
   - **Read-only.** The role reviews the repo's uncommitted diff (or the most relevant recent changes if there is none); the optional focus narrows it.
   - To pin model/effort, add `-m <model>` / `-e <level>`.
   - To target a precise diff (a base branch or a single commit), use Codex's native
     review harness instead: `--review --base=<branch>` (or `--commit=<sha>`,
     `--uncommitted`) **without** the role or focus text — Codex rejects custom
     instructions combined with a target flag.
2. Relay Codex's findings **attributed to Codex**. Do not fix the issues yourself unless I ask; flag anything you disagree with.
