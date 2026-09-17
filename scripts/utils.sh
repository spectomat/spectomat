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
MEMORY="$FLOOR/memory.md"   # what the factory has learned about the codebase; committed
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
# Values are inserted literally - bash pattern substitution gives no meaning to
# & or \ in a replacement, which is why this needs no escaping pass. Keys are
# applied in the order given, so a value holding {{X}} is still expanded by a
# later X= argument.
render_template() {
  local src="$1" dest="$2" kv key val body
  shift 2
  body=$(cat "$src"; printf X)   # X guards the trailing newlines $() would strip
  body="${body%X}"
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    body="${body//\{\{$key\}\}/$val}"
  done
  printf '%s' "$body" > "$dest"
}

# The prompt the Stop hook feeds back every iteration, and what prepare.sh
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

# slug_start_tasks SLUG TOTAL — PLAN -> IMPLEMENT: phase, tasks_total, tasks_done=0.
slug_start_tasks() {
  state_apply '.slugs[$s].phase = "IMPLEMENT" | .slugs[$s].tasks_total = ($t | tonumber) | .slugs[$s].tasks_done = 0' \
    --arg s "$1" --arg t "$2"
}

# slug_task_done SLUG — IMPLEMENT, one task closed: bump tasks_done, and move to
# REVIEW once every task is done.
slug_task_done() {
  state_apply '
    .slugs[$s].tasks_done += 1
    | if .slugs[$s].tasks_done == .slugs[$s].tasks_total
      then .slugs[$s].phase = "REVIEW"
      else . end
  ' --arg s "$1"
}

# slug_add_tasks SLUG N — REVIEW PARKED: N fix tasks added, back to IMPLEMENT.
slug_add_tasks() {
  state_apply '.slugs[$s].tasks_total += ($n | tonumber) | .slugs[$s].phase = "IMPLEMENT"' \
    --arg s "$1" --arg n "$2"
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
# The file check comes first and the jq failure is swallowed: prepare.sh's
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

