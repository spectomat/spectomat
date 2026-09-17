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
  ) >/dev/null 2>&1
  # Captured before arming, so "arming leaves HEAD alone" compares against the
  # real starting branch rather than a guess at git's default name.
  HEAD_BEFORE="$(cd "$R" && git rev-parse --abbrev-ref HEAD)"
  ( cd "$R" && bash "$SCRIPTS/prepare.sh" 3 ) >/dev/null 2>&1
}
# gate_lines — the rendered script minus its comments and blank lines.
gate_lines() { grep -vE '^[[:space:]]*(#|$)' "$R/.spectomat/gates.sh" | grep -v '^set -e$' | grep -v '^cd ' | tr '\n' '|'; }

repo npm '{"name":"x","scripts":{"typecheck":"tsc --noEmit","lint":"eslint .","test":"vitest run"}}'
is "npm scripts become gate lines"  "$(gate_lines)" "npm run typecheck|npm run lint|npm test|"
is "the script is executable"       "$([[ -x "$R/.spectomat/gates.sh" ]] && echo yes || echo no)" "yes"
# The detected gates are real commands: with no node_modules they fail, and the
# script must report that rather than exiting 0 on a gate it could not run.
( cd "$R" && ./.spectomat/gates.sh >/dev/null 2>&1 ); is "a failing gate exits non-zero" "$([[ $? -eq 0 ]] && echo zero || echo nonzero)" "nonzero"
# ...and a red gate is exactly why that repo never armed: require_gates_passed
# refuses before commit_floor. So what arming commits is asserted on a repo
# whose gates are green, below.

# Rendering commits the floor — but only on a repo that arms, which means green
# gates. `true` is a real command that passes, standing in for a repo whose
# checks are actually installed.
repo green '{"name":"x","scripts":{"gates":"true"}}'
is "a green floor arms"            "$(gate_lines)" "npm run gates|"
is "it is committed executable"    "$(cd "$R" && git ls-files -s .spectomat/gates.sh | cut -d' ' -f1)" "100755"
is "rendering leaves a clean tree" "$(cd "$R" && git status --porcelain)" ""
is "the contract is committed"     "$(cd "$R" && git ls-files .spectomat/contract.md)" ".spectomat/contract.md"
# memory.md is gitignored so one memory is shared by every feat/<slug> branch.
is "memory.md is not committed"    "$(cd "$R" && git ls-files .spectomat/memory.md)" ""
is "memory.md exists on disk"      "$([[ -f "$R/.spectomat/memory.md" ]] && echo yes || echo no)" "yes"
# Arming cuts one branch per slug and leaves HEAD where it found it.
is "the slug is branched"          "$(cd "$R" && git rev-parse --verify --quiet refs/heads/feat/001-thing >/dev/null && echo yes || echo no)" "yes"
# Compared against the branch the repo was on before arming, not a hardcoded
# name: git's default branch differs by version and user config.
is "arming leaves HEAD alone"      "$(cd "$R" && git rev-parse --abbrev-ref HEAD)" "$HEAD_BEFORE"

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
