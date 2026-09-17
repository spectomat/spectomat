#!/bin/bash
# Spectomat prepare — set up the factory floor and arm the unattended flow.
#
#   prepare.sh [MAX_ITERATIONS]
#
# Creates .spectomat/drafts/, renders contract.md, memory.md and gates.sh when
# absent, moves each draft into its own slug dir .spectomat/<slug>/draft.md,
# commits what it created, and arms the Stop hook by writing state.json.
# Default 100 iterations. Refuses when a flow is armed or no unfinished slug remains.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gates.sh"
cd_root
TEMPLATES="$PLUGIN_ROOT/templates"
MAX_ITERATIONS=100
STAGE=()     # files prepare.sh created this run, committed by commit_floor
IGNORED=()   # .gitignore lines prepare.sh appended this run, staged by commit_floor
INTAKEN=()   # slug dirs intake_drafts filled this run, committed by commit_floor

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
  mkdir -p "$FLOOR/drafts"
  ensure_gitignored "$STATE_FILE"
  ensure_gitignored "$STATE_FILE.tmp.*"   # stop-hook.sh writes the counter through it
  ensure_gitignored "$FLOOR/work/"
  ensure_gitignored "$FLOOR/log.md"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
}

# Move every draft the operator dropped into drafts/ to its own slug dir, as
# <slug>/draft.md: the floor is slug-major, and drafts/ is a pure inbox that
# arming empties. The slug is the draft's file name without .md, unchanged.
#
# A draft may be tracked or untracked, so this uses a plain mv and lets
# commit_floor stage both sides with `git add -A`; `git mv` would fail on the
# untracked case. Runs before commit_floor, so the move lands in the same
# commit as the floor setup and the tree is clean when the flow arms.
#
# A slug dir that already exists is the operator re-dropping a name that is
# already in the flow: refuse rather than overwrite a draft mid-flight.
intake_drafts() {
  local f s
  for f in "$FLOOR"/drafts/*.md; do
    [[ -f "$f" ]] || continue
    s="$(basename "$f" .md)"
    [[ ! -e "$FLOOR/$s" ]] || die "$FLOOR/$s already exists: rename $f or clear that slug first"
    mkdir -p "$FLOOR/$s"
    mv "$f" "$FLOOR/$s/draft.md"
    INTAKEN+=("$FLOOR/$s")
    echo "$f -> $FLOOR/$s/draft.md"
  done
}

# Stage .gitignore as "what the index had + the lines prepare.sh appended", leaving
# any other working-tree edit of the user unstaged.
stage_ignore_entries() {
  local base blob
  base="$(git show :.gitignore 2>/dev/null || true)"
  blob=$({ [[ -n "$base" ]] && printf '%s\n' "$base"; printf '%s\n' "${IGNORED[@]}"; } | git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$blob,.gitignore"
}

# Commit what this run created — contract, memory, gates, ignore rules — plus
# every slug dir on the floor, so the flow starts on a clean tree. That covers
# both sides of each intake move (drafts/ for the removal, the slug dir for the
# new draft.md) and a spec or plan the operator wrote by hand, which is floor
# content just as a draft is. Nothing outside the floor is staged.
commit_floor() {
  local d
  git add -A "$FLOOR/drafts" ${INTAKEN[@]+"${INTAKEN[@]}"} ${STAGE[@]+"${STAGE[@]}"}
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    git add -A "$FLOOR/$d"
  done < <(slug_dirs)
  [[ ${#IGNORED[@]} -eq 0 ]] || stage_ignore_entries
  git diff --cached --quiet && return 0
  local n msg="chore(spectomat): floor setup"
  n=${#INTAKEN[@]}
  [[ $n -eq 0 ]] || msg+=", $n draft(s)"
  git commit -q -m "$msg"
  echo "committed: $(git log --oneline -1)"
}

# Render contract.md, memory.md and gates.sh from the templates once; never
# overwrite what the project has edited. The gate commands compiled from
# package.json are rendered into gates.sh, so a later package.json change is
# edited into that script by hand. Each file is checked on its own, so a floor
# armed before memory.md or gates.sh existed picks it up on the next run.
render_factory() {
  if [[ -f "$MEMORY" ]]; then
    echo "$MEMORY: exists, kept"
  else
    render_template "$TEMPLATES/memory.md" "$MEMORY" REPO="$ROOT"
    STAGE+=("$MEMORY")
    echo "$MEMORY: written"
  fi

  if [[ -f "$GATES_SH" ]]; then
    echo "$GATES_SH: exists, kept"
  else
    detect_gates
    if [[ -n "$GATES" ]]; then
      echo "gates:"
      printf '%s\n' "$GATES" | sed 's/^/  /'
    else
      echo "gates: none detected"
    fi
    render_template "$TEMPLATES/gates.sh" "$GATES_SH" \
      REPO="$ROOT" \
      GATES="${GATES:-$GATES_NONE}"
    chmod +x "$GATES_SH"
    STAGE+=("$GATES_SH")
    echo "$GATES_SH: written"
  fi

  if [[ -f "$CONTRACT" ]]; then
    echo "$CONTRACT: exists, kept"
  else
    render_template "$TEMPLATES/contract.md" "$CONTRACT" \
      REPO="$ROOT" \
      FLOOR_TEXT="$(cat "$PLUGIN_ROOT/docs/floor.md")"
    STAGE+=("$CONTRACT")
    echo "$CONTRACT: written"
  fi
}

# Print floor counts and a short git status; sets ACTIVE and DONE. Runs after
# intake_drafts, so drafts/ is empty by now and every idea is a slug dir.
report_floor() {
  ACTIVE=$(slug_active_dirs | wc -l | tr -d ' ')
  DONE=$(slugs_marked done.md | wc -l | tr -d ' ')
  BLOCKED=$(slugs_marked blocked.md | wc -l | tr -d ' ')
  echo "--- floor ---"
  echo "active: $ACTIVE   done: $DONE   blocked: $BLOCKED"
  git status --porcelain | head -5
}

# Refuse to arm when a flow is already active or there is nothing to work on.
require_startable() {
  if [[ -f "$STATE_FILE" ]] && [[ "$(state_field active)" == "true" ]]; then
    echo
    echo "❌ Not starting: a flow is already active ($STATE_FILE). Run /spectomat:cancel first."
    exit 1
  fi
  if [[ "$ACTIVE" -eq 0 ]]; then
    echo
    echo "❌ Not starting: nothing to do. Drop a .md idea into $FLOOR/drafts/ and run /spectomat:run again."
    exit 1
  fi
  # Whatever commit_floor did not commit is the user's own work in progress. The
  # picker answers RECOVER to any dirt, so arming now would send every iteration to the
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

# Arm the flow: the state the Stop hook reads on every exit attempt. Resume a
# cancelled (inactive) state if one exists, else create fresh. MAX_ITERATIONS
# is unquoted in the JSON; parse_args has already required it to match
# ^[0-9]+$.
arm_flow() {
  local s
  if [[ -f "$STATE_FILE" ]]; then
    state_apply '
      .active = true
      | .iteration = 1
      | .max_iterations = ($m | tonumber)
      | .session_id = $sid
      | .started_at = $now
      | .slugs = (.slugs // {})
    ' --arg m "$MAX_ITERATIONS" --arg sid "${CLAUDE_CODE_SESSION_ID:-}" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    cat > "$STATE_FILE" <<EOF
{
  "active": true,
  "iteration": 1,
  "max_iterations": $MAX_ITERATIONS,
  "session_id": "${CLAUDE_CODE_SESSION_ID:-}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slugs": {}
}
EOF
  fi

  # Every unfinished slug dir with no state entry enters the flow at the stage
  # its files place it: a draft intake_drafts just moved in starts at SPECIFY,
  # and a spec the operator wrote by hand starts at REVIEW-SPEC. A dir the
  # files do not place — a plan with no spec, say — is left untracked on
  # purpose: the picker's orphan check answers RECOVER and the janitor rules
  # on it, which is the one path that can write to a floor it does not
  # understand.
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -z "$(slug_phase "$s")" ]] || continue
    if [[ -f "$FLOOR/$s/draft.md" && ! -f "$FLOOR/$s/spec.md" ]]; then
      slug_add "$s" SPECIFY
    elif [[ -f "$FLOOR/$s/spec.md" && ! -f "$FLOOR/$s/plan.md" ]]; then
      slug_add "$s" REVIEW-SPEC
    fi
  done < <(slug_active_dirs)
}

announce() {
  cat <<EOF
  
🏭 Spectomat code development flow is armed in this session.

Iteration: 1 of $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
State: $STATE_FILE
Cancel: /spectomat:cancel

When you try to exit, the Stop hook feeds the prompt below back to you.
Each iteration asks scripts/phase.sh which phase applies and dispatches it.
The flow ends when the picker answers FINISH, or at the iteration cap.
EOF
}

main() {
  parse_args "$@"
  require_git_repo
  prepare_floor
  render_factory
  intake_drafts
  commit_floor
  report_floor
  require_startable
  arm_flow
  announce
  pointer_prompt
}

main "$@"
