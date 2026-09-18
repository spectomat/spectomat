# Shared harness for tests/*.sh — sourced, never run directly.
#
# A caller sets SCRIPTS before sourcing this file:
#   SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Every fixture is a real git repo: `git status --porcelain` is normative
# input to the picker and must not be stubbed.

source "$SCRIPTS/utils.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- floor fixtures -------------------------------------------------------

FIXTURE=""
TEMPLATE=""

# Build the one pristine floor repo this file's fixtures copy from. A `git
# init` plus commit is expensive next to the rest of a test file, and floor()
# may run many times, so it pays to do it once and `cp -R` a real repo
# instead of re-running git init/config/commit per call.
floor_template() {
  TEMPLATE="$TMP/floor-template"
  mkdir -p "$TEMPLATE/.spectomat" "$TEMPLATE/.wishlist"
  (
    cd "$TEMPLATE" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    printf '%s\n' '.spectomat/state.json' '.spectomat/work/' '.spectomat/log.md' > .gitignore
    printf '# Spectomat factory log\n\n' > .spectomat/log.md
    printf '{"slugs": {}}\n' > .spectomat/state.json
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
  printf '{"active": true, "iteration": 1, "max_iterations": 5, "session_id": "test", "started_at": "t", "slugs": {}}\n' > "$FIXTURE/.spectomat/state.json"
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

# The floor is slug-major: every fixture helper below writes into the slug's
# own dir, .spectomat/<slug>/, which is where the real phases write too.
draft() {
  mkdir -p "$FIXTURE/.spectomat/$1"
  printf 'idea\n' > "$FIXTURE/.spectomat/$1/draft.md"
  state_slug "$1" SPECIFY
  fixture_commit
}

spec() {
  mkdir -p "$FIXTURE/.spectomat/$1"
  printf 'spec\n' > "$FIXTURE/.spectomat/$1/spec.md"
  if [[ -n "${2:-}" ]]; then state_slug "$1" PLAN; else state_slug "$1" REVIEW-SPEC; fi
  fixture_commit
}

# plan SLUG TASKS OPEN [reviewed] — an overview, TASKS task files, and the
# ledger holding TASKS tasks of which OPEN are still pending. Each task depends
# on the one before it, which is the shape a real PLAN writes and the one that
# exercises task_next's dependency walk.
plan() {
  local slug="$1" tasks="$2" open="$3" reviewed="${4:-}" i f done_n rows
  mkdir -p "$FIXTURE/.spectomat/$slug/tasks"
  printf 'overview\n' > "$FIXTURE/.spectomat/$slug/plan.md"
  done_n=$((tasks - open))
  rows=""
  i=1
  while [[ $i -le $tasks ]]; do
    printf -v f '%s/.spectomat/%s/tasks/task-%02d-x.md' "$FIXTURE" "$slug" "$i"
    printf 'step\n' > "$f"
    rows+="$(ledger_row "$slug" "$i" "$([[ $i -le $done_n ]] && echo done || echo pending)")"
    [[ $i -eq $tasks ]] || rows+=","
    i=$((i + 1))
  done
  printf '{"slug": "%s", "tasks": [%s]}\n' "$slug" "$rows" \
    > "$FIXTURE/.spectomat/$slug/tasks.json"
  if [[ -n "$reviewed" ]]; then
    state_slug "$slug" ARCHIVE
  elif [[ $open -eq 0 ]]; then
    state_slug "$slug" REVIEW
  else
    state_slug "$slug" IMPLEMENT
  fi
  fixture_commit
}

# ledger_row SLUG ID STATUS — one task object, depending on the task before it.
# A done task carries a plausible commit range; a pending one carries nulls.
ledger_row() {
  local slug="$1" id="$2" status="$3" dep="[]" res='null, "tests": null, "gates": null'
  [[ "$id" -eq 1 ]] || dep="[$((id - 1))]"
  [[ "$status" != done ]] || res='"aaaaaaa..bbbbbbb", "tests": "1/1 (x)", "gates": "passed"'
  printf '{"id": %d, "name": "x", "file": "tasks/task-%02d-x.md", "component": "x", "covers": [], "dependsOn": %s, "status": "%s", "commits": %s}' \
    "$id" "$id" "$dep" "$status" "$res"
}

# plan_bare SLUG — an overview with no task files, the half-finished PLAN phase
# (D7). Writes no spec, so used alone it is also the stranded-overview fixture.
plan_bare() {
  mkdir -p "$FIXTURE/.spectomat/$1"
  printf 'overview\n' > "$FIXTURE/.spectomat/$1/plan.md"
  state_slug "$1" PLAN
  fixture_commit
}

# archived SLUG [blocked] — a finished slug, as agent-archive.sh leaves it: the trail
# stays put, one marker file says how it ended, and state.json carries the
# terminal phase that actually takes it out of the flow.
archived() {
  mkdir -p "$FIXTURE/.spectomat/$1"
  printf 'spec\n' > "$FIXTURE/.spectomat/$1/spec.md"
  printf 'plan\n' > "$FIXTURE/.spectomat/$1/plan.md"
  if [[ -z "${2:-}" ]]; then
    printf 'archived\n' > "$FIXTURE/.spectomat/$1/done.md"
    state_slug "$1" DONE
  else
    printf 'blocked\n' > "$FIXTURE/.spectomat/$1/blocked.md"
    state_slug "$1" BLOCKED
  fi
  fixture_commit
}

# logline TEXT — append to the gitignored factory log; never committed.
logline() { printf '%s\n' "$1" >> "$FIXTURE/.spectomat/log.md"; }

# dirty — leave an untracked file so `git status --porcelain` is not silent.
dirty() { printf 'x\n' > "$FIXTURE/untracked.txt"; }

# gates_block LINE... — a .spectomat/gates.sh running LINE..., the way command-run.sh
# renders it: `set -e` chains the lines, so the exit code is the whole run's.
gates_block() {
  {
    printf '#!/bin/bash\nset -e\ncd "$(dirname "${BASH_SOURCE[0]}")/.."\n\n'
    printf '%s\n' "$@"
  } > "$FIXTURE/.spectomat/gates.sh"
  chmod +x "$FIXTURE/.spectomat/gates.sh"
  fixture_commit
}

# state_slug SLUG PHASE — set (or create) SLUG's state.json entry. state.json
# carries no task counters: the ledger does, and plan() writes it.
state_slug() {
  local slug="$1" phase="$2"
  jq --arg s "$slug" --arg p "$phase" \
    '.slugs[$s].phase = $p' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
}

# strike SLUG PHASE [N] — set SLUG's PHASE strike count to N (default 1).
strike() {
  local slug="$1" phase="$2" n="${3:-1}"
  jq --arg s "$slug" --arg p "$phase" --argjson n "$n" \
    '.slugs[$s] //= {} | .slugs[$s].strikes //= {} | .slugs[$s].strikes[$p] = $n' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
}

# verdict DIR SCRIPTS — run phase.sh in DIR and print "PHASE" or "PHASE SLUG",
# extracted from its frontmatter block's phase/slug fields. Shared by every
# test that only cares about the plain verdict, not the block's dispatch
# fields (subagent, brief, plugin_root — covered directly in phase_test.sh).
verdict() {
  local dir="$1" scripts="$2" out phase slug
  out="$(cd "$dir" && bash "$scripts/phase.sh")"
  phase="$(printf '%s\n' "$out" | sed -n 's/^phase://p')"
  slug="$(printf '%s\n' "$out" | sed -n 's/^slug://p')"
  if [[ -z "$slug" ]]; then printf '%s\n' "$phase"; else printf '%s %s\n' "$phase" "$slug"; fi
}

# --- assertions ------------------------------------------------------------

PASS=0; FAIL=0

ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no() {
  FAIL=$((FAIL+1))
  printf '  FAIL %s\n       want: %q\n       got:  %q\n' "$1" "$3" "$2"
}
is() { [[ "$2" == "$3" ]] && ok "$1" || no "$1" "$2" "$3"; }

# finish — print the file's summary line and set the exit status. Every test
# file ends by sourcing this, so the trailing "N passed, M failed" line has
# one spelling everywhere and the runner can rely on it.
finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
