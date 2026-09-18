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
is "plan() writes N task files" "$(ls "$FIXTURE/.spectomat/001-a/tasks"/task-*.md | wc -l | tr -d ' ')" "3"
is "plan() writes a ledger of N tasks" "$(jq -r '.tasks | length' "$FIXTURE/.spectomat/001-a/tasks.json")" "3"
is "plan() leaves OPEN tasks pending"  "$(jq -r '[.tasks[] | select(.status == "pending")] | length' "$FIXTURE/.spectomat/001-a/tasks.json")" "1"
is "plan() closes the rest"            "$(jq -r '[.tasks[] | select(.status == "done")] | length' "$FIXTURE/.spectomat/001-a/tasks.json")" "2"
is "plan() chains dependsOn"           "$(jq -c '[.tasks[].dependsOn]' "$FIXTURE/.spectomat/001-a/tasks.json")" '[[],[1],[2]]'
is "plan() keeps state.json counterless" "$(jq -r '.slugs["001-a"] | has("tasks_total")' "$FIXTURE/.spectomat/state.json")" "false"
is "plan() with an open task is IMPLEMENT" "$(jq -r '.slugs["001-a"].phase' "$FIXTURE/.spectomat/state.json")" "IMPLEMENT"
floor bare; plan_bare 002-b
is "plan_bare() writes no task files" "$(ls "$FIXTURE/.spectomat/002-b/tasks"/task-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"
is "plan_bare() writes the overview"  "$([[ -f "$FIXTURE/.spectomat/002-b/plan.md" ]] && echo yes || echo no)" "yes"

floor marked; archived 003-c; archived 004-d blocked
is "archived() marks a shipped slug" "$([[ -f "$FIXTURE/.spectomat/003-c/done.md" ]] && echo yes || echo no)" "yes"
is "archived() marks a blocked slug" "$([[ -f "$FIXTURE/.spectomat/004-d/blocked.md" ]] && echo yes || echo no)" "yes"

floor quiet; logline note
out=$(fixture_commit 2>&1)
is "fixture_commit is silent for a gitignored-only change" "$out" ""

FIXTURE="$TMP/no-such-fixture"
err=$(fixture_commit 2>&1 1>/dev/null); rc=$?
case "$err" in *"fixture_commit"*) got=yes ;; *) got=no ;; esac
is "fixture_commit reports a broken fixture on stderr" "$got" "yes"
is "fixture_commit still returns 0 on a broken fixture" "$rc" "0"

finish
