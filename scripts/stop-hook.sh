#!/bin/bash
# Spectomat flow Stop hook.
# While the state file exists, block session exit and feed the same prompt back.

set -euo pipefail

HOOK_INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Set by read_state
LOOP=""
MAX_LOOPS=""
STATE_SESSION=""
# Set by require_transcript / read_last_output
TRANSCRIPT_PATH=""
LAST_OUTPUT=""

# --- helpers ---

# End the flow normally: message on stdout, state removed.
finish() { echo "$1"; rm "$STATE_FILE"; exit 0; }

# End the flow on a problem: message on stderr, state removed.
abort() { echo "$1" >&2; rm "$STATE_FILE"; exit 0; }

stop_corrupt() {
  echo "⚠️  Spectomat flow: state file corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: $1" >&2
  echo "   The flow is stopping. Run /spectomat:run again to start fresh." >&2
  rm "$STATE_FILE"
  exit 0
}

# --- phases ---

read_state() {
  LOOP=$(state_field loop)
  MAX_LOOPS=$(state_field max_loops)
  STATE_SESSION=$(state_field session_id)
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
  [[ "$LOOP" =~ ^[0-9]+$ ]] || stop_corrupt "'loop' is not a number (got: '$LOOP')"
  [[ "$MAX_LOOPS" =~ ^[0-9]+$ ]] || stop_corrupt "'max_loops' is not a number (got: '$MAX_LOOPS')"
}

require_below_max() {
  if [[ $MAX_LOOPS -gt 0 ]] && [[ $LOOP -ge $MAX_LOOPS ]]; then
    finish "🛑 Spectomat flow: max loops ($MAX_LOOPS) reached. Run /spectomat:run to resume from the floor."
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
  local promise_text
  # First <promise> tag, whitespace normalised. Literal compare, not glob.
  promise_text=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ -n "$promise_text" ]] && [[ "$promise_text" = "FACTORY EMPTY" ]]; then
    finish "✅ Spectomat flow: detected <promise>FACTORY EMPTY</promise>"
  fi
}

# Bump the loop counter in place and emit the block decision with the prompt.
continue_loop() {
  local next_loop prompt_text temp_file system_msg
  next_loop=$((LOOP + 1))

  # Prompt is everything after the second --- line.
  prompt_text=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
  [[ -n "$prompt_text" ]] || stop_corrupt "no prompt text found"

  temp_file="${STATE_FILE}.tmp.$$"
  sed "s/^loop: .*/loop: $next_loop/" "$STATE_FILE" > "$temp_file"
  mv "$temp_file" "$STATE_FILE"

  system_msg="🔄 Spectomat loop $next_loop | To stop: output <promise>FACTORY EMPTY</promise> (ONLY when the statement is TRUE - do not lie to exit!)"

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
