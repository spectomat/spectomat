#!/bin/bash
# strike_count — reads a slug's per-phase strike count from state.json.
#
#   scripts/tests/strike_count_test.sh          tests the scripts next to it
#   scripts/tests/strike_count_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "strike_count"
floor sc1
is "no entry is zero" "$(cd "$FIXTURE" && strike_count IMPLEMENT 001-a)" "0"
strike 001-a IMPLEMENT 1
is "one strike counts" "$(cd "$FIXTURE" && strike_count IMPLEMENT 001-a)" "1"
strike 001-a IMPLEMENT 2
is "two strikes count" "$(cd "$FIXTURE" && strike_count IMPLEMENT 001-a)" "2"
is "another phase is separate" "$(cd "$FIXTURE" && strike_count PLAN 001-a)" "0"
is "another slug is separate" "$(cd "$FIXTURE" && strike_count IMPLEMENT 002-b)" "0"

floor sc2
strike '001-my idea (draft)' IMPLEMENT 1
is "a slug with a space counts" "$(cd "$FIXTURE" && strike_count IMPLEMENT '001-my idea (draft)')" "1"

finish
