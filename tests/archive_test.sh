#!/bin/bash
# archive.sh — the ARCHIVE phase: green/red gates, strikes, blocking, and the
# marker file that finishes a slug in place without moving its trail.
#
#   tests/archive_test.sh              tests ../scripts
#   tests/archive_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "archive.sh"
# ready NAME SLUG GATE — a floor with a finished plan and a one-line gate block
ready() {
  floor "arc-$1"; spec "$2"; plan "$2" 2 0; gates_block "$3"
  printf '{"active": true, "iteration": 1, "max_iterations": 5, "session_id": "test", "started_at": "t", "slugs": {"%s": {}}}\n' "$2" > "$FIXTURE/.spectomat/state.json"
  fixture_commit
}
arc()   { ( cd "$FIXTURE" && bash "$SCRIPTS/archive.sh" "$1" >/dev/null 2>&1 ); }
there() { [[ -e "$FIXTURE/.spectomat/$1" ]] && echo yes || echo no; }
commits() { ( cd "$FIXTURE" && git rev-list --count HEAD ); }

ready pass 001-a 'true'
n0=$(commits); arc 001-a; is "a green gate exits 0" "$?" "0"
is "done.md marks the slug finished" "$(there 001-a/done.md)"    "yes"
is "no blocked.md is written"        "$(there 001-a/blocked.md)" "no"
is "the spec stays put"              "$(there 001-a/spec.md)"    "yes"
is "the plan stays put"              "$(there 001-a/plan.md)"    "yes"
is "the task files stay put"         "$(there 001-a/task-01-x.md)" "yes"
is "exactly one commit" "$(( $(commits) - n0 ))"     "1"
is "the tree is clean" "$(cd "$FIXTURE" && git status --porcelain)" ""
is "the log names the gate result" "$(grep -c 'gates passed' "$FIXTURE/.spectomat/log.md")" "1"
# ARCHIVE owns the floor: it must not stage a project file.
is "the commit touches only the floor" \
  "$(cd "$FIXTURE" && git show --name-only --format= HEAD | grep -cv '^.spectomat/')" "0"
is "archiving deletes the slug from state.json" "$(cd "$FIXTURE" && jq -r '.slugs["001-a"] // "gone"' .spectomat/state.json)" "gone"

ready fail 001-a 'false'
n0=$(commits); arc 001-a; is "a red gate exits 1" "$?" "1"
is "no marker is written"  "$(there 001-a/done.md)"    "no"
is "no blocked marker yet" "$(there 001-a/blocked.md)" "no"
is "the spec stayed"       "$(there 001-a/spec.md)"    "yes"
is "a red gate commits nothing" "$(( $(commits) - n0 ))" "0"
is "a strike is logged" "$(grep -c '(strike 1)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the second strike counts up" "$(grep -c '(strike 2)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the third strike exits 0" "$?" "0"
is "the third strike writes blocked.md" "$(there 001-a/blocked.md)" "yes"
is "a blocked slug gets no done.md"     "$(there 001-a/done.md)"    "no"
is "blocked.md names the reason" "$(grep -c 'gate failed' "$FIXTURE/.spectomat/001-a/blocked.md")" "1"
is "the blocked trail stays on the floor" "$(there 001-a/spec.md)" "yes"
is "blocking archive deletes the slug from state.json" "$(cd "$FIXTURE" && jq -r '.slugs["001-a"] // "gone"' .spectomat/state.json)" "gone"

ready dirt 001-a 'true'; dirty
arc 001-a; is "a dirty tree is refused" "$?" "1"
is "nothing is marked on a dirty tree" "$(there 001-a/done.md)" "no"

ready nosuch 001-a 'true'
arc 002-b; is "an unknown slug is refused" "$?" "1"

# A slug that already carries a marker is out of the flow: archiving it again
# would write a second commit over finished work, and (for a blocked slug)
# would silently promote it to shipped.
echo "archive.sh: a finished slug is refused"
ready twice 001-a 'true'
arc 001-a; n0=$(commits)
arc 001-a; is "archiving a done slug exits non-zero" "$?" "1"
is "the second archive commits nothing" "$(( $(commits) - n0 ))" "0"

ready blkdone 001-a 'true'
printf 'blocked\n' > "$FIXTURE/.spectomat/001-a/blocked.md"; fixture_commit
n0=$(commits); arc 001-a
is "archiving a blocked slug exits non-zero" "$?" "1"
is "a blocked slug is never promoted to done" "$(there 001-a/done.md)" "no"
is "the refusal commits nothing" "$(( $(commits) - n0 ))" "0"

finish
