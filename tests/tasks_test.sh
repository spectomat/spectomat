#!/bin/bash
# tasks — the per-slug task ledger: scripts/tasks.sh and the tasks_* helpers
# in utils.sh. The ledger is the single source of truth for one slug's tasks,
# so this covers writing it, picking the next ready task by dependsOn, closing
# one with its evidence, and the phase move the last close earns.
#
#   tests/tasks_test.sh              tests ../scripts
#   tests/tasks_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# t SLUG ARGS... — run tasks.sh in the fixture and print its stdout.
t() { (cd "$FIXTURE" && bash "$SCRIPTS/tasks.sh" "$@" 2>/dev/null); }
# terr SLUG ARGS... — the same, capturing stderr and swallowing stdout.
terr() { (cd "$FIXTURE" && bash "$SCRIPTS/tasks.sh" "$@" 2>&1 1>/dev/null); }
# phase SLUG — the slug's phase in the fixture's state.json.
phase() { jq -r --arg s "$1" '.slugs[$s].phase // empty' "$FIXTURE/.spectomat/state.json"; }
# field SLUG ID KEY — one field of one task in the fixture's ledger.
field() { jq -r --arg i "$2" --arg k "$3" '.tasks[] | select(.id == ($i | tonumber)) | .[$k]' \
  "$FIXTURE/.spectomat/$1/tasks.json"; }

THREE='[{"id":1,"name":"a","file":"tasks/task-01-a.md","component":"A","covers":["AC-1"],"dependsOn":[]},
        {"id":2,"name":"b","file":"tasks/task-02-b.md","component":"B","covers":["AC-2"],"dependsOn":[1]},
        {"id":3,"name":"c","file":"tasks/task-03-c.md","component":"C","covers":["AC-3"],"dependsOn":[1]}]'

echo "tasks"

# --- write and init -------------------------------------------------------

floor w; state_slug 001-a PLAN
out=$(t write 001-a "$THREE")
is "write creates the ledger"        "$([[ -f "$FIXTURE/.spectomat/001-a/tasks.json" ]] && echo yes || echo no)" "yes"
is "write keeps every task"          "$(jq -r '.tasks | length' "$FIXTURE/.spectomat/001-a/tasks.json")" "3"
is "write records the slug"          "$(jq -r '.slug' "$FIXTURE/.spectomat/001-a/tasks.json")" "001-a"
is "write keeps dependsOn"           "$(field 001-a 2 dependsOn | tr -d ' \n')" "[1]"
is "write keeps covers"              "$(field 001-a 1 covers | tr -d ' \n')" '["AC-1"]'
is "write starts every task pending" "$(jq -r '[.tasks[] | select(.status == "pending")] | length' "$FIXTURE/.spectomat/001-a/tasks.json")" "3"
is "write leaves results empty"      "$(field 001-a 1 commits)" "null"
is "write moves no phase"            "$(phase 001-a)" "PLAN"

# A caller that passes status or commits must not be believed: the ledger's
# result fields are set by task_close alone, or a plan could arm itself closed.
floor forced; state_slug 001-a PLAN
t write 001-a '[{"id":1,"file":"f.md","dependsOn":[],"status":"done","commits":"deadbee..f00ba12"}]' >/dev/null
is "write forces status to pending"  "$(field 001-a 1 status)" "pending"
is "write discards a passed commits" "$(field 001-a 1 commits)" "null"

floor i; state_slug 001-a PLAN
t init 001-a "$THREE" >/dev/null
is "init moves the phase to IMPLEMENT" "$(phase 001-a)" "IMPLEMENT"

floor s; state_slug 001-a PLAN; t write 001-a "$THREE" >/dev/null
t start 001-a >/dev/null
is "start moves the phase to IMPLEMENT" "$(phase 001-a)" "IMPLEMENT"

# --- next -----------------------------------------------------------------

floor n; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
is "next is the first task"            "$(t next 001-a)" "1"
t close 001-a 1 "aaaaaaa..bbbbbbb" "2/2 (x)" "passed" >/dev/null
is "next is the lowest ready task"     "$(t next 001-a)" "2"
t close 001-a 2 "bbbbbbb..ccccccc" "1/1 (y)" "passed" >/dev/null
is "next walks on"                     "$(t next 001-a)" "3"
t close 001-a 3 "ccccccc..ddddddd" "1/1 (z)" "passed" >/dev/null
is "next is empty when all are done"   "$(t next 001-a)" ""

# A pending task whose dependency is not done is not ready, however low its id.
floor dep; state_slug 001-a PLAN
t init 001-a '[{"id":1,"file":"a.md","dependsOn":[3]},
               {"id":2,"file":"b.md","dependsOn":[3]},
               {"id":3,"file":"c.md","dependsOn":[]}]' >/dev/null
is "next skips a task whose dep is pending" "$(t next 001-a)" "3"

# A cycle leaves every task pending and nothing ready — the one case the
# IMPLEMENT brief turns into a strike rather than a guessed order.
floor cyc; state_slug 001-a PLAN
t init 001-a '[{"id":1,"file":"a.md","dependsOn":[2]},{"id":2,"file":"b.md","dependsOn":[1]}]' >/dev/null
is "next is empty on a cycle"          "$(t next 001-a)" ""
is "count still reports them pending"  "$(t count 001-a pending)" "2"

# --- dispatch -------------------------------------------------------------

# The five lines IMPLEMENT sends the task agent, byte for byte: the worker reads
# them by key, so the shape is part of the contract, not a formatting choice.
ROOT_OF_SCRIPTS="$(cd "$SCRIPTS/.." && pwd)"
floor d; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
is "dispatch prints the next task's five lines" "$(t dispatch 001-a)" "slug: 001-a
task: 01
task_file: .spectomat/001-a/tasks/task-01-a.md
gates_log: .spectomat/work/001-a/task-01.gates.log
plugin_root: $ROOT_OF_SCRIPTS"
is "dispatch creates the scratch dir"  "$([[ -d "$FIXTURE/.spectomat/work/001-a" ]] && echo yes || echo no)" "yes"
# A log left by an earlier strike must not pass for this dispatch's run.
echo "exit: 0" > "$FIXTURE/.spectomat/work/001-a/task-01.gates.log"
t dispatch 001-a >/dev/null
is "dispatch deletes a stale gates log" "$([[ -e "$FIXTURE/.spectomat/work/001-a/task-01.gates.log" ]] && echo yes || echo no)" "no"
t close 001-a 1 "a..b" "1/1" "passed" >/dev/null
is "dispatch follows next"             "$(t dispatch 001-a | sed -n 2,3p)" "task: 02
task_file: .spectomat/001-a/tasks/task-02-b.md"
t close 001-a 2 "b..c" "1/1" "passed" >/dev/null
t close 001-a 3 "c..d" "1/1" "passed" >/dev/null
is "dispatch is empty when all are done" "$(t dispatch 001-a)" ""

floor d12; state_slug 001-a PLAN
t init 001-a '[{"id":12,"name":"x","file":"tasks/task-12-x.md","dependsOn":[]}]' >/dev/null
is "dispatch keeps a two-digit id"      "$(t dispatch 001-a | sed -n 4p)" "gates_log: .spectomat/work/001-a/task-12.gates.log"

floor dcyc; state_slug 001-a PLAN
t init 001-a '[{"id":1,"file":"a.md","dependsOn":[2]},{"id":2,"file":"b.md","dependsOn":[1]}]' >/dev/null
is "dispatch is empty on a cycle"      "$(t dispatch 001-a)" ""

floor dnofile; state_slug 001-a PLAN
t init 001-a '[{"id":1,"name":"x","dependsOn":[]}]' >/dev/null
err=$(terr dispatch 001-a); case "$err" in *"no file"*) got=yes ;; *) got=no ;; esac
is "dispatch refuses a task with no file" "$got" "yes"

# --- close ----------------------------------------------------------------

floor c; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
t close 001-a 1 "aaaaaaa..bbbbbbb" "4/4 (a.test.js)" "passed (lint, test)" >/dev/null
is "close marks the task done"     "$(field 001-a 1 status)" "done"
is "close records the commits"     "$(field 001-a 1 commits)" "aaaaaaa..bbbbbbb"
is "close records the tests"       "$(field 001-a 1 tests)" "4/4 (a.test.js)"
is "close records the gates"       "$(field 001-a 1 gates)" "passed (lint, test)"
is "close touches no other task"   "$(field 001-a 2 status)" "pending"
is "close holds the phase while work remains" "$(phase 001-a)" "IMPLEMENT"
t close 001-a 2 "b..c" "1/1" "passed" >/dev/null
is "still IMPLEMENT with one pending" "$(phase 001-a)" "IMPLEMENT"
t close 001-a 3 "c..d" "1/1" "passed" >/dev/null
is "the last close moves to REVIEW" "$(phase 001-a)" "REVIEW"
is "no task is left pending"        "$(t count 001-a pending)" "0"

# One task closes once: a repeated call would double-count the work and, on the
# last task, move an already-reviewing slug again.
floor twice; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
t close 001-a 1 "a..b" "1/1" "passed" >/dev/null
err=$(terr close 001-a 1 "a..b" "1/1" "passed")
case "$err" in *"already closed"*) got=yes ;; *) got=no ;; esac
is "close refuses an already-closed task" "$got" "yes"
err=$(terr close 001-a 9 "a..b" "1/1" "passed")
case "$err" in *"no task 9"*) got=yes ;; *) got=no ;; esac
is "close refuses an unknown task"        "$got" "yes"

# --- add ------------------------------------------------------------------

floor a; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
t close 001-a 1 "a..b" "1/1" "passed" >/dev/null
t close 001-a 2 "b..c" "1/1" "passed" >/dev/null
t close 001-a 3 "c..d" "1/1" "passed" >/dev/null
is "the plan reached REVIEW" "$(phase 001-a)" "REVIEW"
t add 001-a '[{"id":4,"name":"fix","file":"tasks/task-04-fix.md","dependsOn":[2]}]' >/dev/null
is "add appends to the ledger"    "$(t count 001-a)" "4"
is "add starts the task pending"  "$(field 001-a 4 status)" "pending"
is "add keeps the closed tasks"   "$(t count 001-a done)" "3"
is "add sends the slug back"      "$(phase 001-a)" "IMPLEMENT"
is "next is the added task"       "$(t next 001-a)" "4"
t close 001-a 4 "d..e" "1/1" "passed" >/dev/null
is "closing it returns to REVIEW" "$(phase 001-a)" "REVIEW"

# --- count and show -------------------------------------------------------

floor q; state_slug 001-a PLAN; t init 001-a "$THREE" >/dev/null
is "count is every task"        "$(t count 001-a)" "3"
is "count pending"              "$(t count 001-a pending)" "3"
is "count done is zero"         "$(t count 001-a done)" "0"
is "count is 0 with no ledger"  "$(t count 002-b)" "0"
is "show one task gives its id" "$(t show 001-a 2 | jq -r '.id')" "2"
is "show all gives the ledger"  "$(t show 001-a | jq -r '.tasks | length')" "3"
# IMPLEMENT's step 1 is `show <slug> "$(next <slug>)"`: an empty id must print
# nothing, not the whole ledger, or a finished plan reads as a task to take.
is "show an empty id prints nothing" "$(t show 001-a "")" ""

# --- refusals -------------------------------------------------------------

floor r; state_slug 001-a PLAN
err=$(terr next 001-a);  case "$err" in *"no ledger"*) got=yes ;; *) got=no ;; esac
is "next refuses a missing ledger" "$got" "yes"
err=$(terr dispatch 001-a); case "$err" in *"no ledger"*) got=yes ;; *) got=no ;; esac
is "dispatch refuses a missing ledger" "$got" "yes"
err=$(terr add 001-a '[]'); case "$err" in *"no ledger"*) got=yes ;; *) got=no ;; esac
is "add refuses a missing ledger"  "$got" "yes"
err=$(terr write); case "$err" in *usage*) got=yes ;; *) got=no ;; esac
is "a bare call prints usage"      "$got" "yes"

finish
