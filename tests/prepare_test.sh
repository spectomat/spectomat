#!/bin/bash
# prepare.sh — arms and refuses to arm the floor; commits drafts; arm writes
# state.json, cancel marks it inactive without touching the floor.
#
#   tests/prepare_test.sh              tests ../scripts
#   tests/prepare_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Arming a floor must leave a clean tree. The picker reads `git status` and
# answers RECOVER to any dirt, so a draft the user dropped into drafts/ must be
# committed by prepare.sh, or iteration 1 burns on the janitor.
echo "prepare.sh drafts"

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

# Drop an untracked draft on the floor: prepare.sh commits it and arms.
DROP="$TMP/drop"
mkdir -p "$DROP"
cp -R "$REPO_TEMPLATE/." "$DROP"
mkdir -p "$DROP/.spectomat/drafts"
printf 'idea\n' > "$DROP/.spectomat/drafts/001-thing.md"
(cd "$DROP" && bash "$SCRIPTS/prepare.sh" 3) >/dev/null 2>&1
is "a dropped draft leaves a clean tree" "$(cd "$DROP" && git status --porcelain)" ""
is "the draft is committed"     "$(cd "$DROP" && git log -1 --name-only --format= | grep -c 'drafts/001-thing.md')" "1"
is "iteration 1 is SPECIFY"     "$(verdict "$DROP" "$SCRIPTS")" "SPECIFY 001-thing"

# A draft the user already committed leaves nothing to stage; arming must still
# succeed and reach SPECIFY.
DROP2="$TMP/drop-committed"
mkdir -p "$DROP2"
cp -R "$REPO_TEMPLATE/." "$DROP2"
mkdir -p "$DROP2/.spectomat/drafts"
(
  cd "$DROP2" || exit 1
  printf 'idea\n' > .spectomat/drafts/001-thing.md
  git add .spectomat/drafts/001-thing.md
  git commit -qm draft
) >/dev/null 2>&1
(cd "$DROP2" && bash "$SCRIPTS/prepare.sh" 3) >/dev/null 2>&1
is "a committed draft arms cleanly" "$(cd "$DROP2" && git status --porcelain)" ""
is "a committed draft reaches SPECIFY" "$(verdict "$DROP2" "$SCRIPTS")" "SPECIFY 001-thing"

# Unrelated work in progress would make the picker answer RECOVER every iteration, so
# prepare.sh refuses to arm rather than spend the whole cap on the janitor.
DIRTY="$TMP/dirty"
mkdir -p "$DIRTY"
cp -R "$REPO_TEMPLATE/." "$DIRTY"
mkdir -p "$DIRTY/.spectomat/drafts"
printf 'idea\n' > "$DIRTY/.spectomat/drafts/001-thing.md"
printf 'edited\n' > "$DIRTY/README.md"
out=$(cd "$DIRTY" && bash "$SCRIPTS/prepare.sh" 3 2>&1); rc=$?
case "$out" in *"tree is dirty"*) got=yes ;; *) got=no ;; esac
is "a dirty tree refuses to arm"      "$got" "yes"
is "the refusal exits non-zero"       "$rc" "1"
is "the refusal arms nothing"         "$([[ -e "$DIRTY/.spectomat/state.json" ]] && echo yes || echo no)" "no"

# Drafts are taken in plain alphabetical order of the file name.
ORDER="$TMP/order"
mkdir -p "$ORDER"
cp -R "$REPO_TEMPLATE/." "$ORDER"
mkdir -p "$ORDER/.spectomat/drafts"
printf 'b\n' > "$ORDER/.spectomat/drafts/beta.md"
printf 'a\n' > "$ORDER/.spectomat/drafts/alpha.md"
touch "$ORDER/.spectomat/drafts/beta.md"   # newer, but alphabetically second
(cd "$ORDER" && bash "$SCRIPTS/prepare.sh" 3) >/dev/null 2>&1
is "drafts are read alphabetically" "$(verdict "$ORDER" "$SCRIPTS")" "SPECIFY alpha"

# Arming writes state.json, the armed flag every existence test below reads.
# The prompt fed back each iteration is generated on the fly by pointer_prompt
# in utils.sh (see pointer_prompt_test.sh) — there is no file for cancel to
# leave behind, so arm/cancel/resume only need to agree on state.json.
echo "arm and disarm"
ARM="$TMP/arm"
mkdir -p "$ARM"
cp -R "$REPO_TEMPLATE/." "$ARM"
mkdir -p "$ARM/.spectomat/drafts"
printf 'idea\n' > "$ARM/.spectomat/drafts/001-thing.md"
(cd "$ARM" && bash "$SCRIPTS/prepare.sh" 7) >/dev/null 2>&1
is "state.json is valid JSON"   "$(cd "$ARM" && jq -e . .spectomat/state.json >/dev/null 2>&1 && echo y || echo n)" "y"
is "the iteration starts at 1"       "$(cd "$ARM" && jq -r .iteration .spectomat/state.json)" "1"
is "the cap is a JSON number"   "$(cd "$ARM" && jq -r '.max_iterations | type' .spectomat/state.json)" "number"
is "arming leaves a clean tree" "$(cd "$ARM" && git status --porcelain)" ""
is "arming marks the flow active" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"
(cd "$ARM" && bash "$SCRIPTS/cancel.sh") >/dev/null 2>&1
is "cancel keeps state.json"        "$([[ -e "$ARM/.spectomat/state.json" ]] && echo yes || echo no)" "yes"
is "cancel marks the flow inactive" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "false"
is "cancel keeps the floor"         "$([[ -d "$ARM/.spectomat/drafts" ]] && echo yes || echo no)" "yes"
(cd "$ARM" && bash "$SCRIPTS/prepare.sh" 7) >/dev/null 2>&1
is "resuming re-arms the flow" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"

finish
