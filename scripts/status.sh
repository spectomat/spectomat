#!/bin/bash
# Spectomat status — summarise the build ledger and the Ralph loop state.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
LEDGER=".claude/build-ledger.local.md"
STATE=".claude/spectomat-loop.local.md"

echo "--- loop ---"
if [[ -f "$STATE" ]]; then
  echo "active: iteration $(grep '^iteration:' "$STATE" | sed 's/iteration: *//') of $(grep '^max_iterations:' "$STATE" | sed 's/max_iterations: *//')"
else
  echo "not running"
fi

if [[ ! -f "$LEDGER" ]]; then
  echo "No ledger at $ROOT/$LEDGER - Phase 0 has not run."
  exit 0
fi

DONE=$(grep -cE '^- \[x\]' "$LEDGER" || true)
OPEN=$(grep -cE '^- \[ \]' "$LEDGER" || true)
BLOCKED=$(grep -cE '^- \[x\].*BLOCKED' "$LEDGER" || true)
STRIKES=$(grep -cE '^- \[ \].*\(strike [0-9]\)' "$LEDGER" || true)

echo "--- ledger: $LEDGER ---"
echo "done: $DONE (blocked: $BLOCKED)   open: $OPEN   with strikes: $STRIKES"

echo "--- per phase ---"
awk '
  /^## Phase/ { if (name != "") printf "%-48s done %3d  open %3d\n", name, d, o; name = $0; d = 0; o = 0; next }
  /^- \[x\]/ { d++ }
  /^- \[ \]/ { o++ }
  END { if (name != "") printf "%-48s done %3d  open %3d\n", name, d, o }
' "$LEDGER"

echo "--- next item ---"
awk '
  /^## Phase/ { phase = $0 }
  /^- \[ \]/ { print phase; print $0; exit }
' "$LEDGER"
[[ $OPEN -gt 0 ]] || echo "(none - every item is ticked or BLOCKED)"

if [[ $BLOCKED -gt 0 ]]; then
  echo "--- blocked ---"
  grep -E '^- \[x\].*BLOCKED' "$LEDGER"
fi

echo "--- last commits ---"
git log --oneline -5 2>/dev/null || echo "(no git)"
