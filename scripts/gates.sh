#!/bin/bash
# Spectomat gate detection.
#
#   source gates.sh; detect_gates   sets GATES to the gate lines for this repo
#   gates.sh                        prints those lines for the repo it is run in

# True when package.json defines the named script.
has_script() { [[ -f package.json ]] && grep -qE "\"$1\"[[:space:]]*:" package.json; }

# Compile GATES: `npm run gates` alone when that script exists, else the
# typecheck, lint and test scripts found, one per line.
detect_gates() {
  local s cmd
  GATES=""
  if has_script gates; then
    GATES="npm run gates"
    return 0
  fi
  for s in typecheck lint test; do
    has_script "$s" || continue
    if [[ "$s" == "test" ]]; then cmd="npm test"; else cmd="npm run $s"; fi
    GATES+="${GATES:+$'\n'}$cmd"
  done
}

# What .spectomat/gates.sh gets when nothing was detected: commented examples
# and an honest no-op. It must exit 0 — a repo with no gates yet has not
# failed anything (D22).
GATES_NONE='# No gates detected. Add this repo'"'"'s gates below, one per line:
#   npm run typecheck
#   npm run lint
#   npm test

echo "ok: no gates yet — add them above"'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
  cd_root
  detect_gates
  printf '%s\n' "${GATES:-$GATES_NONE}"
fi
