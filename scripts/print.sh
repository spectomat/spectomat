#!/bin/bash
# Spectomat status sections. Source it after utils.sh, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/print.sh"
#
# Every print_* writes one "--- section ---" block to stdout and needs
# FLOOR, STATE_FILE, MEMORY, count and state_field from utils.sh.

print_iteration() {
  echo "--- flow ---"
  if [[ -f "$STATE_FILE" ]]; then
    if [[ "$(state_field active)" == "true" ]]; then
      echo "active: iteration $(state_field iteration) of $(state_field max_iterations)"
    else
      echo "cancelled: was at iteration $(state_field iteration) of $(state_field max_iterations) — /spectomat:run resumes it"
    fi
  else
    echo "not running"
  fi
}

print_floor() {
  echo "--- floor: $FLOOR ---"
  echo "drafts: $(count "$FLOOR/drafts")   active: $(slug_active_dirs | wc -l | tr -d ' ')   done: $(slugs_marked done.md | wc -l | tr -d ' ')   blocked: $(slugs_marked blocked.md | wc -l | tr -d ' ')   memory: $(memory_entries) entries"
}

# Entries in memory.md: list items, which is what the contract asks a memory to be.
# grep -c exits 1 on no match, so the file check comes first and the count stands alone.
memory_entries() {
  [[ -f "$MEMORY" ]] || { echo 0; return; }
  grep -c '^- ' "$MEMORY" | tr -d ' '
}

print_plans() {
  local slug phase tasks_total tasks_done next
  [[ -f "$STATE_FILE" ]] || return 0
  while IFS=$'\t' read -r slug phase tasks_total tasks_done; do
    [[ -n "$slug" ]] || continue
    next="-"
    [[ "$phase" != "IMPLEMENT" ]] || next=$((tasks_done + 1))
    printf "%-24s phase %-10s tasks %2d  done %3d  next: %s\n" "$slug" "$phase" "$tasks_total" "$tasks_done" "$next"
  done < <(jq -r '
    .slugs // {} | to_entries[]
    | [.key, (.value.phase // "?"), (.value.tasks_total // 0), (.value.tasks_done // 0)] | @tsv
  ' "$STATE_FILE" 2>/dev/null | sort)
}

# One line per blocked slug, each naming the dir whose blocked.md holds the
# reason. A blocked slug that nothing reports is a silently dropped idea.
print_blocked() {
  local blocked
  blocked=$(slugs_marked blocked.md)
  if [[ -n "$blocked" ]]; then
    echo "--- blocked ---"
    printf '%s\n' "$blocked" | sed "s|^|$FLOOR/|; s|\$|/blocked.md|"
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

# What the next iteration will do. This runs the picker itself rather than
# re-deriving the answer, so the prediction cannot drift from the decision.
print_next() {
  echo "--- next ---"
  bash "$PLUGIN_ROOT/scripts/phase.sh"
}
