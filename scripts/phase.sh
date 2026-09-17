#!/bin/bash
# Spectomat phase picker — which phase the next iteration must do.
#
#   phase.sh        prints one frontmatter block and exits 0:
#                     phase:SPECIFY        draft -> spec
#                     phase:REVIEW-SPEC    spec -> revised spec, ready to plan
#                     phase:PLAN           reviewed spec -> plan
#                     phase:IMPLEMENT      plan -> next task
#                     phase:REVIEW         finished plan -> verdict, or fix tasks
#                     phase:ARCHIVE        reviewed plan -> done.md
#                     phase:RECOVER        dirty tree, or every unfinished slug is at the strike limit
#                     phase:FINISH         nothing left; the Stop hook ends the flow
#
#                   The block also names the subagent to dispatch, the brief
#                   file to hand it, and the plugin root, so the pointer prompt
#                   the Stop hook feeds back (pointer_prompt in utils.sh) needs
#                   no lookup table of its own:
#
#                     ---
#                     phase:<PHASE>
#                     slug:<slug, empty for RECOVER and FINISH>
#                     subagent:spectomat:<agent>   (empty for FINISH)
#                     brief:<PLUGIN_ROOT>/agents/<agent>.md   (empty for FINISH)
#                     plugin_root:<PLUGIN_ROOT>
#                     ---
#
#                   <agent> is <PHASE> lowercased, e.g. REVIEW-SPEC -> review-spec.
#
# Pure: reads state.json and git status, writes nothing, and never looks at the
# floor — state.json is the whole of the flow's state (D27). The session runs it
# once per iteration and /spectomat:status runs it on demand.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

# Print the verdict as a frontmatter block: phase, slug (empty for RECOVER and
# FINISH), and everything the pointer prompt needs to dispatch a subagent with
# no lookup table of its own — the agent name, brief path and plugin root are
# all computable from the phase alone.
#
# FINISH is the exception: the Stop hook ends the flow on that verdict, so
# there is no agent to dispatch and no brief to hand it, and both fields stay
# empty. RECOVER has an empty slug but a real agent; do not group them.
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

main() {
  local pick
  [[ -f "$STATE_FILE" ]] || { emit FINISH; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { emit RECOVER; exit 0; }

  pick=$(slugs_at_phase ARCHIVE     | least_struck ARCHIVE);     [[ -z "$pick" ]] || { emit ARCHIVE "$pick"; exit 0; }
  pick=$(slugs_at_phase REVIEW      | least_struck REVIEW);      [[ -z "$pick" ]] || { emit REVIEW "$pick"; exit 0; }
  pick=$(slugs_at_phase IMPLEMENT   | least_struck IMPLEMENT);   [[ -z "$pick" ]] || { emit IMPLEMENT "$pick"; exit 0; }
  pick=$(slugs_at_phase PLAN        | least_struck PLAN);        [[ -z "$pick" ]] || { emit PLAN "$pick"; exit 0; }
  pick=$(slugs_at_phase REVIEW-SPEC | least_struck REVIEW-SPEC); [[ -z "$pick" ]] || { emit REVIEW-SPEC "$pick"; exit 0; }
  pick=$(slugs_at_phase SPECIFY     | least_struck SPECIFY);     [[ -z "$pick" ]] || { emit SPECIFY "$pick"; exit 0; }

  # Nothing left at a working phase is FINISH. Anything left here is a slug the
  # ladder skipped, which only least_struck does, and only at STRIKE_LIMIT.
  if [[ -z "$(slugs_unfinished)" ]]; then emit FINISH; else emit RECOVER; fi
}

main "$@"
