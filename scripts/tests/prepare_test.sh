#!/bin/bash
# prepare.sh — arms and refuses to arm the floor; commits drafts; arm/cancel
# leave state.json and pointer.md in step.
#
#   scripts/tests/prepare_test.sh          tests the scripts next to it
#   scripts/tests/prepare_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
is "iteration 1 is SPECIFY"     "$(cd "$DROP" && bash "$SCRIPTS/phase.sh")" "SPECIFY 001-thing"

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
is "a committed draft reaches SPECIFY" "$(cd "$DROP2" && bash "$SCRIPTS/phase.sh")" "SPECIFY 001-thing"

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
is "drafts are read alphabetically" "$(cd "$ORDER" && bash "$SCRIPTS/phase.sh")" "SPECIFY alpha"

# Arming writes two files that must live and die together: state.json is the
# armed flag every existence test reads, pointer.md is the prompt fed back.
# A pointer left behind by a cancel would be fed to a later flow with no
# counter behind it, so cancel must clear both.
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
is "the pointer has no frontmatter" "$(cd "$ARM" && head -1 .spectomat/pointer.md | grep -c '^---$')" "0"
is "the pointer resolved PLUGIN_ROOT" "$(cd "$ARM" && grep -c '{{' .spectomat/pointer.md)" "0"
is "arming leaves a clean tree" "$(cd "$ARM" && git status --porcelain)" ""
is "arming marks the flow active" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"
(cd "$ARM" && bash "$SCRIPTS/cancel.sh") >/dev/null 2>&1
is "cancel keeps state.json"        "$([[ -e "$ARM/.spectomat/state.json" ]] && echo yes || echo no)" "yes"
is "cancel marks the flow inactive" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "false"
is "cancel removes the pointer"     "$([[ -e "$ARM/.spectomat/pointer.md" ]] && echo yes || echo no)" "no"
is "cancel keeps the floor"         "$([[ -d "$ARM/.spectomat/drafts" ]] && echo yes || echo no)" "yes"
(cd "$ARM" && bash "$SCRIPTS/prepare.sh" 7) >/dev/null 2>&1
is "resuming re-arms the flow" "$(cd "$ARM" && jq -r .active .spectomat/state.json)" "true"
is "resuming keeps the pointer" "$([[ -e "$ARM/.spectomat/pointer.md" ]] && echo yes || echo no)" "yes"

finish
