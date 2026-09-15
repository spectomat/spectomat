# Shared harness for scripts/tests/*.sh — sourced, never run directly.
#
# A caller sets SCRIPTS before sourcing this file:
#   SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
  mkdir -p "$TEMPLATE/.spectomat"/{drafts,specs,plans,snippets,done}
  (
    cd "$TEMPLATE" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    printf '%s\n' '.spectomat/state.json' '.spectomat/pointer.md' \
                   '.spectomat/work/' '.spectomat/log.md' > .gitignore
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

draft() { printf 'idea\n' > "$FIXTURE/.spectomat/drafts/$1.md"; state_slug "$1" SPECIFY; fixture_commit; }

spec() {
  printf 'spec\n' > "$FIXTURE/.spectomat/specs/$1.md"
  if [[ -n "${2:-}" ]]; then state_slug "$1" PLAN; else state_slug "$1" REVIEW-SPEC; fi
  fixture_commit
}

plan() {
  local slug="$1" tasks="$2" open="$3" reviewed="${4:-}" i f done_n
  printf 'overview\n' > "$FIXTURE/.spectomat/plans/$slug.md"
  mkdir -p "$FIXTURE/.spectomat/plans/$slug"
  i=1
  while [[ $i -le $tasks ]]; do
    printf -v f '%s/.spectomat/plans/%s/task-%02d-x.md' "$FIXTURE" "$slug" "$i"
    printf 'step\n' > "$f"
    i=$((i + 1))
  done
  done_n=$((tasks - open))
  if [[ -n "$reviewed" ]]; then
    state_slug "$slug" ARCHIVE "$tasks" "$done_n"
  elif [[ $open -eq 0 ]]; then
    state_slug "$slug" REVIEW "$tasks" "$done_n"
  else
    state_slug "$slug" IMPLEMENT "$tasks" "$done_n"
  fi
  fixture_commit
}

plan_bare() { printf 'overview\n' > "$FIXTURE/.spectomat/plans/$1.md"; state_slug "$1" PLAN; fixture_commit; }

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

# state_slug SLUG PHASE [TASKS_TOTAL TASKS_DONE] — set (or create) SLUG's
# state.json entry.
state_slug() {
  local slug="$1" phase="$2" total="${3:-}" done_n="${4:-}" filter
  filter='.slugs[$s].phase = $p'
  [[ -z "$total" ]] || filter+=' | .slugs[$s].tasks_total = ($t | tonumber)'
  [[ -z "$done_n" ]] || filter+=' | .slugs[$s].tasks_done = ($d | tonumber)'
  jq --arg s "$slug" --arg p "$phase" --arg t "$total" --arg d "$done_n" \
    "$filter" "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
}

# strike SLUG PHASE [N] — set SLUG's PHASE strike count to N (default 1).
strike() {
  local slug="$1" phase="$2" n="${3:-1}"
  jq --arg s "$slug" --arg p "$phase" --argjson n "$n" \
    '.slugs[$s] //= {} | .slugs[$s].strikes //= {} | .slugs[$s].strikes[$p] = $n' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
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
