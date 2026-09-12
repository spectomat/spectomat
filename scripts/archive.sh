#!/bin/bash
# Spectomat archiver — the ARCHIVE phase.
#
#   archive.sh <slug>
#
# Runs the contract's gates, moves the slug's trail into done/, makes one commit
# and writes one log line. A failing gate moves nothing and exits 1, until the
# third strike: then the trail is archived with a .blocked infix so the floor
# can move on. Nothing outside the floor is touched.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

SLUG="${1:-}"
BLOCK=""      # ".blocked" once the third strike lands
GATE_RESULT="" # "N/N" or "failed", for the log line

now() { date -u +%FT%RZ; }
log_line() { printf '%s\n' "$1" >> "$FLOOR/log.md"; }

require_ready() {
  [[ -n "$SLUG" ]] || die "usage: archive.sh <slug>"
  [[ -z "$(git status --porcelain)" ]] || die "tree is dirty: the janitor runs before ARCHIVE"
  [[ -f "$FLOOR/specs/$SLUG.md" ]] || die "no $FLOOR/specs/$SLUG.md"
  [[ -f "$FLOOR/plans/$SLUG.md" ]] || die "no $FLOOR/plans/$SLUG.md"
}

# Log one ARCHIVE strike for this slug and print the new count. Shared by
# every way ARCHIVE can fail - a red gate and a failed move or commit both
# count against the same STRIKE_LIMIT for this slug, so a slug that keeps
# failing archival for any reason eventually drops out of the picker's ARCHIVE
# candidates instead of burning every remaining iteration.
strike() {
  local reason="$1" n
  n=$(( $(strike_count ARCHIVE "$SLUG") + 1 ))
  log_line "- $(now) · ARCHIVE · $SLUG · $reason (strike $n)"
  printf '%s\n' "$n"
}

# Run the gates. A failure logs a strike and stops, unless it is the third:
# then the trail is archived blocked instead of stranding the floor.
gate_or_strike() {
  local total n
  total=$(gate_block | wc -l | tr -d ' ')
  if run_gates; then
    GATE_RESULT="$total/$total"
    return 0
  fi
  n=$(strike "gate failed: $GATE_FAILED")
  if [[ $n -lt $STRIKE_LIMIT ]]; then
    echo "❌ gate failed: $GATE_FAILED (strike $n of $STRIKE_LIMIT)" >&2
    exit 1
  fi
  BLOCK=".blocked"
  GATE_RESULT="failed"
}

# Every move is checked: an unchecked git mv can fail silently (a stray file
# already at the destination) while a later move in the same run succeeds,
# leaving a half-moved trail that a bare `git status --porcelain` marks dirty
# but that commit_archive would otherwise commit as a clean, confident
# "archived". A failed move strikes and exits, leaving the tree exactly as it
# landed: dirty if a later move already ran, clean if this was the first. The
# janitor's recovery path is designed for the dirty case; the clean case is
# safe to retry as-is once the destination conflict is cleared.
move_trail() {
  git mv "$FLOOR/specs/$SLUG.md" "$FLOOR/done/$SLUG.spec$BLOCK.md" || fail_move "specs/$SLUG.md"
  git mv "$FLOOR/plans/$SLUG.md" "$FLOOR/done/$SLUG.plan$BLOCK.md" || fail_move "plans/$SLUG.md"
  if [[ -d "$FLOOR/plans/$SLUG" ]]; then
    git mv "$FLOOR/plans/$SLUG" "$FLOOR/done/$SLUG" || fail_move "plans/$SLUG"
  fi
}

fail_move() {
  strike "move failed: git mv $1" >/dev/null
  echo "❌ move failed: git mv $1" >&2
  exit 1
}

commit_archive() {
  local msg
  if [[ -n "$BLOCK" ]]; then
    msg="chore($SLUG): blocked after $STRIKE_LIMIT strikes"
  else
    msg="chore($SLUG): archived"
  fi
  git add -A "$FLOOR/done" "$FLOOR/specs" "$FLOOR/plans"
  if ! git commit -q -m "$msg"; then
    strike "commit failed" >/dev/null
    echo "❌ commit failed after moving $SLUG's trail" >&2
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
  move_trail
  commit_archive
  log_result
  echo "ARCHIVE $SLUG · gates $GATE_RESULT${BLOCK:+ · BLOCKED}"
}

main "$@"
