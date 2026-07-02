---
description: Explain how to turn the code-intel stack OFF for the current repo (so it doesn't start serena/CBM here), without affecting other projects.
---

The user wants to stop running the code-intel stack in THIS repo (e.g. a small or
throwaway project where indexing/serena/CBM aren't worth it). Explain — do not
edit anything unless the user confirms.

Two opt-out levels, least invasive first:

1. **Per-machine, uncommitted (recommended):** add to `.claude/settings.local.json`
   (gitignored) in this repo:
   ```json
   { "enabledPlugins": { "code-intel@code-intel": false } }
   ```
   This disables the plugin for this repo on this machine only; teammates and
   other repos are unaffected.

2. **Per-repo for everyone (committed):** if the team should never load it here,
   set the same `"code-intel@code-intel": false` in the repo's committed
   `.claude/settings.json`. Project settings override user settings.

Notes:
- ast-grep via `bin/` costs ~0 tokens, so disabling is really about not starting
  the serena LSP + CBM watcher/index for this repo.
- To re-enable later, set the value back to `true` or remove the key.
- The exact plugin key is `code-intel@<marketplace-name>`; confirm the marketplace
  name with `/plugin` if unsure.

Confirm with the user which level they want, then apply only if they say so.
