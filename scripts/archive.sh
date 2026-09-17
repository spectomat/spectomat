#!/bin/bash
# Spectomat archiver — the ARCHIVE phase.
#
#   archive.sh <slug>
#
# Runs the contract's gates, marks the slug finished, makes one commit and
# writes one log line. Nothing moves: the slug's trail stays in .spectomat/<slug>/
# and ARCHIVE writes done.md beside it. A failing gate writes nothing and exits
# 1, until the third strike: then blocked.md is written instead, carrying the
# reason, so the floor can move on. Nothing outside the floor is touched.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

SLUG="${1:-}"
BLOCK=""       # non-empty once the third strike lands: blocked.md, not done.md
GATE_RESULT="" # "passed" or "failed", for the log line and the marker

now() { date -u +%FT%RZ; }
log_line() { printf '%s\n' "$1" >> "$FLOOR/log.md"; }

require_ready() {
  [[ -n "$SLUG" ]] || die "usage: archive.sh <slug>"
  [[ -z "$(git status --porcelain)" ]] || die "tree is dirty: the janitor runs before ARCHIVE"
  [[ -f "$FLOOR/$SLUG/spec.md" ]] || die "no $FLOOR/$SLUG/spec.md"
  [[ -f "$FLOOR/$SLUG/plan.md" ]] || die "no $FLOOR/$SLUG/plan.md"
  slug_finished "$SLUG" && die "$SLUG is already finished: $FLOOR/$SLUG carries a marker"
  return 0
}

# Log one ARCHIVE strike for this slug and print the new count. Shared by
# every way ARCHIVE can fail - a red gate and a failed move or commit both
# count against the same STRIKE_LIMIT for this slug, so a slug that keeps
# failing archival for any reason eventually drops out of the picker's ARCHIVE
# candidates instead of burning every remaining iteration.
strike() {
  local reason="$1" n
  n=$(slug_strike "$SLUG" ARCHIVE)
  log_line "- $(now) · ARCHIVE · $SLUG · $reason (strike $n)"
  printf '%s\n' "$n"
}

# Run the gates. A failure logs a strike and stops, unless it is the third:
# then the slug is marked blocked instead of stranding the floor.
gate_or_strike() {
  local n
  if run_gates; then
    GATE_RESULT="passed"
    return 0
  fi
  n=$(strike "gate failed: $GATE_FAILED")
  if [[ $n -lt $STRIKE_LIMIT ]]; then
    echo "❌ gate failed: $GATE_FAILED (strike $n of $STRIKE_LIMIT)" >&2
    exit 1
  fi
  BLOCK="yes"
  GATE_RESULT="failed"
}

# Mark the slug finished: one new file in its own dir, and nothing else on the
# floor changes. done.md says it shipped; blocked.md says the third strike
# landed and carries the reason, which is what /spectomat:status lists and the
# closing report counts. The picker skips a slug dir carrying either.
write_marker() {
  if [[ -n "$BLOCK" ]]; then
    printf '# %s — blocked\n\nBlocked after %s strikes on %s · gate failed: %s\n' \
      "$SLUG" "$STRIKE_LIMIT" "$(now)" "${GATE_FAILED:-$GATES_SH}" > "$FLOOR/$SLUG/blocked.md"
  else
    printf '# %s — done\n\nArchived %s · gates %s\n' \
      "$SLUG" "$(now)" "$GATE_RESULT" > "$FLOOR/$SLUG/done.md"
  fi
}

commit_archive() {
  local msg
  if [[ -n "$BLOCK" ]]; then
    msg="chore($SLUG): blocked after $STRIKE_LIMIT strikes"
  else
    msg="chore($SLUG): archived"
  fi
  git add -A "$FLOOR/$SLUG"
  if ! git commit -q -m "$msg"; then
    strike "commit failed" >/dev/null
    echo "❌ commit failed after marking $SLUG finished" >&2
    exit 1
  fi
}

log_result() {
  if [[ -n "$BLOCK" ]]; then
    log_line "- $(now) · ARCHIVE · $SLUG · blocked after $STRIKE_LIMIT strikes · gates $GATE_RESULT"
  else
    log_line "- $(now) · ARCHIVE · $SLUG · archived · gates $GATE_RESULT"
  fi
}

main() {
  require_ready
  gate_or_strike
  write_marker
  commit_archive
  slug_delete "$SLUG"
  log_result
  echo "ARCHIVE $SLUG · gates $GATE_RESULT${BLOCK:+ · BLOCKED}"
}

main "$@"
