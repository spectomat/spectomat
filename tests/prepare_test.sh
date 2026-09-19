#!/bin/bash
# command-run.sh — arms and refuses to arm the floor; commits wishes; arm writes
# state.json, cancel marks it inactive without touching the floor.
#
#   tests/prepare_test.sh              tests ../scripts
#   tests/prepare_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Arming a floor must leave a clean tree. The picker reads `git status` and
# answers RECOVER to any dirt, so a draft the user dropped into .wishlist/ must be
# moved into its slug dir and committed by command-run.sh, or iteration 1 burns on
# the janitor.
echo "command-run.sh wishlist"

# One `git init` for every case below, copied like floor() does.
REPO_TEMPLATE="$TMP/repo-template"
mkdir -p "$REPO_TEMPLATE"
(
  cd "$REPO_TEMPLATE" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'x\n' > README.md
  git add README.md
  git commit -qm init
) >/dev/null 2>&1

# Drop an untracked draft on the floor: command-run.sh commits it and arms.
DROP="$TMP/drop"
mkdir -p "$DROP"
cp -R "$REPO_TEMPLATE/." "$DROP"
mkdir -p "$DROP/.wishlist"
printf 'idea\n' > "$DROP/.wishlist/001-thing.md"
(cd "$DROP" && bash "$SCRIPTS/command-run.sh" 3) >/dev/null 2>&1
is "a dropped draft leaves a clean tree" "$(cd "$DROP" && git status --porcelain)" ""
is "the draft moves into its slug dir" "$([[ -f "$DROP/.spectomat/001-thing/draft.md" ]] && echo yes || echo no)" "yes"
is ".wishlist/ is emptied by arming"   "$(ls "$DROP/.wishlist" | wc -l | tr -d ' ')" "0"
is "the draft is committed at its new path" "$(cd "$DROP" && git log -1 --name-only --format= | grep -c '001-thing/draft.md')" "1"
is "iteration 1 is SPECIFY"     "$(verdict "$DROP" "$SCRIPTS")" "SPECIFY 001-thing"

# A draft the user already committed leaves nothing to stage; arming must still
# succeed and reach SPECIFY.
DROP2="$TMP/drop-committed"
mkdir -p "$DROP2"
cp -R "$REPO_TEMPLATE/." "$DROP2"
mkdir -p "$DROP2/.wishlist"
(
  cd "$DROP2" || exit 1
  printf 'idea\n' > .wishlist/001-thing.md
  git add .wishlist/001-thing.md
  git commit -qm draft
) >/dev/null 2>&1
(cd "$DROP2" && bash "$SCRIPTS/command-run.sh" 3) >/dev/null 2>&1
is "a committed draft arms cleanly" "$(cd "$DROP2" && git status --porcelain)" ""
is "a committed draft reaches SPECIFY" "$(verdict "$DROP2" "$SCRIPTS")" "SPECIFY 001-thing"

# A spec the operator wrote by hand has no draft to arm from, so arming must
# place it at REVIEW-SPEC itself; otherwise the slug dir has no state entry and
# the picker's orphan check sends every iteration to the janitor.
HAND="$TMP/handspec"
mkdir -p "$HAND"
cp -R "$REPO_TEMPLATE/." "$HAND"
mkdir -p "$HAND/.spectomat/001-mine"
printf 'spec\n' > "$HAND/.spectomat/001-mine/spec.md"
(cd "$HAND" && bash "$SCRIPTS/command-run.sh" 3) >/dev/null 2>&1
is "a hand-written spec arms cleanly"    "$(cd "$HAND" && git status --porcelain)" ""
is "a hand-written spec reaches REVIEW-SPEC" "$(verdict "$HAND" "$SCRIPTS")" "REVIEW-SPEC 001-mine"

# Unrelated work in progress would make the picker answer RECOVER every iteration, so
# command-run.sh refuses to arm rather than spend the whole cap on the janitor.
DIRTY="$TMP/dirty"
mkdir -p "$DIRTY"
cp -R "$REPO_TEMPLATE/." "$DIRTY"
mkdir -p "$DIRTY/.wishlist"
printf 'idea\n' > "$DIRTY/.wishlist/001-thing.md"
printf 'edited\n' > "$DIRTY/README.md"
out=$(cd "$DIRTY" && bash "$SCRIPTS/command-run.sh" 3 2>&1); rc=$?
case "$out" in *"tree is dirty"*) got=yes ;; *) got=no ;; esac
is "a dirty tree refuses to arm"      "$got" "yes"
is "the refusal exits non-zero"       "$rc" "1"
# seed_state runs before the dirty-tree check, so a refusal may leave an
# unarmed state.json behind. What must never happen is an armed one: the Stop
# hook keys on .active, and anything else is a file the next run re-seeds.
is "the refusal arms nothing" "$(cd "$DIRTY" && jq -r '.active // "unarmed"' .spectomat/state.json 2>/dev/null || echo unarmed)" "unarmed"

# Drafts are taken in plain alphabetical order of the file name.
ORDER="$TMP/order"
mkdir -p "$ORDER"
cp -R "$REPO_TEMPLATE/." "$ORDER"
mkdir -p "$ORDER/.wishlist"
printf 'b\n' > "$ORDER/.wishlist/beta.md"
printf 'a\n' > "$ORDER/.wishlist/alpha.md"
touch "$ORDER/.wishlist/beta.md"   # newer, but alphabetically second
(cd "$ORDER" && bash "$SCRIPTS/command-run.sh" 3) >/dev/null 2>&1
is "wishes are read alphabetically" "$(verdict "$ORDER" "$SCRIPTS")" "SPECIFY alpha"

# Arming writes state.json, the armed flag every existence test below reads.
# The prompt fed back each iteration is generated on the fly by pointer_prompt
# in utils.sh (see pointer_prompt_test.sh) — there is no file for cancel to
# leave behind, so arm/cancel/resume only need to agree on state.json.
echo "arm and disarm"
ARM="$TMP/arm"
mkdir -p "$ARM"
cp -R "$REPO_TEMPLATE/." "$ARM"
mkdir -p "$ARM/.wishlist"
printf 'idea\n' > "$ARM/.wishlist/001-thing.md"
(cd "$ARM" && bash "$SCRIPTS/command-run.sh" 7) >/dev/null 2>&1
is "state.json is valid JSON"   "$(cd "$ARM" && jq -e . .spectomat/state.json >/dev/null 2>&1 && echo y || echo n)" "y"
is "the iteration starts at 1"       "$(cd "$ARM" && jq -r .iteration .spectomat/state.json)" "1"
is "the cap is a JSON number"   "$(cd "$ARM" && jq -r '.max_iterations | type' .spectomat/state.json)" "number"
is "arming leaves a clean tree" "$(cd "$ARM" && git status --porcelain)" ""
is "arming marks the flow active" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"
is "arming records the first verdict as current" "$(cd "$ARM" && jq -r '.current | "\(.phase) \(.slug)"' .spectomat/state.json)" "SPECIFY 001-thing"
(cd "$ARM" && bash "$SCRIPTS/command-cancel.sh") >/dev/null 2>&1
is "cancel keeps state.json"        "$([[ -e "$ARM/.spectomat/state.json" ]] && echo yes || echo no)" "yes"
is "cancel marks the flow inactive" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "false"
is "cancel keeps the inbox"         "$([[ -d "$ARM/.wishlist" ]] && echo yes || echo no)" "yes"
(cd "$ARM" && bash "$SCRIPTS/command-run.sh" 7) >/dev/null 2>&1
is "resuming re-arms the flow" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"
is "arming records the plugin copy" "$(cd "$ARM" && jq -r .plugin_root .spectomat/state.json)" "$(dirname "$SCRIPTS")"

# A finished slug keeps its entry, so re-arming must neither resurrect it nor
# count it as work. This also drives the migration branch: a floor armed before
# D27 has marked dirs with no state entry, and arming seeds their terminal
# phase once.
echo "arming over finished slugs"
RE="$TMP/rearm"
mkdir -p "$RE"
cp -R "$REPO_TEMPLATE/." "$RE"
mkdir -p "$RE/.spectomat/001-old" "$RE/.wishlist"
printf 'spec\n' > "$RE/.spectomat/001-old/spec.md"
printf 'plan\n' > "$RE/.spectomat/001-old/plan.md"
printf 'archived\n' > "$RE/.spectomat/001-old/done.md"
printf 'idea\n' > "$RE/.wishlist/002-new.md"
(cd "$RE" && git add -A && git commit -qm seed) >/dev/null 2>&1
out=$( (cd "$RE" && bash "$SCRIPTS/command-run.sh" 7) 2>&1 )
is "a pre-D27 finished slug is seeded DONE" "$(cd "$RE" && jq -r '.slugs["001-old"].phase' .spectomat/state.json)" "DONE"
is "the finished slug is not counted as active" "$(printf '%s\n' "$out" | grep -c 'active: 1   done: 1')" "1"
is "the new draft still arms" "$(cd "$RE" && jq -r '.slugs["002-new"].phase' .spectomat/state.json)" "SPECIFY"
(cd "$RE" && bash "$SCRIPTS/command-cancel.sh") >/dev/null 2>&1
(cd "$RE" && bash "$SCRIPTS/command-run.sh" 7) >/dev/null 2>&1
is "a second arming leaves the finished slug alone" "$(cd "$RE" && jq -r '.slugs["001-old"].phase' .spectomat/state.json)" "DONE"
is "re-arming leaves a clean tree" "$(cd "$RE" && git status --porcelain)" ""

finish
