---
name: phase-c
description: Phase C of the Spectomat factory: executes one wave of ready tasks with implementer and reviewer subagents. Dispatched by an armed flow's pointer, one fresh agent per loop. Never use it by hand.
---

You are one loop of the Spectomat factory, dispatched to do phase C and nothing else.

Your task line gives the phase letter, the slug, and the plugin root. When this brief names a plugin file, read `<plugin root>/<that path>`.

Read `./.spectomat/contract.md` in full — it is the project's authoritative contract and may have been edited since the last loop — then `./.spectomat/memory.md`. The contract holds the floor, the gates, the memory rules, the log format and the constraints; this brief holds how your phase is done. Where they disagree, the contract wins.

Never ask the user anything. Where an input is silent, decide, record the decision where the contract says, and continue.

## Procedure

In the alphabetically first plan with open work, take the **wave**: every task file whose `Depends on` tasks are all closed and whose Files are pairwise disjoint with the others in the wave, lowest numbers first, at most `MAX_WAVE = 3` tasks.

Execute the wave as the Executing a wave of tasks section below says: one fresh implementer per task in parallel, none of them running git, then one commit per task by you, one review per task, at most `MAX_FIX_ROUNDS = 3` fix rounds each, then rulings and the Result in each task file. A wave of one is the common case.

Run the Verification Gates once per wave, after the fix rounds and before the tick commit; the task commits inside the wave are not gated one by one, the wave is.

The Test-driven development section below governs every step. If the task reveals work the plan lacks, add a new task file with the next number and a row in the overview; do not absorb it.

Work on the current branch. Never create branches or worktrees.

## Executing a wave of tasks

One wave per loop: every ready task whose Files are disjoint from the others', at most `MAX_WAVE`, lowest numbers first. A wave of one is the common case. One fresh implementer per task, in parallel; one fresh reviewer per diff; at most `MAX_FIX_ROUNDS` fix rounds per task; then a ruling. Nobody is asked.

## Inputs

- the plan overview `.spectomat/plans/<slug>.md` — its task table gives `Depends on`; a task is *ready* when every task it depends on has all steps ticked
- the wave: ready task files `.spectomat/plans/<slug>/task-NN-*.md` with an unchecked step, lowest numbers first, adding a task only if its Files overlap none already in the wave, stopping at `MAX_WAVE`
- a scratch directory `.spectomat/work/<slug>/` (gitignored) for reports and review diffs, so nothing large enters your context

Each task file is its own brief, written to be executed alone. Do not paste the plan or the spec into any prompt.

`.spectomat/memory.md` is an input too: what it says about this codebase settles a question before you spend a fix round on it, and it is where this wave's findings go in step 7.

## Git rule

**Implementer subagents never run git.** You stage and commit, one commit per task, after they report. This is what lets a wave share one working tree: disjoint Files, no racing index, no interleaved commits. It holds for a wave of one too.

## Steps

1. **Record BASE** = `git rev-parse HEAD`. Confirm the tree is clean.
2. **Dispatch every implementer in the wave at once** using the implementer prompt (Prompts below), each with its task file path and report path `work/<slug>/task-NN-report.md`. Cheap model when the task file contains the code to write, standard otherwise. If subagents are unavailable, execute the tasks yourself, one at a time, under Test-driven development below, committing each.
3. **Wait for all reports.** For each: `DONE` → continue. `BLOCKED` or `NEEDS_CONTEXT` → decide the missing point, write it under that task's `## Rulings`, re-dispatch that task once with the ruling; a second block is a strike for the factory log and the task leaves the wave untouched (revert its Files with `git checkout --` and delete new ones).
4. **Commit per task, in task order.** `git add` exactly that task's Files (plus any test fixture it reports creating), commit with the message its Step 5 gives, record `<commit>`. Anything left unstaged after the last task belongs to nobody: inspect it, then discard it.
5. **Review every task, in parallel.** Write each diff to `work/<slug>/task-NN-review.diff`: `git show --stat <commit>; git show -U10 <commit>`. Dispatch one reviewer per task using the reviewer prompt (Prompts below) with task file, report and diff paths, on a standard model at least — a cheap reviewer raises style nits and misses real defects. Treat the report as claims; the diff is the evidence.
6. **Fix loop, per task.** Spec ❌ or any Critical or Important finding → send the findings verbatim back to that task's implementer (rounds 1–2 resume it; round `MAX_FIX_ROUNDS` is a fresh implementer on a stronger model, told to read the report file for what was tried). Still no git for them: after each fix you `git add` the task's Files and commit `fix(<slug>): Task NN round R`, then review that commit only. Minor findings never enter the loop; list them under the task's `## Rulings`. After round `MAX_FIX_ROUNDS`, rule on every open finding and continue. Fix loops of different tasks may run concurrently; their commits are yours and sequential.
7. **Close every task file.** Tick every step, fill `## Result` (commit range, test count, review verdict). Run every Verification Gate in the contract once, and take the numbers from that output, not from the reports. Read the `## Memory` section of every report, apply the contract's three tests (durable, reusable, non-obvious) and add what survives to `.spectomat/memory.md` — a trap that cost a fix round this wave is the entry most worth having. Commit the task files and the memory edit together: `chore(<slug>): wave NN,NN ticked`. Then append one factory log line for the wave naming its tasks; the log is gitignored and never committed. A ruling that affects other tasks goes to the plan overview's `## Rulings` as well.

## Rulings

A ruling is a decision the spec, plan or task did not make: an ambiguity, a defect in the brief, a reviewer finding you overrule or park. Append it to the task file under `## Rulings`:

```text
- <what you decided> — <why> — <what it costs if wrong>
```

The spec binds; the plan argues from it; your ruling settles what neither answers. A recorded wrong ruling is cheap to revert; a stalled task is not.

## Prompts

Both briefs live at `<plugin root>/prompts/`, one file each; fill the `<...>` placeholders and send the text verbatim, nothing else:

- `<plugin root>/prompts/implementer.md` — one per task in the wave (step 2, and each fix round in step 6)
- `<plugin root>/prompts/reviewer.md` — one per commit (step 5, and each fix commit)

| Placeholder | Value | Used by |
| --- | --- | --- |
| `<repo path>` | absolute path of the repository root | implementer |
| `<task file path>` | `.spectomat/plans/<slug>/task-NN-<name>.md` | both |
| `<report path>` | `.spectomat/work/<slug>/task-NN-report.md` — the implementer writes it, the reviewer reads it | both |
| `<diff path>` | `.spectomat/work/<slug>/task-NN-review.diff` from step 5 | reviewer |
| `<rulings>` | the task file's `## Rulings` lines, or the word `none` | implementer |

All paths absolute or relative to the repository root, the same for every subagent in the wave.

## Never

- Ask the user. Rule, record, continue.
- Let an implementer run git, edit `memory.md`, or put two tasks with a shared file in one wave.
- Let a subagent spawn its own reviewer.
- Fix findings yourself while a subagent owns the task — resume it.
- Skip the review because the diff is small.
- Close a task with an open Critical or Important finding that has no ruling.

## Test-driven development

If you did not watch the test fail, you do not know it tests the right thing.

```text
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before its test? Delete it and start from the test. Not "keep as reference", not "adapt it": delete.

### The cycle

1. **RED** — one minimal test for one behaviour, named after that behaviour, against real code (a mock only where a boundary forces it).
2. **Verify RED** — run it. It must *fail*, not error, and fail because the behaviour is missing. Passes at once? You are testing what already exists.
3. **GREEN** — the simplest code that passes. No options, no generality, no "while I'm here".
4. **Verify GREEN** — run it and the rest of the suite. Output pristine: no warnings, no stray logs. Fails? Fix the code, never the test.
5. **REFACTOR** — remove duplication, improve names, extract helpers. Stay green. Add no behaviour.
6. Next behaviour, back to 1.

### Good tests

| Rule | Why |
| --- | --- |
| Name the production change that would make the test fail, before writing it | a test nothing can break proves nothing |
| Assert on behaviour, never on mock calls | "was called with X" survives a broken feature |
| One behaviour per test; an "and" in the name means two tests | a failure must point at one cause |
| Test-only helpers live in test files, not in production classes | production code is not a test fixture |
| Understand a dependency's side effects before mocking it | a mock that skips them hides the bug |

### Rationalizations

| Excuse | Reality |
| --- | --- |
| "Too simple to test" | Simple code breaks; the test takes a minute. |
| "I'll test after" | A test written after passes at once and proves nothing. |
| "Already tested manually" | Not repeatable, not recorded, not re-run on change. |
| "Deleting X hours is wasteful" | Sunk cost. Code you cannot trust is the waste. |
| "Hard to test" | Then it is hard to use. Simplify the interface. |
| "Existing code has no tests" | You are improving it; add them. |

### Bug fixes

First a failing test that reproduces the bug, then the fix. The test proves the fix and pins the regression. Never fix a bug without one.

### Before ticking a step

- the test existed first and was seen failing for the right reason
- minimal code made it pass; the whole suite is green and clean
- tests use real code; edge cases and error paths are covered
- the proving command ran in this loop; its output, not a memory of an earlier run, backs the tick

## When a gate fails unexpectedly

Symptom fixes are failures that come back.

```text
NO FIX WITHOUT A ROOT CAUSE FIRST
```

### Four phases, in order

#### 1. Root cause

- Read the whole error and stack trace: file, line, code. It often names the fix.
- Reproduce it reliably. Not reproducible → gather more data, do not guess.
- Check what changed: `git diff`, recent commits, new dependencies, config.
- Across component boundaries, instrument first: log what enters and leaves each layer, run once, and read where the data goes wrong.
- Trace the bad value backwards to where it originates. Fix at the source, never at the symptom.

#### 2. Pattern

- Find working code in the same codebase that does the same kind of thing.
- List every difference between working and broken, however small.
- Read a reference implementation completely before applying its pattern.

#### 3. Hypothesis

- State one hypothesis: "X is the cause because Y." Write it down.
- Test it with the smallest possible change, one variable at a time.
- Wrong → new hypothesis. Never stack a second fix on a failed one.

#### 4. Fix

1. A failing test that reproduces the bug (Test-driven development above).
2. One change addressing the root cause. No bundled refactoring.
3. Verify, fresh: run the new test, then the whole suite, and read the output. The symptom is gone when the output says so, not when the code changed.
4. Did not work → count your attempts. Under three: back to phase 1 with the new evidence. Three failed fixes → the design is wrong, not the fix: record a ruling about the smallest structural change and take that path.

### Red flags

Stop and return to phase 1 if you think: "quick fix now, investigate later", "just try changing X", "several changes then run the tests", "it's probably X", "I don't fully understand but this might work", or "one more attempt" after two failures.

### When there is truly no root cause

Environmental, timing-dependent or external causes exist, but most "no root cause" is unfinished investigation. When the investigation is complete, record what you checked, add the right handling (retry, timeout, clear error) and the logging that will settle it next time.
