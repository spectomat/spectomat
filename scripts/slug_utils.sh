#!/bin/bash
# Spectomat slug-set helpers — queries over every slug in state.json at once,
# as opposed to utils.sh's slug_* helpers, each of which acts on one slug.
# Sourced by utils.sh; do not source this file directly or run it.

# slugs_at_phase PHASE — slugs at PHASE, alphabetically. The picker's candidate
# sets, the finished counts and the blocked list are all this one shape.
#
# The file check comes first and the jq failure is swallowed: command-run.sh's
# report_floor calls this before arm_flow has written state.json, and a script
# running set -e with pipefail would die on the failing jq inside the pipeline.
slugs_at_phase() {
  [[ -f "$STATE_FILE" ]] || return 0
  jq -r --arg p "$1" '.slugs // {} | to_entries[] | select(.value.phase == $p) | .key' \
    "$STATE_FILE" 2>/dev/null | sort || true
}

# The slugs still in the flow: every one whose phase is not terminal. Empty is
# what FINISH means, and it is not the same as "no slugs" — a finished flow
# keeps every slug it ever had, at DONE or BLOCKED.
slugs_unfinished() {
  [[ -f "$STATE_FILE" ]] || return 0
  jq -r '.slugs // {} | to_entries[]
    | select(.value.phase != "DONE" and .value.phase != "BLOCKED") | .key' \
    "$STATE_FILE" 2>/dev/null | sort || true
}
