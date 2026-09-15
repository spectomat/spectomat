#!/bin/bash
# stop-hook.sh — runs on every iteration of every flow and is the only script
# that can end one. Its fixture is a state file, a pointer and a transcript;
# its input is the JSON payload Claude Code pipes in.
#
#   scripts/tests/stop_hook_test.sh          tests the scripts next to it
#   scripts/tests/stop_hook_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "stop-hook.sh"

HOOK="$TMP/hook"

# hook_floor SESSION ITERATION MAX — an armed flow owned by SESSION.
hook_floor() {
  rm -rf "$HOOK"; mkdir -p "$HOOK/.spectomat"
  printf '{"active": true, "iteration": %s, "max_iterations": %s, "session_id": "%s", "started_at": "t"}\n' \
    "$2" "$3" "$1" > "$HOOK/.spectomat/state.json"
  printf 'POINTER PROMPT\n' > "$HOOK/.spectomat/pointer.md"
  transcript 'working on it'
}

# transcript TEXT — one assistant turn whose last text block is TEXT.
transcript() {
  jq -nc --arg t "$1" '{role:"assistant", message:{content:[{type:"text", text:$t}]}}' \
    > "$HOOK/transcript.jsonl"
}

# fire SESSION — run the hook as SESSION; stdout only.
fire() {
  jq -nc --arg s "$1" --arg p "$HOOK/transcript.jsonl" \
      '{session_id:$s, transcript_path:$p}' \
    | ( cd "$HOOK" && bash "$SCRIPTS/stop-hook.sh" 2>/dev/null )
}

hook_state() { [[ -e "$HOOK/.spectomat/state.json" ]] && echo yes || echo no; }
hook_iter()  { jq -r .iteration "$HOOK/.spectomat/state.json" 2>/dev/null; }

hook_floor OWNER 1 5
out=$(fire OWNER)
is "the owner is blocked from exiting" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "the pointer is fed back"           "$(printf '%s' "$out" | jq -r .reason)"   "POINTER PROMPT"
is "the iteration is bumped"           "$(hook_iter)" "2"

# Session isolation: the hook fires in every session of the project, and only
# the one that armed the flow may advance or end it.
hook_floor OWNER 1 5
out=$(fire STRANGER)
is "a foreign session emits nothing"    "$out" ""
is "a foreign session leaves the state" "$(hook_state)" "yes"
is "a foreign session bumps nothing"    "$(hook_iter)" "1"

# A state file jq cannot read names no owner, so no session may disarm it: the
# guard that catches this once ran before the session check and let any session
# in the project destroy a flow it did not own.
hook_floor OWNER 1 5
printf 'not json at all\n' > "$HOOK/.spectomat/state.json"
fire STRANGER >/dev/null
is "a corrupt state survives a foreign session" "$(hook_state)" "yes"
fire OWNER >/dev/null
is "a corrupt state survives its own session"   "$(hook_state)" "yes"

hook_floor OWNER 1 5
jq '.active = false' "$HOOK/.spectomat/state.json" > "$HOOK/.spectomat/state.json.tmp" && mv "$HOOK/.spectomat/state.json.tmp" "$HOOK/.spectomat/state.json"
out=$(fire OWNER)
is "a cancelled flow emits nothing" "$out" ""
is "a cancelled flow bumps nothing" "$(hook_iter)" "1"

hook_floor OWNER 1 5
transcript 'done here <promise>FACTORY EMPTY</promise>'
out=$(fire OWNER)
case "$out" in *"FACTORY EMPTY"*) got=yes ;; *) got=no ;; esac
is "the promise ends the flow"        "$got" "yes"
is "the promise disarms"              "$(hook_state)" "no"
is "the promise removes the pointer"  "$([[ -e "$HOOK/.spectomat/pointer.md" ]] && echo yes || echo no)" "no"

hook_floor OWNER 3 3
out=$(fire OWNER)
case "$out" in *"max iterations"*) got=yes ;; *) got=no ;; esac
is "the cap ends the flow" "$got" "yes"
is "the cap disarms"       "$(hook_state)" "no"

hook_floor OWNER 1 5
rm -f "$HOOK/.spectomat/state.json"
is "no state file means no output" "$(fire OWNER)" ""

finish
