#!/usr/bin/env bash
# Shared helpers for the harness plugin's scripts. Sourced, not executed.

# Plugin root: prefer the value Claude Code injects; otherwise derive it from
# this file's location (scripts/lib/common.sh -> two levels up).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  HP_PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"
else
  HP_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export HP_PLUGIN_DIR

# Target repo: the repo being adopted into. Prefer CLAUDE_PROJECT_DIR, then the
# git work-tree root, then the current directory.
hp_target() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
  elif git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

hp_info() { printf '  %s\n' "$1"; }
hp_ok()   { printf '  OK   %s\n' "$1"; }
hp_skip() { printf '  SKIP %s\n' "$1"; }
hp_warn() { printf '  WARN %s\n' "$1"; }
hp_die()  { printf 'harness FAIL: %s\n' "$1" >&2; exit 1; }

# A payload path is "user-owned" only if it is per-repo facts we must NEVER touch:
# the project overlay. Everything else — including CLAUDE.md/AGENTS.md and the
# settings.json / config.toml wiring — goes through the three-way merge, which
# protects a repo's local edits while still letting an UNTOUCHED file receive
# upstream improvements (e.g. new hook wiring). See install-harness.sh copy_one.
hp_is_user_owned() {
  case "$1" in
    .claude/project/*|.codex/project/*) return 0 ;;
    *) return 1 ;;
  esac
}

# The payload is stored dot-less (claude/… codex/… beads/…) so the source
# harness's own Claude Code does not scan template/.claude as project skills.
# Map a stored payload path back to the dotted path the adopted repo needs
# (.claude/… .codex/… .beads/…). Root files (CLAUDE.md, AGENTS.md) pass through.
hp_to_dotted() {
  case "$1" in
    claude|codex|beads) printf '.%s' "$1" ;;
    claude/*|codex/*|beads/*) printf '.%s' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Content hash (sha256) of a file, for the three-way update merge. Prints an empty
# string for a missing file. Portable across the sha256sum / shasum front-ends.
hp_hash() {
  [ -f "$1" ] || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}
