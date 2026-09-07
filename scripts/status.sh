#!/bin/bash
# Spectomat status — loop state, factory floor counts, plan progress, log tail.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STATE="docs/.spectomat/loop.md"
FLOOR="docs/.spectomat"

echo "--- loop ---"
if [[ -f "$STATE" ]]; then
  echo "active: iteration $(grep '^iteration:' "$STATE" | sed 's/iteration: *//') of $(grep '^max_iterations:' "$STATE" | sed 's/max_iterations: *//')"
else
  echo "not running"
fi

if [[ ! -d "$FLOOR" ]]; then
  echo "No $FLOOR/ in $ROOT - /spectomat:run has not been started here."
  exit 0
fi

count() { find "$1" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '; }
echo "--- floor: $FLOOR ---"
echo "drafts: $(count "$FLOOR/drafts")   specs: $(count "$FLOOR/specs")   plans: $(count "$FLOOR/plans")   done: $(count "$FLOOR/done")"

for p in "$FLOOR"/plans/*.md; do
  [[ -f "$p" ]] || continue
  printf "%-40s steps done %3d  open %3d\n" "$(basename "$p")" \
    "$(grep -cE '^- \[x\]' "$p" || true)" "$(grep -cE '^- \[ \]' "$p" || true)"
done

BLOCKED=$(find "$FLOOR/done" -maxdepth 1 -name '*.blocked.md' -type f 2>/dev/null)
if [[ -n "$BLOCKED" ]]; then
  echo "--- blocked ---"
  echo "$BLOCKED" | sed "s|^$FLOOR/done/||"
fi

if [[ -f "$FLOOR/log.md" ]]; then
  echo "--- log tail ---"
  grep '^- ' "$FLOOR/log.md" | tail -5
fi

echo "--- last commits ---"
git log --oneline -5 2>/dev/null || echo "(no git)"
