#!/bin/bash
# Spectomat verification gates.
#
#   source gates.sh; detect_gates   sets GATES to one command that runs every gate
#   gates.sh                        prints that command for the repo it is run in
#
# A `gates` script in package.json is the single gate. Without one, every
# typecheck, test, lint and build script is a gate, in that order. GATES chains
# them with && so the command stops at the first failure and exits 0 only when
# every gate does. Empty when package.json defines none of them.

# True when package.json defines the named script.
has_script() { [[ -f package.json ]] && grep -qE "\"$1\"[[:space:]]*:" package.json; }

# Compile GATES: `npm run gates` alone when that script exists, else the
# typecheck, test, lint and build scripts found, joined with &&.
detect_gates() {
  local s cmd
  GATES=""
  if has_script gates; then
    GATES="npm run gates"
    return 0
  fi
  for s in typecheck test lint build; do
    has_script "$s" || continue
    if [[ "$s" == "test" ]]; then cmd="npm test"; else cmd="npm run $s"; fi
    GATES+="${GATES:+ && }$cmd"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
  cd_root
  detect_gates
  echo "${GATES:-# ❌ no gates: package.json defines no gates, typecheck, test, lint or build script}"
fi
