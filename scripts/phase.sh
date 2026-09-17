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
#                     phase:RECOVER        dirty tree, or a floor no stage claims
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
# Pure: reads the floor, state.json and git status, writes nothing. The
# session runs it once per iteration and /spectomat:status runs it on demand.

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

# Slugs state.json tracks at PHASE, alphabetically.
slugs_at() {
  jq -r --arg p "$1" '.slugs // {} | to_entries[] | select(.value.phase == $p) | .key' "$STATE_FILE" 2>/dev/null | sort
}

# Every slug state.json tracks, regardless of phase.
all_slugs() {
  jq -r '.slugs // {} | keys[]' "$STATE_FILE" 2>/dev/null | sort
}

# The one floor path that must exist for a slug parked at PHASE, inside its
# own slug dir.
phase_file() {
  local slug="$1" phase="$2"
  case "$phase" in
    SPECIFY)                  printf '%s\n' "$FLOOR/$slug/draft.md" ;;
    REVIEW-SPEC|PLAN)         printf '%s\n' "$FLOOR/$slug/spec.md" ;;
    IMPLEMENT|REVIEW|ARCHIVE) printf '%s\n' "$FLOOR/$slug/plan.md" ;;
  esac
}

# The safety net: every unfinished slug dir must have a state.json entry, and
# every state.json entry must have its phase-appropriate floor file. Directory
# listings only, never file content. A finished slug dir (done.md or
# blocked.md) is out of the flow and has no entry to match.
check_orphans() {
  local s p
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -n "$(slug_phase "$s")" ]] || return 1
  done < <(slug_active_dirs)

  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    p=$(slug_phase "$s")
    [[ -f "$(phase_file "$s" "$p")" ]] || return 1
  done < <(all_slugs)
  return 0
}

main() {
  local pick
  [[ -d "$FLOOR" ]] || { emit FINISH; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { emit RECOVER; exit 0; }
  check_orphans || { emit RECOVER; exit 0; }

  pick=$(slugs_at ARCHIVE     | least_struck ARCHIVE);     [[ -z "$pick" ]] || { emit ARCHIVE "$pick"; exit 0; }
  pick=$(slugs_at REVIEW      | least_struck REVIEW);      [[ -z "$pick" ]] || { emit REVIEW "$pick"; exit 0; }
  pick=$(slugs_at IMPLEMENT   | least_struck IMPLEMENT);   [[ -z "$pick" ]] || { emit IMPLEMENT "$pick"; exit 0; }
  pick=$(slugs_at PLAN        | least_struck PLAN);        [[ -z "$pick" ]] || { emit PLAN "$pick"; exit 0; }
  pick=$(slugs_at REVIEW-SPEC | least_struck REVIEW-SPEC); [[ -z "$pick" ]] || { emit REVIEW-SPEC "$pick"; exit 0; }
  pick=$(slugs_at SPECIFY     | least_struck SPECIFY);     [[ -z "$pick" ]] || { emit SPECIFY "$pick"; exit 0; }

  if [[ -z "$(all_slugs)" ]]; then emit FINISH; else emit RECOVER; fi
}

main "$@"
