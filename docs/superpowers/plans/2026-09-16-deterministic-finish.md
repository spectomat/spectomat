# Deterministic Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Spectomat flow end when and only when `scripts/phase.sh` answers `FINISH`, by having the Stop hook run the picker itself instead of grepping the transcript for a promise string.

**Architecture:** `scripts/stop-hook.sh` gains `ask_picker()` (runs `scripts/phase.sh`, prints its `phase:` value) and `closing_report()` (counts `done/*.spec.md` and `done/*.spec.blocked.md`), and ends the flow on a `FINISH` verdict. Everything that read the transcript is deleted, along with `promised_empty()` in `scripts/utils.sh` and the `spectomat:finish` agent. `FINISH` becomes the one verdict that names no subagent.

**Tech Stack:** bash 3.2 (no GNU-only flags), `jq`, `git`. No build, no dependencies. Tests are plain bash under `tests/`, run by `scripts/selftest.sh`.

**Spec:** `docs/superpowers/specs/2026-09-16-deterministic-finish-design.md`

## Global Constraints

- bash 3.2 compatible; no GNU-only flags (no `grep -P`, no `sed -i` without a backup arg, no `find -printf`).
- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- Verdicts are upper case (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, `FINISH`); agent types and brief files are lower case.
- Every fixture in `tests/` is a real git repo. `git status --porcelain` is normative input to the picker and must never be stubbed. Use `floor`, `draft`, `spec`, `plan`, `dirty` from `tests/lib.sh`.
- Each `tests/*_test.sh` file is independently runnable: `bash tests/phase_test.sh` and `bash tests/phase_test.sh DIR`.
- Third-party material and its licence go in `NOTICE.md`; changes to derived files are listed there. `scripts/stop-hook.sh` is derived from Anthropic's ralph-loop under Apache-2.0.
- Every task ends with `scripts/selftest.sh` fully green before its commit.
- Commit messages end with: `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Change | Responsibility after the change |
| --- | --- | --- |
| `scripts/phase.sh` | modify `emit()` | `FINISH` emits empty `subagent:` and `brief:`; every other verdict is unchanged |
| `scripts/utils.sh` | modify `count()`, delete `promised_empty()`, edit `pointer_prompt()` | `count()` takes an optional glob; no promise helper; the pointer knows `FINISH` dispatches nothing |
| `scripts/stop-hook.sh` | add `ask_picker()`, `closing_report()`; rewrite `finish()` and `main()`; delete three functions | the sole authority on when a flow ends; reads no transcript |
| `agents/finish.md` | delete | — |
| `tests/phase_test.sh` | add assertions | covers `FINISH`'s empty dispatch fields |
| `tests/stop_hook_test.sh` | rewrite `hook_floor`, `fire`; replace the promise case | drives the hook against a real git floor |
| `tests/promised_empty_test.sh` | delete | — |
| `tests/briefs_test.sh` | modify | seven agents, not eight |
| `docs/specification.md`, `docs/guide.md`, `CLAUDE.md`, `NOTICE.md`, `scripts/prepare.sh` | modify prose | describe the hook as the authority |
| `.claude-plugin/plugin.json` | bump version | makes the change installable for live verification |

---

### Task 1: `FINISH` emits no dispatch fields

`emit()` in `scripts/phase.sh` derives `subagent` and `brief` from the phase for all eight verdicts. Once `agents/finish.md` is deleted in Task 3, the `FINISH` block would name a file that does not exist — and `/spectomat:status`'s `print_next` prints that block to the operator. `FINISH` must stop naming an agent first.

**Files:**
- Modify: `scripts/phase.sh:31-44` (`emit()`)
- Test: `tests/phase_test.sh` (append before the final `finish` call)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a `FINISH` block whose `subagent:` and `brief:` lines are present but empty, exactly like `slug:` already is. Task 3 relies on this; Task 4 documents it.

- [ ] **Step 1: Write the failing test**

Append to `tests/phase_test.sh`, immediately before the final `finish` line (after the `p_frontmatter_recover` block):

```bash
# FINISH dispatches nothing: the Stop hook ends the flow on this verdict, so
# the block names no agent and no brief. RECOVER, which does dispatch, keeps
# both — the two empty-slug verdicts are not alike here.
floor p_frontmatter_finish
out="$(cd "$FIXTURE" && bash "$SCRIPTS/phase.sh")"
is "FINISH's slug field is empty"     "$(printf '%s\n' "$out" | grep '^slug:')"        "slug:"
is "FINISH names no subagent"         "$(printf '%s\n' "$out" | grep '^subagent:')"    "subagent:"
is "FINISH names no brief"            "$(printf '%s\n' "$out" | grep '^brief:')"       "brief:"
is "FINISH still names plugin_root"   "$(printf '%s\n' "$out" | grep '^plugin_root:')" "plugin_root:$plugin_root_expect"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/phase_test.sh
```

Expected: FAIL on `FINISH names no subagent` (`want: subagent:` / `got: subagent:spectomat:finish`) and on `FINISH names no brief`. Every other assertion passes.

- [ ] **Step 3: Make the change**

Replace `emit()` in `scripts/phase.sh` with:

```bash
# Print the verdict as a frontmatter block: phase, slug (empty for RECOVER and
# FINISH), and everything the pointer prompt needs to dispatch a subagent with
# no lookup table of its own — the agent name, brief path and plugin root are
# all computable from the phase alone.
#
# FINISH is the exception: the Stop hook ends the flow on that verdict, so
# there is no agent to dispatch and no brief to hand it, and both fields stay
# empty. RECOVER has an empty slug but a real agent; do not group them.
emit() {
  local phase="$1" slug="${2:-}" agent=""
  if [[ "$phase" != FINISH ]]; then
    agent="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')"
  fi
  cat <<EOF
---
phase:$phase
slug:$slug
subagent:${agent:+spectomat:$agent}
brief:${agent:+$PLUGIN_ROOT/agents/$agent.md}
plugin_root:$PLUGIN_ROOT
---
EOF
}
```

Also update the header comment block at `scripts/phase.sh:16-27`: change the line `slug:<slug, empty for RECOVER and FINISH>` to be followed by a note. The block becomes:

```bash
#                     ---
#                     phase:<PHASE>
#                     slug:<slug, empty for RECOVER and FINISH>
#                     subagent:spectomat:<agent>   (empty for FINISH)
#                     brief:<PLUGIN_ROOT>/agents/<agent>.md   (empty for FINISH)
#                     plugin_root:<PLUGIN_ROOT>
#                     ---
```

And change the `phase:FINISH` line in the same header from `nothing left; the flow may end` to `nothing left; the Stop hook ends the flow`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bash -n scripts/phase.sh && bash tests/phase_test.sh && scripts/selftest.sh
```

Expected: `bash -n` silent, `phase_test.sh` all `ok`, `selftest.sh` ends `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/phase.sh tests/phase_test.sh
git commit -m "$(cat <<'MSG'
feat(picker): FINISH names no subagent or brief

FINISH is about to stop dispatching anything: the Stop hook will end the
flow on that verdict directly. emit() leaves subagent and brief empty for
it, so /spectomat:status stops printing a path to a brief that is being
deleted. RECOVER keeps both fields — an empty slug is not the same thing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: the Stop hook runs the picker and ends the flow

This is the change. The hook stops reading the transcript and asks `phase.sh` instead.

Note the trap in the existing test fixture: `hook_floor` builds a bare `.spectomat/` directory with no `drafts/`, no `specs/`, no `plans/` and no `slugs` key, in a directory that is not a git repo. Against that floor `phase.sh` answers `FINISH`, so after this change every existing "the owner is blocked from exiting" assertion would invert. `hook_floor` must be rebuilt on `tests/lib.sh`'s `floor`/`draft` helpers, which produce a real git repo with a real floor.

**Files:**
- Modify: `scripts/utils.sh:29` (`count()`), delete `scripts/utils.sh:101` (`promised_empty()`)
- Modify: `scripts/stop-hook.sh` (`finish()`, `main()`; delete `require_transcript`, `read_last_output`, `check_promise`; add `ask_picker`, `closing_report`)
- Rewrite: `tests/stop_hook_test.sh`
- Delete: `tests/promised_empty_test.sh`

**Interfaces:**
- Consumes: `emit()`'s `FINISH` block from Task 1 (the hook reads only its `phase:` line, so it does not depend on the empty fields, but the two land in the same release).
- Produces: `count DIR [GLOB]` in `utils.sh` — second argument defaults to `*.md`, so every existing single-argument call in `scripts/print.sh` is unchanged. `closing_report()` and `ask_picker()` are private to `stop-hook.sh` and no other file calls them.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `tests/stop_hook_test.sh` with:

```bash
#!/bin/bash
# stop-hook.sh — runs on every iteration of every flow and is the only script
# that can end one. Its fixture is a real floor in a real git repo; its input
# is the JSON payload Claude Code pipes in. The hook reads no transcript: it
# runs the picker and ends the flow on FINISH.
#
#   tests/stop_hook_test.sh              tests ../scripts
#   tests/stop_hook_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "stop-hook.sh"

# hook_floor NAME SESSION ITERATION MAX — a real git floor with one draft, so
# the picker answers SPECIFY and the hook blocks. A bare .spectomat/ would be
# answered FINISH and end the flow before any assertion could run.
hook_floor() {
  floor "$1"
  draft 001-a
  jq --arg s "$2" --argjson i "$3" --argjson m "$4" \
    '.session_id = $s | .iteration = $i | .max_iterations = $m' \
    "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
}

# empty_floor — remove the draft and its state entry, so the picker says
# FINISH. The removal is committed, or the tree is dirty and the answer is
# RECOVER instead.
empty_floor() {
  rm -f "$FIXTURE/.spectomat/drafts/001-a.md"
  jq 'del(.slugs["001-a"])' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" \
    && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
  fixture_commit
}

# archived SLUG [blocked] — a finished trail in done/, as archive.sh leaves it.
archived() {
  local infix=""
  [[ -z "${2:-}" ]] || infix=".blocked"
  printf 'spec\n' > "$FIXTURE/.spectomat/done/$1.spec$infix.md"
  printf 'plan\n' > "$FIXTURE/.spectomat/done/$1.plan$infix.md"
  fixture_commit
}

# fire SESSION — run the hook as SESSION in the fixture; stdout only. The
# payload carries no transcript_path: the hook no longer reads one.
fire() {
  jq -nc --arg s "$1" '{session_id:$s}' \
    | ( cd "$FIXTURE" && bash "$SCRIPTS/stop-hook.sh" 2>/dev/null )
}

hook_state() { [[ -e "$FIXTURE/.spectomat/state.json" ]] && echo yes || echo no; }
hook_iter()  { jq -r .iteration "$FIXTURE/.spectomat/state.json" 2>/dev/null; }
msg()        { printf '%s' "$1" | jq -r '.systemMessage // ""' 2>/dev/null; }

# The pointer prompt stop-hook.sh feeds back, computed the same way it does:
# by sourcing utils.sh (in a subshell, so PLUGIN_ROOT etc. do not leak here).
POINTER_PROMPT="$(source "$SCRIPTS/utils.sh" && pointer_prompt)"

hook_floor h_block OWNER 1 5
out=$(fire OWNER)
is "the owner is blocked from exiting" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "the pointer is fed back"           "$(printf '%s' "$out" | jq -r .reason)"   "$POINTER_PROMPT"
is "the iteration is bumped"           "$(hook_iter)" "2"

# Session isolation: the hook fires in every session of the project, and only
# the one that armed the flow may advance or end it.
hook_floor h_stranger OWNER 1 5
out=$(fire STRANGER)
is "a foreign session emits nothing"    "$out" ""
is "a foreign session leaves the state" "$(hook_state)" "yes"
is "a foreign session bumps nothing"    "$(hook_iter)" "1"

# A state file jq cannot read names no owner, so no session may disarm it: the
# guard that catches this once ran before the session check and let any session
# in the project destroy a flow it did not own.
hook_floor h_corrupt OWNER 1 5
printf 'not json at all\n' > "$FIXTURE/.spectomat/state.json"
fire STRANGER >/dev/null
is "a corrupt state survives a foreign session" "$(hook_state)" "yes"
fire OWNER >/dev/null
is "a corrupt state survives its own session"   "$(hook_state)" "yes"

hook_floor h_cancelled OWNER 1 5
jq '.active = false' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
out=$(fire OWNER)
is "a cancelled flow emits nothing" "$out" ""
is "a cancelled flow bumps nothing" "$(hook_iter)" "1"

# The flow ends on the picker's FINISH verdict, not on anything a model said.
hook_floor h_finish OWNER 4 20
archived 001-a
archived 002-b blocked
empty_floor
out=$(fire OWNER)
is "an empty floor ends the flow"  "$(msg "$out" | grep -c 'flow complete')" "1"
is "the report counts what shipped" "$(msg "$out" | grep -c 'Shipped 1')"     "1"
is "the report counts what blocked" "$(msg "$out" | grep -c 'blocked 1')"     "1"
is "the report names the blocked slug" "$(msg "$out" | grep -c '002-b')"      "1"
is "the flow does not block"        "$(printf '%s' "$out" | jq -r '.decision // ""')" ""
is "an empty floor disarms"         "$(hook_state)" "no"

# The bug the promise could not see: an empty floor in a dirty tree is
# RECOVER, so the flow must continue instead of ending on a mess.
hook_floor h_finish_dirty OWNER 4 20
empty_floor
dirty
out=$(fire OWNER)
is "an empty floor with a dirty tree keeps going" "$(printf '%s' "$out" | jq -r .decision)" "block"
is "a dirty finish does not disarm"               "$(hook_state)" "yes"

hook_floor h_cap OWNER 3 3
out=$(fire OWNER)
is "the cap ends the flow" "$(msg "$out" | grep -c 'max iterations')" "1"
is "the cap disarms"       "$(hook_state)" "no"

# The cap is checked before the picker, so a capped flow ends on the cap's
# message even when the floor happens to be empty.
hook_floor h_cap_empty OWNER 3 3
empty_floor
is "the cap outranks FINISH" "$(msg "$(fire OWNER)" | grep -c 'max iterations')" "1"

hook_floor h_nostate OWNER 1 5
rm -f "$FIXTURE/.spectomat/state.json"
is "no state file means no output" "$(fire OWNER)" ""

finish
```

Then delete the old promise test:

```bash
git rm tests/promised_empty_test.sh
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/stop_hook_test.sh
```

Expected: FAIL on `an empty floor ends the flow` (the hook still greps a transcript that no longer exists, so `require_transcript` aborts), on the three report assertions, on `the cap ends the flow` (the message is now bare text, not `systemMessage` JSON), and on `an empty floor with a dirty tree keeps going`. The isolation and corrupt-state assertions still pass.

- [ ] **Step 3: Generalise `count()` in `scripts/utils.sh`**

The closing report counts `done/*.spec.md`, not `done/*.md`. Rather than a near-duplicate `find` in the hook, give `count` an optional glob. Every existing call passes one argument and is unaffected.

Replace `scripts/utils.sh:28-29` with:

```bash
# Number of files matching GLOB (default '*.md') directly inside a directory,
# 0 when it is missing. The glob is passed to find -name, so it must be
# quoted at the call site, not expanded by the shell.
count() { find "$1" -maxdepth 1 -name "${2:-*.md}" -type f 2>/dev/null | wc -l | tr -d ' '; }
```

- [ ] **Step 4: Delete `promised_empty()` from `scripts/utils.sh`**

Find `promised_empty` in `scripts/utils.sh` and delete its six lines entirely — do not go by line number, Step 3's edit has already shifted them:

```bash
# True when $1 carries the completion promise. Whitespace is stripped from the
# haystack rather than parsed out of the tags, so any line breaks or indentation
# the model puts inside <promise>...</promise> still match. That also makes the
# test lenient about spacing within the words themselves, which costs nothing:
# no other wording ends the flow.
promised_empty() { [[ "${1//[[:space:]]/}" == *"<promise>FACTORYEMPTY</promise>"* ]]; }
```

- [ ] **Step 5: Rewrite the hook**

In `scripts/stop-hook.sh`, delete the `require_transcript`, `read_last_output` and `check_promise` functions, and delete the two globals and their comment:

```bash
# Set by require_transcript / read_last_output
TRANSCRIPT_PATH=""
LAST_OUTPUT=""
```

Replace `finish()` (`scripts/stop-hook.sh:23`) with:

```bash
# End the flow normally: the message reaches the operator as systemMessage,
# the flow is disarmed. A Stop hook that exits 0 with plain stdout surfaces
# only in transcript mode, and since FINISH no longer dispatches an agent
# there is no assistant message left to carry the ending. No "decision" key,
# so the stop itself proceeds.
finish() { jq -n --arg msg "$1" '{"systemMessage": $msg}'; disarm; exit 0; }
```

Add these two functions after `stop_corrupt()`:

```bash
# The picker's verdict for the floor as it stands now. phase.sh cd_root's
# itself, so this is safe from any cwd, and it mutates nothing.
ask_picker() {
  bash "$PLUGIN_ROOT/scripts/phase.sh" 2>/dev/null | sed -n 's/^phase://p'
}

# The lines the flow ends on, at most four. archive.sh's require_ready demands
# specs/<slug>.md before anything moves, so every archived slug leaves exactly
# one done/<slug>.spec.md or one done/<slug>.spec.blocked.md — never both and
# never neither, which makes these counts slug counts. print_blocked in
# print.sh matches '*.blocked.md' instead, listing up to four files per slug:
# right for /spectomat:status, wrong for a count.
closing_report() {
  local shipped blocked names
  shipped=$(count "$FLOOR/done" '*.spec.md')
  blocked=$(count "$FLOOR/done" '*.spec.blocked.md')
  printf '✅ Spectomat flow complete: the floor is empty and the tree is clean.\n'
  printf '   Shipped %s · blocked %s · %s iterations.\n' "$shipped" "$blocked" "$ITERATION"
  if [[ "$blocked" -gt 0 ]]; then
    names=$(find "$FLOOR/done" -maxdepth 1 -name '*.spec.blocked.md' -type f 2>/dev/null \
      | sed 's|.*/||; s|\.spec\.blocked\.md$||' | sort | tr '\n' ' ')
    printf '   Blocked after %s strikes: %s\n' "$STRIKE_LIMIT" "${names% }"
    printf '   Reasons are in %s/log.md; /spectomat:status lists them.\n' "$FLOOR"
  fi
}
```

Replace `main()` with:

```bash
main() {
  [[ -f "$STATE_FILE" ]] || exit 0
  read_state
  require_own_session
  require_readable_state
  require_sane_state
  [[ "$STATE_ACTIVE" == "true" ]] || exit 0
  require_below_max
  [[ "$(ask_picker)" != FINISH ]] || finish "$(closing_report)"
  continue_iteration
  exit 0
}
```

Finally, update the file's header comment (`scripts/stop-hook.sh:2-3`) to:

```bash
# Spectomat flow Stop hook.
# While the state file exists, block session exit and feed the pointer back.
# The flow ends when scripts/phase.sh answers FINISH, or at the iteration cap;
# no transcript is read and no promise string is trusted.
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bash -n scripts/stop-hook.sh scripts/utils.sh && bash tests/stop_hook_test.sh && scripts/selftest.sh
```

Expected: `bash -n` silent, `stop_hook_test.sh` all `ok`, `selftest.sh` ends `N passed, 0 failed`. The selftest file count drops by one (`promised_empty_test.sh` is gone).

- [ ] **Step 7: Commit**

```bash
git add scripts/stop-hook.sh scripts/utils.sh tests/stop_hook_test.sh
git commit -m "$(cat <<'MSG'
fix(hook): end the flow on the picker's verdict, not on a promise string

The picker computed the verdict and a model was trusted to transcribe it
into the transcript, where check_promise grepped for it. That let any
assistant text containing the string end a flow, let a tool-call-final
turn strand one, and ended a flow whose tree the picker would have sent
to the janitor.

The hook now runs phase.sh itself and ends the flow on FINISH, composing
the closing report from done/. It reads no transcript, which also removes
two ways an iteration could die for unrelated reasons. finish() emits
systemMessage so the ending is still visible once the FINISH agent goes.

count() takes an optional glob so the report can count spec trails
without a second find; every existing caller passes one argument.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: retire the `spectomat:finish` agent

With the hook composing the ending, the seventh brief has no caller. The pointer must also stop asking for a promise it no longer needs.

**Files:**
- Delete: `agents/finish.md`
- Modify: `scripts/utils.sh` (`pointer_prompt()`, sections 2 and 3)
- Modify: `tests/briefs_test.sh:13` (the agent loop), `tests/briefs_test.sh:19` (`AGENT_COUNT`), `tests/briefs_test.sh:34-35` (the D21 comment)

**Interfaces:**
- Consumes: `FINISH`'s empty `subagent:` field from Task 1 — the pointer's new §3 sentence tells the session to key off exactly that.
- Produces: an agent roster of seven (`specify`, `review-spec`, `plan`, `implement`, `review`, `archive`, `recover`). Task 4's documentation states the same number.

- [ ] **Step 1: Write the failing test**

In `tests/briefs_test.sh`, make three edits.

Line 13, drop `finish` from the loop:

```bash
for a in specify review-spec plan implement review archive recover; do
```

Line 19, the count drops to seven:

```bash
is "AGENT_COUNT is 7" "$(ls "$AGENTS"/*.md | wc -l | tr -d ' ')" "7"
```

Lines 33-35, the comment loses its finish clause and gains an assertion that the roster really is gone:

```bash
# archive.md is a thin wrapper (D21): the mutation stays in archive.sh. FINISH
# has no brief at all (D23) — the Stop hook ends the flow and composes the
# report, so no agent can claim the floor is empty.
is "archive.md invokes archive.sh" "$(grep -q 'archive.sh' "$AGENTS/archive.md" && echo yes || echo no)" "yes"
is "archive.md never calls slug_delete itself" "$(grep -q 'slug_delete' "$AGENTS/archive.md" && echo yes || echo no)" "no"
is "there is no finish brief" "$([[ -e "$AGENTS/finish.md" ]] && echo yes || echo no)" "no"
is "no brief mentions the retired promise" "$(grep -l 'FACTORY EMPTY' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/briefs_test.sh
```

Expected: FAIL on `AGENT_COUNT is 7` (`want: 7` / `got: 8`), on `there is no finish brief` (`want: no` / `got: yes`), and on `no brief mentions the retired promise` (`want: 0` / `got: 1`).

- [ ] **Step 3: Delete the brief**

```bash
git rm agents/finish.md
```

- [ ] **Step 4: Update the pointer prompt**

In `scripts/utils.sh`, inside `pointer_prompt()`'s heredoc, replace the first paragraph of section 2 with:

```text
Launch exactly one subagent with the Agent tool: `run_in_background: false`, `subagent_type` set to the block's `subagent` field, and the body of the file named by `brief` — its own frontmatter stripped — as the brief. The one exception is a block whose `subagent` field is empty, which only `FINISH` produces: dispatch nothing and go to step 3.
```

And replace the last sentence of section 3 — the one beginning `Write \`<promise>FACTORY EMPTY</promise>\`` — with:

```text
A `FINISH` block means the flow has already ended and the Stop hook has reported it; say so in one line and stop. There is no promise to write and nothing to confirm.
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bash -n scripts/utils.sh && bash tests/briefs_test.sh && bash tests/pointer_prompt_test.sh && scripts/selftest.sh
```

Expected: all `ok`; `selftest.sh` ends `N passed, 0 failed`. `pointer_prompt_test.sh` still passes unchanged — it asserts the heading, that no `{{` placeholder survives, and that `phase.sh` is named once, all of which hold.

- [ ] **Step 6: Verify the plugin still loads**

```bash
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

Expected: both report valid. Neither manifest lists agents individually, so removing one brief needs no manifest edit — confirm that by checking the output, and if either manifest does name `finish`, remove that entry and re-run.

- [ ] **Step 7: Commit**

```bash
git add -A agents scripts/utils.sh tests/briefs_test.sh
git commit -m "$(cat <<'MSG'
refactor(finish): delete the spectomat:finish brief

The Stop hook now composes the closing report itself, so the seventh
brief had no caller and the pointer had no promise to write. Dispatch
drops to six rows; FINISH is the one verdict that names no agent.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: documentation

Every document that describes the ending describes the old one. This task changes no behaviour and adds no test; `scripts/selftest.sh` must stay green, and `tests/licence_test.sh` and `tests/fixtures_test.sh` are the ones most likely to notice a wrong edit.

**Files:**
- Modify: `docs/specification.md` (§1.1 table, §1.2 diagram, §3.3, §3.5, §8 decisions table, §9.1 AC-4.9, §9.2 E2E-1)
- Modify: `docs/guide.md:55`, and four glossary entries
- Modify: `scripts/prepare.sh:9`
- Modify: `CLAUDE.md`
- Modify: `NOTICE.md`

**Interfaces:**
- Consumes: the seven-agent roster from Task 3 and the empty `FINISH` dispatch fields from Task 1.
- Produces: nothing code depends on.

- [ ] **Step 1: `docs/specification.md` — the roles table**

Delete the `Finisher` row (line 21) entirely. It is the last row of the §1.1 table.

- [ ] **Step 2: `docs/specification.md` — the picture**

In the §1.2 diagram, replace the `phase:FINISH` line (line 38) with:

```text
          └─ phase:FINISH         →  dispatches nothing; the Stop hook ends the flow and reports
```

- [ ] **Step 3: `docs/specification.md` — §3.3 Dispatch**

Replace the first paragraph (line 99) with:

```text
The pointer has no lookup table: every field it needs is in the block. It launches exactly one subagent — `run_in_background: false`, `subagent_type` set to the block's `subagent` field, and the body of the file named by `brief` (after that file's own frontmatter) as the task's brief — for every `phase` from `SPECIFY` through `RECOVER`. `FINISH` is the exception: its block names no `subagent` and no `brief`, because the Stop hook ends the flow on that verdict before the pointer ever sees it (§3.5). A pointer that does see a `FINISH` block — from `/spectomat:status`, or a janitor running the picker by hand — dispatches nothing.
```

- [ ] **Step 4: `docs/specification.md` — §3.5 Completion**

Replace the whole section body (line 113) with:

```text
The Stop hook ends the flow if and only if the picker answers `FINISH` in that hook invocation. The picker answers `FINISH` only when `drafts/`, `specs/` and `plans/` hold no `.md` files **and** `git status --porcelain` is silent, both evaluated in that invocation. No model output is consulted: the hook runs `scripts/phase.sh` itself and reads no transcript, so nothing a session writes can end a flow or keep one alive.

The hook composes the closing report from `done/`: one `<slug>.spec.md` per shipped slug, one `<slug>.spec.blocked.md` per blocked one, both guaranteed by `archive.sh`'s `require_ready` (§5.5). It reaches the operator as the hook's `systemMessage`.
```

- [ ] **Step 5: `docs/specification.md` — the decisions table**

Append one row to the §8 table, after D22:

```text
| D23 | The Stop hook runs `phase.sh` itself and ends the flow on `FINISH`, composing the closing report in bash; `FINISH` dispatches no agent and the `<promise>FACTORY EMPTY</promise>` string is retired | keeping the promise as the signal; keeping `agents/finish.md` and latching the finished iteration in `state.json` | the promise put the verdict's authority in the model's hands: `check_promise` never consulted the picker, so any text carrying the string ended a flow, a tool-call-final turn stranded one, and a dirty tree at finish time ended the flow instead of reaching the janitor. D1 claimed a false completion promise was structurally impossible; this makes that true. Supersedes D21 for `FINISH` only — `ARCHIVE`'s wrapper is untouched, and D2's and D14's argument that mechanical work stays mechanical is what `FINISH` returns to. A `state.json` latch was rejected because `FINISH` is a stable predicate and an actuator inside the process that evaluates it fires exactly once with no memory |
```

- [ ] **Step 6: `docs/specification.md` — the acceptance criteria**

Replace AC-4.9 with two rows:

```text
| AC-4.9 | An empty floor with a clean tree disarms the flow and reports what shipped and what was blocked; the iteration cap disarms it too | selftest |
| AC-4.11 | An empty floor with a dirty tree does not end the flow: the hook blocks and the next verdict is `RECOVER` | selftest |
```

Replace E2E-1 with:

```text
| E2E-1 | A scratch repo with two drafts runs until the Stop hook reports the flow complete, producing two archived trails and committed code | `claude -p` run, §10.5 |
```

- [ ] **Step 7: `docs/guide.md`**

Replace line 55 with:

```text
`RECOVER` sends a dirty tree to the janitor instead of any of the above; `FINISH` fires once `drafts/`, `specs/` and `plans/` are all empty and the tree is clean, and the Stop hook ends the flow and prints what shipped. Nothing the session says can end a flow: the hook runs the picker itself.
```

In the glossary, delete the **Finisher** entry outright. Then replace the **Flow** entry with:

```text
- **Flow** is the sequence of iterations from the first `/spectomat:run` until the picker answers `FINISH` and the Stop hook ends it, or until the iteration cap.
```

Append one sentence to the **Picker** entry: `The `FINISH` verdict names no `subagent` and no `brief`, because it dispatches nothing.` Append the same clause to the **Verdict** entry, whose parenthetical currently says the fields are "derived from `phase` alone".

Check the **Phase agent** entry: it lists `spectomat:specify|review-spec|plan|implement|review|archive`, which never included `finish` and needs no change. Confirm rather than assume.

- [ ] **Step 8: `scripts/prepare.sh`**

Replace line 9's fragment `Default 100 iterations, the promise "FACTORY EMPTY". Refuses` with:

```bash
# state.json. Default 100 iterations. Refuses
```

Line 197 already reads `The flow ends when the picker answers FINISH, or at the iteration cap.` — verify it and leave it alone.

- [ ] **Step 9: `CLAUDE.md`**

In the "How the pieces fit" section, replace the sentence beginning `hooks/hooks.json wires scripts/stop-hook.sh: while state.json exists...` through the end of that paragraph's description of dispatch, so it reads:

```text
`hooks/hooks.json` wires `scripts/stop-hook.sh`: while `state.json` exists for the session that started it (session id match, so other sessions in the same project are untouched), it runs the picker, blocks exit unless the verdict is `FINISH`, bumps `iteration` with `jq` and feeds the pointer prompt back. On `FINISH` it disarms and reports what shipped, composed in bash from `done/`; it reads no transcript and trusts no model output, so nothing a session writes can end a flow (D23). The pointer dispatches to the picker (`scripts/phase.sh`): one verdict per iteration, one subagent for every verdict but `FINISH` — `spectomat:specify|review-spec|plan|implement|review|archive`, or `spectomat:recover`. The session itself does no factory work.
```

Then, in the same section, delete the clause `and \`spectomat:finish\`'s brief only composes the closing report — the session still emits the promise (D21 in \`docs/specification.md\`)`, keeping the `spectomat:archive` clause that precedes it and ending that sentence at the archive brief.

- [ ] **Step 10: `NOTICE.md`**

In the ralph-loop paragraph, extend the `Changes:` list with a fourth item, so the sentence ends:

```text
Changes: the state is `.spectomat/state.json`, the prompt fed back each iteration is fixed text generated by `pointer_prompt` in `scripts/utils.sh` rather than read from disk, the setup prepares the factory floor before arming the hook, and the loop ends on a verdict the hook computes itself by running `scripts/phase.sh` rather than on a completion string detected in the session transcript.
```

- [ ] **Step 11: Verify nothing stale is left**

```bash
grep -rn "FACTORY EMPTY\|promised_empty\|spectomat:finish\|agents/finish" \
  scripts tests agents commands docs templates hooks CLAUDE.md README.md NOTICE.md .claude-plugin
```

Expected: no output at all. Any hit is a document this task missed. Then:

```bash
bash -n scripts/*.sh tests/*.sh && scripts/selftest.sh
```

Expected: `bash -n` silent, `selftest.sh` ends `N passed, 0 failed`.

- [ ] **Step 12: Commit**

```bash
git add -A docs CLAUDE.md NOTICE.md scripts/prepare.sh
git commit -m "$(cat <<'MSG'
docs: the hook ends the flow, and D23 records why

Updates the specification's roles table, dispatch picture, §3.3, §3.5,
acceptance criteria and decisions table; the guide's flow diagram note
and four glossary entries; prepare.sh's header; CLAUDE.md's dispatch
paragraph; and NOTICE.md's list of divergences from ralph-loop, which
now includes ending on a computed verdict rather than a detected string.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: live verification

`scripts/selftest.sh` cannot reach the live runtime. One claim in this change is only provable there: that a Stop hook emitting `{"systemMessage": ...}` with no `decision` key both allows the stop and shows the message. Everything else has a test.

The installed plugin is a cache copy under `~/.claude/plugins/cache/spectomat/`, so none of this is live until the version is bumped and the plugin reinstalled.

**Files:**
- Modify: `.claude-plugin/plugin.json` (version `0.6.0` → `0.7.0`)

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: nothing code depends on.

- [ ] **Step 1: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "0.6.0"` to `"version": "0.7.0"`. A minor bump, not a patch: the promise is a removed interface and `agents/finish.md` is a removed file.

```bash
claude plugin validate .claude-plugin/plugin.json --strict
```

Expected: valid.

- [ ] **Step 2: Commit and reinstall**

```bash
git add .claude-plugin/plugin.json
git commit -m "$(cat <<'MSG'
chore: 0.7.0

The <promise>FACTORY EMPTY</promise> interface and agents/finish.md are
both gone; the Stop hook decides when a flow ends.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

Then reinstall the plugin so the cache copy under `~/.claude/plugins/cache/spectomat/` matches. A project with an active flow needs `/spectomat:cancel` and `/spectomat:run` again.

- [ ] **Step 3: Confirm the installed copy passes its own tests**

```bash
scripts/selftest.sh ~/.claude/plugins/cache/spectomat/scripts
```

Expected: `N passed, 0 failed`. This runs this repo's tests against the installed scripts, which is what the optional `DIR` argument is for. A failure here means the reinstall did not take.

- [ ] **Step 4: Run a real flow in a scratch repo**

Never in this repo. In a scratch git repo with two small drafts in `.spectomat/drafts/`:

```bash
claude -p "/spectomat:run 25" --plugin-dir . --model opus
```

Watch for three things:

1. The flow reaches the end without a promise being written anywhere.
2. The closing report appears to the operator — `✅ Spectomat flow complete: ...` with the shipped and blocked counts. If it does **not** appear, `systemMessage` on a non-blocking Stop hook is not rendered: change `finish()` back to `echo "$1"` and accept transcript-mode-only visibility, then note the limitation in `docs/specification.md` §3.5.
3. `.spectomat/state.json` is gone afterwards and `git status` is clean.

- [ ] **Step 5: Confirm the dirty-finish path by hand**

In the same scratch repo, re-arm with one draft, let it run one iteration, then interrupt it mid-`IMPLEMENT` so the tree is dirty, and empty the floor. The next Stop hook must block and dispatch `spectomat:recover`, not end the flow. This is the failure mode the promise could not see, and E2E-2 already covers the janitor half of it.

- [ ] **Step 6: Record the result**

If step 4's item 2 failed, apply the fallback and commit it. Otherwise commit nothing further — the plan is done.

## Self-Review Notes

Checked against `docs/superpowers/specs/2026-09-16-deterministic-finish-design.md`:

- Spec §1 (hook is the authority) → Task 2 steps 5-6. Spec §2 (`closing_report`) → Task 2 step 5. Spec §3 (`systemMessage`) → Task 2 step 5, verified live in Task 5 step 4. Spec §4 (`FINISH` loses dispatch fields) → Task 1. Spec §5 (promise leaves `utils.sh`) → Task 2 step 4 and Task 3 step 4. Spec §6 (`agents/finish.md` deleted) → Task 3 step 3. Spec "Tests" → Tasks 1-3 steps 1. Spec "Documentation" → Task 4.
- One spec correction: the spec lists `scripts/prepare.sh:197` as needing an edit. It already reads "The flow ends when the picker answers FINISH, or at the iteration cap" and is correct as written; only line 9 changes. Task 4 step 8 says so.
- Two additions beyond the spec. The version bump in Task 5: the spec did not mention it, but `CLAUDE.md` makes it a precondition for the live verification the spec itself demands. And AC-4.11 in Task 4 step 6: the spec asked only that AC-4.9 be updated, but it also specifies a new dirty-tree test, and an acceptance criterion with no row is a test nothing traces to.
- `tests/status_test.sh:19` asserts an empty floor predicts `phase:FINISH` through `/spectomat:status`. That stays true — Task 1 changes the block's `subagent`/`brief` fields, not its `phase` line — so the file needs no edit.
