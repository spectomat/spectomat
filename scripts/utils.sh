#!/bin/bash
# Spectomat shared constants and helpers. Source it, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#
# Sets no shell options; each script chooses its own set -e/-u/pipefail.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOOR=".spectomat"
STATE_FILE="$FLOOR/state.json"   # the flow's mutable state; gitignored
CONTRACT="$FLOOR/contract.md"
MEMORY="$FLOOR/memory.md"   # what the factory has learned about the codebase; gitignored, so one
                            # memory is shared by every feat/<slug> branch instead of forking per branch
GATES_SH="$FLOOR/gates.sh"   # the project's single gate command; committed, operator-editable

# Move to the git root (or stay put outside a repo); sets ROOT.
cd_root() {
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cd "$ROOT"
}

die() { echo "❌ $*" >&2; exit 1; }

# Number of files matching GLOB (default '*.md') directly inside a directory,
# 0 when it is missing. The glob is passed to find -name, so it must be
# quoted at the call site, not expanded by the shell.
count() { find "$1" -maxdepth 1 -name "${2:-*.md}" -type f 2>/dev/null | wc -l | tr -d ' '; }

# Value of one key in the state file; empty when absent or unreadable.
# Reading several keys at once is one jq call, not several - see read_state
# in stop-hook.sh, which is on the path of every iteration.
state_field() {
  jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || true
}

# Remove the armed flag. Nothing else needs cleaning up: the prompt the Stop
# hook feeds back is generated fresh by pointer_prompt(), not stored on disk.
disarm() { rm -f "$STATE_FILE"; }

# Render a template, replacing every {{KEY}} with its value:
#   render_template SRC DEST KEY=value ...
# Values are inserted literally. Bash 5.2 gave an unquoted & in a substitution
# replacement the sed meaning "the text that matched", so ${body//.../$val} put
# the {{KEY}} back for any value holding & - and escaping it instead leaves a
# literal backslash under bash 3.2, which never had that rule. Splitting the
# body on the placeholder sidesteps the replacement rules altogether and reads
# the same on every bash. Keys are applied in the order given, so a value
# holding {{X}} is still expanded by a later X= argument.
render_template() {
  local src="$1" dest="$2" kv key val body out head
  shift 2
  body=$(cat "$src"; printf X)   # X guards the trailing newlines $() would strip
  body="${body%X}"
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    out=""
    while [[ "$body" == *"{{$key}}"* ]]; do
      head="${body%%\{\{$key\}\}*}"       # everything before the first match
      out="$out$head$val"
      body="${body#"$head"\{\{$key\}\}}"  # everything after it
    done
    body="$out$body"
  done
  printf '%s' "$body" > "$dest"
}

# The prompt the Stop hook feeds back every iteration, and what command-run.sh
# previews when it arms a flow. No template file on disk: PLUGIN_ROOT is
# already a shell variable in every script that sources this file, so it is
# substituted the same way render_template does, straight into the heredoc.
pointer_prompt() {
  local body
  body=$(cat <<'EOF'
# Spectomat pointer

Fresh context each iteration. Do no factory work here.

## 1. Ask the picker

Run `bash {{PLUGIN_ROOT}}/scripts/phase.sh` once. It prints exactly one frontmatter block and exits 0:

```text
---
phase:<PHASE>
slug:<slug, empty for RECOVER and FINISH>
subagent:<subagent_type>
brief:<absolute path to the brief file>
plugin_root:<absolute plugin path>
---
```

Do not interpret the floor, the contract or the code yourself — act only on that block.

## 2. Act on that block, and only on it

Launch exactly one subagent with the Agent tool: 
 `run_in_background: false`, 
 `subagent_type` set to the `subagent` field of that block, 
  and the body of the file named by `brief` — its own frontmatter stripped — as the brief. 

The one exception is a block whose `subagent` field is empty, which only `FINISH` produces: dispatch nothing and go to step 3.

The task handed to the subagent is the block phase.sh printed, verbatim, fences included. 

Do not reformat it, extract fields out of it, or drop any line — the subagent reads `phase:`, `slug:` and `plugin_root:` for itself.

## 3. Report and stop

Print the report in at most five lines, then stop. 
Never retry a failed iteration here — the next iteration is a new picker call and a new subagent. 
A `FINISH` block means the flow has already ended and the Stop hook has reported it; say so in one line and stop. 
EOF
)
  printf '%s\n' "${body//\{\{PLUGIN_ROOT\}\}/$PLUGIN_ROOT}"
}

# slug_branch SLUG — the branch every phase of SLUG works on. One name, one
# place: command-run.sh creates it, the phase agents check it out, and nothing else
# composes "feat/$slug" by hand.
slug_branch() { printf 'feat/%s\n' "$1"; }

# slug_checkout SLUG — put the slug's branch in the working tree. Used by the
# phase scripts and by any agent following the contract's "Where you work".
#
# Refuses rather than creates: arming is the only thing that cuts a branch, so
# a missing one is a broken floor, not something to paper over mid-flow. The
# caller turns that non-zero into a strike.
slug_checkout() {
  local b; b="$(slug_branch "$1")"
  git rev-parse --verify --quiet "refs/heads/$b" >/dev/null \
    || { echo "❌ branch $b does not exist; re-arm the flow" >&2; return 1; }
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "$b" ]] && return 0
  git checkout -q "$b"
}

# Failed attempts at one phase for one slug before that slug is blocked.
STRIKE_LIMIT=3

# Run the project's gates: .spectomat/gates.sh, always, and nothing else. The
# script is operator-authored shell committed in their own repository, at the
# same trust level as a package.json script. Its own `set -e` chains its lines,
# so one exit code answers for the whole run. Sets GATE_FAILED on failure. A
# floor with no gates.sh has nothing to verify and passes.
run_gates() {
  GATE_FAILED=""
  [[ -f "$GATES_SH" ]] || return 0
  if ! bash "$GATES_SH"; then
    GATE_FAILED="$GATES_SH"
    return 1
  fi
  return 0
}

strike_count() {
  local phase="$1" slug="$2" n
  n=$(jq -r --arg p "$phase" --arg s "$slug" '.slugs[$s].strikes[$p] // 0' "$STATE_FILE" 2>/dev/null) || n=0
  printf '%s\n' "${n:-0}"
}

# The candidate with the fewest strikes at PHASE; candidate slugs arrive on
# stdin, one per line, already sorted, because a slug may contain spaces. Ties
# go to the first, which is the alphabetically first. Prints nothing when there
# are no candidates or every one has reached STRIKE_LIMIT, and the caller then
# moves on to the next stage.
least_struck() {
  local phase="$1" slug n best_n=-1 best=""
  while IFS= read -r slug; do
    [[ -n "$slug" ]] || continue
    n=$(strike_count "$phase" "$slug")
    [[ $n -lt $STRIKE_LIMIT ]] || continue
    if [[ $best_n -lt 0 ]] || [[ $n -lt $best_n ]]; then
      best_n=$n
      best="$slug"
    fi
  done
  [[ -z "$best" ]] || printf '%s\n' "$best"
}

# state_apply FILTER [JQ_ARGS...] — atomic jq write to STATE_FILE. JQ_ARGS
# (e.g. --arg s "$SLUG") must precede FILTER, matching jq's own argument
# order, so this takes FILTER first and re-appends it after "$@".
state_apply() {
  local filter="$1"; shift
  local tmp="$STATE_FILE.tmp.$$"
  jq "$@" "$filter" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# slug_add SLUG PHASE — register a new slug entering the flow, with no strikes yet.
slug_add() {
  state_apply '.slugs[$s] = {"phase": $p, "strikes": {}}' --arg s "$1" --arg p "$2"
}

# slug_phase SLUG — the slug's current phase, or empty if untracked.
slug_phase() {
  jq -r --arg s "$1" '.slugs[$s].phase // empty' "$STATE_FILE" 2>/dev/null || true
}

# slug_set_phase SLUG PHASE — advance a slug to a new phase with no task counters.
slug_set_phase() {
  state_apply '.slugs[$s].phase = $p' --arg s "$1" --arg p "$2"
}

# --- the task ledger ------------------------------------------------------
#
# .spectomat/<slug>/tasks.json is the single source of truth for one slug's
# tasks: the list PLAN writes, the dependencies IMPLEMENT picks by, and the
# per-task record it closes with. Unlike state.json it is committed, so the
# commit range of every task survives in git (D31). state.json keeps only
# flow-level state — phase, strikes, iteration — and no task counters.
#
#   {"slug": "<slug>",
#    "tasks": [{"id": 1, "name": "<name>", "file": "tasks/task-01-<name>.md",
#               "component": "<component>", "covers": ["AC-1.1"],
#               "dependsOn": [], "status": "pending",
#               "commits": null, "tests": null, "gates": null}]}
#
# `status` is "pending" or "done"; nothing else. A task's `file` is relative to
# the slug dir, and `dependsOn` holds ids, which are always lower than its own.

# tasks_file SLUG — path to the slug's ledger.
tasks_file() { printf '%s/%s/tasks.json\n' "$FLOOR" "$1"; }

# tasks_apply SLUG FILTER [JQ_ARGS...] — atomic jq write to the ledger, the
# same shape as state_apply. JQ_ARGS precede FILTER at the call site.
tasks_apply() {
  local slug="$1" filter="$2"; shift 2
  local f; f="$(tasks_file "$slug")"
  local tmp="$f.tmp.$$"
  jq "$@" "$filter" "$f" > "$tmp" && mv "$tmp" "$f"
}

# The normalising filter both writers share: a caller gives the fields that
# describe a task, and every result field is set here, never taken from input.
# A plan cannot arm itself half-closed, and a fix task cannot arrive "done".
TASK_SHAPE='{
  id: .id, name: (.name // ""), file: .file,
  component: (.component // ""), covers: (.covers // []),
  dependsOn: (.dependsOn // []),
  status: "pending", commits: null, tests: null, gates: null }'

# tasks_write SLUG JSON — write the ledger from a JSON array of tasks. Moves no
# phase: PLAN writes the ledger before its commit, since the file is committed,
# and calls tasks_start after. JSON is read from the argument, or from stdin
# when it is "-".
tasks_write() {
  local slug="$1" json="${2:--}" f; f="$(tasks_file "$slug")"
  [[ "$json" != "-" ]] || json="$(cat)"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$json" | jq --arg s "$slug" "{slug: \$s, tasks: [ .[] | $TASK_SHAPE ]}" > "$f"
}

# tasks_start SLUG — PLAN -> IMPLEMENT, the ledger already written and committed.
tasks_start() { slug_set_phase "$1" IMPLEMENT; }

# tasks_init SLUG JSON — both at once, for a caller not building a commit
# around the file.
tasks_init() { tasks_write "$@" && tasks_start "$1"; }

# tasks_add SLUG JSON — REVIEW: append fix tasks to the ledger and send the
# slug back to IMPLEMENT. Same task shape as tasks_init.
tasks_add() {
  local slug="$1" json="${2:--}"
  [[ "$json" != "-" ]] || json="$(cat)"
  tasks_apply "$slug" ".tasks += [ \$new[] | $TASK_SHAPE ]" --argjson new "$json" || return 1
  slug_set_phase "$slug" IMPLEMENT
}

# task_next SLUG — the id of the next ready task: the lowest-numbered pending
# task whose every dependsOn is done. Prints nothing when none is ready, which
# means either the slug is finished or its dependsOn rows hold a cycle — the
# caller tells the two apart with tasks_pending.
task_next() {
  jq -r '
    (.tasks | map(select(.status == "done") | .id)) as $done
    | [ .tasks[] | select(.status != "done")
        | select([ .dependsOn[] | IN($done[]) ] | all) ]
    | sort_by(.id) | first | if . then .id else empty end
  ' "$(tasks_file "$1")" 2>/dev/null || true
}

# tasks_count SLUG [STATUS] — how many tasks the ledger holds, or how many are
# at STATUS. Prints 0 when there is no ledger.
tasks_count() {
  local f; f="$(tasks_file "$1")"
  [[ -f "$f" ]] || { echo 0; return; }
  jq -r --arg st "${2:-}" '
    [ .tasks[] | select($st == "" or .status == $st) ] | length
  ' "$f" 2>/dev/null || echo 0
}

# tasks_pending SLUG — how many tasks are not yet done.
tasks_pending() { tasks_count "$1" pending; }

# task_close SLUG ID COMMITS TESTS GATES — IMPLEMENT, one task closed: record
# its evidence and mark it done, then move the slug to REVIEW once no task is
# left pending. The phase move lives here, so a closed task and the transition
# it earns cannot disagree.
task_close() {
  local slug="$1" id="$2"
  tasks_apply "$slug" '
    (.tasks[] | select(.id == ($i | tonumber)))
      |= (.status = "done" | .commits = $c | .tests = $t | .gates = $g)
  ' --arg i "$id" --arg c "$3" --arg t "$4" --arg g "$5" || return 1
  [[ "$(tasks_pending "$slug")" != "0" ]] || slug_set_phase "$slug" REVIEW
}

# slug_finish SLUG done|blocked [REASON] — the slug leaves the flow and keeps
# its entry at a terminal phase. state.json is the whole record, so a finished
# slug is recorded, not forgotten: the counters and strikes it ends with stay
# readable, and /spectomat:status counts it from here rather than from the
# done.md or blocked.md its dir carries.
slug_finish() {
  local phase=DONE
  [[ "$2" != blocked ]] || phase=BLOCKED
  state_apply '.slugs[$s].phase = $p | .slugs[$s].reason = $r | .slugs[$s].finished_at = $t' \
    --arg s "$1" --arg p "$phase" --arg r "${3:-}" --arg t "$(date -u +%FT%RZ)"
}

# slugs_at_phase PHASE — slugs at PHASE, alphabetically. The picker's candidate
# sets, the finished counts and the blocked list are all this one shape.
#
# The file check comes first and the jq failure is swallowed: command-run.sh's
# report_floor calls this before arm_flow has written state.json, and a script
# running set -e with pipefail would die on the failing jq inside the pipeline.
slugs_at_phase() {
  [[ -f "$STATE_FILE" ]] || return 0
  jq -r --arg p "$1" '.slugs // {} | to_entries[] | select(.value.phase == $p) | .key' \
    "$STATE_FILE" 2>/dev/null | sort || true
}

# The slugs still in the flow: every one whose phase is not terminal. Empty is
# what FINISH means, and it is not the same as "no slugs" — a finished flow
# keeps every slug it ever had, at DONE or BLOCKED.
slugs_unfinished() {
  [[ -f "$STATE_FILE" ]] || return 0
  jq -r '.slugs // {} | to_entries[]
    | select(.value.phase != "DONE" and .value.phase != "BLOCKED") | .key' \
    "$STATE_FILE" 2>/dev/null | sort || true
}

# slug_strike SLUG PHASE — bump PHASE's strike count for SLUG and print the new
# count. Argument order is SLUG first, PHASE second — the reverse of
# strike_count (phase, slug) — because callers already have the slug in hand
# first at every phase-failure site; do not swap them by pattern-matching
# strike_count's order.
slug_strike() {
  state_apply '.slugs[$s].strikes[$p] = ((.slugs[$s].strikes[$p] // 0) + 1)' --arg s "$1" --arg p "$2"
  jq -r --arg s "$1" --arg p "$2" '.slugs[$s].strikes[$p]' "$STATE_FILE"
}

