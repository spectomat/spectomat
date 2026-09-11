#!/bin/bash
# Spectomat shared constants and helpers. Source it, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#
# Sets no shell options; each script chooses its own set -e/-u/pipefail.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOOR=".spectomat"
STATE_FILE="$FLOOR/state.md"
CONTRACT="$FLOOR/contract.md"
MEMORY="$FLOOR/memory.md"   # what the factory has learned about the codebase; committed
INC="$FLOOR/.inc"   # last intake number issued to a wish

# Move to the git root (or stay put outside a repo); sets ROOT.
cd_root() {
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cd "$ROOT"
}

die() { echo "❌ $*" >&2; exit 1; }

# Number of .md files directly inside a floor directory (0 when it is missing).
count() { find "$1" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '; }

# Value of a "key: value" line in the state file frontmatter; empty when absent.
state_field() {
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep "^$1:" | sed "s/$1: *//" || true
}

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
