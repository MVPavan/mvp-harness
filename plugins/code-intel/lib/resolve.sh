# Shared binary resolver for code-intel launcher shims.
# Sourced (never executed) by bin/*. Targets bash 4+.
#
# resolve_bin <tool> <override> <self_dir>
#   <tool>      real executable name to find on PATH (e.g. serena, ast-grep)
#   <override>  explicit path from an env var, or "" to search PATH
#   <self_dir>  this plugin's bin/ dir; skipped during the PATH search so a
#               shim named after its own tool cannot recurse into itself
# Prints the resolved absolute path on stdout. On failure, prints an
# actionable message to stderr and exits 127 (fail loud — never silent).
resolve_bin() {
  local tool="$1" override="$2" self_dir="$3" dir
  if [ -n "$override" ]; then
    if [ -x "$override" ] && [ ! -d "$override" ]; then
      printf '%s' "$override"
      return 0
    fi
    printf 'code-intel: override path for %s is not an executable file: %s\n' "$tool" "$override" >&2
    exit 127
  fi
  local IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || dir=.
    [ "$dir" = "$self_dir" ] && continue
    if [ -x "$dir/$tool" ] && [ ! -d "$dir/$tool" ]; then
      printf '%s' "$dir/$tool"
      return 0
    fi
  done
  printf "code-intel: '%s' not found. Run /code-intel:setup to auto-detect and wire it up, or set its override env var / add it to PATH. See /code-intel:doctor.\n" "$tool" >&2
  exit 127
}
