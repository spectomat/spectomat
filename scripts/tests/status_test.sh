#!/bin/bash
# status.sh — predicts the next verdict and lists floor state for the operator.
#
#   scripts/tests/status_test.sh          tests the scripts next to it
#   scripts/tests/status_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "status"
floor st; spec 001-a; plan 001-a 2 1
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "status prints the next section" "$(printf '%s\n' "$st_out" | grep -c '^--- next ---$')" "1"
is "status predicts the verdict"    "$(printf '%s\n' "$st_out" | grep -c '^IMPLEMENT 001-a$')" "1"
floor st2
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "an empty floor predicts FINISH" "$(printf '%s\n' "$st_out" | grep -c '^FINISH$')" "1"

# A slug at SPECIFY/REVIEW-SPEC/PLAN/ARCHIVE must still show in the plans
# section, not just IMPLEMENT/REVIEW, or it silently vanishes from status.
floor st3; draft 002-b; spec 001-a yes
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "status lists a PLAN-phase slug" "$(printf '%s\n' "$st_out" | grep -c 'phase PLAN')" "1"

finish
