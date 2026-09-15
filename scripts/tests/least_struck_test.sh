#!/bin/bash
# least_struck — picks the candidate with the fewest strikes at a phase.
#
#   scripts/tests/least_struck_test.sh          tests the scripts next to it
#   scripts/tests/least_struck_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "least_struck"
floor ls1
ls_pick() { ( cd "$FIXTURE" && printf '%s\n' "$@" | least_struck IMPLEMENT ); }
is "single candidate" "$(ls_pick 001-a)" "001-a"
is "no candidates" "$(ls_pick)" ""
is "ties go alphabetically" "$(ls_pick 001-a 002-b)" "001-a"
strike 001-a IMPLEMENT 1
is "fewer strikes wins" "$(ls_pick 001-a 002-b)" "002-b"
strike 002-b IMPLEMENT 1
strike 002-b IMPLEMENT 2
is "fewest strikes wins" "$(ls_pick 001-a 002-b)" "001-a"
strike 001-a IMPLEMENT 2
strike 001-a IMPLEMENT 3
is "a slug at the limit is skipped" "$(ls_pick 001-a 002-b)" "002-b"
strike 002-b IMPLEMENT 3
is "all at the limit yields nothing" "$(ls_pick 001-a 002-b)" ""
is "a slug with a space survives" "$(ls_pick '003-my idea')" "003-my idea"

finish
