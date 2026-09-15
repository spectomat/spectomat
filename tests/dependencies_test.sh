#!/bin/bash
# dependencies — jq is the only non-base dependency the scripts may take.
#
#   tests/dependencies_test.sh              tests ../scripts
#   tests/dependencies_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "dependencies"
# This file and the rest of tests/ name the forbidden command, so
# they have to leave themselves out of their own scan.
hits=$(grep -ln 'perl' "$SCRIPTS"/*.sh "$(dirname "${BASH_SOURCE[0]}")"/*.sh 2>/dev/null \
        | grep -v '/tests/dependencies_test\.sh$' | tr '\n' ' ')
is "scripts invoke no perl" "${hits% }" ""

finish
