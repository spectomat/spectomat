#!/bin/bash
# Spectomat cancel — disarm the flow so the Stop hook releases the session.
# The floor under .spectomat/ stays; `/spectomat:run` resumes from it.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

main() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "No active Spectomat flow."
    exit 0
  fi
  local iteration
  iteration=$(state_field iteration)
  disarm
  echo "Cancelled Spectomat flow (was at iteration ${iteration:-?}). The floor stays; /spectomat:run resumes from it."
}

main "$@"
