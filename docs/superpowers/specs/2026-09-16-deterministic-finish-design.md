# Deterministic finish: the Stop hook ends the flow, not a promise string

Date: 2026-09-16
Status: approved, not yet implemented

## Problem

The flow's termination is computed in one place and acted on in another, with a language model in between.

`scripts/phase.sh` prints `phase:FINISH` when `drafts/`, `specs/` and `plans/` hold no `.md` files **and** `git status --porcelain` is silent. That is the real verdict: deterministic, pure, testable. But the Stop hook never reads it. `pointer_prompt` in `scripts/utils.sh` asks the session to write `<promise>FACTORY EMPTY</promise>` when the block's phase was `FINISH`, and `check_promise` in `scripts/stop-hook.sh` greps the last assistant text block of the transcript for that string. The picker decides, the model transcribes, the hook reads the transcription.

Three failure modes follow, and `docs/specification.md`'s D1 claims none of them exist ("makes a false completion promise structurally impossible"):

- **False positive.** `check_promise` runs before `continue_iteration` and never consults the picker, so any assistant text containing the string ends the flow — a `RECOVER` agent quoting the contract, a spec draft echoed back, a `/spectomat:help` paste.
- **False negative.** A final turn that ends on tool calls yields `LAST_OUTPUT=""`, so the flow idles on `FINISH` iterations until the cap.
- **Dirty finish.** If the `FINISH` agent leaves the tree dirty, the promise still ends the flow. The picker would have answered `RECOVER`.

## Decision

The Stop hook runs the picker itself and ends the flow on a `FINISH` verdict, composing the closing report in bash. The `spectomat:finish` agent, the promise, and all transcript reading are removed.

This was chosen over two alternatives:

- **Hook asks the picker, `state.json` latches the FINISH iteration.** Keeps `agents/finish.md` and D21's uniform dispatch; costs a top-level state field and one iteration. Rejected: the operator preferred the smaller machine.
- **The pointer writes `phase: FINISH` into `state.json`, the hook reads it.** Rejected: moves the trust from "the model emits an exact string" to "the model runs an exact command", which is the same dependency wearing a different hat, and lets the field and the promise disagree.

`FINISH` is a stable predicate — once true it stays true — so an actuator that lives in the same process that evaluates the predicate fires exactly once with no memory. That is why this design needs no state field. A latch is only required when the actuator is a separate turn.

## Changes

### 1. `scripts/stop-hook.sh` — the hook becomes the sole authority

`main()` becomes:

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

`ask_picker()` runs `bash "$PLUGIN_ROOT/scripts/phase.sh"` and prints the value of its `phase:` line. `phase.sh` calls `cd_root` itself, so it is safe to invoke from the hook regardless of the hook's cwd.

Deleted: `require_transcript`, `read_last_output`, `check_promise`, and the `TRANSCRIPT_PATH` and `LAST_OUTPUT` globals. The hook no longer reads `transcript_path` from the payload at all, which also removes two `abort` paths — missing transcript, unparsable transcript — that could kill a flow for reasons unrelated to the work.

The picker now runs twice per iteration: once by the hook at the close of iteration N, once by the session at the start of N+1. This is accepted rather than optimised away. Passing the hook's verdict into the pointer prompt would make the pointer act on a verdict computed before its own turn began, and would end "the pointer asks the picker" as a rule.

### 2. `scripts/stop-hook.sh` — `closing_report()`

A new function, at most five lines of output, built only from what `archive.sh` already guarantees. `require_ready` in `archive.sh` demands `specs/$SLUG.md` exists, so every archived slug leaves exactly one `done/<slug>.spec.md` **or** one `done/<slug>.spec.blocked.md`, never both and never neither.

- shipped: the number of `$FLOOR/done/*.spec.md` files (the `.blocked` infix means `*.spec.md` does not match a blocked trail)
- blocked: the number of `$FLOOR/done/*.spec.blocked.md` files, each slug named, with its reason taken from `grep 'blocked after' "$FLOOR/log.md"`
- a confirmation line: the floor is empty and the tree is clean

It must not reuse `print_blocked` from `scripts/print.sh`: that function matches `*.blocked.md`, which lists up to four files per blocked slug, correct for `/spectomat:status` and wrong for a count.

### 3. `scripts/stop-hook.sh` — `finish()` emits `systemMessage`

`finish()` is currently `echo "$1"; disarm; exit 0`. A Stop hook that exits 0 with non-JSON stdout surfaces only in transcript mode. That is tolerable today because the visible ending is the `spectomat:finish` agent's assistant message; once that agent is gone, the report has nowhere else to appear.

`finish()` emits `{"systemMessage": $msg}` — the same channel `continue_iteration` already uses — with no `decision` key, so the stop proceeds. `abort()` and `stop_corrupt()` keep writing to stderr; only `finish()` changes. The iteration cap message becomes more visible as a side effect.

This is the one change in this design that cannot be proven by `scripts/selftest.sh`: whether a Stop hook allows the stop while rendering `systemMessage` is live-runtime behaviour. Verify it in a scratch git repo before considering the work done. If a bare `systemMessage` blocks the stop, fall back to plain stdout and accept transcript-mode-only visibility.

### 4. `scripts/phase.sh` — `FINISH` loses its dispatch fields

`emit()` computes `subagent:spectomat:<agent>` and `brief:$PLUGIN_ROOT/agents/<agent>.md` from the phase. With `agents/finish.md` deleted, the `FINISH` block would name a file that does not exist, and `/spectomat:status`'s `print_next` prints that block.

`emit()` special-cases `FINISH` to leave `subagent:` and `brief:` empty, alongside the already-empty `slug:`. `RECOVER` keeps its dispatch fields; only `FINISH` loses them.

### 5. `scripts/utils.sh` — the promise leaves

Delete `promised_empty()`. In `pointer_prompt`, §3's last sentence — the one instructing the session to write the promise — is replaced by: a `FINISH` block means the flow has already ended, so report nothing and stop. In a live flow the pointer cannot see `FINISH`, because the hook ends the flow at the close of the iteration that empties the floor; the sentence exists for `/spectomat:status` and for a `RECOVER` agent that runs the picker by hand.

### 6. `agents/finish.md` — deleted

Dispatch drops from seven rows to six.

## Tests

`hook_floor` in `tests/stop_hook_test.sh` creates a bare `.spectomat/` with no `drafts/`, no `specs/`, no `plans/` and no `slugs` key. Against that floor `phase.sh` answers `FINISH` — so under this design every existing "the owner is blocked from exiting" assertion inverts. `hook_floor` must gain a real floor: one `drafts/<slug>.md` and a matching `slugs` entry at `SPECIFY`, so the picker answers `SPECIFY` and the hook blocks.

- `tests/promised_empty_test.sh` — deleted.
- `tests/stop_hook_test.sh` — `hook_floor` gains a floor as above. The promise case becomes "emptying the floor ends the flow": remove the draft and its `slugs` entry, fire, assert the report names the counts and that `state.json` is gone. A new case asserts the inverse of today's dirty-finish bug: an empty floor in a dirty git repo yields `RECOVER`, so the hook blocks and the flow continues rather than ending dirty. Note that the fixture is not a git repo today; the dirty case needs one, or a stub on `PATH` that makes `git status --porcelain` print a line.
- `tests/briefs_test.sh` — drop `finish` from the agent loop, change `AGENT_COUNT is 8` to 7, and cut the `finish.md` half of the D21 comment and its promise clause.
- `tests/phase_test.sh` — assert the `FINISH` block emits empty `subagent:` and `brief:` fields, and that every non-`FINISH` block still names an existing brief file.

`scripts/selftest.sh` needs no change beyond the deleted file, since it globs `tests/*_test.sh`.

## Documentation

- `docs/specification.md`: §2.1's Finisher row; the §2.2 dispatch diagram's `phase:FINISH` line; §3.3's "for every `phase`, `SPECIFY` through `FINISH` alike"; §3.5's promise rule, which becomes a statement about the hook; D1's "false completion promise" claim, which this change makes true rather than aspirational; a new D23 recording that `FINISH` returns to a bare hook decision, superseding D21 for that one row while leaving `ARCHIVE`'s wrapper intact; AC-4.9 ("the promise and the iteration cap both disarm the flow"); E2E-1's success condition.
- `docs/guide.md`: line 55's `FINISH` sentence. In the glossary: the **Finisher** entry is deleted outright; **Flow**'s "until the promise `FACTORY EMPTY`" becomes "until the picker answers `FINISH`"; **Picker** and **Verdict** both describe `subagent`/`brief` as "derived from `phase` alone" and need the `FINISH` exception; **Phase** already says "`FINISH` ends the flow" and is correct as written. There is no standalone **promise** entry to retire.
- `scripts/prepare.sh`: the header comment at line 9 naming the promise, and the armed-flow preview text at line 197.
- `CLAUDE.md`: the "How the pieces fit" paragraph describing the pointer and D21's uniform dispatch.
- `NOTICE.md`: `stop-hook.sh` is derived from Anthropic's ralph-loop, and its change list must gain this divergence — ralph-loop's hook ends its loop by detecting a completion string in the transcript, where this one runs `scripts/phase.sh` and ends on its verdict, reading no transcript at all. The three changes already listed stay.

## What this buys and what it costs

Buys: the flow ends when and only when the picker says so. A hallucinated promise cannot end it, a tool-call-final turn cannot strand it, and a dirty tree at finish time routes to the janitor. One iteration and one agent are saved per flow, and the hook loses two unrelated ways to die.

Costs: D21's uniform seven-row dispatch table is reversed for `FINISH`. D2 and D14 both argued for mechanical work staying mechanical, so this is a return rather than a novelty, but it should be recorded as such. The closing report's wording moves from a model that read the log into bash that counts files.
