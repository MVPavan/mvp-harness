---
description: Adopt the agent harness into this repo — copy the .claude/.codex setup, init beads, then adapt the project overlay to this repo's reality.
---

# /mvp-plugin:adopt

Install the self-contained harness into the current repository, then adapt it.

## Steps

1. **Copy + initialise (deterministic).** Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-harness.sh"
   ```

   This copies both harness trees, preserves anything the repo already owns
   (`CLAUDE.md`/`AGENTS.md`, settings/config, the overlay), drops project-overlay
   skeletons, runs `bd init`, and points beads sync at the repo's own git remote.
   It is idempotent and never `git add`s.

2. **Adapt (judgement).** Use the **harness-adopt** skill to replace the overlay
   skeletons in `.claude/project/*` and `.codex/project/*` with facts derived
   from THIS repo, and to append report-only automation recommendations.

3. **Review.** Present `.claude/project/adoption-report.md` and stop. Do not
   commit or `git add` — let the user review first.

If the installer warns that `bd` is missing, tell the user to run
`npm i -g @beads/bd`, then re-run `/mvp-plugin:adopt`.
