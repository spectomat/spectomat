#!/bin/bash
# Spectomat shared constants and helpers. Source it, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#
# Sets no shell options; each script chooses its own set -e/-u/pipefail.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOOR=".spectomat"
STATE_FILE="$FLOOR/state.json"   # the flow's mutable state; gitignored
POINTER="$FLOOR/pointer.md"      # the prompt the Stop hook feeds back; gitignored
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

# Remove both halves of an armed flow. The state file is the armed flag; the
# pointer is its payload, and a pointer left behind would outlive its state.
disarm() { rm -f "$STATE_FILE" "$POINTER"; }

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

# How many times PHASE was struck on SLUG, per the factory log. The log
# is gitignored and append-only, so this is the only record of a strike. Both
# matches are fixed-string (grep -F), so a slug carrying regex metacharacters
# such as parentheses or an unclosed bracket is matched literally, never as a
# pattern: it cannot fail to compile and it cannot accidentally match less
# than the literal text.
strike_count() {
  local phase="$1" slug="$2" n
  [[ -f "$FLOOR/log.md" ]] || { echo 0; return 0; }
  n=$(grep -F " · $phase · $slug · " "$FLOOR/log.md" 2>/dev/null | grep -cF '(strike ') || n=0
  printf '%s\n' "${n// /}"
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

