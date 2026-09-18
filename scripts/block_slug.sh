#!/bin/bash
# Spectomat block_slug — take one slug out of the flow at BLOCKED with a
# reason, for a brief's `!` block or an agent's own Bash calls:
#
#   scripts/block_slug.sh <slug> <reason>
#
# Only marks the state; it does not write blocked.md or commit it — the
# caller does that itself first, per the contract.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

main() {
  local slug="${1:-}"
  shift 2>/dev/null || true
  local reason="$*"
  [[ -n "$slug" && -n "$reason" ]] || die "usage: block_slug.sh <slug> <reason>"
  [[ -f "$STATE_FILE" ]] || die "no $STATE_FILE — is a flow armed?"
  state_apply '.slugs[$s].phase = "BLOCKED" | .slugs[$s].reason = $r | .slugs[$s].finished_at = $t' \
    --arg s "$slug" --arg r "$reason" --arg t "$(date -u +%FT%RZ)"
  echo "$slug -> BLOCKED ($reason)"
}

main "$@"
