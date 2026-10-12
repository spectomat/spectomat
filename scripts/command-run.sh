#!/bin/bash
# Spectomat run — set up the factory floor and arm the unattended flow.
#
#   command-run.sh [MAX_ITERATIONS]
#
# Creates .wishlist/, renders .gitignore, amendments.md, memory.md and gates.sh
# when absent, moves each wish into its own slug dir .spectomat/<slug>/draft.md,
# commits the operator's files, and arms the Stop hook by writing state.json.
# Default 100 iterations. Refuses when a flow is armed or no unfinished slug remains.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$PLUGIN_ROOT/scripts/gates.sh"
cd_root
TEMPLATES="$PLUGIN_ROOT/templates"
MAX_ITERATIONS=100
STAGE=()     # tracked floor files rendered this run, committed by commit_floor
INTAKEN=()   # slug dirs intake_wishes filled this run, counted in the commit message

# --- helpers ---

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- phases ---

require_git_repo() {
  [[ -d .git ]] || die "Not a git repository. The factory commits every task; run 'git init' first."
}

# Refuse to arm on a repo whose own gates are red. Only checks a gates.sh
# already rendered by a prior run — a floor with none yet has nothing to
# check here, and render_factory will compile one after this passes.
require_gates_passed() {
  run_gates || die "$GATE_FAILED failed. Fix the gates, then run /spectomat:run again."
}

# The inbox, the floor and the log file. Idempotent.
# .wishlist/ sits beside the floor, not in it: it is the operator's inbox.
prepare_floor() {
  mkdir -p "$FLOOR" "$WISHLIST"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
}

# The floor is slug-major: everything of one idea lives in .spectomat/<slug>/,
# named after the draft it came from. A directory directly under the floor is a
# slug dir when it holds at least one of draft.md, spec.md or plan.md.
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
# A draft may be tracked or untracked, so this uses a plain mv; `git mv` would
# fail on the untracked case, and the target is gitignored anyway. A tracked
# draft leaves a deletion behind, which commit_floor stages with `git add -A`,
# so the tree is clean when the flow arms.
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

# Commit what this run rendered on the tracked side of the floor — .gitignore,
# amendments.md, gates.sh — and the inbox's removals, so the flow starts on a
# clean tree. Slug dirs and memory.md are gitignored (D36): nothing to stage.
commit_floor() {
  git add -A "$WISHLIST" ${STAGE[@]+"${STAGE[@]}"}
  git diff --cached --quiet && return 0
  local n msg="chore(spectomat): floor setup"
  n=${#INTAKEN[@]}
  [[ $n -eq 0 ]] || msg+=", $n draft(s)"
  git commit -q -m "$msg"
  echo "committed: $(git log --oneline -1)"
}

# Render .gitignore, amendments.md, memory.md and gates.sh from the templates
# once; never overwrite what the project has edited. The gate commands compiled from
# package.json are rendered into gates.sh, so a later package.json change is
# edited into that script by hand. Each file is checked on its own, so a floor
# armed before one of them existed picks it up on the next run.
render_factory() {
  if [[ -f "$FLOOR_IGNORE" ]]; then
    echo "$FLOOR_IGNORE: exists, kept"
  else
    cp "$TEMPLATES/gitignore" "$FLOOR_IGNORE"
    STAGE+=("$FLOOR_IGNORE")
    echo "$FLOOR_IGNORE: written"
  fi

  if [[ -f "$AMENDMENTS" ]]; then
    echo "$AMENDMENTS: exists, kept"
  else
    render_template "$TEMPLATES/amendments.md" "$AMENDMENTS" REPO="$ROOT"
    STAGE+=("$AMENDMENTS")
    echo "$AMENDMENTS: written"
  fi

  if [[ -f "$MEMORY" ]]; then
    echo "$MEMORY: exists, kept"
  else
    render_template "$TEMPLATES/memory.md" "$MEMORY" REPO="$ROOT"
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

  # The contract lives in the plugin now; a floor copy is a leftover nobody reads.
  if [[ -f "$FLOOR/contract.md" ]]; then
    echo "⚠️ $FLOOR/contract.md is no longer read: move your edits into $AMENDMENTS, then delete it"
  fi
}

# Refuse a floor that git still tracks beyond its three operator files: an
# older flow committed it. Checking out a branch that tracks a now-ignored file
# silently overwrites the local copy, and leaving one deletes it. Checks HEAD
# and every feat/* branch, since the phases check those out.
require_untracked_floor() {
  local ref tracked
  tracked=$(
    for ref in HEAD $(git for-each-ref --format='%(refname:short)' 'refs/heads/feat/'); do
      git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || continue
      git ls-tree -r --name-only "$ref" -- "$FLOOR" \
        | { grep -vxF -e "$FLOOR_IGNORE" -e "$AMENDMENTS" -e "$GATES_SH" || true; } \
        | sed "s|^|$ref: |"
    done
  )
  [[ -z "$tracked" ]] && return 0
  printf '%s\n' "$tracked" | head -5 >&2
  die "Not starting: git still tracks floor files, and the floor is now local (D36). Merge or delete the feat/* branches listed, then on your branch: git rm -r -q --cached $FLOOR && git add $FLOOR && git commit -m 'chore(spectomat): untrack the floor'"
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
      # A planned slug re-entering the flow: the ledger is on the floor, so it
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
      slug_add "$s" BLOCKED
      echo "$FLOOR/$s: files match no phase, blocked"
    fi
  done < <(slug_dirs)
}

# One branch per unfinished slug, feat/<slug>, cut from the armed commit. This
# is the only place a branch is created: the phase agents check theirs out and
# never branch, and the operator merges finished work by hand.
#
# Runs after commit_floor and seed_state, so every branch carries the
# operator's floor files and every slug has a state entry to be judged
# unfinished by. The rest of the floor is gitignored and shared by them all. Idempotent — a slug
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
  require_untracked_floor
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
