#!/bin/bash
# fixtures — the floor/draft/spec/plan/fixture_commit helpers in lib.sh
# behave correctly, since every other test file trusts them.
#
#   tests/fixtures_test.sh              tests ../scripts
#   tests/fixtures_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "fixtures"
floor clean
is "fresh fixture is clean"     "$(cd "$FIXTURE" && git status --porcelain)" ""
floor dirt; dirty
is "dirty() dirties the tree"   "$(cd "$FIXTURE" && git status --porcelain)" "?? untracked.txt"
floor counted; plan 001-a 3 1
is "plan() writes N task files" "$(ls "$FIXTURE/.spectomat/plans/001-a" | wc -l | tr -d ' ')" "3"
is "plan() seeds tasks_total"   "$(jq -r '.slugs["001-a"].tasks_total' "$FIXTURE/.spectomat/state.json")" "3"
is "plan() seeds tasks_done from OPEN" "$(jq -r '.slugs["001-a"].tasks_done' "$FIXTURE/.spectomat/state.json")" "2"
is "plan() with an open task is IMPLEMENT" "$(jq -r '.slugs["001-a"].phase' "$FIXTURE/.spectomat/state.json")" "IMPLEMENT"
floor bare; plan_bare 002-b
is "plan_bare() has no task dir" "$([[ -d "$FIXTURE/.spectomat/plans/002-b" ]] && echo yes || echo no)" "no"

floor quiet; logline note
out=$(fixture_commit 2>&1)
is "fixture_commit is silent for a gitignored-only change" "$out" ""

FIXTURE="$TMP/no-such-fixture"
err=$(fixture_commit 2>&1 1>/dev/null); rc=$?
case "$err" in *"fixture_commit"*) got=yes ;; *) got=no ;; esac
is "fixture_commit reports a broken fixture on stderr" "$got" "yes"
is "fixture_commit still returns 0 on a broken fixture" "$rc" "0"

finish
