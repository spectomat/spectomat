#!/bin/bash
# run_gates — runs .spectomat/gates.sh and reports its exit code.
#
#   tests/run_gates_test.sh              tests ../scripts
#   tests/run_gates_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "run_gates"
floor rg1; gates_block 'true' 'true'
( cd "$FIXTURE" && run_gates ); is "all gates pass" "$?" "0"
floor rg2; gates_block 'false' 'touch ran'
( cd "$FIXTURE" && run_gates ); is "a failing gate fails" "$?" "1"
is "set -e stops at the first failure" "$([[ -e "$FIXTURE/ran" ]] && echo yes || echo no)" "no"
( cd "$FIXTURE" && run_gates 2>/dev/null; printf '%s' "$GATE_FAILED" ) > "$TMP/gf"
is "it names the gate script" "$(cat "$TMP/gf")" ".spectomat/gates.sh"
floor rg3
( cd "$FIXTURE" && run_gates ); is "no gates.sh passes" "$?" "0"
# gates.sh cds to the repo root itself, so a phase may run it from anywhere.
floor rg4; gates_block 'test -d .spectomat'
mkdir -p "$FIXTURE/sub"
( cd "$FIXTURE/sub" && GATES_SH="$FIXTURE/.spectomat/gates.sh" run_gates ); is "it runs from a subdirectory" "$?" "0"

finish
