#!/bin/bash
# Spectomat status — loop state, factory floor counts, plan progress, log tail.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/print.sh"
cd_root

main() {
  print_loop
  if [[ ! -d "$FLOOR" ]]; then
    echo "No $FLOOR/ in $ROOT - /spectomat:run has not been started here."
    exit 0
  fi
  print_floor
  print_plans
  print_blocked
  print_log_tail
  print_commits
}

main "$@"
