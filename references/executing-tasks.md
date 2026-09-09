# Executing a wave of tasks

One wave per loop: every ready task whose Files are disjoint from the others', at most three, lowest numbers first. A wave of one is the common case. One fresh implementer per task, in parallel; one fresh reviewer per diff; at most three fix rounds per task; then a ruling. Nobody is asked.

## Inputs

- the plan overview `.spectomat/plans/<slug>.md` — its task table gives `Depends on`; a task is *ready* when every task it depends on has all steps ticked
- the wave: ready task files `.spectomat/plans/<slug>/task-NN-*.md` with an unchecked step, lowest numbers first, adding a task only if its Files overlap none already in the wave, stopping at three
- a scratch directory `.spectomat/work/<slug>/` (gitignored) for reports and review diffs, so nothing large enters your context

Each task file is its own brief, written to be executed alone. Do not paste the plan or the spec into any prompt.

`.spectomat/memory.md` is an input too: what it says about this codebase settles a question before you spend a fix round on it, and it is where this wave's findings go in step 7.

## Git rule

**Implementer subagents never run git.** You stage and commit, one commit per task, after they report. This is what lets a wave share one working tree: disjoint Files, no racing index, no interleaved commits. It holds for a wave of one too.

## Steps

1. **Record BASE** = `git rev-parse HEAD`. Confirm the tree is clean.
2. **Dispatch every implementer in the wave at once** using `prompts/implementer.md`, each with its task file path and report path `work/<slug>/task-NN-report.md`. Cheap model when the task file contains the code to write, standard otherwise. If subagents are unavailable, execute the tasks yourself, one at a time, under `test-driven-development.md` next to this file, committing each.
3. **Wait for all reports.** For each: `DONE` → continue. `BLOCKED` or `NEEDS_CONTEXT` → decide the missing point, write it under that task's `## Rulings`, re-dispatch that task once with the ruling; a second block is a strike for the factory log and the task leaves the wave untouched (revert its Files with `git checkout --` and delete new ones).
4. **Commit per task, in task order.** `git add` exactly that task's Files (plus any test fixture it reports creating), commit with the message its Step 5 gives, record `<commit>`. Anything left unstaged after the last task belongs to nobody: inspect it, then discard it.
5. **Review every task, in parallel.** Write each diff to `work/<slug>/task-NN-review.diff`: `git show --stat <commit>; git show -U10 <commit>`. Dispatch one reviewer per task (`prompts/reviewer.md`) with task file, report and diff paths, on a standard model at least — a cheap reviewer raises style nits and misses real defects. Treat the report as claims; the diff is the evidence.
6. **Fix loop, per task.** Spec ❌ or any Critical or Important finding → send the findings verbatim back to that task's implementer (rounds 1–2 resume it; round 3 is a fresh implementer on a stronger model, told to read the report file for what was tried). Still no git for them: after each fix you `git add` the task's Files and commit `fix(<slug>): Task NN round R`, then review that commit only. Minor findings never enter the loop; list them under the task's `## Rulings`. After round 3, rule on every open finding and continue. Fix loops of different tasks may run concurrently; their commits are yours and sequential.
7. **Close every task file.** Tick every step, fill `## Result` (commit range, test count, review verdict). Run every Verification Gate in the contract once, and take the numbers from that output, not from the reports. Read the `## Memory` section of every report, apply the contract's three tests (durable, reusable, non-obvious) and add what survives to `.spectomat/memory.md` — a trap that cost a fix round this wave is the entry most worth having. Commit the task files and the memory edit together: `chore(<slug>): wave NN,NN ticked`. Then append one factory log line for the wave naming its tasks; the log is gitignored and never committed. A ruling that affects other tasks goes to the plan overview's `## Rulings` as well.

## Rulings

A ruling is a decision the spec, plan or task did not make: an ambiguity, a defect in the brief, a reviewer finding you overrule or park. Append it to the task file under `## Rulings`:

```text
- <what you decided> — <why> — <what it costs if wrong>
```

The spec binds; the plan argues from it; your ruling settles what neither answers. A recorded wrong ruling is cheap to revert; a stalled task is not.

## Prompts

Both briefs live in this plugin, one file each; fill the `<...>` placeholders and send the text verbatim, nothing else:

- `prompts/implementer.md` — one per task in the wave (step 2, and each fix round in step 6)
- `prompts/reviewer.md` — one per commit (step 5, and each fix commit)

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
