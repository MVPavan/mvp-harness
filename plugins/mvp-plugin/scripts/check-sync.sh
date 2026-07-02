#!/usr/bin/env bash
# check-sync.sh — surface drift between the two harness payload trees.
#
# The plugin ships two hand-maintained trees, template/.claude and template/.codex.
# They share most content but diverge by design in a few places (declared in
# scripts/sync-manifest.txt). This tool does NOT transform one into the other —
# it tells you, run-on-demand, where the SHARED content has drifted apart so you
# can reconcile it in the source harness and rebuild. The judgement of how to
# reconcile stays with you; this only narrows the field.
#
# Usage:
#   bash scripts/check-sync.sh [check]    # report drift (default). Exit 1 if any.
#   bash scripts/check-sync.sh accept     # record the current state as the accepted
#                                         # baseline (do this AFTER reconciling drift).
#
# A hash baseline (scripts/sync-baseline.txt) records the last accepted state of
# every body-compared pair, so the report shows only NEW drift — not the
# permanent, intentional within-file differences (e.g. Codex's $use-codex wiring).
#
# Override the trees for ad-hoc comparison:
#   SYNC_LEFT=/path/.claude SYNC_RIGHT=/path/.codex bash scripts/check-sync.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  hp_die "bash >= 4 required (uses associative arrays); found ${BASH_VERSION:-unknown}"
fi

LEFT="${SYNC_LEFT:-$HP_PLUGIN_DIR/template/.claude}"
RIGHT="${SYNC_RIGHT:-$HP_PLUGIN_DIR/template/.codex}"
MANIFEST="$SCRIPT_DIR/sync-manifest.txt"
BASELINE="$SCRIPT_DIR/sync-baseline.txt"
MODE="${1:-check}"

[ -d "$LEFT" ]      || hp_die "left tree not found: $LEFT"
[ -d "$RIGHT" ]     || hp_die "right tree not found: $RIGHT"
[ -f "$MANIFEST" ]  || hp_die "manifest not found: $MANIFEST"

# Normalized content hash: collapse the harness path-prefix noise (.claude/.codex)
# so a pure path rename does not read as content drift; everything else counts.
norm_hash() { sed -e 's/\.codex/<<H>>/g' -e 's/\.claude/<<H>>/g' "$1" | sha1sum | cut -d' ' -f1; }

# --- Parse the manifest -----------------------------------------------------
declare -A COVERED_L COVERED_R   # rel paths already accounted for, per tree
declare -a BODY PAIRS            # "left|right" entries
declare -a CIGN RIGN            # claude-only / codex-only allowlist (exact or dir prefix)

while read -r directive a b _rest; do
  case "$directive" in
    ''|\#*) continue ;;
    body) BODY+=("$a|$b"); COVERED_L["$a"]=1; COVERED_R["$b"]=1 ;;
    pair) PAIRS+=("$a|$b"); COVERED_L["$a"]=1; COVERED_R["$b"]=1 ;;
    claude) CIGN+=("$a") ;;
    codex)  RIGN+=("$a") ;;
    *) hp_die "unknown manifest directive: $directive" ;;
  esac
done < "$MANIFEST"

in_ignore() { # path  arr-name -> 0 if allowlisted (exact or "<prefix>/" match)
  local p="$1"; local -n arr="$2"; local pat
  for pat in "${arr[@]:-}"; do
    [ -n "$pat" ] || continue
    if [ "$p" = "$pat" ] || { [ "${pat: -1}" = "/" ] && [[ "$p" == "$pat"* ]]; }; then
      return 0
    fi
  done
  return 1
}

list_tree() { (cd "$1" && find . -type f | sed 's|^\./||' | sort); }

declare -a DRIFT_STRUCT   # missing counterparts / broken pairs (hard)
declare -a DRIFT_ONE      # one side changed since baseline (hard)
declare -a INFO_BOTH      # both sides changed since baseline (informational)
declare -a INFO_NEW       # body pair with no baseline entry yet

# --- Auto-pair same-path files; flag unaccounted ones -----------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -n "${COVERED_L[$f]:-}" ] && continue
  in_ignore "$f" CIGN && { COVERED_L["$f"]=1; continue; }
  if [ -f "$RIGHT/$f" ]; then
    BODY+=("$f|$f"); COVERED_L["$f"]=1; COVERED_R["$f"]=1
  else
    DRIFT_STRUCT+=("only in .claude (no counterpart, not allowlisted): $f")
  fi
done < <(list_tree "$LEFT")

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -n "${COVERED_R[$f]:-}" ] && continue
  in_ignore "$f" RIGN && { COVERED_R["$f"]=1; continue; }
  if [ -f "$LEFT/$f" ]; then
    BODY+=("$f|$f"); COVERED_R["$f"]=1; COVERED_L["$f"]=1
  else
    DRIFT_STRUCT+=("only in .codex (no counterpart, not allowlisted): $f")
  fi
done < <(list_tree "$RIGHT")

# --- Verify presence-only pairs ---------------------------------------------
for entry in "${PAIRS[@]:-}"; do
  [ -n "$entry" ] || continue
  l="${entry%%|*}"; r="${entry#*|}"
  [ -f "$LEFT/$l" ]  || DRIFT_STRUCT+=("declared pair missing .claude side: $l")
  [ -f "$RIGHT/$r" ] || DRIFT_STRUCT+=("declared pair missing .codex side: $r")
done

# --- accept mode: record current body-pair hashes as the baseline -----------
if [ "$MODE" = "accept" ]; then
  : > "$BASELINE"
  printf '# sync-baseline — accepted state of body-compared pairs.\n' >> "$BASELINE"
  printf '# Regenerate with: bash scripts/check-sync.sh accept\n' >> "$BASELINE"
  n=0
  for entry in "${BODY[@]:-}"; do
    [ -n "$entry" ] || continue
    l="${entry%%|*}"; r="${entry#*|}"
    printf 'B %s %s %s\n' "$entry" "$(norm_hash "$LEFT/$l")" "$(norm_hash "$RIGHT/$r")" >> "$BASELINE"
    n=$((n+1))
  done
  hp_ok "baseline recorded: $n body pairs -> ${BASELINE#"$HP_PLUGIN_DIR"/}"
  exit 0
fi

# --- check mode: compare body pairs against the baseline --------------------
declare -A BL_L BL_R
have_baseline=0
if [ -f "$BASELINE" ]; then
  have_baseline=1
  while read -r tag key lh rh _; do
    [ "$tag" = "B" ] || continue
    BL_L["$key"]="$lh"; BL_R["$key"]="$rh"
  done < "$BASELINE"
fi

for entry in "${BODY[@]:-}"; do
  [ -n "$entry" ] || continue
  l="${entry%%|*}"; r="${entry#*|}"
  cur_l="$(norm_hash "$LEFT/$l")"; cur_r="$(norm_hash "$RIGHT/$r")"
  if [ "$have_baseline" -eq 0 ]; then
    [ "$cur_l" = "$cur_r" ] || INFO_NEW+=("$entry")
    continue
  fi
  base_l="${BL_L[$entry]:-}"; base_r="${BL_R[$entry]:-}"
  if [ -z "$base_l" ] && [ -z "$base_r" ]; then
    INFO_NEW+=("$entry"); continue
  fi
  l_changed=0; r_changed=0
  [ "$cur_l" != "$base_l" ] && l_changed=1
  [ "$cur_r" != "$base_r" ] && r_changed=1
  if   [ "$l_changed" -eq 1 ] && [ "$r_changed" -eq 0 ]; then
    DRIFT_ONE+=(".claude changed, .codex stale: $entry")
  elif [ "$r_changed" -eq 1 ] && [ "$l_changed" -eq 0 ]; then
    DRIFT_ONE+=(".codex changed, .claude stale: $entry")
  elif [ "$l_changed" -eq 1 ] && [ "$r_changed" -eq 1 ]; then
    INFO_BOTH+=("$entry")
  fi
done

# --- Report -----------------------------------------------------------------
# Below this point we only read already-populated arrays. Relax nounset because
# bash < 4.4 raises "unbound variable" on ${#empty_array[@]}; all data is final.
set +u
printf '#### check-sync: %s  vs  %s\n' "${LEFT#"$HP_PLUGIN_DIR"/}" "${RIGHT#"$HP_PLUGIN_DIR"/}"

if [ "${#DRIFT_STRUCT[@]}" -gt 0 ]; then
  printf '\nSTRUCTURAL DRIFT — unpaired or broken-pair files (%d):\n' "${#DRIFT_STRUCT[@]}"
  for x in "${DRIFT_STRUCT[@]}"; do [ -n "$x" ] && printf '  - %s\n' "$x"; done
fi
if [ "${#DRIFT_ONE[@]}" -gt 0 ]; then
  printf '\nONE-SIDED DRIFT — a shared file moved on one side only (%d):\n' "${#DRIFT_ONE[@]}"
  for x in "${DRIFT_ONE[@]}"; do
    [ -n "$x" ] || continue
    printf '  - %s\n' "$x"
    entry="${x##*: }"; l="${entry%%|*}"; r="${entry#*|}"
    diff <(sed -e 's/\.codex/<<H>>/g' -e 's/\.claude/<<H>>/g' "$LEFT/$l") \
         <(sed -e 's/\.codex/<<H>>/g' -e 's/\.claude/<<H>>/g' "$RIGHT/$r") \
      | sed 's/^/        /' | head -40 || true
  done
fi
if [ "${#INFO_BOTH[@]}" -gt 0 ]; then
  printf '\nBOTH SIDES CHANGED since baseline (likely already reconciled — informational) (%d):\n' "${#INFO_BOTH[@]}"
  for x in "${INFO_BOTH[@]}"; do [ -n "$x" ] && printf '  - %s\n' "$x"; done
fi
if [ "${#INFO_NEW[@]}" -gt 0 ]; then
  if [ "$have_baseline" -eq 0 ]; then
    printf '\nNO BASELINE — body pairs that currently differ (run '\''accept'\'' to record state) (%d):\n' "${#INFO_NEW[@]}"
  else
    printf '\nNEW pairs not in baseline (run '\''accept'\'' to record) (%d):\n' "${#INFO_NEW[@]}"
  fi
  for x in "${INFO_NEW[@]}"; do [ -n "$x" ] && printf '  - %s\n' "$x"; done
fi

n_hard=$(( ${#DRIFT_STRUCT[@]} + ${#DRIFT_ONE[@]} ))
printf '\n'
if [ "$n_hard" -gt 0 ]; then
  hp_warn "drift found: $n_hard item(s) need reconciliation (see above). Fix in the source harness, rebuild, then run 'accept'."
  exit 1
fi
hp_ok "no drift: shared .claude/.codex content is in sync."
exit 0
