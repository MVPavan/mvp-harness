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

# A payload path is "user-owned" if it is something a repo owner customises and
# we must never clobber: the per-repo overlay, the root instruction files, and
# the hook/config wiring surfaces. Everything else (rules, skills, agents,
# commands, hook scripts, docs) is reusable harness core we may overwrite.
hp_is_user_owned() {
  case "$1" in
    CLAUDE.md|AGENTS.md) return 0 ;;
    .claude/settings.json|.codex/config.toml|.codex/hooks.json) return 0 ;;
    .claude/project/*|.codex/project/*) return 0 ;;
    *) return 1 ;;
  esac
}
