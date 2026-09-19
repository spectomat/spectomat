#!/bin/bash
# Spectomat phase picker — which phase the next iteration must do.
#
#   phase.sh        prints one frontmatter block and exits 0:
#                     ---
#                     phase:<PHASE>
#                     slug:<slug; empty for FINISH, and for a RECOVER on a clean tree>
#                     subagent:spectomat:<agent>   (is <PHASE> lowercased; empty for FINISH)
#                     brief:<PLUGIN_ROOT>/agents/<agent>.md   (empty for FINISH)
#                     plugin_root:<PLUGIN_ROOT>
#                     ---

#                     phase:SPECIFY        draft -> spec
#                     phase:REVIEW-SPEC    spec -> revised spec, ready to plan
#                     phase:PLAN           reviewed spec -> plan
#                     phase:IMPLEMENT      plan -> next task
#                     phase:REVIEW         finished plan -> verdict, or fix tasks
#                     phase:ARCHIVE        reviewed plan -> done.md
#                     phase:RECOVER        dirty tree, with the slug of the iteration that died
#                                          (state.json's `current`), or every unfinished slug
#                                          at the strike limit, with no slug
#                     phase:FINISH         nothing left; the Stop hook ends the flow
#
# Pure: reads state.json and git status, writes nothing, and never looks at the
# floor — state.json is the whole of the flow's state (D27). The session runs it
# once per iteration and /spectomat:status runs it on demand.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

# Print the verdict as a frontmatter block: phase, slug (empty for FINISH and a
# clean-tree RECOVER), and everything the pointer prompt needs to dispatch a
# subagent with no lookup table of its own — the agent name, brief path and
# plugin root are all computable from the phase alone.
#
# FINISH is the exception: the Stop hook ends the flow on that verdict, so
# there is no agent to dispatch and no brief to hand it, and both fields stay
# empty. RECOVER has a real agent, and on a dirty tree a slug too; do not group them.
emit() {
  local phase="$1" slug="${2:-}" agent=""
  if [[ "$phase" != FINISH ]]; then
    agent="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')"
  fi
  cat <<EOF
---
phase:$phase
slug:$slug
subagent:${agent:+spectomat:$agent}
brief:${agent:+$PLUGIN_ROOT/agents/$agent.md}
plugin_root:$PLUGIN_ROOT
---
EOF
}

# Emit PHASE with its least-struck slug and exit, if one is waiting there;
# otherwise return and let the ladder try the next phase.
try_phase() {
  local phase="$1" pick
  pick=$(slugs_at_phase "$phase" | least_struck "$phase")
  [[ -z "$pick" ]] || { emit "$phase" "$pick"; exit 0; }
}

main() {
  local phase
  [[ -f "$STATE_FILE" ]] || { emit FINISH; exit 0; }
  # Dirt is an iteration that died mid-phase, and `current` still names it:
  # the Stop hook records working verdicts only, never a RECOVER.
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { emit RECOVER "$(current_field slug)"; exit 0; }

  for phase in ARCHIVE REVIEW IMPLEMENT PLAN REVIEW-SPEC SPECIFY; do try_phase "$phase"; done

  # Nothing left at a working phase is FINISH. Anything left here is a slug the
  # ladder skipped, which only least_struck does, and only at STRIKE_LIMIT.
  if [[ -z "$(slugs_unfinished)" ]]; then emit FINISH; else emit RECOVER; fi
}

main "$@"
