#!/bin/bash
# gate_block — parses the Verification Gates fence out of contract.md.
#
#   tests/gate_block_test.sh              tests ../scripts
#   tests/gate_block_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "gate_block"
gb() { is "$1" "$(cd "$FIXTURE" && gate_block | tr '\n' '|')" "$2"; }

floor gb1; gates_block 'echo one' 'echo two'
gb "two gate lines"            'echo one|echo two|'
floor gb2; gates_block '# a comment' '' '   ' 'echo one'
gb "comments and blanks drop"  'echo one|'
floor gb3
gb "no contract yields nothing" ''
floor gb4; gates_block 'echo one'
gb "a later fence is ignored"  'echo one|'

finish
