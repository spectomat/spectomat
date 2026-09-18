#!/bin/bash
# Spectomat archiver — the ARCHIVE phase.
#
#   agent-archive.sh <slug>
#
# Runs the contract's gates, marks the slug finished, makes one commit, records
# the terminal phase in state.json and writes one log line. Nothing moves: the
# slug's trail stays in .spectomat/<slug>/ and ARCHIVE writes done.md beside it.
# A failing gate writes nothing and exits 1, until the third strike: then
# blocked.md is written instead, carrying the reason, so the floor can move on.
# Nothing outside the floor is touched.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

SLUG="${1:-}"
BLOCK=""       # non-empty once the third strike lands: blocked.md, not done.md
GATE_RESULT="" # "passed" or "failed", for the log line and the marker

now() { date -u +%FT%RZ; }
log_line() { bash "$PLUGIN_ROOT/scripts/log.sh" ARCHIVE "$SLUG" "$1"; }

# One state check does the work of the three file checks it replaces, and is
# stronger than all of them: a slug only reaches ARCHIVE through REVIEW, which
# only happens after PLAN wrote a plan and IMPLEMENT closed every task. It also
# refuses a second archive and refuses to promote a blocked slug to shipped,
# since neither DONE nor BLOCKED is ARCHIVE.
require_ready() {
  local phase
  [[ -n "$SLUG" ]] || die "usage: agent-archive.sh <slug>"
  [[ -z "$(git status --porcelain)" ]] || die "tree is dirty: the janitor runs before ARCHIVE"
  phase="$(slug_phase "$SLUG")"
  [[ -n "$phase" ]] || die "$SLUG is not tracked in $STATE_FILE"
  [[ "$phase" == ARCHIVE ]] || die "$SLUG is at $phase, not ARCHIVE"
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
  log_line "$reason (strike $n)"
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
# landed and carries the reason. These are the committed human record — the
# only trace of how a slug ended that survives in git, since state.json is
# gitignored — and nothing reads them back: slug_finish below is what takes the
# slug out of the flow.
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
    log_line "blocked after $STRIKE_LIMIT strikes · gates $GATE_RESULT"
  else
    log_line "archived · gates $GATE_RESULT"
  fi
}

# Record the terminal phase. This is what takes the slug out of the flow, and
# it runs last on purpose: a failed commit exits above with a strike and no
# terminal entry, so the picker hands ARCHIVE back next iteration.
finish_slug() {
  if [[ -n "$BLOCK" ]]; then
    slug_finish "$SLUG" blocked "gate failed: ${GATE_FAILED:-$GATES_SH}"
  else
    slug_finish "$SLUG" done "gates $GATE_RESULT"
  fi
}

main() {
  require_ready
  # Before the gates: they must run against the slug's own work, and done.md
  # must land on its branch. A missing branch is a strike, never a new branch.
  if ! slug_checkout "$SLUG"; then
    strike "branch $(slug_branch "$SLUG") missing" >/dev/null
    echo "❌ cannot check out $(slug_branch "$SLUG")" >&2
    exit 1
  fi
  gate_or_strike
  write_marker
  commit_archive
  finish_slug
  log_result
  echo "ARCHIVE $SLUG · gates $GATE_RESULT${BLOCK:+ · BLOCKED}"
}

main "$@"
