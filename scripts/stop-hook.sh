#!/bin/bash
# Spectomat loop Stop hook.
# While the state file exists, block session exit and feed the same prompt back.

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

# End the loop normally: message on stdout, state removed.
finish() { echo "$1"; rm "$STATE_FILE"; exit 0; }

# End the loop on a problem: message on stderr, state removed.
abort() { echo "$1" >&2; rm "$STATE_FILE"; exit 0; }

stop_corrupt() {
  echo "⚠️  Spectomat loop: state file corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: $1" >&2
  echo "   The loop is stopping. Run /spectomat:run again to start fresh." >&2
  rm "$STATE_FILE"
  exit 0
}

# --- phases ---

read_state() {
  ITERATION=$(state_field iteration)
  MAX_ITERATIONS=$(state_field max_iterations)
  STATE_SESSION=$(state_field session_id)
}

# Session isolation: the Stop hook fires in every session of this project.
# Only the session that started the loop may continue it.
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
    finish "🛑 Spectomat loop: max iterations ($MAX_ITERATIONS) reached. Run /spectomat:run to resume from the floor."
  fi
}

require_transcript() {
  TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
  [[ -f "$TRANSCRIPT_PATH" ]] || abort "⚠️  Spectomat loop: transcript not found at $TRANSCRIPT_PATH. The loop is stopping."
  grep -q '"role":"assistant"' "$TRANSCRIPT_PATH" || abort "⚠️  Spectomat loop: no assistant messages in transcript. The loop is stopping."
}

# Each content block is its own JSONL line with role=assistant. Take the last
# text block of the last 100 assistant lines; a turn of only tool calls yields
# "" and the loop simply continues.
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
    abort "⚠️  Spectomat loop: failed to parse transcript ($LAST_OUTPUT). The loop is stopping."
  fi
}

# Finish when the last output carries the exact completion promise.
check_promise() {
  local promise_text
  # First <promise> tag, whitespace normalised. Literal compare, not glob.
  promise_text=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ -n "$promise_text" ]] && [[ "$promise_text" = "FACTORY EMPTY" ]]; then
    finish "✅ Spectomat loop: detected <promise>FACTORY EMPTY</promise>"
  fi
}

# Bump the iteration counter in place and emit the block decision with the prompt.
continue_loop() {
  local next_iteration prompt_text temp_file system_msg
  next_iteration=$((ITERATION + 1))

  # Prompt is everything after the second --- line.
  prompt_text=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
  [[ -n "$prompt_text" ]] || stop_corrupt "no prompt text found"

  temp_file="${STATE_FILE}.tmp.$$"
  sed "s/^iteration: .*/iteration: $next_iteration/" "$STATE_FILE" > "$temp_file"
  mv "$temp_file" "$STATE_FILE"

  system_msg="🔄 Spectomat iteration $next_iteration | To stop: output <promise>FACTORY EMPTY</promise> (ONLY when the statement is TRUE - do not lie to exit!)"

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
  continue_loop
  exit 0
}

main "$@"
