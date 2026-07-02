---
description: Verify the harness is correctly installed and wired in this repo (payload, hooks, beads, overlay, codex CLI).
---

# /mvp-plugin:doctor

Run the wiring checks and report the result:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

Summarize the PASS/WARN/FAIL lines. For each WARN or FAIL, give the one concrete
fix (an install command, or `/mvp-plugin:adopt`, or running the harness-adopt skill
to fill the overlay). Do not change anything unless the user asks.
