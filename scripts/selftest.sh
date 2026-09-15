#!/bin/bash
# Spectomat self-test — runs every scripts/tests/*_test.sh file and reports
# the combined tally.
#
#   scripts/selftest.sh          tests the scripts next to it
#   scripts/selftest.sh DIR      tests the scripts in DIR
#
# Each file under scripts/tests/ is independently runnable and owns its own
# fixtures, so a single section can be driven alone, e.g.:
#
#   bash scripts/tests/phase_test.sh
#   bash scripts/tests/phase_test.sh DIR
#
# No dependencies and no network. Every fixture is a real git repo, because
# `git status --porcelain` is normative input.

set -uo pipefail

SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/tests" && pwd)"

TOTAL_PASS=0; TOTAL_FAIL=0; FILES_FAILED=0

for f in "$TESTS_DIR"/*_test.sh; do
  out=$(bash "$f" "$SCRIPTS" 2>&1); rc=$?
  printf '%s\n' "$out" | sed '$d'   # every line but the file's own summary
  summary=$(printf '%s\n' "$out" | tail -1)
  p=$(printf '%s' "$summary" | sed -n 's/^\([0-9]*\) passed, .*/\1/p')
  fl=$(printf '%s' "$summary" | sed -n 's/.*, \([0-9]*\) failed$/\1/p')
  TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${fl:-0}))
  [[ $rc -eq 0 ]] || FILES_FAILED=$((FILES_FAILED + 1))
done

printf '\n%d passed, %d failed\n' "$TOTAL_PASS" "$TOTAL_FAIL"
[[ $FILES_FAILED -eq 0 && $TOTAL_FAIL -eq 0 ]]
