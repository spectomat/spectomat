#!/bin/bash
# pointer_prompt — the pointer text the Stop hook feeds back, in utils.sh.
#
#   tests/pointer_prompt_test.sh              tests ../scripts
#   tests/pointer_prompt_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "pointer_prompt"

block=$'---\nphase:SPECIFY\nslug:001-a\nsubagent:spectomat:specify\nbrief:'"$PLUGIN_ROOT"$'/agents/specify.md\nplugin_root:'"$PLUGIN_ROOT"$'\n---'
out="$(pointer_prompt "$block")"
is "it opens with the pointer heading" "$(printf '%s\n' "$out" | head -1)" "# Spectomat next iteration pointer"
is "no unresolved placeholder is left" "$(printf '%s\n' "$out" | grep -c '{{')" "0"
is "it embeds the picker's block verbatim" "$(printf '%s\n' "$out" | grep -c "^phase:SPECIFY$")" "1"
is "it does not tell the agent to run phase.sh itself" \
  "$(printf '%s\n' "$out" | grep -c "bash .*phase.sh")" "0"

finish
