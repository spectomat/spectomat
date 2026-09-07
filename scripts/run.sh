#!/bin/bash
# Spectomat run — prepare the factory floor and arm the unattended loop.
#
#   run.sh [MAX_ITERATIONS]
#
# Creates docs/.spectomat/{drafts,specs,plans,done}, renders factory.md from the
# template when absent, and arms the Stop hook with the factory pointer prompt.
# Default 100 iterations, promise "FACTORY EMPTY". Refuses when a loop is
# already active or there is no work at all.

set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STATE_FILE="docs/.spectomat/loop.md"
FLOOR="docs/.spectomat"
FACTORY="$FLOOR/factory.md"
COMPLETION_PROMISE="FACTORY EMPTY"
MAX_ITERATIONS=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "❌ unknown option: $1" >&2; exit 1 ;;
    *)
      [[ "$1" =~ ^[0-9]+$ ]] || { echo "❌ max iterations must be a number, got: $1" >&2; exit 1; }
      MAX_ITERATIONS="$1"; shift ;;
  esac
done

[[ -d .git ]] || { echo "❌ Not a git repository. The factory commits every unit; run 'git init' first." >&2; exit 1; }

mkdir -p "$FLOOR"/{drafts,specs,plans,done}
for IGN in "$STATE_FILE" "$FLOOR/work/"; do
  if ! { [[ -f .gitignore ]] && grep -qxF "$IGN" .gitignore; }; then
    printf '%s\n' "$IGN" >> .gitignore
    echo ".gitignore: added $IGN"
  fi
done
[[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"

GATES=""
if [[ -f package.json ]]; then
  for s in typecheck test lint synth; do
    if grep -qE "\"$s\"[[:space:]]*:" package.json; then
      if [[ "$s" == "test" ]]; then GATES+="npm test"$'\n'; else GATES+="npm run $s"$'\n'; fi
    fi
  done
fi
[[ -n "$GATES" ]] || GATES="# no gates detected - add one command per line, each must exit 0"$'\n'
GATES="${GATES%$'\n'}"

if [[ -f "$FACTORY" ]]; then
  echo "$FACTORY: exists, kept"
else
  REPO="$ROOT" GATES="$GATES" perl -pe 's/\{\{REPO\}\}/$ENV{REPO}/g; s/\{\{GATES\}\}/$ENV{GATES}/g;' "$TEMPLATES/factory.md" > "$FACTORY"
  echo "$FACTORY: written (gates: $(echo "$GATES" | tr '\n' ';'))"
fi

count() { find "$1" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' '; }
DRAFTS=$(count "$FLOOR/drafts"); SPECS=$(count "$FLOOR/specs"); PLANS=$(count "$FLOOR/plans"); DONE=$(count "$FLOOR/done")
echo "--- floor ---"
echo "drafts: $DRAFTS   specs: $SPECS   plans: $PLANS   done: $DONE"
git status --porcelain | head -5

if [[ -f "$STATE_FILE" ]]; then
  echo
  echo "❌ Not starting: a loop is already active ($STATE_FILE). Run /spectomat:cancel first."
  exit 1
fi
if [[ $((DRAFTS + SPECS + PLANS)) -eq 0 ]]; then
  echo
  echo "❌ Not starting: nothing to do. Drop a .md idea into $FLOOR/drafts/ and run /spectomat:run again."
  exit 1
fi

PROMPT="Read ./$FACTORY in full - it is the authoritative factory contract and may have been edited since your last iteration. Then follow its Loop Contract exactly: orient, pick exactly one unit of work (draft to spec, spec to plan, plan to task, plan to done), do it, verify, commit, log. One unit per iteration, then stop. Never ask the user anything."

cat > "$STATE_FILE" <<EOF
---
active: true
iteration: 1
session_id: ${CLAUDE_CODE_SESSION_ID:-}
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

cat <<EOF

🏭 Spectomat factory armed in this session.

Iteration: 1 of $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
State: $STATE_FILE
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
To finish, output <promise>$COMPLETION_PROMISE</promise> — ONLY when drafts/,
specs/ and plans/ are all empty and the tree is clean, verified this iteration.
Never output a false promise to escape.

$PROMPT
EOF
