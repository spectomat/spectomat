#!/bin/bash
# Spectomat run — prepare the factory floor and arm the unattended flow.
#
#   run.sh [MAX_LOOPS]
#
# Creates .spectomat/{drafts,specs,plans,done}, moves ./wishlist/*.md into
# drafts/ as NNN-<name>.md (oldest first, counter in .spectomat/.inc), renders
# contract.md and memory.md when absent, commits what it created (contract,
# memory, .inc, ignore rules, new drafts), and arms the Stop hook from
# templates/state.md. Default 100 loops, promise "FACTORY EMPTY". Refuses
# when a flow is already active or there is no work at all.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gates.sh"
cd_root
TEMPLATES="$PLUGIN_ROOT/templates"
MAX_LOOPS=100
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
        [[ "$1" =~ ^[0-9]+$ ]] || die "max loops must be a number, got: $1"
        MAX_LOOPS="$1"; shift ;;
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

# Move wishes from ./wishlist/ into drafts/, oldest modification first, each
# renamed to NNN-<name>.md so the alphabetical order the contract uses equals
# intake order. NNN continues from $INC, which holds the last number issued and
# is committed with the drafts. A wish whose name is already in drafts/ under
# any prefix waits and takes no number.
intake_wishes() {
  local wish name slug n start
  n=$(cat "$INC" 2>/dev/null || echo 0)
  [[ "$n" =~ ^[0-9]+$ ]] || die "$INC: expected a number, got: $n"
  n=$((10#$n)); start=$n
  while IFS= read -r wish; do
    [[ -f "$wish" ]] || continue
    name="$(basename "$wish")"
    if compgen -G "$FLOOR/drafts/[0-9]*-$name" > /dev/null || [[ -e "$FLOOR/drafts/$name" ]]; then
      echo "wishlist: $name kept, drafts/ already has it"
      continue
    fi
    n=$((n + 1))
    printf -v slug '%03d-%s' "$n" "$name"
    mv "$wish" "$FLOOR/drafts/$slug"
    echo "wishlist: $name moved to drafts/$slug"
  done < <(ls -tr wishlist/*.md 2>/dev/null)
  if [[ $n -ne $start ]]; then
    printf '%d\n' "$n" > "$INC"
    STAGE+=("$INC")
  fi
}

# Stage .gitignore as "what the index had + the lines run.sh appended", leaving
# any other working-tree edit of the user unstaged.
stage_ignore_entries() {
  local base blob
  base="$(git show :.gitignore 2>/dev/null || true)"
  blob=$({ [[ -n "$base" ]] && printf '%s\n' "$base"; printf '%s\n' "${IGNORED[@]}"; } | git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$blob,.gitignore"
}

# Commit what this run created — contract, memory, ignore rules, new drafts — so the
# flow starts on a clean tree. Nothing else of the user's is staged.
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
    if migrate_contract; then
      STAGE+=("$CONTRACT")
      echo "$CONTRACT: migrated to the phase-agent contract (gates preserved)"
    else
      echo "$CONTRACT: exists, kept"
    fi
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
}

# Write the state file the Stop hook reads on every exit attempt. PLUGIN_ROOT
# lets the pointer name agents/looper.md and references/ by absolute path.
write_state() {
  render_template "$TEMPLATES/state.md" "$STATE_FILE" \
    PLUGIN_ROOT="$PLUGIN_ROOT" \
    SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}" \
    MAX_LOOPS="$MAX_LOOPS" \
    STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

announce() {
  cat <<EOF

🏭 Spectomat factory armed in this session.

Loop: 1 of $(if [[ $MAX_LOOPS -gt 0 ]]; then echo "$MAX_LOOPS"; else echo "unlimited"; fi)
State: $STATE_FILE
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
Each loop asks scripts/phase.sh which phase applies and dispatches it.
The flow ends when the picker answers E, or at the loop cap.
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
