#!/bin/bash
# Spectomat loop Stop hook.
# While the state file exists, block session exit and feed the same prompt back.
# The state file name differs from ralph-loop's on purpose: both plugins can be
# installed without their Stop hooks acting on the same loop.

set -euo pipefail

HOOK_INPUT=$(cat)
STATE_FILE="docs/.spectomat/loop.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

stop_corrupt() {
  echo "⚠️  Spectomat loop: state file corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: $1" >&2
  echo "   The loop is stopping. Run /spectomat:run again to start fresh." >&2
  rm "$STATE_FILE"
  exit 0
}

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# Session isolation: the Stop hook fires in every session of this project.
# Only the session that started the loop may continue it.
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

[[ "$ITERATION" =~ ^[0-9]+$ ]] || stop_corrupt "'iteration' is not a number (got: '$ITERATION')"
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || stop_corrupt "'max_iterations' is not a number (got: '$MAX_ITERATIONS')"

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Spectomat loop: max iterations ($MAX_ITERATIONS) reached. Run /spectomat:run to resume from the floor."
  rm "$STATE_FILE"
  exit 0
fi

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Spectomat loop: transcript not found at $TRANSCRIPT_PATH. The loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Spectomat loop: no assistant messages in transcript. The loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Each content block is its own JSONL line with role=assistant. Take the last
# text block of the last 100 assistant lines; a turn of only tool calls yields
# "" and the loop simply continues.
LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e
if [[ $JQ_EXIT -ne 0 ]]; then
  echo "⚠️  Spectomat loop: failed to parse transcript ($LAST_OUTPUT). The loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # First <promise> tag, whitespace normalised. Literal compare, not glob.
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ Spectomat loop: detected <promise>$COMPLETION_PROMISE</promise>"
    rm "$STATE_FILE"
    exit 0
  fi
fi

NEXT_ITERATION=$((ITERATION + 1))

# Prompt is everything after the second --- line.
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
[[ -n "$PROMPT_TEXT" ]] || stop_corrupt "no prompt text found"

TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="🔄 Spectomat iteration $NEXT_ITERATION | To stop: output <promise>$COMPLETION_PROMISE</promise> (ONLY when the statement is TRUE - do not lie to exit!)"
else
  SYSTEM_MSG="🔄 Spectomat iteration $NEXT_ITERATION | No completion promise set - loop runs until max iterations"
fi

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
