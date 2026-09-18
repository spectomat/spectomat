#!/bin/bash
# command-status.sh — predicts the next verdict and lists floor state for the operator.
#
#   tests/status_test.sh              tests ../scripts
#   tests/status_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "status"
floor st; spec 001-a; plan 001-a 2 1
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/command-status.sh" 2>/dev/null)
is "status prints the next section" "$(printf '%s\n' "$st_out" | grep -c '^--- next ---$')" "1"
is "status predicts the verdict"    "$(printf '%s\n' "$st_out" | grep -c '^phase:IMPLEMENT$')" "1"
is "status predicts the slug"       "$(printf '%s\n' "$st_out" | grep -c '^slug:001-a$')" "1"
floor st2
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/command-status.sh" 2>/dev/null)
is "an empty floor predicts FINISH" "$(printf '%s\n' "$st_out" | grep -c '^phase:FINISH$')" "1"

# A slug at SPECIFY/REVIEW-SPEC/PLAN/ARCHIVE must still show in the plans
# section, not just IMPLEMENT/REVIEW, or it silently vanishes from status.
floor st3; draft 002-b; spec 001-a yes
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/command-status.sh" 2>/dev/null)
is "status lists a PLAN-phase slug" "$(printf '%s\n' "$st_out" | grep -c 'phase PLAN')" "1"

# A blocked slug that nothing reports is a silently dropped idea, so the
# blocked section names the file holding the reason.
floor st4; draft 001-a; archived 002-b blocked; archived 003-c
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/command-status.sh" 2>/dev/null)
is "status opens a blocked section"   "$(printf '%s\n' "$st_out" | grep -c '^--- blocked ---$')" "1"
is "status names the blocked slug"    "$(printf '%s\n' "$st_out" | grep -c '^.spectomat/002-b/blocked.md$')" "1"
is "status leaves a done slug out of blocked" "$(printf '%s\n' "$st_out" | grep -c '003-c/blocked.md')" "0"
is "the floor line counts the finished slugs" "$(printf '%s\n' "$st_out" | grep -c 'done: 1   blocked: 1')" "1"
is "the floor line counts the active slug"    "$(printf '%s\n' "$st_out" | grep -c 'active: 1')" "1"

finish
