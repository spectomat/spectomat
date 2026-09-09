#!/bin/bash
# Spectomat status sections. Source it after utils.sh, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/print.sh"
#
# Every print_* writes one "--- section ---" block to stdout and needs
# FLOOR, STATE_FILE, MEMORY, count and state_field from utils.sh.

print_loop() {
  echo "--- flow ---"
  if [[ -f "$STATE_FILE" ]]; then
    echo "active: loop $(state_field loop) of $(state_field max_loops)"
  else
    echo "not running"
  fi
}

print_floor() {
  echo "--- floor: $FLOOR ---"
  echo "drafts: $(count "$FLOOR/drafts")   specs: $(count "$FLOOR/specs")   plans: $(count "$FLOOR/plans")   done: $(count "$FLOOR/done")   memory: $(memory_entries) entries"
}

# Entries in memory.md: list items, which is what the contract asks a memory to be.
# grep -c exits 1 on no match, so the file check comes first and the count stands alone.
memory_entries() {
  [[ -f "$MEMORY" ]] || { echo 0; return; }
  grep -c '^- ' "$MEMORY" | tr -d ' '
}

# One line per plan: task count, ticked/open steps across its task files, next open task.
print_plans() {
  local p slug tasks ticked open next
  for p in "$FLOOR"/plans/*.md; do
    [[ -f "$p" ]] || continue
    slug="$(basename "$p" .md)"
    tasks=$(find "$FLOOR/plans/$slug" -maxdepth 1 -name 'task-*.md' 2>/dev/null | wc -l | tr -d ' ')
    ticked=$(cat "$FLOOR/plans/$slug"/task-*.md 2>/dev/null | grep -cE '^- \[x\]' || true)
    open=$(cat "$FLOOR/plans/$slug"/task-*.md 2>/dev/null | grep -cE '^- \[ \]' || true)
    next=$(grep -lE '^- \[ \]' "$FLOOR/plans/$slug"/task-*.md 2>/dev/null | head -1)
    printf "%-24s tasks %2d  steps done %3d  open %3d  next: %s\n" "$slug" "$tasks" "$ticked" "$open" "${next:+$(basename "$next")}"
  done
}

print_blocked() {
  local blocked
  blocked=$(find "$FLOOR/done" -maxdepth 1 -name '*.blocked.md' -type f 2>/dev/null)
  if [[ -n "$blocked" ]]; then
    echo "--- blocked ---"
    echo "$blocked" | sed "s|^$FLOOR/done/||"
  fi
}

print_log_tail() {
  if [[ -f "$FLOOR/log.md" ]]; then
    echo "--- log tail ---"
    grep '^- ' "$FLOOR/log.md" | tail -5
  fi
}

print_commits() {
  echo "--- last commits ---"
  git log --oneline -5 2>/dev/null || echo "(no git)"
}
