#!/bin/bash
# Spectomat self-test — the helpers in utils.sh, plus the picker, the archiver,
# run.sh and the Stop hook end to end.
#
#   scripts/selftest.sh          tests the scripts next to it
#   scripts/selftest.sh DIR      tests the scripts in DIR
#
# No dependencies and no network; runs in under 8 seconds. Every fixture is a
# real git repo, because `git status --porcelain` is normative input.

set -uo pipefail

SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPTS/utils.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- floor fixtures -------------------------------------------------------
# Every fixture is a real git repo: `git status --porcelain` is normative
# input to the picker and must not be stubbed.

FIXTURE=""
TEMPLATE=""

# Build the one pristine floor repo the whole suite copies from. A `git init`
# plus commit is expensive next to the rest of this suite, and floor() runs
# dozens of times across all the fixtures below, so it pays to do it once and
# `cp -R` a real repo instead of re-running git init/config/commit per call.
floor_template() {
  TEMPLATE="$TMP/floor-template"
  mkdir -p "$TEMPLATE/.spectomat"/{drafts,specs,plans,done}
  (
    cd "$TEMPLATE" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    printf '%s\n' '.spectomat/state.json' '.spectomat/pointer.md' \
                   '.spectomat/work/' '.spectomat/log.md' > .gitignore
    printf '# Spectomat factory log\n\n' > .spectomat/log.md
    git add .gitignore
    git commit -qm init
  )
}

# floor NAME — fresh repo with an empty, clean floor. Sets FIXTURE.
# A copy of a real git repo is still a real git repo: `git status --porcelain`
# in the copy reports exactly what it would in a freshly `git init`ed one.
floor() {
  [[ -n "$TEMPLATE" ]] || floor_template
  FIXTURE="$TMP/floor-$1"
  mkdir -p "$FIXTURE"
  cp -R "$TEMPLATE/." "$FIXTURE"
}

# Commit whatever the last fixture helper created, so the tree stays clean.
# Staging only gitignored paths (e.g. logline's log.md) is a normal no-op and
# must stay silent. A real failure — bad $FIXTURE, a git error — must not
# vanish into that same silence, so it gets a diagnostic on stderr instead.
fixture_commit() {
  (
    cd "$FIXTURE" 2>/dev/null || { printf 'fixture_commit: no such fixture: %s\n' "$FIXTURE" >&2; exit 0; }
    # A failing `git add` stages nothing, which is indistinguishable from the
    # normal no-op two lines down, so it gets its own diagnostic first.
    git add -A .spectomat >/dev/null 2>&1 ||
      { printf 'fixture_commit: git add failed in %s\n' "$FIXTURE" >&2; exit 0; }
    git diff --cached --quiet 2>/dev/null && exit 0
    git commit -qm fixture >/dev/null 2>&1 || printf 'fixture_commit: commit failed in %s\n' "$FIXTURE" >&2
  )
  return 0
}

draft() { printf 'idea\n' > "$FIXTURE/.spectomat/drafts/$1.md"; fixture_commit; }
spec()  { printf 'spec\n' > "$FIXTURE/.spectomat/specs/$1.md";  fixture_commit; }

# plan SLUG TASKS OPEN — an overview plus TASKS task files, the first OPEN
# of them carrying an unchecked step and the rest ticked.
plan() {
  local slug="$1" tasks="$2" open="$3" i box f
  printf 'overview\n' > "$FIXTURE/.spectomat/plans/$slug.md"
  mkdir -p "$FIXTURE/.spectomat/plans/$slug"
  i=1
  while [[ $i -le $tasks ]]; do
    if [[ $i -le $open ]]; then box='- [ ] step'; else box='- [x] step'; fi
    printf -v f '%s/.spectomat/plans/%s/task-%02d-x.md' "$FIXTURE" "$slug" "$i"
    printf '%s\n' "$box" > "$f"
    i=$((i + 1))
  done
  fixture_commit
}

# plan_bare SLUG — an overview with no task directory: a phase B that died.
plan_bare() { printf 'overview\n' > "$FIXTURE/.spectomat/plans/$1.md"; fixture_commit; }

# logline TEXT — append to the gitignored factory log; never committed.
logline() { printf '%s\n' "$1" >> "$FIXTURE/.spectomat/log.md"; }

# dirty — leave an untracked file so `git status --porcelain` is not silent.
dirty() { printf 'x\n' > "$FIXTURE/untracked.txt"; }

# gates_block LINE... — a contract.md whose Verification Gates block holds LINE...
gates_block() {
  {
    printf '# Contract\n\n## Verification Gates\n\nProse the parser must skip.\n\n'
    printf '```bash\n'
    printf '# project-specific gates, one command per line, You may change it\n'
    printf '%s\n' "$@"
    printf '```\n\n## Memory\n\n'
    printf '```bash\n'
    printf 'echo a later fence that must be ignored\n'
    printf '```\n'
  } > "$FIXTURE/.spectomat/contract.md"
  fixture_commit
}

PASS=0; FAIL=0

ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no() {
  FAIL=$((FAIL+1))
  printf '  FAIL %s\n       want: %q\n       got:  %q\n' "$1" "$3" "$2"
}
is() { [[ "$2" == "$3" ]] && ok "$1" || no "$1" "$2" "$3"; }

# rt NAME TEMPLATE_BODY WANT KEY=VAL...
# The trailing X on both sides keeps the comparison byte-exact at end of file.
rt() {
  local name="$1" body="$2" want="$3"; shift 3
  printf '%s' "$body" > "$TMP/src"
  render_template "$TMP/src" "$TMP/dst" "$@" 2>/dev/null
  is "$name" "$(cat "$TMP/dst"; printf X)" "$want$(printf X)"
}

echo "render_template"
rt "single key"            'hello {{NAME}}'            'hello world'          NAME=world
rt "repeated key"          '{{A}}/{{A}}'               'x/x'                  A=x
rt "two keys"              '{{A}}-{{B}}'               'x-y'                  A=x B=y
rt "unknown key kept"      'a {{NOPE}} b'              'a {{NOPE}} b'         A=x
rt "empty value"           '[{{A}}]'                   '[]'                   A=
rt "value with ampersand"  '{{A}}'                     'me & you'             'A=me & you'
rt "value with backslash"  '{{A}}'                     'a\nb'                 'A=a\nb'
rt "value with slash"      '{{A}}'                     'a/b/c'                'A=a/b/c'
rt "value with dollar"     '{{A}}'                     'cost $5'              'A=cost $5'
rt "value with braces"     '{{A}}'                     '{{B}}'                'A={{B}}'
rt "trailing newlines"     $'x{{A}}\n\n'               $'xv\n\n'              A=v
rt "no trailing newline"   'x{{A}}'                    'xv'                   A=v
rt "multiline body"        $'{{A}}\nmid\n{{A}}'        $'v\nmid\nv'           A=v

# ep NAME INPUT yes|no — does INPUT carry the completion promise?
ep() {
  local got=no
  promised_empty "$2" && got=yes
  is "$1" "$got" "$3"
}

echo "promised_empty"
ep "bare tag"          '<promise>FACTORY EMPTY</promise>'                 yes
ep "surrounded"        'blah <promise>FACTORY EMPTY</promise> blah'       yes
ep "tag on own line"   $'text\n<promise>FACTORY EMPTY</promise>\nmore'    yes
ep "inner padding"     '<promise>  FACTORY EMPTY  </promise>'             yes
ep "inner newlines"    $'<promise>\nFACTORY\nEMPTY\n</promise>'          yes
ep "indented tags"     $'  <promise>\n\t FACTORY EMPTY\n  </promise>'    yes
ep "second of two"     '<promise>ONE</promise><promise>FACTORY EMPTY</promise>' yes
ep "lenient spacing"   '<promise>FACTORYEMPTY</promise>'                  yes
ep "other wording"     '<promise>ALL DONE</promise>'                      no
ep "wrong case"        '<promise>factory empty</promise>'                 no
ep "no tag"            'I am done, the factory is empty.'                 no
ep "no tag, exact"     'FACTORY EMPTY'                                    no
ep "unclosed tag"      'x <promise>FACTORY EMPTY'                         no
ep "empty input"       ''                                                 no
ep "empty tag"         '<promise></promise>'                              no

# jq is the only non-base dependency the scripts may take. This file names the
# forbidden command, so it has to leave itself out of its own scan.
echo "dependencies"
hits=$(grep -ln 'perl' "$SCRIPTS"/*.sh 2>/dev/null | grep -v '/selftest\.sh$' | tr '\n' ' ')
is "scripts invoke no perl" "${hits% }" ""

echo "fixtures"
floor clean
is "fresh fixture is clean"     "$(cd "$FIXTURE" && git status --porcelain)" ""
floor dirt; dirty
is "dirty() dirties the tree"   "$(cd "$FIXTURE" && git status --porcelain)" "?? untracked.txt"
floor counted; plan 001-a 3 1
is "plan() writes N task files" "$(ls "$FIXTURE/.spectomat/plans/001-a" | wc -l | tr -d ' ')" "3"
is "plan() leaves OPEN open"    "$(grep -lE '^- \[ \]' "$FIXTURE"/.spectomat/plans/001-a/*.md | wc -l | tr -d ' ')" "1"
is "plan() ticks the rest"      "$(grep -lE '^- \[x\]' "$FIXTURE"/.spectomat/plans/001-a/*.md | wc -l | tr -d ' ')" "2"
floor bare; plan_bare 002-b
is "plan_bare() has no task dir" "$([[ -d "$FIXTURE/.spectomat/plans/002-b" ]] && echo yes || echo no)" "no"

floor quiet; logline note
out=$(fixture_commit 2>&1)
is "fixture_commit is silent for a gitignored-only change" "$out" ""

FIXTURE="$TMP/no-such-fixture"
err=$(fixture_commit 2>&1 1>/dev/null); rc=$?
case "$err" in *"fixture_commit"*) got=yes ;; *) got=no ;; esac
is "fixture_commit reports a broken fixture on stderr" "$got" "yes"
is "fixture_commit still returns 0 on a broken fixture" "$rc" "0"

echo "gate_block"
gb() { is "$1" "$(cd "$FIXTURE" && gate_block | tr '\n' '|')" "$2"; }

floor gb1; gates_block 'echo one' 'echo two'
gb "two gate lines"            'echo one|echo two|'
floor gb2; gates_block '# a comment' '' '   ' 'echo one'
gb "comments and blanks drop"  'echo one|'
floor gb3
gb "no contract yields nothing" ''
floor gb4; gates_block 'echo one'
gb "a later fence is ignored"  'echo one|'

echo "run_gates"
floor rg1; gates_block 'true' 'true'
( cd "$FIXTURE" && run_gates ); is "all gates pass" "$?" "0"
floor rg2; gates_block 'false' 'touch ran'
( cd "$FIXTURE" && run_gates ); is "a failing gate fails" "$?" "1"
is "it stops at the first failure" "$([[ -e "$FIXTURE/ran" ]] && echo yes || echo no)" "no"
( cd "$FIXTURE" && run_gates; printf '%s' "$GATE_FAILED" ) > "$TMP/gf"
is "it names the failing gate" "$(cat "$TMP/gf")" "false"

echo "strike_count"
floor sc1
is "no log entry is zero" "$(cd "$FIXTURE" && strike_count C 001-a)" "0"
logline '- 2026-09-11T10:00Z · C · 001-a · Task 1 (strike 1: gate red)'
is "one strike counts"    "$(cd "$FIXTURE" && strike_count C 001-a)" "1"
logline '- 2026-09-11T10:10Z · C · 001-a · Task 1 (strike 2: gate red)'
is "two strikes count"    "$(cd "$FIXTURE" && strike_count C 001-a)" "2"
is "another phase is separate" "$(cd "$FIXTURE" && strike_count B 001-a)" "0"
is "another slug is separate"  "$(cd "$FIXTURE" && strike_count C 002-b)" "0"
logline '- 2026-09-11T10:20Z · C · 001-a · Task 2 done'
is "a clean line is not a strike" "$(cd "$FIXTURE" && strike_count C 001-a)" "2"

floor sc2
logline '- t · C · 001-my idea (draft) · x (strike 1: gate red)'
is "a slug with a balanced metachar counts" "$(cd "$FIXTURE" && strike_count C '001-my idea (draft)')" "1"
logline '- t · C · 001-a[ · x (strike 1: gate red)'
is "a slug with an unbalanced bracket counts" "$(cd "$FIXTURE" && strike_count C '001-a[')" "1"

echo "least_struck"
floor ls1
ls_pick() { ( cd "$FIXTURE" && printf '%s\n' "$@" | least_struck C ); }
is "single candidate"        "$(ls_pick 001-a)" "001-a"
is "no candidates"           "$(ls_pick)" ""
is "ties go alphabetically"  "$(ls_pick 001-a 002-b)" "001-a"
logline '- t · C · 001-a · x (strike 1)'
is "fewer strikes wins"      "$(ls_pick 001-a 002-b)" "002-b"
logline '- t · C · 002-b · x (strike 1)'
logline '- t · C · 002-b · x (strike 2)'
is "fewest strikes wins"     "$(ls_pick 001-a 002-b)" "001-a"
logline '- t · C · 001-a · x (strike 2)'
logline '- t · C · 001-a · x (strike 3)'
is "a slug at the limit is skipped" "$(ls_pick 001-a 002-b)" "002-b"
logline '- t · C · 002-b · x (strike 3)'
is "all at the limit yields nothing" "$(ls_pick 001-a 002-b)" ""
is "a slug with a space survives" "$(ls_pick '003-my idea')" "003-my idea"

echo "phase.sh"
pk() { is "$1" "$(cd "$FIXTURE" && bash "$SCRIPTS/phase.sh")" "$2"; }

floor p_empty
pk "empty floor is E" "E"

floor p_a; draft 001-a
pk "a draft is A" "A 001-a"

floor p_b; spec 001-a
pk "a spec with no plan is B" "B 001-a"

floor p_bare; spec 001-a; plan_bare 001-a
pk "an overview with no task files is B" "B 001-a"

floor p_c; spec 001-a; plan 001-a 3 1
pk "an open step is C" "C 001-a"

floor p_d; spec 001-a; plan 001-a 3 0
pk "every step ticked is D" "D 001-a"

floor p_vacuous; spec 001-a; plan_bare 001-a
mkdir -p "$FIXTURE/.spectomat/plans/001-a"
pk "an empty task dir is never D" "B 001-a"

floor p_order; draft 004-d; spec 003-c; plan 002-b 2 1; spec 002-b; spec 001-a; plan 001-a 2 0
pk "D outranks C, B and A" "D 001-a"

floor p_dirty; draft 001-a; dirty
pk "a dirty tree is R" "R"

floor p_dirty_empty; dirty
pk "a dirty tree beats E" "R"

floor p_strike; draft 001-a; draft 002-b
logline '- t · A · 001-a · x (strike 1)'
pk "the less-struck draft wins" "A 002-b"

floor p_blocked; draft 001-a
logline '- t · A · 001-a · x (strike 1)'
logline '- t · A · 001-a · x (strike 2)'
logline '- t · A · 001-a · x (strike 3)'
pk "a leftover at the limit is R, not E" "R"

floor p_orphan; plan_bare 001-a
pk "an orphan overview is R, not E" "R"

floor p_pure; spec 001-a; plan 001-a 2 1
before=$(cd "$FIXTURE" && find .spectomat -type f -exec cksum {} \; | sort; cd "$FIXTURE" && git status --porcelain)
pk "the picker still says C" "C 001-a"
after=$(cd "$FIXTURE" && find .spectomat -type f -exec cksum {} \; | sort; cd "$FIXTURE" && git status --porcelain)
is "the picker mutates nothing" "$after" "$before"

echo "archive.sh"
# ready NAME SLUG GATE — a floor with a finished plan and a one-line gate block
ready() { floor "arc-$1"; spec "$2"; plan "$2" 2 0; gates_block "$3"; }
arc()   { ( cd "$FIXTURE" && bash "$SCRIPTS/archive.sh" "$1" >/dev/null 2>&1 ); }
there() { [[ -e "$FIXTURE/.spectomat/$1" ]] && echo yes || echo no; }
commits() { ( cd "$FIXTURE" && git rev-list --count HEAD ); }

ready pass 001-a 'true'
n0=$(commits); arc 001-a; is "a green gate exits 0" "$?" "0"
is "the spec moved"    "$(there done/001-a.spec.md)" "yes"
is "the plan moved"    "$(there done/001-a.plan.md)" "yes"
is "the task dir moved" "$(there done/001-a)"        "yes"
is "specs/ is empty"   "$(there specs/001-a.md)"     "no"
is "exactly one commit" "$(( $(commits) - n0 ))"     "1"
is "the tree is clean" "$(cd "$FIXTURE" && git status --porcelain)" ""
is "the log names the gate count" "$(grep -c 'gates 1/1' "$FIXTURE/.spectomat/log.md")" "1"
# Phase D owns the floor and nothing else: it must not stage a project file,
# which is what the old package.json version bump did.
is "the commit touches only the floor" \
  "$(cd "$FIXTURE" && git show --name-only --format= HEAD | grep -cv '^.spectomat/')" "0"

ready fail 001-a 'false'
arc 001-a; is "a red gate exits 1" "$?" "1"
is "nothing moved"     "$(there done/001-a.spec.md)" "no"
is "the spec stayed"   "$(there specs/001-a.md)"     "yes"
is "a strike is logged" "$(grep -c '(strike 1)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the second strike counts up" "$(grep -c '(strike 2)' "$FIXTURE/.spectomat/log.md")" "1"
arc 001-a; is "the third strike exits 0" "$?" "0"
is "the blocked spec moved" "$(there done/001-a.spec.blocked.md)" "yes"
is "the blocked plan moved" "$(there done/001-a.plan.blocked.md)" "yes"
is "print_blocked lists both" \
  "$(cd "$FIXTURE" && find .spectomat/done -maxdepth 1 -name '*.blocked.md' | wc -l | tr -d ' ')" "2"

ready dirt 001-a 'true'; dirty
arc 001-a; is "a dirty tree is refused" "$?" "1"
is "nothing moved on a dirty tree" "$(there done/001-a.spec.md)" "no"

ready nosuch 001-a 'true'
arc 002-b; is "an unknown slug is refused" "$?" "1"

echo "archive.sh: unchecked move/commit failures (regression)"
# conflict PATH — pre-place and commit a file at a done/ destination so the
# git mv that targets it is refused; the tree must stay clean going in, or
# require_ready would reject it for the wrong reason.
conflict() { printf 'conflict\n' > "$FIXTURE/.spectomat/$1"; fixture_commit; }

ready blk1 001-a 'true'
conflict done/001-a.spec.md
n0=$(commits); arc 001-a
is "a blocked spec move exits non-zero"        "$?" "1"
is "no commit is made when the spec can't move" "$(( $(commits) - n0 ))" "0"
is "a strike is logged for the failed move"    "$(grep -c '(strike 1)' "$FIXTURE/.spectomat/log.md")" "1"
is "the spec never moved"                      "$(there specs/001-a.md)" "yes"
is "the plan never moved either"               "$(there plans/001-a.md)" "yes"

ready blk2 001-a 'true'
conflict done/001-a.spec.md
conflict done/001-a.plan.md
n0=$(commits); arc 001-a
is "both destinations blocked exits non-zero" "$?" "1"
is "zero new commits when nothing could move" "$(( $(commits) - n0 ))" "0"

echo "briefs"
AGENTS="$(dirname "$SCRIPTS")/agents"
for a in phase-a phase-b phase-c recover; do
  is "agents/$a.md exists" "$([[ -f "$AGENTS/$a.md" ]] && echo yes || echo no)" "yes"
  is "agents/$a.md is named $a" "$(sed -n 's/^name: *//p' "$AGENTS/$a.md" | head -1)" "$a"
  is "agents/$a.md has a description" \
    "$(grep -c '^description: ' "$AGENTS/$a.md")" "1"
done
is "AGENT_COUNT is 4" "$(ls "$AGENTS"/*.md | wc -l | tr -d ' ')" "4"
is "no brief carries a placeholder" "$(grep -l '{{' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "phase-c names both prompts" \
  "$(grep -cE 'prompts/(implementer|reviewer)\.md' "$AGENTS/phase-c.md" | tr -d ' ')" "2"

echo "status"
floor st; spec 001-a; plan 001-a 2 1
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "status prints the next section" "$(printf '%s\n' "$st_out" | grep -c '^--- next ---$')" "1"
is "status predicts the verdict"    "$(printf '%s\n' "$st_out" | grep -c '^C 001-a$')" "1"
floor st2
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "an empty floor predicts E"      "$(printf '%s\n' "$st_out" | grep -c '^E$')" "1"

# Arming a floor must leave a clean tree. The picker reads `git status` and
# answers R to any dirt, so a draft the user dropped into drafts/ must be
# committed by run.sh, or iteration 1 burns on the janitor.
echo "run.sh drafts"

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

# Drop an untracked draft on the floor: run.sh commits it and arms.
DROP="$TMP/drop"
mkdir -p "$DROP"
cp -R "$REPO_TEMPLATE/." "$DROP"
mkdir -p "$DROP/.spectomat/drafts"
printf 'idea\n' > "$DROP/.spectomat/drafts/001-thing.md"
(cd "$DROP" && bash "$SCRIPTS/run.sh" 3) >/dev/null 2>&1
is "a dropped draft leaves a clean tree" "$(cd "$DROP" && git status --porcelain)" ""
is "the draft is committed"     "$(cd "$DROP" && git log -1 --name-only --format= | grep -c 'drafts/001-thing.md')" "1"
is "iteration 1 is phase A"     "$(cd "$DROP" && bash "$SCRIPTS/phase.sh")" "A 001-thing"

# A draft the user already committed leaves nothing to stage; arming must still
# succeed and reach phase A.
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
(cd "$DROP2" && bash "$SCRIPTS/run.sh" 3) >/dev/null 2>&1
is "a committed draft arms cleanly" "$(cd "$DROP2" && git status --porcelain)" ""
is "a committed draft reaches A"    "$(cd "$DROP2" && bash "$SCRIPTS/phase.sh")" "A 001-thing"

# Unrelated work in progress would make the picker answer R every iteration, so
# run.sh refuses to arm rather than spend the whole cap on the janitor.
DIRTY="$TMP/dirty"
mkdir -p "$DIRTY"
cp -R "$REPO_TEMPLATE/." "$DIRTY"
mkdir -p "$DIRTY/.spectomat/drafts"
printf 'idea\n' > "$DIRTY/.spectomat/drafts/001-thing.md"
printf 'edited\n' > "$DIRTY/README.md"
out=$(cd "$DIRTY" && bash "$SCRIPTS/run.sh" 3 2>&1); rc=$?
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
(cd "$ORDER" && bash "$SCRIPTS/run.sh" 3) >/dev/null 2>&1
is "drafts are read alphabetically" "$(cd "$ORDER" && bash "$SCRIPTS/phase.sh")" "A alpha"

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
(cd "$ARM" && bash "$SCRIPTS/run.sh" 7) >/dev/null 2>&1
is "state.json is valid JSON"   "$(cd "$ARM" && jq -e . .spectomat/state.json >/dev/null 2>&1 && echo y || echo n)" "y"
is "the iteration starts at 1"       "$(cd "$ARM" && jq -r .iteration .spectomat/state.json)" "1"
is "the cap is a JSON number"   "$(cd "$ARM" && jq -r '.max_iterations | type' .spectomat/state.json)" "number"
is "the pointer has no frontmatter" "$(cd "$ARM" && head -1 .spectomat/pointer.md | grep -c '^---$')" "0"
is "the pointer resolved PLUGIN_ROOT" "$(cd "$ARM" && grep -c '{{' .spectomat/pointer.md)" "0"
is "arming leaves a clean tree" "$(cd "$ARM" && git status --porcelain)" ""
(cd "$ARM" && bash "$SCRIPTS/cancel.sh") >/dev/null 2>&1
is "cancel removes the state"   "$([[ -e "$ARM/.spectomat/state.json" ]] && echo yes || echo no)" "no"
is "cancel removes the pointer" "$([[ -e "$ARM/.spectomat/pointer.md" ]] && echo yes || echo no)" "no"
is "cancel keeps the floor"     "$([[ -d "$ARM/.spectomat/drafts" ]] && echo yes || echo no)" "yes"

# stop-hook.sh runs on every iteration of every flow and is the only script that
# can end one. Its fixture is a state file, a pointer and a transcript; its input
# is the JSON payload Claude Code pipes in.
echo "stop-hook.sh"

HOOK="$TMP/hook"

# hook_floor SESSION ITERATION MAX — an armed flow owned by SESSION.
hook_floor() {
  rm -rf "$HOOK"; mkdir -p "$HOOK/.spectomat"
  printf '{"iteration": %s, "max_iterations": %s, "session_id": "%s", "started_at": "t"}\n' \
    "$2" "$3" "$1" > "$HOOK/.spectomat/state.json"
  printf 'POINTER PROMPT\n' > "$HOOK/.spectomat/pointer.md"
  transcript 'working on it'
}

# transcript TEXT — one assistant turn whose last text block is TEXT.
transcript() {
  jq -nc --arg t "$1" '{role:"assistant", message:{content:[{type:"text", text:$t}]}}' \
    > "$HOOK/transcript.jsonl"
}

# fire SESSION — run the hook as SESSION; stdout only.
fire() {
  jq -nc --arg s "$1" --arg p "$HOOK/transcript.jsonl" \
      '{session_id:$s, transcript_path:$p}' \
    | ( cd "$HOOK" && bash "$SCRIPTS/stop-hook.sh" 2>/dev/null )
}

hook_state() { [[ -e "$HOOK/.spectomat/state.json" ]] && echo yes || echo no; }
hook_iter()  { jq -r .iteration "$HOOK/.spectomat/state.json" 2>/dev/null; }

hook_floor OWNER 1 5
out=$(fire OWNER)
is "the owner is blocked from exiting" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "the pointer is fed back"           "$(printf '%s' "$out" | jq -r .reason)"   "POINTER PROMPT"
is "the iteration is bumped"           "$(hook_iter)" "2"

# Session isolation: the hook fires in every session of the project, and only
# the one that armed the flow may advance or end it.
hook_floor OWNER 1 5
out=$(fire STRANGER)
is "a foreign session emits nothing"    "$out" ""
is "a foreign session leaves the state" "$(hook_state)" "yes"
is "a foreign session bumps nothing"    "$(hook_iter)" "1"

# A state file jq cannot read names no owner, so no session may disarm it: the
# guard that catches this once ran before the session check and let any session
# in the project destroy a flow it did not own.
hook_floor OWNER 1 5
printf 'not json at all\n' > "$HOOK/.spectomat/state.json"
fire STRANGER >/dev/null
is "a corrupt state survives a foreign session" "$(hook_state)" "yes"
fire OWNER >/dev/null
is "a corrupt state survives its own session"   "$(hook_state)" "yes"

hook_floor OWNER 1 5
transcript 'done here <promise>FACTORY EMPTY</promise>'
out=$(fire OWNER)
case "$out" in *"FACTORY EMPTY"*) got=yes ;; *) got=no ;; esac
is "the promise ends the flow"        "$got" "yes"
is "the promise disarms"              "$(hook_state)" "no"
is "the promise removes the pointer"  "$([[ -e "$HOOK/.spectomat/pointer.md" ]] && echo yes || echo no)" "no"

hook_floor OWNER 3 3
out=$(fire OWNER)
case "$out" in *"max iterations"*) got=yes ;; *) got=no ;; esac
is "the cap ends the flow" "$got" "yes"
is "the cap disarms"       "$(hook_state)" "no"

hook_floor OWNER 1 5
rm -f "$HOOK/.spectomat/state.json"
is "no state file means no output" "$(fire OWNER)" ""

# The licence obligation: NOTICE.md must not point at a file that is gone.
echo "licence"
REPO_ROOT="$(dirname "$SCRIPTS")"
missing=$(cd "$REPO_ROOT" && for f in $(grep -oE '`[a-zA-Z0-9_./-]+\.(md|sh|json)`' NOTICE.md | tr -d '`'); do
            # `.spectomat/` paths are written into the user's project at runtime,
            # so they are not files of this repo and are not checked here.
            [[ "$f" == .spectomat/* ]] && continue
            [[ -e "$f" ]] || printf '%s ' "$f"; done)
is "NOTICE.md names only files that exist" "${missing% }" ""

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
