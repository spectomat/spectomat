#!/bin/bash
# Spectomat cancel — remove the flow's state file so the Stop hook releases the session.
# The floor under docs/.spectomat/ stays; run.sh resumes from it.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

main() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "No active Spectomat flow."
    exit 0
  fi
  local loop
  loop=$(state_field loop)
  rm "$STATE_FILE"
  echo "Cancelled Spectomat flow (was at loop ${loop:-?}). The floor stays; /spectomat:run resumes from it."
}

main "$@"
