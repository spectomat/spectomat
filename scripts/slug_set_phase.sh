#!/bin/bash
# Spectomat slug_set_phase — advance one slug to a new phase with no task
# counters. A thin CLI over utils.sh's slug_set_phase, for a brief's `!`
# block or an agent's own Bash calls:
#
#   scripts/slug_set_phase.sh <slug> <phase>
#
# Never call this for PLAN -> IMPLEMENT or a task close inside IMPLEMENT:
# those carry the task ledger and belong to scripts/tasks.sh.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

main() {
  local slug="${1:-}" phase="${2:-}"
  [[ -n "$slug" && -n "$phase" ]] || die "usage: slug_set_phase.sh <slug> <phase>"
  [[ -f "$STATE_FILE" ]] || die "no $STATE_FILE — is a flow armed?"
  slug_set_phase "$slug" "$phase"
  echo "$slug -> $phase"
}

main "$@"
