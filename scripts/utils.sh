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

# The floor is slug-major: everything of one idea lives in .spectomat/<slug>/,
# named after the draft it came from. A directory directly under the floor is a
# slug dir when it holds at least one of draft.md, spec.md or plan.md — which
# drafts/ and work/ never do, so no reserved-name list is needed here.
slug_dirs() {
  local d
  for d in "$FLOOR"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"
    if [[ -f "$d/draft.md" || -f "$d/spec.md" || -f "$d/plan.md" ]]; then
      printf '%s\n' "$(basename "$d")"
    fi
  done | sort
}

# True when a slug is finished: ARCHIVE wrote done.md, or a third strike wrote
# blocked.md. Nothing moves when a slug finishes, so this marker is the only
# thing that tells a finished slug dir from a working one. The two markers
# never coexist.
slug_finished() {
  [[ -f "$FLOOR/$1/done.md" || -f "$FLOOR/$1/blocked.md" ]]
}

# The slugs still in the flow: every slug dir the markers do not claim. This is
# what the picker walks, so a finished slug never re-enters a stage.
slug_active_dirs() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    slug_finished "$s" || printf '%s\n' "$s"
  done < <(slug_dirs)
}

# Slugs whose dir carries MARKER ("done.md" or "blocked.md"), alphabetically.
# The closing report and /spectomat:status both count finished slugs this way.
slugs_marked() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -f "$FLOOR/$s/$1" ]] && printf '%s\n' "$s"
  done < <(slug_dirs)
  return 0
}

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

# slug_delete SLUG — the slug is finished (done.md or blocked.md written):
# drop its entry, so the picker stops counting it as work in the flow.
slug_delete() {
  state_apply 'del(.slugs[$s])' --arg s "$1"
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

