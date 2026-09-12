#!/bin/bash
# Spectomat flow Stop hook.
# While the state file exists, block session exit and feed the pointer back.

set -euo pipefail

HOOK_INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Set by read_state
ITERATION=""
MAX_ITERATIONS=""
STATE_SESSION=""
# Set by require_transcript / read_last_output
TRANSCRIPT_PATH=""
LAST_OUTPUT=""

# --- helpers ---

# End the flow normally: message on stdout, flow disarmed.
finish() { echo "$1"; disarm; exit 0; }

# End the flow on a problem: message on stderr, flow disarmed.
abort() { echo "$1" >&2; disarm; exit 0; }

stop_corrupt() {
  echo "⚠️  Spectomat flow: state corrupted" >&2
  echo "   Files: $STATE_FILE, $POINTER" >&2
  echo "   Problem: $1" >&2
  echo "   The flow is stopping. Run /spectomat:run again to start fresh." >&2
  disarm
  exit 0
}

# --- phases ---

# One jq call for all three fields: this runs on every iteration, and three
# separate state_field calls would spawn three processes for one small file.
# @tsv renders a null or missing value as an empty field, which
# require_own_session and require_sane_state already handle.
read_state() {
  local tsv
  tsv=$(jq -r '[.iteration, .max_iterations, .session_id] | @tsv' "$STATE_FILE" 2>/dev/null) \
    || stop_corrupt "$STATE_FILE is not valid JSON"
  IFS=$'\t' read -r ITERATION MAX_ITERATIONS STATE_SESSION <<< "$tsv"
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

require_sane_state() {
  [[ "$ITERATION" =~ ^[0-9]+$ ]] || stop_corrupt "'iteration' is not a number (got: '$ITERATION')"
  [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || stop_corrupt "'max_iterations' is not a number (got: '$MAX_ITERATIONS')"
}

require_below_max() {
  if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    finish "🛑 Spectomat flow: max iterations ($MAX_ITERATIONS) reached. Run /spectomat:run to resume from the floor."
  fi
}

require_transcript() {
  TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
  [[ -f "$TRANSCRIPT_PATH" ]] || abort "⚠️  Spectomat flow: transcript not found at $TRANSCRIPT_PATH. The flow is stopping."
  grep -q '"role":"assistant"' "$TRANSCRIPT_PATH" || abort "⚠️  Spectomat flow: no assistant messages in transcript. The flow is stopping."
}

# Each content block is its own JSONL line with role=assistant. Take the last
# text block of the last 100 assistant lines; a turn of only tool calls yields
# "" and the flow simply continues.
read_last_output() {
  local last_lines jq_exit
  last_lines=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
  set +e
  LAST_OUTPUT=$(echo "$last_lines" | jq -rs '
    map(.message.content[]? | select(.type == "text") | .text) | last // ""
  ' 2>&1)
  jq_exit=$?
  set -e
  if [[ $jq_exit -ne 0 ]]; then
    abort "⚠️  Spectomat flow: failed to parse transcript ($LAST_OUTPUT). The flow is stopping."
  fi
}

# Finish when the last output carries the exact completion promise.
check_promise() {
  if promised_empty "$LAST_OUTPUT"; then
    finish "✅ Spectomat flow: detected <promise>FACTORY EMPTY</promise>"
  fi
}

# Bump the iteration counter in place and emit the block decision with the prompt.
continue_iteration() {
  local next_iteration prompt_text temp_file system_msg
  next_iteration=$((ITERATION + 1))

  prompt_text=$(cat "$POINTER" 2>/dev/null || true)
  [[ -n "$prompt_text" ]] || stop_corrupt "$POINTER is empty or missing"

  temp_file="${STATE_FILE}.tmp.$$"
  jq --argjson n "$next_iteration" '.iteration = $n' "$STATE_FILE" > "$temp_file" \
    && mv "$temp_file" "$STATE_FILE" \
    || { rm -f "$temp_file"; stop_corrupt "could not write the iteration counter"; }

  system_msg="🔄 Spectomat iteration $next_iteration | Ends when scripts/phase.sh answers E, or at the cap ($MAX_ITERATIONS)"

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
  require_sane_state
  require_below_max
  require_transcript
  read_last_output
  check_promise
  continue_iteration
  exit 0
}

main "$@"
