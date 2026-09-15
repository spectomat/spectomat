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

# Move to the git root (or stay put outside a repo); sets ROOT.
cd_root() {
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cd "$ROOT"
}

die() { echo "❌ $*" >&2; exit 1; }

# Number of .md files directly inside a floor directory (0 when it is missing).
count() { find "$1" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '; }

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

Launch exactly one subagent with the Agent tool: `run_in_background: false`, `subagent_type` set to the block's `subagent` field, and the body of the file named by `brief` — its own frontmatter stripped — as the brief.

The task handed to the subagent is the block phase.sh printed, verbatim, fences included. Do not reformat it, extract fields out of it, or drop any line — the subagent reads `phase:`, `slug:` and `plugin_root:` for itself.

## 3. Report and stop

Print the report in at most five lines, then stop. Never retry a failed iteration here — the next iteration is a new picker call and a new subagent. Write `<promise>FACTORY EMPTY</promise>` only when the block's `phase` was `FINISH`; it is a verdict you relay, never a judgement you make.
EOF
)
  printf '%s\n' "${body//\{\{PLUGIN_ROOT\}\}/$PLUGIN_ROOT}"
}

# True when $1 carries the completion promise. Whitespace is stripped from the
# haystack rather than parsed out of the tags, so any line breaks or indentation
# the model puts inside <promise>...</promise> still match. That also makes the
# test lenient about spacing within the words themselves, which costs nothing:
# no other wording ends the flow.
promised_empty() { [[ "${1//[[:space:]]/}" == *"<promise>FACTORYEMPTY</promise>"* ]]; }

# Failed attempts at one phase for one slug before that slug is blocked.
STRIKE_LIMIT=3

# The contract's gate commands, one per line: everything inside the first fenced
# block after the Verification Gates heading, minus comment and blank lines. A
# later fenced block in the file is not part of the gates.
gate_block() {
  [[ -f "$CONTRACT" ]] || return 0
  awk '
    /^## Verification Gates/ { seen = 1; next }
    seen && !finished && /^```/ {
      if (open) { open = 0; finished = 1 } else { open = 1 }
      next
    }
    open { print }
  ' "$CONTRACT" | grep -vE '^[[:space:]]*(#|$)'
  return 0
}

# Run every gate line in order, stopping at the first failure; sets GATE_FAILED
# to the command that failed. The lines are operator-authored shell from a file
# committed in their own repository, at the same trust level as a package.json
# script: eval is the interface, not a shortcut.
run_gates() {
  local cmd
  GATE_FAILED=""
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    if ! eval "$cmd"; then
      GATE_FAILED="$cmd"
      return 1
    fi
  done < <(gate_block)
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

# slug_delete SLUG — ARCHIVE finished (or blocked): drop the slug's entry.
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

