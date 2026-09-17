#!/bin/bash
# prepare.sh renders .spectomat/gates.sh — once, from package.json, executable,
# and never over an existing one.
#
#   tests/gates_render_test.sh              tests ../scripts
#   tests/gates_render_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "gates.sh render"

# repo NAME [package.json body] — a git repo with one draft, armed by prepare.sh.
repo() {
  R="$TMP/gr-$1"
  mkdir -p "$R/.spectomat/drafts"
  (
    cd "$R" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    [[ $# -lt 2 ]] || printf '%s\n' "$2" > package.json
    printf 'idea\n' > .spectomat/drafts/001-thing.md
    git add -A
    git commit -qm init
    bash "$SCRIPTS/prepare.sh" 3
  ) >/dev/null 2>&1
}
# gate_lines — the rendered script minus its comments and blank lines.
gate_lines() { grep -vE '^[[:space:]]*(#|$)' "$R/.spectomat/gates.sh" | grep -v '^set -e$' | grep -v '^cd ' | tr '\n' '|'; }

repo npm '{"name":"x","scripts":{"typecheck":"tsc --noEmit","lint":"eslint .","test":"vitest run"}}'
is "npm scripts become gate lines"  "$(gate_lines)" "npm run typecheck|npm run lint|npm test|"
is "the script is executable"       "$([[ -x "$R/.spectomat/gates.sh" ]] && echo yes || echo no)" "yes"
is "it is committed executable"     "$(cd "$R" && git ls-files -s .spectomat/gates.sh | cut -d' ' -f1)" "100755"
is "rendering leaves a clean tree"  "$(cd "$R" && git status --porcelain)" ""
# The detected gates are real commands: with no node_modules they fail, and the
# script must report that rather than exiting 0 on a gate it could not run.
( cd "$R" && ./.spectomat/gates.sh >/dev/null 2>&1 ); is "a failing gate exits non-zero" "$([[ $? -eq 0 ]] && echo zero || echo nonzero)" "nonzero"

repo gatesscript '{"name":"x","scripts":{"gates":"make check","typecheck":"tsc","test":"vitest"}}'
is "a gates script is the single gate" "$(gate_lines)" "npm run gates|"

repo bare
is "no package.json is an honest no-op" "$(gate_lines)" 'echo "ok: no gates yet — add them above"|'
( cd "$R" && ./.spectomat/gates.sh >/dev/null 2>&1 ); is "the no-op exits 0" "$?" "0"

# A second run must not overwrite what the operator edited.
printf '#!/bin/bash\nset -e\necho mine\n' > "$R/.spectomat/gates.sh"
( cd "$R" && git commit -qam edit && bash "$SCRIPTS/prepare.sh" 3 ) >/dev/null 2>&1
is "an edited gates.sh is kept" "$(gate_lines)" "echo mine|"

finish
