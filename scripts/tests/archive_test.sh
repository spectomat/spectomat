#!/bin/bash
# archive.sh — the ARCHIVE phase: green/red gates, strikes, blocking, and the
# unchecked-move regression that leaves the tree dirty rather than committing
# a partial move.
#
#   scripts/tests/archive_test.sh          tests the scripts next to it
#   scripts/tests/archive_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
is "the spec moved"    "$(there done/001-a.spec.md)" "yes"
is "the plan moved"    "$(there done/001-a.plan.md)" "yes"
is "the task dir moved" "$(there done/001-a)"        "yes"
is "specs/ is empty"   "$(there specs/001-a.md)"     "no"
is "exactly one commit" "$(( $(commits) - n0 ))"     "1"
is "the tree is clean" "$(cd "$FIXTURE" && git status --porcelain)" ""
is "the log names the gate count" "$(grep -c 'gates 1/1' "$FIXTURE/.spectomat/log.md")" "1"
# ARCHIVE owns the floor and nothing else: it must not stage a project file,
# which is what the old package.json version bump did.
is "the commit touches only the floor" \
  "$(cd "$FIXTURE" && git show --name-only --format= HEAD | grep -cv '^.spectomat/')" "0"
is "archiving deletes the slug from state.json" "$(cd "$FIXTURE" && jq -r '.slugs["001-a"] // "gone"' .spectomat/state.json)" "gone"

ready fail 001-a 'false'
arc 001-a; is "a red gate exits 1" "$?" "1"
is "nothing moved"     "$(there done/001-a.spec.md)" "no"
is "the spec stayed"   "$(there specs/001-a.md)"     "yes"
is "a strike is logged" "$(grep -c '(strike 1)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the second strike counts up" "$(grep -c '(strike 2)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the third strike exits 0" "$?" "0"
is "the blocked spec moved" "$(there done/001-a.spec.blocked.md)" "yes"
is "the blocked plan moved" "$(there done/001-a.plan.blocked.md)" "yes"
is "print_blocked lists both" \
  "$(cd "$FIXTURE" && find .spectomat/done -maxdepth 1 -name '*.blocked.md' | wc -l | tr -d ' ')" "2"
is "blocking archive deletes the slug from state.json" "$(cd "$FIXTURE" && jq -r '.slugs["001-a"] // "gone"' .spectomat/state.json)" "gone"

ready dirt 001-a 'true'; dirty
arc 001-a; is "a dirty tree is refused" "$?" "1"
is "nothing moved on a dirty tree" "$(there done/001-a.spec.md)" "no"

ready nosuch 001-a 'true'
arc 002-b; is "an unknown slug is refused" "$?" "1"

echo "archive.sh: unchecked move/commit failures (regression)"
# conflict PATH — pre-place and commit a file at a done/ destination so the
# git mv that targets it is refused; the tree must stay clean going in, or
# require_ready would reject it for the wrong reason.
conflict() { printf 'conflict\n' > "$FIXTURE/.spectomat/$1"; fixture_commit; }

ready blk1 001-a 'true'
conflict done/001-a.spec.md
n0=$(commits); arc 001-a
is "a blocked spec move exits non-zero"        "$?" "1"
is "no commit is made when the spec can't move" "$(( $(commits) - n0 ))" "0"
is "a strike is logged for the failed move"    "$(grep -c '(strike 1)' "$FIXTURE/.spectomat/log.md")" "1"
is "the spec never moved"                      "$(there specs/001-a.md)" "yes"
is "the plan never moved either"               "$(there plans/001-a.md)" "yes"

ready blk2 001-a 'true'
conflict done/001-a.spec.md
conflict done/001-a.plan.md
n0=$(commits); arc 001-a
is "both destinations blocked exits non-zero" "$?" "1"
is "zero new commits when nothing could move" "$(( $(commits) - n0 ))" "0"

finish
