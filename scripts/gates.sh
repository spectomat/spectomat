#!/bin/bash
# Spectomat verification gates.
#
#   gates.sh          run every detected gate from the repo root; stop at the first failure
#   source gates.sh   use detect_gates / run_gates from another script
#
# A `gates` script in package.json is the single gate. Without one, every
# typecheck, test, lint and build script is a gate, run in that order.
# Exit 0 only when every gate exits 0.

# True when package.json defines the named script.
has_script() { [[ -f package.json ]] && grep -qE "\"$1\"[[:space:]]*:" package.json; }

# Fill GATES with one command per line: `npm run gates` alone when that script
# exists, else every typecheck, test, lint and build script found.
detect_gates() {
  local s
  GATES=""
  if has_script gates; then
    GATES="npm run gates"
    return 0
  fi
  for s in typecheck test lint build; do
    if has_script "$s"; then
      if [[ "$s" == "test" ]]; then GATES+="npm test"$'\n'; else GATES+="npm run $s"$'\n'; fi
    fi
  done
  GATES="${GATES%$'\n'}"
}

# Run every detected gate in order, printing each command; stop at the first failure.
run_gates() {
  local cmd status n=0
  detect_gates
  if [[ -z "$GATES" ]]; then
    echo "gates: none detected (no gates, typecheck, test, lint or build script in package.json)"
    return 0
  fi
  while IFS= read -r cmd; do
    echo "--- gate: $cmd ---"
    $cmd && status=0 || status=$?
    if [[ $status -ne 0 ]]; then
      echo "❌ gate failed: $cmd (exit $status)"
      return "$status"
    fi
    n=$((n + 1))
  done <<< "$GATES"
  echo "✅ gates: $n/$n passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
  cd_root
  run_gates
fi
