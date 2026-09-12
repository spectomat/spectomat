#!/bin/bash
# Spectomat phase picker — which phase the next iteration must do.
#
#   phase.sh        prints one line and exits 0:
#                     "A <slug>"  draft -> spec
#                     "B <slug>"  spec -> plan
#                     "C <slug>"  plan -> next task
#                     "D <slug>"  plan -> done
#                     "R"         dirty tree, or a floor no stage claims
#                     "E"         nothing left; the flow may end
#
# Pure: reads the floor, log.md and git status, writes nothing. The session
# runs it once per iteration and /spectomat:status runs it on demand.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

# Slugs of the .md files directly inside a floor directory, alphabetically.
# Bash sorts a glob, so no `ls` is parsed and a slug may contain spaces.
slugs_in() {
  local f
  for f in "$FLOOR/$1"/*.md; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "$(basename "$f" .md)"
  done
}

# Task files of one plan.
task_count() {
  local f n=0
  for f in "$FLOOR/plans/$1"/task-*.md; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
  done
  printf '%s\n' "$n"
}

# True when any task file of the plan still has an unchecked step.
has_open_step() { grep -qE '^- \[ \]' "$FLOOR/plans/$1"/task-*.md 2>/dev/null; }

# D: a plan whose task files exist and are all ticked. The task-file count is
# what stops an empty plan directory from satisfying "all steps ticked" for
# free and archiving work that was never built.
candidates_d() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ $(task_count "$s") -ge 1 ]] || continue
    has_open_step "$s" && continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# C: a plan with an unchecked step.
candidates_c() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    has_open_step "$s" || continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# B: a spec with no plan overview, or an overview with no task files — a phase
# B that died before writing them. Without the second clause that plan matches
# no stage and is unreachable for the life of the floor.
candidates_b() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if [[ ! -f "$FLOOR/plans/$s.md" ]] || [[ $(task_count "$s") -eq 0 ]]; then
      printf '%s\n' "$s"
    fi
  done < <(slugs_in specs)
}

# A: any draft.
candidates_a() { slugs_in drafts; }

# The floor holds no .md work at all.
floor_is_empty() {
  [[ $(count "$FLOOR/drafts") -eq 0 ]] &&
  [[ $(count "$FLOOR/specs") -eq 0 ]] &&
  [[ $(count "$FLOOR/plans") -eq 0 ]]
}

main() {
  local pick
  [[ -d "$FLOOR" ]] || { echo "E"; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { echo "R"; exit 0; }

  pick=$(candidates_d | least_struck D); [[ -z "$pick" ]] || { echo "D $pick"; exit 0; }
  pick=$(candidates_c | least_struck C); [[ -z "$pick" ]] || { echo "C $pick"; exit 0; }
  pick=$(candidates_b | least_struck B); [[ -z "$pick" ]] || { echo "B $pick"; exit 0; }
  pick=$(candidates_a | least_struck A); [[ -z "$pick" ]] || { echo "A $pick"; exit 0; }

  # No stage claimed the floor. That is the end of the flow only when nothing
  # is left; anything remaining is an anomaly for the janitor — an orphan plan
  # overview whose spec is gone, or a slug parked at STRIKE_LIMIT that was
  # never moved to done/.
  if floor_is_empty; then echo "E"; else echo "R"; fi
}

main "$@"
