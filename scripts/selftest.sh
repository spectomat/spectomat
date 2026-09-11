#!/bin/bash
# Spectomat self-test — the helpers in utils.sh that parse or build text.
#
#   scripts/selftest.sh          tests the utils.sh next to it
#
# No dependencies and no network; runs in under 8 seconds. Everything else in
# scripts/ is orchestration, exercised by hand in a scratch repo (see .claude/CLAUDE.md).

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
    printf '%s\n' '.spectomat/state.md' '.spectomat/work/' '.spectomat/log.md' > .gitignore
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
    git add -A .spectomat >/dev/null 2>&1
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

# old_contract LINE... — a pre-migration contract: a "## Phases" section and a
# Verification Gates block holding LINE...
old_contract() {
  {
    printf '# Spectomat Factory\n\n## The floor\n\nfloor text\n\n'
    printf '## Phases\n\n### A · Draft → Spec\n\nold phase craft\n\n'
    printf '## Verification Gates\n\n'
    printf '```bash\n# project-specific gates, one command per line\n'
    printf '%s\n' "$@"
    printf '```\n\n## Memory\n\nmemory rules\n'
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
logline '- 2026-09-11T10:00Z · C · 001-a · wave 1 (strike 1: gate red)'
is "one strike counts"    "$(cd "$FIXTURE" && strike_count C 001-a)" "1"
logline '- 2026-09-11T10:10Z · C · 001-a · wave 1 (strike 2: gate red)'
is "two strikes count"    "$(cd "$FIXTURE" && strike_count C 001-a)" "2"
is "another phase is separate" "$(cd "$FIXTURE" && strike_count B 001-a)" "0"
is "another slug is separate"  "$(cd "$FIXTURE" && strike_count C 002-b)" "0"
logline '- 2026-09-11T10:20Z · C · 001-a · wave 2 done'
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

echo "next_version"
is "patch becomes NNN"      "$(next_version 0.1.8 003-auth)" "0.1.3"
is "leading zeros are decimal" "$(next_version 2.4.0 008-x)" "2.4.8"
is "no octal surprise"      "$(next_version 1.0.0 009-x)" "1.0.9"
is "three digits"           "$(next_version 1.2.3 120-x)" "1.2.120"
next_version 1.0.0 no-number >/dev/null 2>&1; is "a slug with no NNN fails" "$?" "1"

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
is "the looper is gone"     "$([[ -e "$AGENTS/looper.md" ]] && echo yes || echo no)" "no"
is "references/ is gone"    "$([[ -d "$(dirname "$SCRIPTS")/references" ]] && echo yes || echo no)" "no"
is "no brief names references/" "$(grep -l 'references/' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "no brief carries a placeholder" "$(grep -l '{{' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "phase-c names both prompts" \
  "$(grep -cE 'prompts/(implementer|reviewer)\.md' "$AGENTS/phase-c.md" | tr -d ' ')" "2"

echo "migrate_contract"
floor mig; old_contract 'npm run custom-gate' 'bash ci/extra.sh'
( cd "$FIXTURE" && migrate_contract ); is "an old contract migrates" "$?" "0"
C="$FIXTURE/.spectomat/contract.md"
is "the phases section is gone"  "$(grep -c '^## Phases' "$C")" "0"
is "the marker is there"         "$(grep -c '^<!-- spectomat-contract: 2 -->' "$C")" "1"
is "the first gate survived"     "$(grep -c '^npm run custom-gate$' "$C")" "1"
is "the second gate survived"    "$(grep -c '^bash ci/extra.sh$' "$C")" "1"
is "the memory rules came back"  "$(grep -c '^## Memory' "$C")" "1"
( cd "$FIXTURE" && migrate_contract ); is "a migrated contract is left alone" "$?" "1"
floor mig2
( cd "$FIXTURE" && migrate_contract ); is "no contract is nothing to do" "$?" "1"

echo "status"
floor st; spec 001-a; plan 001-a 2 1
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "status prints the next section" "$(printf '%s\n' "$st_out" | grep -c '^--- next ---$')" "1"
is "status predicts the verdict"    "$(printf '%s\n' "$st_out" | grep -c '^C 001-a$')" "1"
floor st2
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "an empty floor predicts E"      "$(printf '%s\n' "$st_out" | grep -c '^E$')" "1"

# Arming a floor must leave a clean tree. The picker reads `git status` and
# answers R to any dirt, so a wishlist move that stages the new draft but not
# the removal of the file it came from burns loop 1 on the janitor.
echo "run.sh intake"
INTAKE="$TMP/intake"
mkdir -p "$INTAKE/wishlist"
(
  cd "$INTAKE" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'idea\n' > wishlist/thing.md
  git add -A
  git commit -qm init
) >/dev/null 2>&1
(cd "$INTAKE" && bash "$SCRIPTS/run.sh" 3) >/dev/null 2>&1
is "intake leaves a clean tree" "$(cd "$INTAKE" && git status --porcelain)" ""
is "the draft is committed"     "$(cd "$INTAKE" && git log -1 --name-only --format= | grep -c 'drafts/001-thing.md')" "1"
is "the wish is gone from HEAD" "$(cd "$INTAKE" && git ls-tree -r --name-only HEAD | grep -c '^wishlist/')" "0"
is "loop 1 is phase A"          "$(cd "$INTAKE" && bash "$SCRIPTS/phase.sh")" "A 001-thing"

# An untracked wish has no removal to stage; arming must still leave a clean
# tree and must not fail on a `git add` of a path that was never in the index.
INTAKE2="$TMP/intake-untracked"
mkdir -p "$INTAKE2/wishlist"
(
  cd "$INTAKE2" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'x\n' > README.md
  git add README.md
  git commit -qm init
  printf 'idea\n' > wishlist/thing.md
) >/dev/null 2>&1
(cd "$INTAKE2" && bash "$SCRIPTS/run.sh" 3) >/dev/null 2>&1
is "an untracked wish arms cleanly" "$(cd "$INTAKE2" && git status --porcelain)" ""
is "an untracked wish reaches A"    "$(cd "$INTAKE2" && bash "$SCRIPTS/phase.sh")" "A 001-thing"

# The retired vocabulary. This file names the retired words in order to scan
# for them, so it leaves itself out of its own scan, as the perl check does.
# docs/ is excluded: it records the design that removed them.
echo "vocabulary"
REPO_ROOT="$(dirname "$SCRIPTS")"
stale=$(cd "$REPO_ROOT" && grep -rl --exclude-dir=.git --exclude-dir=docs --exclude-dir=.superpowers \
          -e 'looper' -e 'references/' . 2>/dev/null | grep -v 'selftest\.sh$' | tr '\n' ' ')
is "nothing names the looper or references/" "${stale% }" ""
missing=$(cd "$REPO_ROOT" && for f in $(grep -oE '`[a-zA-Z0-9_./-]+\.(md|sh|json)`' NOTICE.md | tr -d '`'); do
            # `.spectomat/` paths are written into the user's project at runtime,
            # so they are not files of this repo and are not checked here.
            [[ "$f" == .spectomat/* ]] && continue
            [[ -e "$f" ]] || printf '%s ' "$f"; done)
is "NOTICE.md names only files that exist" "${missing% }" ""

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
