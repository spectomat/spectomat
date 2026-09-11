# Spectomat Phase-Specialized Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `looper` subagent with a deterministic bash picker, three phase-specialized agent briefs, a script for phase D, and a janitor for dirty-tree recovery.

**Architecture:** `scripts/phase.sh` reads the floor, `log.md` and `git status` and prints one verdict line. The session's pointer prompt dispatches that letter to a phase agent (`spectomat:phase-a|b|c`), to `scripts/archive.sh` (phase D), to `spectomat:recover` (dirty tree), or emits the completion promise. The project-owned `contract.md` keeps only job invariants; the craft of each phase moves into the plugin-owned brief that performs it, absorbing `references/` entirely.

**Tech Stack:** bash 3.2, `jq`, `git`, `npm` (only where a `package.json` exists). No build, no package manager, no network.

**Spec:** `docs/superpowers/specs/2026-09-11-spectomat-phase-agents-design.md`

## Global Constraints

- bash 3.2 compatible; no GNU-only flags; `jq` is the only non-base dependency; no `perl` (asserted by the existing dependency test in `selftest.sh`).
- `scripts/utils.sh` sets no shell options; every script chooses its own `set -e/-u/pipefail`.
- `scripts/selftest.sh` must still finish in under one second and touch no network. Anything needing `npm` or the Claude runtime is verified out-of-band, never in selftest.
- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- A new `{{KEY}}` placeholder requires a matching value in the `render_template` call in `run.sh`. This plan adds none.
- Constants, each defined exactly once: `STRIKE_LIMIT = 3` (`scripts/utils.sh`), `MAX_WAVE = 3` and `MAX_FIX_ROUNDS = 3` (`agents/phase-c.md`), `AGENT_COUNT = 4` (asserted, not stored).
- Glossary terms are normative (`.claude/CLAUDE.md`): **picker**, **phase agent**, **archiver**, **janitor**, **verdict**, **loop**, **flow**, **phase**, **wave**, **floor**, **contract**, **slug**, **strike**. The word **looper** is retired and must appear nowhere after Task 11.
- Every commit message ends with the trailer `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- Verification gates for every task: `bash -n scripts/*.sh && scripts/selftest.sh`.

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `scripts/selftest.sh` | fixtures and every unit assertion | 1, and every task after |
| `scripts/utils.sh` | shared pure helpers: gates, strikes, version | 2, 3 |
| `scripts/phase.sh` | the picker: floor state → one verdict line | 4 |
| `scripts/archive.sh` | the archiver: phase D end to end | 5 |
| `agents/phase-a.md` | draft → spec, absorbing `writing-specs` | 6 |
| `agents/phase-b.md` | spec → plan, absorbing `writing-plans` | 6 |
| `agents/phase-c.md` | plan → wave, absorbing `executing-tasks`, TDD, debugging | 6 |
| `agents/recover.md` | dirty-tree recovery | 6 |
| `templates/contract.md` | job invariants only | 7 |
| `templates/state.md` | pointer: picker call + dispatch table | 8 |
| `scripts/run.sh` | floor setup, plus contract migration | 9 |
| `scripts/status.sh` | operator surface, plus the picker prediction | 10 |
| `NOTICE.md`, `README.md`, `.claude/CLAUDE.md`, `templates/guide.md` | documentation and licence | 11 |

---

### Task 1: Test fixtures

**Files:**
- Modify: `scripts/selftest.sh:14-31` (after the `TMP`/`trap` line, before the `render_template` section)

**Interfaces:**
- Consumes: `TMP`, `is`, `ok`, `no` from the existing selftest harness; `SCRIPTS` (path to `scripts/`).
- Produces: `floor NAME` (sets `FIXTURE`), `draft SLUG`, `spec SLUG`, `plan SLUG TASKS OPEN`, `plan_bare SLUG`, `logline TEXT`, `gates_block LINE...` and `dirty`. (`pk`, the picker assertion, arrives with Task 4; `old_contract` with Task 9.)

Every fixture is a real git repository: `git status --porcelain` is normative input to the picker (spec §4) and must never be stubbed.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh`, immediately before the final `printf '\n%d passed...'` line:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `floor: command not found`, non-zero exit.

- [ ] **Step 3: Write the fixture builders**

Insert into `scripts/selftest.sh` after the `trap` line and before `PASS=0; FAIL=0`:

```bash
# --- floor fixtures -------------------------------------------------------
# Every fixture is a real git repo: `git status --porcelain` is normative
# input to the picker and must not be stubbed.

FIXTURE=""

# floor NAME — fresh repo with an empty, clean floor. Sets FIXTURE.
floor() {
  FIXTURE="$TMP/floor-$1"
  mkdir -p "$FIXTURE/.spectomat"/{drafts,specs,plans,done}
  (
    cd "$FIXTURE" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    printf '%s\n' '.spectomat/state.md' '.spectomat/work/' '.spectomat/log.md' > .gitignore
    printf '# Spectomat factory log\n\n' > .spectomat/log.md
    git add .gitignore
    git commit -qm init
  )
}

# Commit whatever the last fixture helper created, so the tree stays clean.
fixture_commit() { ( cd "$FIXTURE" && git add -A .spectomat && git commit -qm fixture >/dev/null 2>&1 ); return 0; }

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/selftest.sh`
Expected: PASS, 7 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/selftest.sh
git commit -m "test(selftest): add floor fixtures for the picker and archiver"
```

---

### Task 2: `gate_block` and `run_gates`

**Files:**
- Modify: `scripts/utils.sh` (append after `promised_empty`)
- Modify: `scripts/selftest.sh` (new assertions, plus the `gates_block` fixture)

**Interfaces:**
- Consumes: `CONTRACT` from `utils.sh`, `floor`/`is` from Task 1.
- Produces: `gate_block` (prints one gate command per line, comments and blanks dropped, exit 0), `run_gates` (exit 0 when every line exits 0; on failure exit 1 and set `GATE_FAILED` to the failing command).

- [ ] **Step 1: Write the failing test**

Add the fixture helper next to the Task 1 builders in `scripts/selftest.sh`. It needs four-backtick quoting here because its body writes a triple-backtick fence:

````bash
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
````

Then append the assertions before the final summary:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `gate_block: command not found`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/utils.sh`:

```bash
# Failed attempts at one phase for one slug before that slug is blocked.
STRIKE_LIMIT=3

# The contract's gate commands, one per line: everything inside the first fenced
# block after the Verification Gates heading, minus comment and blank lines. A
# later fenced block in the file is not part of the gates.
gate_block() {
  [[ -f "$CONTRACT" ]] || return 0
  awk '
    /^## Verification Gates/ { seen = 1; next }
    seen && !finished && /^```/ {
      if (open) { open = 0; finished = 1 } else { open = 1 }
      next
    }
    open { print }
  ' "$CONTRACT" | grep -vE '^[[:space:]]*(#|$)'
  return 0
}

# Run every gate line in order, stopping at the first failure; sets GATE_FAILED
# to the command that failed. The lines are operator-authored shell from a file
# committed in their own repository, at the same trust level as a package.json
# script: eval is the interface, not a shortcut.
run_gates() {
  local cmd
  GATE_FAILED=""
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    if ! eval "$cmd"; then
      GATE_FAILED="$cmd"
      return 1
    fi
  done < <(gate_block)
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/selftest.sh`
Expected: PASS, 9 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/utils.sh scripts/selftest.sh
git commit -m "feat(utils): read and run the contract's gate block"
```

---

### Task 3: `strike_count`, `least_struck`, `next_version`

**Files:**
- Modify: `scripts/utils.sh` (append after `run_gates`)
- Modify: `scripts/selftest.sh` (new assertions)

**Interfaces:**
- Consumes: `FLOOR`, `STRIKE_LIMIT` from `utils.sh`; `floor`, `logline`, `is` from Task 1.
- Produces: `strike_count LETTER SLUG` → integer on stdout; `least_struck LETTER` → reads candidate slugs from **stdin**, one per line, already sorted, prints the winner or nothing; `next_version CURRENT SLUG` → `major.minor.NNN` on stdout, exit 1 when the slug has no numeric prefix.

`least_struck` reads stdin rather than arguments because a slug may contain spaces: `run.sh` builds slugs as `NNN-<wish file name>`, and a wish named `my idea.md` yields the slug `001-my idea`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `strike_count: command not found`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/utils.sh`:

```bash
# How many times phase LETTER was struck on SLUG, per the factory log. The log
# is gitignored and append-only, so this is the only record of a strike. A slug
# containing a regex metacharacter can only over-match, never under-match.
strike_count() {
  local letter="$1" slug="$2" n
  [[ -f "$FLOOR/log.md" ]] || { echo 0; return 0; }
  n=$(grep -cE "^- .* · $letter · $slug · .*\(strike " "$FLOOR/log.md" 2>/dev/null) || n=0
  printf '%s\n' "${n// /}"
}

# The candidate with the fewest strikes at LETTER; candidate slugs arrive on
# stdin, one per line, already sorted, because a slug may contain spaces. Ties
# go to the first, which is the alphabetically first. Prints nothing when there
# are no candidates or every one has reached STRIKE_LIMIT, and the caller then
# moves on to the next stage.
least_struck() {
  local letter="$1" slug n best_n=-1 best=""
  while IFS= read -r slug; do
    [[ -n "$slug" ]] || continue
    n=$(strike_count "$letter" "$slug")
    [[ $n -lt $STRIKE_LIMIT ]] || continue
    if [[ $best_n -lt 0 ]] || [[ $n -lt $best_n ]]; then
      best_n=$n
      best="$slug"
    fi
  done
  [[ -z "$best" ]] || printf '%s\n' "$best"
}

# CURRENT with its patch replaced by the slug's NNN as a decimal integer.
next_version() {
  local cur="$1" slug="$2" n
  n=$(printf '%s' "$slug" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')
  [[ -n "$n" ]] || return 1
  printf '%s.%s.%d\n' \
    "$(printf '%s' "$cur" | cut -d. -f1)" \
    "$(printf '%s' "$cur" | cut -d. -f2)" \
    "$((10#$n))"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/selftest.sh`
Expected: PASS, 18 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/utils.sh scripts/selftest.sh
git commit -m "feat(utils): strike counting, candidate ordering and version bump"
```

---

### Task 4: The picker — `scripts/phase.sh`

**Files:**
- Create: `scripts/phase.sh`
- Modify: `scripts/selftest.sh` (the `pk` assertion helper and the verdict cases)

**Interfaces:**
- Consumes: `FLOOR`, `count`, `cd_root`, `least_struck` from `utils.sh`; the Task 1 fixtures.
- Produces: an executable printing exactly one verdict line — `A <slug>`, `B <slug>`, `C <slug>`, `D <slug>`, `R` or `E` — and exiting 0. Writes nothing; `status.sh` (Task 10) and every loop call it.

Implements spec §5.1 plus reconciliation R1: after the four stages, `E` is printed only when all three directories are empty; a floor with leftovers that matched no stage is an anomaly and yields `R`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — every `pk` assertion gets `""`, because `bash scripts/phase.sh` cannot open the file.

- [ ] **Step 3: Write the implementation**

Create `scripts/phase.sh`:

```bash
#!/bin/bash
# Spectomat phase picker — which phase the next loop must do.
#
#   phase.sh        prints one line and exits 0:
#                     "A <slug>"  draft -> spec
#                     "B <slug>"  spec -> plan
#                     "C <slug>"  plan -> wave
#                     "D <slug>"  plan -> done
#                     "R"         dirty tree, or a floor no stage claims
#                     "E"         nothing left; the flow may end
#
# Pure: reads the floor, log.md and git status, writes nothing. The session
# runs it once per loop and /spectomat:status runs it on demand.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

# Slugs of the .md files directly inside a floor directory, alphabetically.
# Bash sorts a glob, so no `ls` is parsed and a slug may contain spaces.
slugs_in() {
  local f
  for f in "$FLOOR/$1"/*.md; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "$(basename "$f" .md)"
  done
}

# Task files of one plan.
task_count() {
  local f n=0
  for f in "$FLOOR/plans/$1"/task-*.md; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
  done
  printf '%s\n' "$n"
}

# True when any task file of the plan still has an unchecked step.
has_open_step() { grep -qE '^- \[ \]' "$FLOOR/plans/$1"/task-*.md 2>/dev/null; }

# D: a plan whose task files exist and are all ticked. The task-file count is
# what stops an empty plan directory from satisfying "all steps ticked" for
# free and archiving work that was never built.
candidates_d() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ $(task_count "$s") -ge 1 ]] || continue
    has_open_step "$s" && continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# C: a plan with an unchecked step.
candidates_c() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    has_open_step "$s" || continue
    printf '%s\n' "$s"
  done < <(slugs_in plans)
}

# B: a spec with no plan overview, or an overview with no task files — a phase
# B that died before writing them. Without the second clause that plan matches
# no stage and is unreachable for the life of the floor.
candidates_b() {
  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if [[ ! -f "$FLOOR/plans/$s.md" ]] || [[ $(task_count "$s") -eq 0 ]]; then
      printf '%s\n' "$s"
    fi
  done < <(slugs_in specs)
}

# A: any draft.
candidates_a() { slugs_in drafts; }

# The floor holds no .md work at all.
floor_is_empty() {
  [[ $(count "$FLOOR/drafts") -eq 0 ]] &&
  [[ $(count "$FLOOR/specs") -eq 0 ]] &&
  [[ $(count "$FLOOR/plans") -eq 0 ]]
}

main() {
  local pick
  [[ -d "$FLOOR" ]] || { echo "E"; exit 0; }
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || { echo "R"; exit 0; }

  pick=$(candidates_d | least_struck D); [[ -z "$pick" ]] || { echo "D $pick"; exit 0; }
  pick=$(candidates_c | least_struck C); [[ -z "$pick" ]] || { echo "C $pick"; exit 0; }
  pick=$(candidates_b | least_struck B); [[ -z "$pick" ]] || { echo "B $pick"; exit 0; }
  pick=$(candidates_a | least_struck A); [[ -z "$pick" ]] || { echo "A $pick"; exit 0; }

  # No stage claimed the floor. That is the end of the flow only when nothing
  # is left; anything remaining is an anomaly for the janitor — an orphan plan
  # overview whose spec is gone, or a slug parked at STRIKE_LIMIT that was
  # never moved to done/.
  if floor_is_empty; then echo "E"; else echo "R"; fi
}

main "$@"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `chmod +x scripts/phase.sh && scripts/selftest.sh`
Expected: PASS, 15 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/phase.sh scripts/selftest.sh
git commit -m "feat(phase): pick the loop's phase from the floor in bash"
```

---

### Task 5: The archiver — `scripts/archive.sh`

**Files:**
- Create: `scripts/archive.sh`
- Modify: `scripts/selftest.sh` (archive scenarios)

**Interfaces:**
- Consumes: `FLOOR`, `die`, `gate_block`, `run_gates`, `GATE_FAILED`, `strike_count`, `STRIKE_LIMIT`, `next_version` from `utils.sh`; the Task 1 and Task 2 fixtures.
- Produces: `archive.sh <slug>` — exit 0 after archiving, exit 1 after a strike that is not the third. No other script calls it; the pointer runs it directly.

Implements spec §5.5. The third strike takes the same three `git mv` calls with a `.blocked` infix, so the moves are written once and `print_blocked` (which matches `*.blocked.md`) needs no change.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `arc` exits 127, so the first assertion reports `127` instead of `0`.

- [ ] **Step 3: Write the implementation**

Create `scripts/archive.sh`:

```bash
#!/bin/bash
# Spectomat archiver — phase D.
#
#   archive.sh <slug>
#
# Runs the contract's gates, moves the slug's trail into done/, bumps the patch
# version to the slug's NNN, makes one commit and writes one log line. A failing
# gate moves nothing and exits 1, until the third strike: then the trail is
# archived with a .blocked infix so the floor can move on.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

SLUG="${1:-}"
BLOCK=""      # ".blocked" once the third strike lands
GATE_RESULT="" # "N/N" or "failed", for the log line
VERSION=""    # the new package.json version, when there is one

now() { date -u +%FT%RZ; }
log_line() { printf '%s\n' "$1" >> "$FLOOR/log.md"; }

require_ready() {
  [[ -n "$SLUG" ]] || die "usage: archive.sh <slug>"
  [[ -z "$(git status --porcelain)" ]] || die "tree is dirty: the janitor runs before phase D"
  [[ -f "$FLOOR/specs/$SLUG.md" ]] || die "no $FLOOR/specs/$SLUG.md"
  [[ -f "$FLOOR/plans/$SLUG.md" ]] || die "no $FLOOR/plans/$SLUG.md"
}

# Run the gates. A failure logs a strike and stops, unless it is the third:
# then the trail is archived blocked instead of stranding the floor.
gate_or_strike() {
  local total n
  total=$(gate_block | wc -l | tr -d ' ')
  if run_gates; then
    GATE_RESULT="$total/$total"
    return 0
  fi
  n=$(( $(strike_count D "$SLUG") + 1 ))
  log_line "- $(now) · D · $SLUG · gate failed: $GATE_FAILED (strike $n)"
  if [[ $n -lt $STRIKE_LIMIT ]]; then
    echo "❌ gate failed: $GATE_FAILED (strike $n of $STRIKE_LIMIT)" >&2
    exit 1
  fi
  BLOCK=".blocked"
  GATE_RESULT="failed"
}

move_trail() {
  git mv "$FLOOR/specs/$SLUG.md" "$FLOOR/done/$SLUG.spec$BLOCK.md"
  git mv "$FLOOR/plans/$SLUG.md" "$FLOOR/done/$SLUG.plan$BLOCK.md"
  [[ ! -d "$FLOOR/plans/$SLUG" ]] || git mv "$FLOOR/plans/$SLUG" "$FLOOR/done/$SLUG"
}

# The patch version becomes the slug's NNN; major and minor are kept. Blocked
# work ships no version. npm is used rather than a jq rewrite so package-lock
# stays in step.
bump_version() {
  local cur
  [[ -z "$BLOCK" ]] || return 0
  [[ -f package.json ]] || return 0
  cur=$(jq -r '.version // empty' package.json 2>/dev/null) || return 0
  [[ -n "$cur" ]] || return 0
  VERSION=$(next_version "$cur" "$SLUG") || { VERSION=""; return 0; }
  npm version --no-git-tag-version "$VERSION" >/dev/null 2>&1 || VERSION=""
}

commit_archive() {
  local msg
  if [[ -n "$BLOCK" ]]; then
    msg="chore($SLUG): blocked after $STRIKE_LIMIT strikes"
  else
    msg="chore($SLUG): archived${VERSION:+, v$VERSION}"
  fi
  git add -A "$FLOOR/done" "$FLOOR/specs" "$FLOOR/plans"
  [[ ! -f package.json ]] || git add package.json
  [[ ! -f package-lock.json ]] || git add package-lock.json
  git commit -q -m "$msg"
}

log_result() {
  if [[ -n "$BLOCK" ]]; then
    log_line "- $(now) · D · $SLUG · blocked after $STRIKE_LIMIT strikes · gates $GATE_RESULT"
  else
    log_line "- $(now) · D · $SLUG · archived · gates $GATE_RESULT${VERSION:+ · v$VERSION}"
  fi
}

main() {
  require_ready
  gate_or_strike
  move_trail
  bump_version
  commit_archive
  log_result
  echo "D $SLUG · gates $GATE_RESULT${VERSION:+ · v$VERSION}${BLOCK:+ · BLOCKED}"
}

main "$@"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `chmod +x scripts/archive.sh && scripts/selftest.sh`
Expected: PASS, 20 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/archive.sh scripts/selftest.sh
git commit -m "feat(archive): run phase D as a script"
```

---

### Task 6: The four briefs

**Files:**
- Create: `agents/phase-a.md`, `agents/phase-b.md`, `agents/phase-c.md`, `agents/recover.md`
- Delete: `agents/looper.md`, `references/writing-specs.md`, `references/writing-plans.md`, `references/executing-tasks.md`, `references/test-driven-development.md`, `references/systematic-debugging.md`
- Modify: `scripts/selftest.sh` (brief hygiene assertions)

**Interfaces:**
- Consumes: the task line the pointer sends (Task 8), whose exact shape is two lines — the verdict line, then `Plugin root: <absolute path>`.
- Produces: agent types `spectomat:phase-a`, `spectomat:phase-b`, `spectomat:phase-c`, `spectomat:recover`. `AGENT_COUNT` is 4.

Implements spec §6.3 and reconciliation R2: a brief carries no plugin path of its own, but the task line supplies one, because phase A needs `templates/spec.md`, phase B needs `templates/plan.md` and `templates/task.md`, and phase C sends `prompts/implementer.md` and `prompts/reviewer.md` verbatim to its subagents.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
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
is "no script names the looper" \
  "$(grep -l 'looper' "$SCRIPTS"/*.sh | grep -v selftest | wc -l | tr -d ' ')" "0"
is "phase-c names both prompts" \
  "$(grep -cE 'prompts/(implementer|reviewer)\.md' "$AGENTS/phase-c.md" | tr -d ' ')" "2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `agents/phase-a.md exists` reports `no`, `references/ is gone` reports `yes`.

- [ ] **Step 3: Write the four briefs**

Each brief opens with frontmatter and the same four-line preamble, then its own craft. The preamble, identical in all four apart from the phase named:

```markdown
You are one loop of the Spectomat factory, dispatched to do phase <X> and nothing else.

Your task line gives the phase letter, the slug, and the plugin root. When this brief names a plugin file, read `<plugin root>/<that path>`.

Read `./.spectomat/contract.md` in full — it is the project's authoritative contract and may have been edited since the last loop — then `./.spectomat/memory.md`. The contract holds the floor, the gates, the memory rules, the log format and the constraints; this brief holds how your phase is done. Where they disagree, the contract wins.

Never ask the user anything. Where an input is silent, decide, record the decision where the contract says, and continue.
```

`agents/phase-a.md` — frontmatter `name: phase-a`, description `Phase A of the Spectomat factory: turns one draft into a normative spec. Dispatched by an armed flow's pointer, one fresh agent per loop. Never use it by hand.` Body: the preamble, then the procedure from the old contract's `### A · Draft → Spec` (read the draft in full; write `specs/<slug>.md` from `templates/spec.md`; scope to what the draft asks; every choice the draft did not make is an `assumed` row in the Decisions table; the draft's precise words go into §1 verbatim; then `git mv drafts/<slug>.md done/<slug>.draft.md`), then the whole body of the deleted `references/writing-specs.md` as its Shape, Rules, Smells and Review checklist sections. Close with: record memory, commit `<type>(<slug>): …`, log one line, report.

`agents/phase-b.md` — frontmatter `name: phase-b`, description `Phase B of the Spectomat factory: turns one spec into a plan overview and one task file per task. Dispatched by an armed flow's pointer, one fresh agent per loop. Never use it by hand.` Body: the preamble, then the procedure from `### B · Spec → Plan`, then the whole body of the deleted `references/writing-plans.md`, whose `templates/plan.md` and `templates/task.md` references become `<plugin root>/templates/…`. Close as phase A does.

`agents/phase-c.md` — frontmatter `name: phase-c`, description `Phase C of the Spectomat factory: executes one wave of ready tasks with implementer and reviewer subagents. Dispatched by an armed flow's pointer, one fresh agent per loop. Never use it by hand.` Body: the preamble, then the procedure from `### C · Plan → Wave`, then the whole body of `references/executing-tasks.md`, then `references/test-driven-development.md` as a `## Test-driven development` section, then `references/systematic-debugging.md` as a `## When a gate fails unexpectedly` section. The two constants live here and nowhere else, stated once each: `MAX_WAVE = 3` (at most three tasks in one wave) and `MAX_FIX_ROUNDS = 3` (at most three fix rounds per task). Every cross-reference of the form "the `<name>` reference next to this file" becomes a section link within this brief. `prompts/implementer.md` and `prompts/reviewer.md` stay separate files, read from `<plugin root>/prompts/` and sent verbatim.

`agents/recover.md` — the full text:

```markdown
---
name: recover
description: The Spectomat janitor: restores a clean tree after a loop died mid-phase, or rules on a floor the picker could not classify. Dispatched by an armed flow's pointer. Never use it by hand.
---

You are the Spectomat janitor. The picker returned `R`, so this floor is not in a state any phase can start from.

Read `./.spectomat/contract.md` and `./.spectomat/memory.md`. Never ask the user anything.

Find which of the two cases you are in, and do only that one:

**A dirty tree.** `git status --porcelain` is not silent, so a previous loop died mid-phase. Inspect the changes. If they are a phase all but finished, finish it and commit it under that phase's own message. If they are partial or you cannot tell what they were for, discard them — `git checkout -- .` and `git clean -fd` the paths under `.spectomat/` and the paths the task files name. Never discard a change outside those paths; report it instead and stop.

**A floor no stage claims.** The tree is clean but `drafts/`, `specs/` or `plans/` still holds a file. Two causes, and each has one fix: a plan overview whose spec is gone is stranded, so move the overview and its task directory into `done/` with the `.blocked` infix; a slug at three strikes that was never blocked is moved into `done/` the same way. Log the reason in both cases.

Then commit, append one line to `log.md` in the contract's format, and report what you found, what you did, and the commit hash.

Do no phase work. Your only job is to leave a floor the picker can classify.
```

- [ ] **Step 4: Delete what the briefs replaced, then run the tests**

```bash
git rm -q agents/looper.md
git rm -qr references/
scripts/selftest.sh
```

Expected: PASS, 18 new `ok` lines, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add agents scripts/selftest.sh
git commit -m "feat(agents): one brief per phase, absorbing references/"
```

---

### Task 7: Cut the contract

**Files:**
- Modify: `templates/contract.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: a contract of roughly 105 lines carrying only job invariants, opening with the marker `<!-- spectomat-contract: 2 -->` that Task 9 greps.

Implements spec §6.2 and §8.2.

- [ ] **Step 1: Add the version marker**

Insert as the very first line of `templates/contract.md`, before `# Spectomat Factory`:

```markdown
<!-- spectomat-contract: 2 -->
```

- [ ] **Step 2: Remove the whole `## Phases` section**

Delete from the line `## Phases` up to but not including `## Verification Gates` — the four `### A/B/C/D` subsections, 45 lines. Their content now lives in the briefs of Task 6.

- [ ] **Step 3: Remove the References line**

Delete the line beginning `References: instruction files the phases below name by short name`. The directory no longer exists.

- [ ] **Step 4: Rewrite Loop Contract step 2**

Replace the whole of numbered item 2 (`**Pick exactly one phase**, …` and its five bullets) with:

```markdown
2. **Do the phase you were handed.** The picker chose it from the floor before you were launched; your task line names it and the slug. Never do a second phase, and never substitute a different one — if the phase makes no sense for this floor, say so in your report and stop.
```

- [ ] **Step 5: Remove the Completion section and two constraints**

Delete the whole `## Completion` section (five lines): the flow now ends when the picker prints `E` and the session relays it, so no agent can claim completion. From `## Constraints`, delete `- DO NOT Emit a false promise.` and `- DO NOT more than one phase in a loop.` — the first is structurally impossible, the second is impossible for an agent that only knows one phase.

- [ ] **Step 6: Verify the shape**

```bash
grep -c '^## ' templates/contract.md          # expect 6: floor, Loop Contract, Gates, Memory, Log Format, Constraints
grep -q '^<!-- spectomat-contract: 2 -->' templates/contract.md && echo marker ok
grep -c 'Phases\|references/\|false promise' templates/contract.md   # expect 0
wc -l templates/contract.md                   # expect 100-115
bash -n scripts/*.sh && scripts/selftest.sh
```

Expected: `marker ok`, a zero from the third grep, and a green selftest.

- [ ] **Step 7: Commit**

```bash
git add templates/contract.md
git commit -m "refactor(contract): keep the job invariants, drop the phase craft"
```

---

### Task 8: Rewrite the pointer

**Files:**
- Modify: `templates/state.md:9-26` (everything after the frontmatter)

**Interfaces:**
- Consumes: `{{PLUGIN_ROOT}}`, already rendered by `run.sh`.
- Produces: the per-loop instruction the Stop hook feeds back. `stop-hook.sh` reads the body with `awk '/^---$/{i++; next} i>=2'` and is unaffected by its content.

Implements spec §3.3, §6.4 and reconciliation R2.

- [ ] **Step 1: Replace the body**

Keep the frontmatter exactly as it is. Replace everything from `# State tracker` to the end of the file with:

```markdown
# State tracker

Every loop runs in a fresh context. Do no factory work in this session.

## 1. Ask the picker

Run: `bash {{PLUGIN_ROOT}}/scripts/phase.sh`

It prints exactly one line. Do not interpret the floor yourself, and do not run it twice.

## 2. Act on that line, and only on it

| Line | Do |
| --- | --- |
| `A <slug>` / `B <slug>` / `C <slug>` | launch exactly one subagent with the Agent tool, `run_in_background: false`, `subagent_type: "spectomat:phase-<letter>"` when that type is listed; otherwise `subagent_type: "general-purpose"` with the body of `{{PLUGIN_ROOT}}/agents/phase-<letter>.md` after its frontmatter as the brief |
| `R` | the same, with `spectomat:recover` / `{{PLUGIN_ROOT}}/agents/recover.md` |
| `D <slug>` | run `bash {{PLUGIN_ROOT}}/scripts/archive.sh <slug>` and report its output; launch no subagent |
| `E` | the floor is empty and the tree is clean. Report what finished, then make `<promise>FACTORY EMPTY</promise>` the last line of your message |

The task line for any subagent is these two lines, verbatim:

```text
<the line phase.sh printed>
Plugin root: {{PLUGIN_ROOT}}
```

## 3. Report and stop

Print the report in at most five lines, then stop.

Do not read the contract, the floor or the code yourself. Do not retry a failed loop here — the next loop is a new picker call and a new subagent. Write `<promise>FACTORY EMPTY</promise>` only when the picker printed `E`; it is a verdict you relay, never a judgement you make.
```

- [ ] **Step 2: Verify the hook still finds a body**

```bash
awk '/^---$/{i++; next} i>=2' templates/state.md | head -3
grep -c '{{PLUGIN_ROOT}}' templates/state.md    # expect 5
grep -c 'looper\|references/' templates/state.md # expect 0
```

Expected: the body prints starting at `# State tracker`, five placeholder hits, zero stale names.

- [ ] **Step 3: Commit**

```bash
git add templates/state.md
git commit -m "feat(state): dispatch the picker's verdict instead of one looper"
```

---

### Task 9: Migrate existing contracts

**Files:**
- Modify: `scripts/utils.sh` (append `migrate_contract`)
- Modify: `scripts/run.sh:120-141` (`render_factory`)
- Modify: `scripts/selftest.sh` (the `old_contract` fixture and migration cases)

**Interfaces:**
- Consumes: `CONTRACT`, `PLUGIN_ROOT`, `gate_block`, `render_template` from `utils.sh`.
- Produces: `migrate_contract` — exit 0 when it rewrote the contract, exit 1 when there was nothing to do. It lives in `utils.sh` rather than `run.sh` so selftest can call it without running `main`.

Implements spec §8.1. `contract.md` is committed, so the previous text stays recoverable in git history; `memory.md` is never touched, because it belongs to the project.

- [ ] **Step 1: Write the failing test**

Add the fixture next to the Task 1 builders, four-backtick quoted because it writes a fence:

````bash
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
````

Then the assertions, before the final summary:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — `migrate_contract: command not found`, so the first assertion reports `127`.

- [ ] **Step 3: Write `migrate_contract`**

Append to `scripts/utils.sh`:

```bash
# Rewrite a pre-migration contract from the current template, carrying the
# operator's gate lines across verbatim. A contract that no longer has a
# "## Phases" section is already current and is left alone. Exit 0 when it
# rewrote the file, 1 when there was nothing to do. The previous text stays in
# git history, because the contract is committed.
migrate_contract() {
  local gates
  [[ -f "$CONTRACT" ]] || return 1
  grep -q '^## Phases' "$CONTRACT" || return 1
  gates=$(gate_block)
  render_template "$PLUGIN_ROOT/templates/contract.md" "$CONTRACT" \
    REPO="$(pwd)" \
    GATES="$gates"
}
```

- [ ] **Step 4: Wire it into `run.sh`**

In `render_factory()`, replace the contract branch (currently `if [[ -f "$CONTRACT" ]]; then echo "$CONTRACT: exists, kept"`) with:

```bash
  if [[ -f "$CONTRACT" ]]; then
    if migrate_contract; then
      STAGE+=("$CONTRACT")
      echo "$CONTRACT: migrated to the phase-agent contract (gates preserved)"
    else
      echo "$CONTRACT: exists, kept"
    fi
  else
```

Leave the `else` branch — `detect_gates`, `render_template`, `STAGE+=`, `echo` — exactly as it is.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash -n scripts/run.sh && scripts/selftest.sh`
Expected: PASS, 8 new `ok` lines, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils.sh scripts/run.sh scripts/selftest.sh
git commit -m "feat(run): migrate an old contract, keeping the operator's gates"
```

---

### Task 10: Operator surface

**Files:**
- Modify: `scripts/print.sh` (new `print_next`)
- Modify: `scripts/status.sh:16-20` (`main`)
- Modify: `scripts/run.sh:175-190` (`announce`)
- Modify: `scripts/stop-hook.sh:107` (`system_msg`)
- Modify: `scripts/selftest.sh` (status prediction case)

**Interfaces:**
- Consumes: `PLUGIN_ROOT` from `utils.sh`, `phase.sh` from Task 4.
- Produces: a `--- next ---` section in `/spectomat:status`, and two runtime strings that no longer claim the model decides completion.

Implements spec §7.2 and §7.3. AC-5.1 is automated here rather than left manual, because the fixtures of Task 1 make it cheap.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
echo "status"
floor st; spec 001-a; plan 001-a 2 1
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "status prints the next section" "$(printf '%s\n' "$st_out" | grep -c '^--- next ---$')" "1"
is "status predicts the verdict"    "$(printf '%s\n' "$st_out" | grep -c '^C 001-a$')" "1"
floor st2
st_out=$(cd "$FIXTURE" && bash "$SCRIPTS/status.sh" 2>/dev/null)
is "an empty floor predicts E"      "$(printf '%s\n' "$st_out" | grep -c '^E$')" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — both counts are `0`; `status.sh` has no `--- next ---` section.

- [ ] **Step 3: Add `print_next` to `print.sh`**

Append to `scripts/print.sh`:

```bash
# What the next loop will do. This runs the picker itself rather than
# re-deriving the answer, so the prediction cannot drift from the decision.
print_next() {
  echo "--- next ---"
  bash "$PLUGIN_ROOT/scripts/phase.sh"
}
```

- [ ] **Step 4: Call it from `status.sh`**

In `main()`, insert `print_next` immediately after `print_floor`, so it runs only once the floor directory is known to exist:

```bash
  print_floor
  print_next
  print_plans
```

- [ ] **Step 5: Correct the two runtime strings**

In `scripts/run.sh`, `announce()`, replace the last four lines of the heredoc (from `When you try to exit` to `Never output a false promise.`) with:

```text
When you try to exit, the Stop hook feeds the prompt below back to you.
Each loop asks scripts/phase.sh which phase applies and dispatches it.
The flow ends when the picker answers E, or at the loop cap.
```

In `scripts/stop-hook.sh`, `continue_loop()`, replace the `system_msg` assignment with:

```bash
  system_msg="🔄 Spectomat loop $next_loop | Ends when scripts/phase.sh answers E, or at the cap ($MAX_LOOPS)"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash -n scripts/*.sh && scripts/selftest.sh`
Expected: PASS, 3 new `ok` lines, `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add scripts/print.sh scripts/status.sh scripts/run.sh scripts/stop-hook.sh scripts/selftest.sh
git commit -m "feat(status): predict the next phase with the picker itself"
```

---

### Task 11: Documentation, licence and release

**Files:**
- Modify: `NOTICE.md`, `README.md`, `.claude/CLAUDE.md`, `templates/guide.md`, `.claude-plugin/plugin.json`
- Modify: `scripts/selftest.sh` (repo-wide hygiene)

**Interfaces:**
- Consumes: everything built in Tasks 1–10.
- Produces: a repo where the word **looper** and the path `references/` survive only in `docs/`, which records the design that removed them.

Implements spec §7.4, §8.3 and §8.4. The `NOTICE.md` change is a licence obligation, not housekeeping: it currently attributes four superpowers-derived files by a path that no longer exists.

- [ ] **Step 1: Write the failing test**

Append to `scripts/selftest.sh` before the final summary:

```bash
# The retired vocabulary. This file names the retired words in order to scan
# for them, so it leaves itself out of its own scan, as the perl check does.
# docs/ is excluded: it records the design that removed them.
echo "vocabulary"
REPO_ROOT="$(dirname "$SCRIPTS")"
stale=$(cd "$REPO_ROOT" && grep -rl --exclude-dir=.git --exclude-dir=docs \
          -e 'looper' -e 'references/' . 2>/dev/null | grep -v 'selftest\.sh$' | tr '\n' ' ')
is "nothing names the looper or references/" "${stale% }" ""
missing=$(cd "$REPO_ROOT" && for f in $(grep -oE '`[a-zA-Z0-9_./-]+\.(md|sh|json)`' NOTICE.md | tr -d '`'); do
            [[ -e "$f" ]] || printf '%s ' "$f"; done)
is "NOTICE.md names only files that exist" "${missing% }" ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/selftest.sh`
Expected: FAIL — the stale list names `README.md`, `.claude/CLAUDE.md`, `templates/guide.md` and `NOTICE.md`; the missing list names the five deleted `references/*.md` files.

- [ ] **Step 3: Rewrite `NOTICE.md`**

Replace the third paragraph with one that follows the material to where it now lives:

```markdown
Material condensed from [superpowers](https://github.com/obra/superpowers) 6.3.0 by Jesse Vincent, MIT License (`LICENSE-superpowers`), is carried by two agent briefs. `agents/phase-b.md` contains a condensed `writing-plans`. `agents/phase-c.md` contains condensed `test-driven-development` and `systematic-debugging`, and a merge of `subagent-driven-development`, `executing-plans`, `requesting-code-review` and `receiving-code-review`. All of it is shortened and rewritten for an unattended loop: no questions to a human, no branches or worktrees, plan and work paths under `.spectomat/`, and the text inlined into the brief that uses it rather than kept as separate reference files.
```

Leave the ralph-loop paragraph as it is: `scripts/stop-hook.sh` and the state-file format still derive from it.

- [ ] **Step 4: Update `README.md`**

In the File Layout list: replace the `agents/` bullet with one naming the four briefs and the dispatch rule; replace the `references/` bullet with nothing; extend the `scripts/` sub-list with `phase.sh` (the picker, one verdict line per loop) and `archive.sh` (phase D end to end). In the opening diagram line, keep `idea ──A──▶ specs ──B──▶ plans/tasks×n ──C×n──▶ code + commits ──D──▶ done` as it is — the phases did not change, only who performs them.

- [ ] **Step 5: Update `.claude/CLAUDE.md`**

In *How the pieces fit*: replace the paragraph describing `hooks/hooks.json` and the pointer so it names the picker, the four briefs, and `archive.sh`; delete the `references/` paragraph entirely and replace it with one sentence saying the craft of each phase lives in its brief and the invariants in the contract. In *Conventions*, replace the last bullet's keep-in-step rule with: a change to the verdict grammar must keep `phase.sh`, `templates/state.md`, `print.sh` and `archive.sh` in step; a change to what a phase does belongs in its brief, not in the contract or the pointer.

- [ ] **Step 6: Update `templates/guide.md`**

Three edits. In *The Flow*, replace the opening sentence with: each loop is one picker verdict, dispatched to a fresh phase agent, to the archiver, or to the janitor. In *Loops Mechanics*, replace the paragraph describing the looper with one describing `phase.sh` and the dispatch table, and state that the flow ends when the picker answers `E`. In *Glossary*, delete **Looper** and add, in the file's existing one-line style: **Picker**, **Phase agent**, **Archiver**, **Janitor**, **Verdict**, and amend **Loop** to *one picker verdict, one phase, one commit, one log line*.

- [ ] **Step 7: Bump the plugin version**

Set `.claude-plugin/plugin.json` `"version"` to `"0.2.0"` — the flow's mechanics changed, so this is not a patch. If `.claude-plugin/marketplace.json` pins a version, set it to match.

- [ ] **Step 8: Run the full gates**

```bash
bash -n scripts/*.sh
scripts/selftest.sh
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

Expected: all green, `0 failed`, both manifests valid.

- [ ] **Step 9: Commit**

```bash
git add NOTICE.md README.md .claude/CLAUDE.md templates/guide.md .claude-plugin scripts/selftest.sh
git commit -m "docs: retire the looper, move attribution to the briefs, v0.2.0"
```

---

## Out-of-band verification

Not gated by `selftest.sh`; run these by hand once Task 11 is committed, per spec §15.2.

- [ ] **Agents load.** Reinstall the plugin, restart Claude Code, then run any nested session with `--debug-file /tmp/sp.log --model opus` and grep the log for `Loaded 4 agents from plugin`. A `-p` prompt asking Claude to list agent types reports NONE even when they are loaded, so it must not be used as the check.
- [ ] **A full flow.** In a scratch git repo with two drafts on the floor: `claude -p "/spectomat:run 25" --plugin-dir <this repo> --model opus`. Expect two archived trails in `done/`, committed code, and the run ending on `<promise>FACTORY EMPTY</promise>`.
- [ ] **The Stop hook still releases.** Pipe a fabricated `{"session_id","transcript_path"}` payload into `scripts/stop-hook.sh` and confirm `decision`, the bumped `loop:`, and removal of the state file on the promise and at the cap.
- [ ] **The `telegator` migration.** Run `/spectomat:run` in `~/Projects/telegator` and read the diff of `.spectomat/contract.md`: the phases section gone, the marker present, its gate lines unchanged, `memory.md` untouched.
- [ ] **Picker cost.** `time scripts/phase.sh` on a floor of 20 plans stays under 200 ms; it is on the path of every loop and of every `status`.
