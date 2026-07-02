#!/usr/bin/env bash
# code-intel: discover where serena, CBM, and ast-grep live on this machine.
# Read-only. For each tool prints a status line, and emits ready-to-paste
# `export CODE_INTEL_*_BIN=...` lines for any binary found OFF PATH.
# Used by /code-intel:doctor (diagnose) and /code-intel:setup (wire up).
#
# Resolution order per tool: explicit env override -> canonical name on PATH ->
# known install locations (incl. this repo's cloned harness, if present).
set -u

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
HARNESS="$PROJECT/external/harness_repos"   # present only in the dev repo; skipped elsewhere

# Install hints — keep in sync with README "Installing the underlying tools".
HINT_SERENA='uv tool install -p 3.13 serena-agent   (needs uv: https://docs.astral.sh/uv/)'
HINT_CBM='npm i -g codebase-memory-mcp   (binary only; or: curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --skip-config)'
HINT_ASTGREP='npm install --global @ast-grep/cli   (or: brew install ast-grep | cargo install ast-grep --locked | pip install ast-grep-cli)'

EXPORTS=""

report() { printf '  %-9s %s\n' "$1" "$2"; }

discover() {
  # $1 label  $2 canonical-name  $3 envvar  $4 install-hint  $5.. candidate paths (globs ok)
  local label="$1" name="$2" envvar="$3" hint="$4"; shift 4
  local override="${!envvar:-}" p q
  if [ -n "$override" ]; then
    if [ -x "$override" ] && [ ! -d "$override" ]; then
      report "$label:" "OK (env $envvar) -> $override"
    else
      report "$label:" "env $envvar is set but not an executable file: $override"
    fi
    return
  fi
  if p="$(command -v "$name" 2>/dev/null)"; then
    report "$label:" "ON PATH -> $p   (no env var needed)"
    return
  fi
  for p in "$@"; do
    for q in $p; do                       # unquoted: expand any glob in the candidate
      if [ -x "$q" ] && [ ! -d "$q" ]; then
        report "$label:" "FOUND off PATH -> $q"
        EXPORTS="${EXPORTS}export $envvar=\"$q\""$'\n'
        return
      fi
    done
  done
  report "$label:" "MISSING — install: $hint"
}

echo "code-intel binary discovery (project: $PROJECT)"
discover serena   serena               CODE_INTEL_SERENA_BIN  "$HINT_SERENA" \
  "$HOME/.local/bin/serena" \
  "$HARNESS/serena/.venv/bin/serena"
discover cbm      codebase-memory-mcp  CODE_INTEL_CBM_BIN     "$HINT_CBM" \
  "$HOME/.local/bin/codebase-memory-mcp" \
  "$HARNESS/codebase-memory-mcp/build/c/codebase-memory-mcp"
discover ast-grep ast-grep             CODE_INTEL_ASTGREP_BIN "$HINT_ASTGREP" \
  "$HOME/.cargo/bin/ast-grep" \
  "/opt/homebrew/bin/ast-grep" \
  "$HARNESS/ast-grep/.local-npm/node_modules/@ast-grep/cli-"*"/ast-grep"

if [ -n "$EXPORTS" ]; then
  echo
  echo 'Found off PATH — paste into your shell profile, or the "env" block of ~/.claude/settings.json:'
  printf '%s' "$EXPORTS" | sed 's/^/  /'
fi
exit 0
