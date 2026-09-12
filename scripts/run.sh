#!/bin/bash
# Spectomat run — prepare the factory floor and arm the unattended flow.
#
#   run.sh [MAX_ITERATIONS]
#
# Creates .spectomat/{drafts,specs,plans,done}, renders contract.md and
# memory.md when absent, commits what it created (contract, memory, ignore
# rules, drafts the user dropped in), and arms the Stop hook by writing
# state.json and rendering templates/pointer.md. Default 100 iterations, the
# promise "FACTORY EMPTY". Refuses when a flow is armed or the floor is empty.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gates.sh"
cd_root
TEMPLATES="$PLUGIN_ROOT/templates"
MAX_ITERATIONS=100
STAGE=()     # files run.sh created this run, committed by commit_floor
IGNORED=()   # .gitignore lines run.sh appended this run, staged by commit_floor

# --- helpers ---

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- phases ---

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -*) die "unknown option: $1" ;;
      *)
        [[ "$1" =~ ^[0-9]+$ ]] || die "max iterations must be a number, got: $1"
        MAX_ITERATIONS="$1"; shift ;;
    esac
  done
}

require_git_repo() {
  [[ -d .git ]] || die "Not a git repository. The factory commits every phase; run 'git init' first."
}

# Add a line to .gitignore unless it is already present verbatim.
ensure_gitignored() {
  local entry="$1"
  if ! { [[ -f .gitignore ]] && grep -qxF "$entry" .gitignore; }; then
    printf '%s\n' "$entry" >> .gitignore
    echo ".gitignore: added $entry"
    IGNORED+=("$entry")
  fi
}

# Floor directories, ignore rules and the log file. Idempotent.
# The log, the state file and work/ stay local: never committed.
prepare_floor() {
  mkdir -p "$FLOOR"/{drafts,specs,plans,done}
  ensure_gitignored "$STATE_FILE"
  ensure_gitignored "$STATE_FILE.tmp.*"   # stop-hook.sh writes the counter through it
  ensure_gitignored "$POINTER"
  ensure_gitignored "$FLOOR/work/"
  ensure_gitignored "$FLOOR/log.md"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
}

# Stage .gitignore as "what the index had + the lines run.sh appended", leaving
# any other working-tree edit of the user unstaged.
stage_ignore_entries() {
  local base blob
  base="$(git show :.gitignore 2>/dev/null || true)"
  blob=$({ [[ -n "$base" ]] && printf '%s\n' "$base"; printf '%s\n' "${IGNORED[@]}"; } | git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$blob,.gitignore"
}

# Commit what this run created — contract, memory, ignore rules — plus whatever
# the user dropped into drafts/, so the flow starts on a clean tree. Nothing else
# of the user's is staged.
commit_floor() {
  git add "$FLOOR/drafts" ${STAGE[@]+"${STAGE[@]}"}
  [[ ${#IGNORED[@]} -eq 0 ]] || stage_ignore_entries
  git diff --cached --quiet && return 0
  local n msg="chore(spectomat): floor setup"
  n=$(git diff --cached --name-only -- "$FLOOR/drafts" | wc -l | tr -d ' ')
  [[ $n -eq 0 ]] || msg+=", $n draft(s)"
  git commit -q -m "$msg"
  echo "committed: $(git log --oneline -1)"
}

# Render contract.md and memory.md from the templates once; never overwrite what
# the project has edited. The gate command compiled from package.json is rendered
# into the contract's Verification Gates block, so a later package.json change is
# edited into the contract by hand. Each file is checked on its own, so a floor
# armed before memory.md existed picks it up on the next run.
render_factory() {
  if [[ -f "$MEMORY" ]]; then
    echo "$MEMORY: exists, kept"
  else
    render_template "$TEMPLATES/memory.md" "$MEMORY" REPO="$ROOT"
    STAGE+=("$MEMORY")
    echo "$MEMORY: written"
  fi

  if [[ -f "$CONTRACT" ]]; then
    echo "$CONTRACT: exists, kept"
  else
    detect_gates
    echo "gates: ${GATES:-none detected}"
    render_template "$TEMPLATES/contract.md" "$CONTRACT" \
      REPO="$ROOT" \
      GATES="${GATES:-echo \"❌ no gates: package.json defines no gates, typecheck, test, lint or build script\"}"

    STAGE+=("$CONTRACT")
    echo "$CONTRACT: written"
  fi
}

# Print floor counts and a short git status; sets DRAFTS/SPECS/PLANS/DONE.
report_floor() {
  DRAFTS=$(count "$FLOOR/drafts"); SPECS=$(count "$FLOOR/specs"); PLANS=$(count "$FLOOR/plans"); DONE=$(count "$FLOOR/done")
  echo "--- floor ---"
  echo "drafts: $DRAFTS   specs: $SPECS   plans: $PLANS   done: $DONE"
  git status --porcelain | head -5
}

# Refuse to arm when a flow is already active or there is nothing to work on.
require_startable() {
  if [[ -f "$STATE_FILE" ]]; then
    echo
    echo "❌ Not starting: a flow is already active ($STATE_FILE). Run /spectomat:cancel first."
    exit 1
  fi
  if [[ $((DRAFTS + SPECS + PLANS)) -eq 0 ]]; then
    echo
    echo "❌ Not starting: nothing to do. Drop a .md idea into $FLOOR/drafts/ and run /spectomat:run again."
    exit 1
  fi
  # Whatever commit_floor did not commit is the user's own work in progress. The
  # picker answers R to any dirt, so arming now would send every iteration to the
  # janitor - which reports and stops rather than discarding work it does not own,
  # burning the whole cap.
  local dirt
  dirt="$(git status --porcelain)"
  if [[ -n "$dirt" ]]; then
    echo
    echo "❌ Not starting: the tree is dirty. Every iteration would go to the janitor."
    printf '%s\n' "$dirt" | head -10
    echo "Commit or stash the above, then run /spectomat:run again."
    exit 1
  fi
}

# Arm the flow: the state the Stop hook reads on every exit attempt, and the
# pointer it feeds back. Both are written on every run, so a pointer holding a
# stale PLUGIN_ROOT - the plugin reinstalled at a new cache path - is replaced
# rather than migrated. The state is four fields, so it is written here instead
# of rendered from a template. MAX_ITERATIONS is unquoted in the JSON;
# parse_args has already required it to match ^[0-9]+$.
arm_flow() {
  cat > "$STATE_FILE" <<EOF
{
  "iteration": 1,
  "max_iterations": $MAX_ITERATIONS,
  "session_id": "${CLAUDE_CODE_SESSION_ID:-}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  render_template "$TEMPLATES/pointer.md" "$POINTER" \
    PLUGIN_ROOT="$PLUGIN_ROOT"
}

announce() {
  cat <<EOF

🏭 Spectomat factory armed in this session.

Iteration: 1 of $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
State: $STATE_FILE
Pointer: $POINTER
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
Each iteration asks scripts/phase.sh which phase applies and dispatches it.
The flow ends when the picker answers E, or at the iteration cap.
EOF
  cat "$POINTER"
}

main() {
  parse_args "$@"
  require_git_repo
  prepare_floor
  render_factory
  commit_floor
  report_floor
  require_startable
  arm_flow
  announce
}

main "$@"
