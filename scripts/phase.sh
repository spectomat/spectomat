#!/bin/bash
# Spectomat phase picker — which phase the next iteration must do.
#
#   phase.sh        prints one line and exits 0:
#                     "SPECIFY <slug>"    draft -> spec
#                     "PLAN <slug>"       spec -> plan
#                     "IMPLEMENT <slug>"  plan -> next task
#                     "ARCHIVE <slug>"    plan -> done
#                     "RECOVER"           dirty tree, or a floor no stage claims
#                     "FINISH"            nothing left; the flow may end
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

# ARCHIVE: a plan whose task files exist and are all ticked. The task-file count
# is what stops an empty plan directory from satisfying "all steps ticked" for
# free and archiving work that was never built.
candidates_archive() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ $(task_count "$s") -ge 1 ]] || continue
    has_open_step "$s" && continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# IMPLEMENT: a plan with an unchecked step.
candidates_implement() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    has_open_step "$s" || continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# PLAN: a spec with no plan overview, or an overview with no task files — a
# PLAN phase that died before writing them. Without the second clause that plan
# matches no stage and is unreachable for the life of the floor.
candidates_plan() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if [[ ! -f "$FLOOR/plans/$s.md" ]] || [[ $(task_count "$s") -eq 0 ]]; then
      printf '%s\n' "$s"
    fi
  done < <(slugs_in specs)
}

# SPECIFY: any draft.
candidates_specify() { slugs_in drafts; }

# The floor holds no .md work at all.
floor_is_empty() {
  [[ $(count "$FLOOR/drafts") -eq 0 ]] &&
  [[ $(count "$FLOOR/specs") -eq 0 ]] &&
  [[ $(count "$FLOOR/plans") -eq 0 ]]
}

main() {
  local pick
  [[ -d "$FLOOR" ]] || { echo "FINISH"; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { echo "RECOVER"; exit 0; }

  pick=$(candidates_archive   | least_struck ARCHIVE);   [[ -z "$pick" ]] || { echo "ARCHIVE $pick"; exit 0; }
  pick=$(candidates_implement | least_struck IMPLEMENT); [[ -z "$pick" ]] || { echo "IMPLEMENT $pick"; exit 0; }
  pick=$(candidates_plan      | least_struck PLAN);      [[ -z "$pick" ]] || { echo "PLAN $pick"; exit 0; }
  pick=$(candidates_specify   | least_struck SPECIFY);   [[ -z "$pick" ]] || { echo "SPECIFY $pick"; exit 0; }

  # No stage claimed the floor. That is the end of the flow only when nothing
  # is left; anything remaining is an anomaly for the janitor — an orphan plan
  # overview whose spec is gone, or a slug parked at STRIKE_LIMIT that was
  # never moved to done/.
  if floor_is_empty; then echo "FINISH"; else echo "RECOVER"; fi
}

main "$@"
