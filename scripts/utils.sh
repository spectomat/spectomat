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
# Values are inserted literally; the env vars live only for the perl call.
render_template() {
  local src="$1" dest="$2" kv key expr=""
  shift 2
  local -a envs=()
  for kv in "$@"; do
    key="${kv%%=*}"
    envs+=("TPL_$key=${kv#*=}")
    expr+="s/\\{\\{$key\\}\\}/\$ENV{TPL_$key}/g;"
  done
  env ${envs[@]+"${envs[@]}"} perl -pe "$expr" "$src" > "$dest"
}
