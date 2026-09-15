#!/bin/bash
# pointer_prompt — the pointer text the Stop hook feeds back, in utils.sh.
#
#   tests/pointer_prompt_test.sh              tests ../scripts
#   tests/pointer_prompt_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "pointer_prompt"

out="$(pointer_prompt)"
is "it opens with the pointer heading" "$(printf '%s\n' "$out" | head -1)" "# Spectomat pointer"
is "PLUGIN_ROOT is resolved, not a placeholder" "$(printf '%s\n' "$out" | grep -c '{{')" "0"
is "it names the phase.sh command under PLUGIN_ROOT" \
  "$(printf '%s\n' "$out" | grep -c "bash $PLUGIN_ROOT/scripts/phase.sh")" "1"

finish
