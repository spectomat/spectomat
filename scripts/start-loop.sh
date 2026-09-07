#!/bin/bash
# Spectomat start-loop — run the preflight, then arm the Stop hook.
#
#   start-loop.sh [MAX_ITERATIONS] [--completion-promise TEXT]
#
# Defaults: 30 iterations, promise "DONE". Refuses to start when the preflight
# verdict is NOT READY or a loop is already active in this project.
# State-file format derived from Anthropic's ralph-loop plugin (Apache-2.0);
# see NOTICE.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STATE_FILE=".claude/spectomat-loop.local.md"

MAX_ITERATIONS=30
COMPLETION_PROMISE="DONE"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --completion-promise)
      [[ -n "${2:-}" ]] || { echo "❌ --completion-promise needs a text" >&2; exit 1; }
      COMPLETION_PROMISE="$2"; shift 2 ;;
    --max-iterations)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "❌ --max-iterations needs a number" >&2; exit 1; }
      MAX_ITERATIONS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "❌ unknown option: $1" >&2; exit 1 ;;
    *)
      [[ "$1" =~ ^[0-9]+$ ]] || { echo "❌ max iterations must be a number, got: $1" >&2; exit 1; }
      MAX_ITERATIONS="$1"; shift ;;
  esac
done

PREFLIGHT=$(bash "$HERE/preflight.sh")
echo "$PREFLIGHT"
if ! echo "$PREFLIGHT" | tail -1 | grep -qx 'READY'; then
  echo
  echo "❌ Not starting: fix the items above, then run /spectomat:build again."
  exit 1
fi

if [[ -f "$STATE_FILE" ]]; then
  echo
  echo "❌ Not starting: a loop is already active ($STATE_FILE). Run /spectomat:cancel first."
  exit 1
fi

PROMPT='Read ./ralph-loop-prompt.md in full - it is the authoritative loop spec and may have been edited since your last iteration. Then follow its Loop Contract exactly: orient, claim the first unchecked ledger item, do that one item, verify, commit, record. One item per iteration, then stop.'

mkdir -p .claude
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

🔄 Spectomat loop armed in this session.

Iteration: 1 of $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
State: $STATE_FILE
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
To finish the loop, output <promise>$COMPLETION_PROMISE</promise> — ONLY when
the Completion Gate in ralph-loop-prompt.md is genuinely satisfied. Never
output a false promise to escape, even if you believe you are stuck.

$PROMPT
EOF
