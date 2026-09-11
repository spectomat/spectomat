#!/bin/bash
# Spectomat self-test — the helpers in utils.sh that parse or build text.
#
#   scripts/selftest.sh          tests the utils.sh next to it
#
# No dependencies and no network; runs in under a second. Everything else in
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
