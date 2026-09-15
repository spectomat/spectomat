#!/bin/bash
# Spectomat phase picker — which phase the next iteration must do.
#
#   phase.sh        prints one line and exits 0:
#                     "SPECIFY <slug>"    draft -> spec
#                     "REVIEW-SPEC <slug>" spec -> revised spec, ready to plan
#                     "PLAN <slug>"       reviewed spec -> plan
#                     "IMPLEMENT <slug>"  plan -> next task
#                     "REVIEW <slug>"     finished plan -> verdict, or fix tasks
#                     "ARCHIVE <slug>"    reviewed plan -> done
#                     "RECOVER"           dirty tree, or a floor no stage claims
#                     "FINISH"            nothing left; the flow may end
#
# Pure: reads the floor, state.json and git status, writes nothing. The
# session runs it once per iteration and /spectomat:status runs it on demand.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

# Slugs of the .md files directly inside a floor directory, alphabetically.
slugs_in() {
  local f
  for f in "$FLOOR/$1"/*.md; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "$(basename "$f" .md)"
  done
}

# Slugs state.json tracks at PHASE, alphabetically.
slugs_at() {
  jq -r --arg p "$1" '.slugs // {} | to_entries[] | select(.value.phase == $p) | .key' "$STATE_FILE" 2>/dev/null | sort
}

# Every slug state.json tracks, regardless of phase.
all_slugs() {
  jq -r '.slugs // {} | keys[]' "$STATE_FILE" 2>/dev/null | sort
}

# The one floor path that must exist for a slug parked at PHASE.
phase_file() {
  local slug="$1" phase="$2"
  case "$phase" in
    SPECIFY)                  printf '%s\n' "$FLOOR/drafts/$slug.md" ;;
    REVIEW-SPEC|PLAN)         printf '%s\n' "$FLOOR/specs/$slug.md" ;;
    IMPLEMENT|REVIEW|ARCHIVE) printf '%s\n' "$FLOOR/plans/$slug.md" ;;
  esac
}

# The safety net: every floor .md must have a state.json entry, and every
# state.json entry must have its phase-appropriate floor file. Directory
# listings only, never file content.
check_orphans() {
  local s p
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -n "$(slug_phase "$s")" ]] || return 1
  done < <(slugs_in drafts; slugs_in specs; slugs_in plans)

  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    p=$(slug_phase "$s")
    [[ -f "$(phase_file "$s" "$p")" ]] || return 1
  done < <(all_slugs)
  return 0
}

main() {
  local pick
  [[ -d "$FLOOR" ]] || { echo "FINISH"; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { echo "RECOVER"; exit 0; }
  check_orphans || { echo "RECOVER"; exit 0; }

  pick=$(slugs_at ARCHIVE     | least_struck ARCHIVE);     [[ -z "$pick" ]] || { echo "ARCHIVE $pick"; exit 0; }
  pick=$(slugs_at REVIEW      | least_struck REVIEW);      [[ -z "$pick" ]] || { echo "REVIEW $pick"; exit 0; }
  pick=$(slugs_at IMPLEMENT   | least_struck IMPLEMENT);   [[ -z "$pick" ]] || { echo "IMPLEMENT $pick"; exit 0; }
  pick=$(slugs_at PLAN        | least_struck PLAN);        [[ -z "$pick" ]] || { echo "PLAN $pick"; exit 0; }
  pick=$(slugs_at REVIEW-SPEC | least_struck REVIEW-SPEC); [[ -z "$pick" ]] || { echo "REVIEW-SPEC $pick"; exit 0; }
  pick=$(slugs_at SPECIFY     | least_struck SPECIFY);     [[ -z "$pick" ]] || { echo "SPECIFY $pick"; exit 0; }

  if [[ -z "$(all_slugs)" ]]; then echo "FINISH"; else echo "RECOVER"; fi
}

main "$@"
