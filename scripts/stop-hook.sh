#!/bin/bash
# Spectomat flow Stop hook.
# While the state file exists, block session exit and feed the pointer back.
# The flow ends when scripts/phase.sh answers FINISH, or at the iteration cap;
# no transcript is read and no promise string is trusted.

set -euo pipefail

HOOK_INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Set by read_state
ITERATION=""
MAX_ITERATIONS=""
STATE_SESSION=""
STATE_ACTIVE=""
STATE_BROKEN=""   # why the state file could not be parsed, when it could not

# --- helpers ---

# End the flow normally: the message reaches the operator as systemMessage,
# the flow is disarmed. A Stop hook that exits 0 with plain stdout surfaces
# only in transcript mode, and since FINISH no longer dispatches an agent
# there is no assistant message left to carry the ending. No "decision" key,
# so the stop itself proceeds.
finish() { jq -n --arg msg "$1" '{"systemMessage": $msg}'; disarm; exit 0; }

# End the flow on a problem: message on stderr, flow disarmed.
abort() { echo "$1" >&2; disarm; exit 0; }

stop_corrupt() {
  echo "⚠️  Spectomat flow: state corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: $1" >&2
  echo "   The flow is stopping. Run /spectomat:run again to start fresh." >&2
  disarm
  exit 0
}

# The picker's verdict for the floor as it stands now. phase.sh cd_root's
# itself, so this is safe from any cwd, and it mutates nothing.
ask_picker() {
  bash "$PLUGIN_ROOT/scripts/phase.sh" 2>/dev/null | sed -n 's/^phase://p'
}

# The lines the flow ends on, at most four. Every finished slug keeps its
# state.json entry at DONE or BLOCKED, so the counts are one jq call each and
# no marker file is read.
closing_report() {
  local shipped blocked names
  shipped=$(slugs_at_phase DONE | wc -l | tr -d ' ')
  blocked=$(slugs_at_phase BLOCKED | wc -l | tr -d ' ')
  printf '✅ Spectomat flow complete: every slug is finished and the tree is clean.\n'
  printf '   Shipped %s · blocked %s · %s iterations.\n' "$shipped" "$blocked" "$ITERATION"
  if [[ "$blocked" -gt 0 ]]; then
    names=$(slugs_at_phase BLOCKED | tr '\n' ' ')
    printf '   Blocked after %s strikes: %s\n' "$STRIKE_LIMIT" "${names% }"
    printf '   Reasons are in %s/log.md; /spectomat:status lists them.\n' "$FLOOR"
  fi
}

# --- phases ---

# One jq call for all three fields: this runs on every iteration, and three
# separate state_field calls would spawn three processes for one small file.
# @tsv renders a null or missing value as an empty field, which
# require_own_session and require_sane_state already handle.
#
# A parse failure is recorded rather than acted on. This runs before the session
# guard, and disarming here would let any session in the project delete a flow
# it does not own - see require_readable_state.
read_state() {
  local tsv
  tsv=$(jq -r '[.iteration, .max_iterations, .session_id, (.active // false)] | @tsv' "$STATE_FILE" 2>/dev/null) \
    || { STATE_BROKEN="not valid JSON"; tsv=""; }
  IFS=$'\t' read -r ITERATION MAX_ITERATIONS STATE_SESSION STATE_ACTIVE <<< "$tsv"
}

# Session isolation: the Stop hook fires in every session of this project.
# Only the session that started the flow may continue it.
require_own_session() {
  local hook_session
  hook_session=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
  if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$hook_session" ]]; then
    exit 0
  fi
}

# An unparsable state file names no owner, so this session cannot prove the flow
# is its own. Report and leave both files in place: ending it is the operator's
# call, via /spectomat:cancel.
require_readable_state() {
  [[ -z "$STATE_BROKEN" ]] || {
    echo "⚠️  Spectomat flow: $STATE_FILE is $STATE_BROKEN." >&2
    echo "   The flow is stopping, and its files are kept because the session that armed it" >&2
    echo "   cannot be identified. Run /spectomat:cancel, then /spectomat:run to start fresh." >&2
    exit 0
  }
}

require_sane_state() {
  [[ "$ITERATION" =~ ^[0-9]+$ ]] || stop_corrupt "'iteration' is not a number (got: '$ITERATION')"
  [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || stop_corrupt "'max_iterations' is not a number (got: '$MAX_ITERATIONS')"
}

require_below_max() {
  if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    finish "🛑 Spectomat flow: max iterations ($MAX_ITERATIONS) reached. Run /spectomat:run to resume from the floor."
  fi
}

# Bump the iteration counter in place and emit the block decision with the prompt.
continue_iteration() {
  local next_iteration prompt_text temp_file system_msg
  next_iteration=$((ITERATION + 1))

  prompt_text=$(pointer_prompt)

  temp_file="${STATE_FILE}.tmp.$$"
  jq --argjson n "$next_iteration" '.iteration = $n' "$STATE_FILE" > "$temp_file" \
    && mv "$temp_file" "$STATE_FILE" \
    || { rm -f "$temp_file"; stop_corrupt "could not write the iteration counter"; }

  system_msg="🔄 Spectomat iteration $next_iteration | Ends when scripts/phase.sh answers FINISH, or at the cap ($MAX_ITERATIONS)"

  jq -n \
    --arg prompt "$prompt_text" \
    --arg msg "$system_msg" \
    '{
      "decision": "block",
      "reason": $prompt,
      "systemMessage": $msg
    }'
}

main() {
  [[ -f "$STATE_FILE" ]] || exit 0
  read_state
  require_own_session
  require_readable_state
  require_sane_state
  [[ "$STATE_ACTIVE" == "true" ]] || exit 0
  require_below_max
  [[ "$(ask_picker)" != FINISH ]] || finish "$(closing_report)"
  continue_iteration
  exit 0
}

main "$@"
