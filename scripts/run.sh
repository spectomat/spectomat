#!/bin/bash
# Spectomat run — prepare the factory floor and arm the unattended loop.
#
#   run.sh [MAX_ITERATIONS]
#
# Creates docs/.spectomat/{drafts,specs,plans,done}, moves ./wishlist/*.md into
# drafts/, renders contract.md when absent, commits what it created (contract,
# ignore rules, new drafts), and arms the Stop hook with the state file from
# templates/state.md. Default 100 iterations, promise "FACTORY EMPTY". Refuses
# when a loop is already active or there is no work at all.

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
  ensure_gitignored "$FLOOR/work/"
  ensure_gitignored "$FLOOR/log.md"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
}

# Move wishes from ./wishlist/ into drafts/. A wish whose slug already exists in
# drafts/ waits.
intake_wishes() {
  local wish slug
  for wish in wishlist/*.md; do
    [[ -f "$wish" ]] || continue
    slug="$(basename "$wish")"
    if [[ -e "$FLOOR/drafts/$slug" ]]; then
      echo "wishlist: $slug kept, drafts/$slug already exists"
      continue
    fi
    mv "$wish" "$FLOOR/drafts/$slug"
    echo "wishlist: $slug moved to drafts/"
  done
}

# Stage .gitignore as "what the index had + the lines run.sh appended", leaving
# any other working-tree edit of the user unstaged.
stage_ignore_entries() {
  local base blob
  base="$(git show :.gitignore 2>/dev/null || true)"
  blob=$({ [[ -n "$base" ]] && printf '%s\n' "$base"; printf '%s\n' "${IGNORED[@]}"; } | git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$blob,.gitignore"
}

# Commit what this run created — contract, ignore rules, new drafts — so the
# loop starts on a clean tree. Nothing else of the user's is staged.
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

# Render contract.md from the template once; never overwrite a user-edited contract.
# {{GATES}} becomes a call to gates.sh; detect_gates only feeds the summary line.
render_factory() {
  if [[ -f "$CONTRACT" ]]; then
    echo "$CONTRACT: exists, kept"
  else
    render_template "$TEMPLATES/contract.md" "$CONTRACT" \
      REPO="$ROOT" \
      GATES="bash \"$PLUGIN_ROOT/scripts/gates.sh\""

    STAGE+=("$CONTRACT")
    detect_gates
    local gates="${GATES//$'\n'/; }"
    echo "$CONTRACT: written (gates: ${gates:-none detected})"
  fi
}

# Print floor counts and a short git status; sets DRAFTS/SPECS/PLANS/DONE.
report_floor() {
  DRAFTS=$(count "$FLOOR/drafts"); SPECS=$(count "$FLOOR/specs"); PLANS=$(count "$FLOOR/plans"); DONE=$(count "$FLOOR/done")
  echo "--- floor ---"
  echo "drafts: $DRAFTS   specs: $SPECS   plans: $PLANS   done: $DONE"
  git status --porcelain | head -5
}

# Refuse to arm when a loop is already active or there is nothing to work on.
require_startable() {
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
}

# Write the state file the Stop hook reads on every exit attempt.
write_state() {
  render_template "$TEMPLATES/state.md" "$STATE_FILE" \
    SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}" \
    MAX_ITERATIONS="$MAX_ITERATIONS" \
    STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

announce() {
  cat <<EOF

🏭 Spectomat factory armed in this session.

Iteration: 1 of $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
State: $STATE_FILE
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
To finish, output <promise>FACTORY EMPTY</promise> — ONLY when drafts/,
specs/ and plans/ are all empty and the tree is clean, verified this iteration.
Never output a false promise to escape.
EOF
  awk '/^---$/{i++; next} i>=2' "$STATE_FILE"
}

main() {
  parse_args "$@"
  require_git_repo
  prepare_floor
  intake_wishes
  render_factory
  commit_floor
  report_floor
  require_startable
  write_state
  announce
}

main "$@"
