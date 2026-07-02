---
description: Check that the Codex CLI is installed, on PATH, and authenticated for the adapter.
allowed-tools: Bash
---

Verify the Codex CLI is ready for the codex-adapter plugin, then report clearly.

Do this:

1. Run these checks via Bash:
   ```bash
   command -v codex >/dev/null 2>&1 && codex --version || echo "codex: NOT FOUND on PATH"
   test -f "$HOME/.codex/auth.json" && echo "auth: credentials present" || echo "auth: NOT logged in"
   node --version || echo "node: NOT FOUND on PATH"
   ```
2. Report the result and the fix for anything missing:
   - `codex` not found → run `npm i -g @openai/codex`.
   - auth missing → run `codex login`.
   - `node` not found → install Node.js ≥ 18.
   - All present → confirm the adapter is ready to use (`/codex`, `/codex-review`, …).
3. Note honestly: credential presence does not guarantee a valid or unexpired
   session — the first real `/codex` call will surface any auth error.
