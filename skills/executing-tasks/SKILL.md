---
name: executing-tasks
description: Use when the factory's unit C takes the next unchecked task from a plan in docs/.spectomat/plans — dispatch a fresh implementer subagent, review its diff for spec compliance and quality, fix, tick the steps, commit. Unattended; decisions become rulings in the plan.
---

# Executing one task

One task per iteration. A fresh implementer per task, a fresh reviewer per
diff, at most three fix rounds, then a ruling. Nobody is asked anything.

## Inputs

- the plan `docs/.spectomat/plans/<slug>.md` and the spec it names
- the first task in the plan with an unchecked `- [ ]` step
- a scratch directory `docs/.spectomat/work/<slug>/` (gitignored) for the
  brief, the report and the diff, so nothing large enters your context

## Steps

1. **Brief.** Copy the task's full text from the plan into
   `work/<slug>/task-<N>-brief.md`. Add the plan's Global Constraints and
   the interfaces earlier tasks produced. Exact values live only in the
   brief. Never hand a subagent the whole plan.
2. **Record BASE** = `git rev-parse HEAD`.
3. **Dispatch the implementer** (template below) with the brief path and the
   report path `work/<slug>/task-<N>-report.md`. Run it on a cheap model
   when the brief contains the code to write, a standard model otherwise.
   Never run two implementers at once. If subagents are unavailable, do the
   task yourself, following the brief and `spectomat:test-driven-development`,
   and skip to step 6.
4. **Read the report's status line.** `DONE` → step 5. `BLOCKED` or
   `NEEDS_CONTEXT` → decide the missing point yourself, write it as a ruling
   (below), re-dispatch once with the ruling in the prompt; a second block
   is a strike for the factory log.
5. **Review.** Write the diff to `work/<slug>/task-<N>-review.diff`:
   `git log --oneline BASE..HEAD; git diff --stat BASE..HEAD; git diff -U10 BASE..HEAD`.
   Dispatch the reviewer (template below) with brief, report and diff paths,
   on a standard model at least — a cheap reviewer raises style nits and
   misses real defects. Treat the report as claims; the diff is the evidence.
6. **Fix loop.** Spec ❌ or any Critical or Important finding → send the
   findings verbatim back to the implementer (rounds 1–2 resume it; round 3
   is a fresh implementer on a stronger model, told to read the report file
   for what was tried). After each fix, review the fix range only. Minor
   findings never enter the loop; list them under the plan's `## Rulings`.
   After round 3, rule on every open finding yourself and continue.
7. **Tick** every step of the task in the plan, append the factory log line,
   and commit both in one `chore(<slug>): Task N ticked` commit. The
   implementer's commits already carry the code.

## Rulings

A ruling is a decision the spec or plan did not make: an ambiguity, a plan
defect, a reviewer finding you overrule or park. Append it to the plan under
a `## Rulings` heading at the end:

```
- Task 3 · <what you decided> — <why> — <what it costs if wrong>
```

The spec binds; the plan argues from it; your ruling settles what neither
answers. A recorded wrong ruling is cheap to revert; a stalled task is not.

## Implementer prompt

```
You are implementing Task N: <name> in <repo path>.

Read your brief first: <brief path>. It is your requirements; use its exact
values verbatim. Context: <one line on where this task fits>. Interfaces from
earlier tasks: <names and signatures>. Rulings that bind you: <list or none>.

Do the work yourself; never spawn subagents. Follow TDD: write the failing
test, watch it fail, implement minimally, watch it pass. Run the focused
test while iterating and the full suite once before committing. Commit with
message "feat(<slug>): Task N — <name>". Do not touch files outside the
brief's list unless the brief's tests require it.

Write your full report to <report path>: what you built, the test command
and its output, anything you doubted and how you decided. Reply with one
line only: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED, the commit
range, and the test count.
```

## Reviewer prompt

```
You are reviewing one task's implementation. Read-only: do not change the
tree, run only a focused test if the code raises a specific doubt. Do not
spawn subagents.

Requested: <brief path>. Constraints from the spec: <verbatim lines>.
Claimed: <report path> — unverified claims; judge the diff.
Diff: <diff path> (commit list, stat, full diff with context). Read it once.

Part 1 — Spec compliance: Missing (skipped or claimed but absent), Extra
(not requested), Misunderstood (right feature, wrong way). Verdict ✅ or ❌
with file:line for every finding. A requirement you cannot verify from the
diff is a ⚠️ line, not a search.

Part 2 — Quality: tests assert behaviour not mocks; edge cases covered;
one responsibility per file; no duplication of a spec constant; error paths
handled; test output pristine. Severity: Critical (wrong or unsafe),
Important (task cannot be trusted until fixed), Minor (everything else).
Cite file:line for each.

Reply with the report only: the two verdicts, then findings grouped by
severity. No preamble, no summary.
```

## Never

- Ask the user. Rule, record, continue.
- Run implementers in parallel, or let a subagent spawn its own reviewer.
- Fix findings yourself while a subagent owns the task — resume it.
- Skip the review because the diff is small.
- Move to the next task with an open Critical or Important finding that has
  no ruling.
