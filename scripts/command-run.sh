#!/bin/bash
# Spectomat run — set up the factory floor and arm the unattended flow.
#
#   command-run.sh [MAX_ITERATIONS]
#
# Creates .wishlist/, renders contract.md, memory.md and gates.sh when
# absent, moves each wish into its own slug dir .spectomat/<slug>/draft.md,
# commits what it created, and arms the Stop hook by writing state.json.
# Default 100 iterations. Refuses when a flow is armed or no unfinished slug remains.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$PLUGIN_ROOT/scripts/gates.sh"
cd_root
TEMPLATES="$PLUGIN_ROOT/templates"
MAX_ITERATIONS=100
STAGE=()     # files prepare.sh created this run, committed by commit_floor
IGNORED=()   # .gitignore lines prepare.sh appended this run, staged by commit_floor
INTAKEN=()   # slug dirs intake_wishes filled this run, committed by commit_floor

# --- helpers ---

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- phases ---

require_git_repo() {
  [[ -d .git ]] || die "Not a git repository. The factory commits every phase; run 'git init' first."
}

# Refuse to arm on a repo whose own gates are red. Only checks a gates.sh
# already rendered by a prior run — a floor with none yet has nothing to
# check here, and render_factory will compile one after this passes.
require_gates_passed() {
  run_gates || die "$GATE_FAILED failed. Fix the gates, then run /spectomat:run again."
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

# The inbox, the floor's ignore rules and the log file. Idempotent.
# .wishlist/ sits beside the floor, not in it: it is the operator's inbox.
# The log, the state file and work/ stay local: never committed.
prepare_floor() {
  mkdir -p "$FLOOR" "$WISHLIST"
  ensure_gitignored "$STATE_FILE"
  ensure_gitignored "$STATE_FILE.tmp.*"   # stop-hook.sh writes the counter through it
  ensure_gitignored "$FLOOR/work/"
  ensure_gitignored "$FLOOR/log.md"
  ensure_gitignored "$MEMORY"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
}

# The floor is slug-major: everything of one idea lives in .spectomat/<slug>/,
# named after the draft it came from. A directory directly under the floor is a
# slug dir when it holds at least one of draft.md, spec.md or plan.md — which
# work/ never does, so no reserved-name list is needed here.
#
# This is the flow's only directory scan (D27). It lives here rather than in
# utils.sh because prepare.sh is the intake boundary: after arming, every
# script reads state.json and nothing walks the floor again.
slug_dirs() {
  local d
  for d in "$FLOOR"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"
    if [[ -f "$d/draft.md" || -f "$d/spec.md" || -f "$d/plan.md" ]]; then
      printf '%s\n' "$(basename "$d")"
    fi
  done | sort
}

# Move every draft the operator dropped into .wishlist/ to its own slug dir, as
# <slug>/draft.md: the floor is slug-major, and .wishlist/ is a pure inbox that
# arming empties. The slug is the draft's file name without .md, unchanged.
#
# A draft may be tracked or untracked, so this uses a plain mv and lets
# commit_floor stage both sides with `git add -A`; `git mv` would fail on the
# untracked case. Runs before commit_floor, so the move lands in the same
# commit as the floor setup and the tree is clean when the flow arms.
#
# A slug dir that already exists is the operator re-dropping a name that is
# already in the flow: refuse rather than overwrite a draft mid-flight.
intake_wishes() {
  local f s
  for f in "$WISHLIST"/*.md; do
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
# both sides of each intake move (.wishlist/ for the removal, the slug dir for
# the new draft.md) and a spec or plan the operator wrote by hand, which is
# floor content just as a draft is. Nothing but the inbox and the floor is staged.
commit_floor() {
  local d
  git add -A "$WISHLIST" ${INTAKEN[@]+"${INTAKEN[@]}"} ${STAGE[@]+"${STAGE[@]}"}
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
    # Not staged: prepare_floor gitignored it, so it stays a local file shared
    # by every feat/<slug> branch rather than a per-branch copy.
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
      FLOOR_TEXT="$(cat "$PLUGIN_ROOT/references/floor.md")"
    STAGE+=("$CONTRACT")
    echo "$CONTRACT: written"
  fi
}

# Print floor counts and a short git status; sets ACTIVE. Runs after
# seed_state, so every slug dir has an entry and all three counts come from
# state.json — the scan has already done its one job by then.
report_floor() {
  ACTIVE=$(slugs_unfinished | wc -l | tr -d ' ')
  DONE=$(slugs_at_phase DONE | wc -l | tr -d ' ')
  BLOCKED=$(slugs_at_phase BLOCKED | wc -l | tr -d ' ')
  echo "--- floor ---"
  echo "active: $ACTIVE   done: $DONE   blocked: $BLOCKED"
  git status --porcelain | head -5
}

# Refuse before seed_state touches anything: an active flow belongs to another
# session, and this one must not write into its state.
require_no_active_flow() {
  if [[ -f "$STATE_FILE" ]] && [[ "$(state_field active)" == "true" ]]; then
    die "Not starting: a flow is already active ($STATE_FILE). Run /spectomat:cancel first."
  fi
}

# Refuse to arm when there is nothing to work on or the tree is dirty. Both
# refusals leave the seeded, unarmed state.json in place: it records only what
# the floor holds, and the next run re-seeds it.
require_startable() {
  if [[ "$ACTIVE" -eq 0 ]]; then
    die "Not starting: nothing to do. Drop a .md idea into $WISHLIST/ and run /spectomat:run again."
  fi
  # Whatever commit_floor did not commit is the user's own work in progress. The
  # picker answers RECOVER to any dirt, so arming now would send every iteration to the
  # janitor - which reports and stops rather than discarding work it does not own,
  # burning the whole cap.
  local dirt
  dirt="$(git status --porcelain)"
  if [[ -n "$dirt" ]]; then
    die "Not starting: the git tree is dirty."
  fi
}

# Read the floor into state.json: the flow's one and only directory scan (D27).
# Runs before report_floor, so every count that follows comes from state.json
# and the floor is never consulted about the flow again.
#
# Creates state.json when there is none. The flow is armed separately, by
# arm_flow after require_startable has approved it — seeding is safe to do on a
# floor that then refuses to arm, since it only records what the floor holds.
seed_state() {
  local s
  [[ -f "$STATE_FILE" ]] || printf '{"slugs": {}}\n' > "$STATE_FILE"
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -z "$(slug_phase "$s")" ]] || continue
    if [[ -f "$FLOOR/$s/done.md" ]]; then
      slug_add "$s" DONE
    elif [[ -f "$FLOOR/$s/blocked.md" ]]; then
      slug_add "$s" BLOCKED
    elif [[ -f "$FLOOR/$s/draft.md" && ! -f "$FLOOR/$s/spec.md" ]]; then
      slug_add "$s" SPECIFY
    elif [[ -f "$FLOOR/$s/spec.md" && ! -f "$FLOOR/$s/plan.md" ]]; then
      slug_add "$s" REVIEW-SPEC
    elif [[ -f "$(tasks_file "$s")" ]]; then
      # A planned slug re-entering the flow: the ledger is committed, so it
      # says by itself how far the plan got. Pending tasks left means
      # IMPLEMENT; none left means the plan is built and owed a REVIEW.
      if [[ "$(tasks_pending "$s")" == "0" ]]; then
        slug_add "$s" REVIEW
      else
        slug_add "$s" IMPLEMENT
      fi
    else
      printf '# %s — blocked\n\nArming could not classify this slug dir: its files match no phase.\n' \
        "$s" > "$FLOOR/$s/blocked.md"
      # commit_floor has already run, and arming must end on a clean tree or
      # the picker answers RECOVER to every iteration. A failure here is fatal
      # rather than skipped: require_startable would refuse on the dirt anyway,
      # and an uncommitted marker with a BLOCKED entry is the one state the
      # migration must never leave behind.
      git add -A "$FLOOR/$s" || die "could not stage $FLOOR/$s"
      git commit -q -m "chore($s): blocked, files match no phase" || die "could not commit $FLOOR/$s"
      slug_add "$s" BLOCKED
      echo "$FLOOR/$s: files match no phase, blocked"
    fi
  done < <(slug_dirs)
}

# One branch per unfinished slug, feat/<slug>, cut from the armed commit. This
# is the only place a branch is created: the phase agents check theirs out and
# never branch, and the operator merges finished work by hand.
#
# Runs after commit_floor and seed_state, so every branch carries the floor and
# every slug has a state entry to be judged unfinished by. Idempotent — a slug
# already branched by an earlier arming keeps its branch and whatever work is on
# it, so re-arming a floor mid-flight never rewinds a slug.
#
# Leaves HEAD where it was: the first iteration checks out the branch its picker
# names, and the operator's own branch is what the flow was armed from.
branch_slugs() {
  local s b
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    b="$(slug_branch "$s")"
    if git rev-parse --verify --quiet "refs/heads/$b" >/dev/null; then
      echo "branch $b: exists, kept"
    else
      git branch "$b" || die "could not create branch $b"
      echo "branch $b: created"
    fi
  done < <(slugs_unfinished)
}

main() {
  require_git_repo
  prepare_floor
  render_factory
  require_gates_passed
  intake_wishes
  commit_floor
  require_no_active_flow
  seed_state
  report_floor
  require_startable
  branch_slugs
  ask_picker
  # arm_flow
  state_apply '
    .active = true
    | .iteration = 1
    | .max_iterations = ($m | tonumber)
    | .session_id = $sid
    | .started_at = $now
    | .plugin_root = $root
    | '"$CURRENT_SET" \
    --arg m "$MAX_ITERATIONS" \
    --arg sid "${CLAUDE_CODE_SESSION_ID:-}" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg root "$PLUGIN_ROOT" \
    --arg p "$PICK_PHASE" \
    --arg s "$PICK_SLUG"
  echo "🏭 Spectomat flow is armed."
}

main "$@"
