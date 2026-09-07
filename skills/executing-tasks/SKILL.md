---
name: executing-tasks
description: Use when the factory's unit C takes the next wave of ready task files under docs/.spectomat/plans/<slug>/ — one fresh implementer per task in parallel, none running git; then per task a commit by the controller, a diff review, fixes, ticked steps and a Result. Unattended; decisions become rulings in the task file.
---

# Executing a wave of tasks

One wave per iteration: every ready task whose Files are disjoint from the
others', at most three, lowest numbers first. A wave of one is the common
case. One fresh implementer per task, in parallel; one fresh reviewer per
diff; at most three fix rounds per task; then a ruling. Nobody is asked.

## Inputs

- the plan overview `docs/.spectomat/plans/<slug>.md` — its task table gives
  `Depends on`; a task is *ready* when every task it depends on has all steps
  ticked
- the wave: ready task files `docs/.spectomat/plans/<slug>/task-NN-*.md`
  with an unchecked step, lowest numbers first, adding a task only if its
  Files overlap none already in the wave, stopping at three
- a scratch directory `docs/.spectomat/work/<slug>/` (gitignored) for reports
  and review diffs, so nothing large enters your context

Each task file is its own brief, written to be executed alone. Do not paste
the plan or the spec into any prompt.

## Git rule

**Implementer subagents never run git.** You stage and commit, one commit
per task, after they report. This is what lets a wave share one working
tree: disjoint Files, no racing index, no interleaved commits. It holds for
a wave of one too.

## Steps

1. **Record BASE** = `git rev-parse HEAD`. Confirm the tree is clean.
2. **Dispatch every implementer in the wave at once** (template below), each
   with its task file path and report path `work/<slug>/task-NN-report.md`.
   Cheap model when the task file contains the code to write, standard
   otherwise. If subagents are unavailable, execute the tasks yourself, one
   at a time, under `spectomat:test-driven-development`, committing each.
3. **Wait for all reports.** For each: `DONE` → continue. `BLOCKED` or
   `NEEDS_CONTEXT` → decide the missing point, write it under that task's
   `## Rulings`, re-dispatch that task once with the ruling; a second block
   is a strike for the factory log and the task leaves the wave untouched
   (revert its Files with `git checkout --` and delete new ones).
4. **Commit per task, in task order.** `git add` exactly that task's Files
   (plus any test fixture it reports creating), commit with the message its
   Step 5 gives, record `<commit>`. Anything left unstaged after the last
   task belongs to nobody: inspect it, then discard it.
5. **Review every task, in parallel.** Write each diff to
   `work/<slug>/task-NN-review.diff`: `git show --stat <commit>; git show -U10
   <commit>`. Dispatch one reviewer per task (template below) with task file,
   report and diff paths, on a standard model at least — a cheap reviewer
   raises style nits and misses real defects. Treat the report as claims;
   the diff is the evidence.
6. **Fix loop, per task.** Spec ❌ or any Critical or Important finding →
   send the findings verbatim back to that task's implementer (rounds 1–2
   resume it; round 3 is a fresh implementer on a stronger model, told to
   read the report file for what was tried). Still no git for them: after
   each fix you `git add` the task's Files and commit `fix(<slug>): Task NN
   round R`, then review that commit only. Minor findings never enter the
   loop; list them under the task's `## Rulings`. After round 3, rule on
   every open finding and continue. Fix loops of different tasks may run
   concurrently; their commits are yours and sequential.
7. **Close every task file.** Tick every step, fill `## Result` (commit
   range, test count, review verdict). Run the full suite once. Append one
   factory log line for the wave naming its tasks, and commit the task files
   and log together: `chore(<slug>): wave NN,NN ticked`. A ruling that
   affects other tasks goes to the plan overview's `## Rulings` as well.

## Rulings

A ruling is a decision the spec, plan or task did not make: an ambiguity, a
defect in the brief, a reviewer finding you overrule or park. Append it to
the task file under `## Rulings`:

```
- <what you decided> — <why> — <what it costs if wrong>
```

The spec binds; the plan argues from it; your ruling settles what neither
answers. A recorded wrong ruling is cheap to revert; a stalled task is not.

## Implementer prompt

```
You are implementing one task in <repo path>. Other implementers may be
working in the same tree on other files at the same time.

Read your task file first: <task file path>. It is your complete brief; use
its exact values verbatim. Create or modify only the files it lists under
Files; if its tests need a file it does not list, say so in your report
rather than creating it. Rulings that bind you: <list or none>.

Do the work yourself; never spawn subagents. Follow the Steps in order under
TDD: write the failing test, watch it fail, implement minimally, watch it
pass. Run the focused test while iterating and the full suite once at the
end. Do not run any git command: the controller commits. Do not edit the
task file.

Write your full report to <report path>: what you built, every file you
touched, the test command and its output, anything you doubted and how you
decided. Reply with one line only: DONE | DONE_WITH_CONCERNS |
NEEDS_CONTEXT | BLOCKED, and the test count.
```

## Reviewer prompt

```
You are reviewing one task's implementation. Read-only: do not change the
tree, run only a focused test if the code raises a specific doubt. Do not
spawn subagents.

Requested: <task file path> — its Constraints, Files, Interfaces, Covers and
Steps are the requirements.
Claimed: <report path> — unverified claims; judge the diff.
Diff: <diff path> (stat and full diff with context of one commit). Read it once.

Part 1 — Spec compliance: Missing (skipped or claimed but absent), Extra
(not requested, or a file outside the task's Files), Misunderstood (right
feature, wrong way). Verdict ✅ or ❌ with file:line for every finding. A
requirement you cannot verify from the diff is a ⚠️ line, not a search.

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
- Let an implementer run git, or put two tasks with a shared file in one wave.
- Let a subagent spawn its own reviewer.
- Fix findings yourself while a subagent owns the task — resume it.
- Skip the review because the diff is small.
- Close a task with an open Critical or Important finding that has no ruling.
