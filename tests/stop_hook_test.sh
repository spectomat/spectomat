#!/bin/bash
# stop-hook.sh — runs on every iteration of every flow and is the only script
# that can end one. Its fixture is a real floor in a real git repo; its input
# is the JSON payload Claude Code pipes in. The hook reads no transcript: it
# runs the picker and ends the flow on FINISH.
#
#   tests/stop_hook_test.sh              tests ../scripts
#   tests/stop_hook_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "stop-hook.sh"

# hook_floor NAME SESSION ITERATION MAX — a real git floor with one draft, so
# the picker answers SPECIFY and the hook blocks. A bare .spectomat/ would be
# answered FINISH and end the flow before any assertion could run.
hook_floor() {
  floor "$1"
  draft 001-a
  jq --arg s "$2" --argjson i "$3" --argjson m "$4" \
    '.session_id = $s | .iteration = $i | .max_iterations = $m' \
    "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
}

# empty_floor — remove the unfinished slug and its state entry, so the picker
# says FINISH. The removal is committed, or the tree is dirty and the answer is
# RECOVER instead. Slugs archived() marked are finished and stay put: the
# closing report counts them.
empty_floor() {
  rm -rf "$FIXTURE/.spectomat/001-a"
  jq 'del(.slugs["001-a"])' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
  fixture_commit
}

# fire SESSION — run the hook as SESSION in the fixture; stdout only. The
# payload carries no transcript_path: the hook no longer reads one.
fire() {
  jq -nc --arg s "$1" '{session_id:$s}' \
    | ( cd "$FIXTURE" && bash "$SCRIPTS/stop-hook.sh" 2>/dev/null )
}

hook_state() { [[ -e "$FIXTURE/.spectomat/state.json" ]] && echo yes || echo no; }
hook_iter()  { jq -r .iteration "$FIXTURE/.spectomat/state.json" 2>/dev/null; }
hook_current() { jq -r '.current | "\(.phase) \(.slug)"' "$FIXTURE/.spectomat/state.json" 2>/dev/null; }
msg()        { printf '%s' "$1" | jq -r '.systemMessage // ""' 2>/dev/null; }

# The pointer prompt stop-hook.sh feeds back, computed the same way it does:
# by sourcing utils.sh (in a subshell, so PLUGIN_ROOT etc. do not leak here).
POINTER_PROMPT="$(source "$SCRIPTS/utils.sh" && pointer_prompt)"

hook_floor h_block OWNER 1 5
out=$(fire OWNER)
is "the owner is blocked from exiting" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "the pointer is fed back"           "$(printf '%s' "$out" | jq -r .reason)"   "$POINTER_PROMPT"
is "the iteration is bumped"           "$(hook_iter)" "2"
is "the verdict is recorded as current" "$(hook_current)" "SPECIFY 001-a"

# A RECOVER is never recorded: after a dirty death `current` must still name the
# iteration that died, for the picker to hand that slug to the janitor.
dirty
fire OWNER >/dev/null
is "a RECOVER leaves current alone"    "$(hook_current)" "SPECIFY 001-a"

# Session isolation: the hook fires in every session of the project, and only
# the one that armed the flow may advance or end it.
hook_floor h_stranger OWNER 1 5
out=$(fire STRANGER)
is "a foreign session emits nothing"    "$out" ""
is "a foreign session leaves the state" "$(hook_state)" "yes"
is "a foreign session bumps nothing"    "$(hook_iter)" "1"

# A state file jq cannot read names no owner, so no session may disarm it: the
# guard that catches this once ran before the session check and let any session
# in the project destroy a flow it did not own.
hook_floor h_corrupt OWNER 1 5
printf 'not json at all\n' > "$FIXTURE/.spectomat/state.json"
fire STRANGER >/dev/null
is "a corrupt state survives a foreign session" "$(hook_state)" "yes"
fire OWNER >/dev/null
is "a corrupt state survives its own session"   "$(hook_state)" "yes"

hook_floor h_cancelled OWNER 1 5
jq '.active = false' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
out=$(fire OWNER)
is "a cancelled flow emits nothing" "$out" ""
is "a cancelled flow bumps nothing" "$(hook_iter)" "1"

# The flow ends on the picker's FINISH verdict, not on anything a model said.
hook_floor h_finish OWNER 4 20
empty_floor
archived 003-c
archived 002-b blocked
out=$(fire OWNER)
is "a finished floor ends the flow"  "$(msg "$out" | grep -c 'flow complete')" "1"
is "the report counts what shipped" "$(msg "$out" | grep -c 'Shipped 1')"     "1"
is "the report counts what blocked" "$(msg "$out" | grep -c 'blocked 1')"     "1"
is "the report names the blocked slug" "$(msg "$out" | grep -c '002-b')"      "1"
is "the report's tally line" "$(msg "$out" | sed -n '2p')" "   Shipped 1 · blocked 1 · 4 iterations."
is "the flow does not block"        "$(printf '%s' "$out" | jq -r '.decision // ""')" ""
is "a finished floor disarms"         "$(hook_state)" "no"

# The bug the promise could not see: an empty floor in a dirty tree is
# RECOVER, so the flow must continue instead of ending on a mess.
hook_floor h_finish_dirty OWNER 4 20
empty_floor
dirty
out=$(fire OWNER)
is "a finished floor with a dirty tree keeps going" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "a dirty finish does not disarm"               "$(hook_state)" "yes"

hook_floor h_cap OWNER 3 3
out=$(fire OWNER)
is "the cap ends the flow" "$(msg "$out" | grep -c 'max iterations')" "1"
is "the cap disarms"       "$(hook_state)" "no"

# The cap is checked before the picker, so a capped flow ends on the cap's
# message even when the floor happens to be empty.
hook_floor h_cap_empty OWNER 3 3
empty_floor
is "the cap outranks FINISH" "$(msg "$(fire OWNER)" | grep -c 'max iterations')" "1"

hook_floor h_nostate OWNER 1 5
rm -f "$FIXTURE/.spectomat/state.json"
is "no state file means no output" "$(fire OWNER)" ""

finish
