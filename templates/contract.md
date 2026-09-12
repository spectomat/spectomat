# Spectomat Factory — `.spectomat/`

You are running unattended inside a Stop-hook flow. Every iteration feeds you the same pointer prompt and you arrive with no memory of the last one. **This file is your only memory of intent, `memory.md` your only memory of this codebase, and the filesystem under `.spectomat/` your only memory of progress.** Read this file in full before doing anything.

Repository: `{{REPO}}`

Nobody is watching. **Never ask a question.** Where an input is silent, decide, record the decision where this file says, and continue. A recorded assumption beats a stalled factory.

## The floor

```text
.spectomat/
  drafts/      raw ideas, one .md each — the user drops them here; worked in alphabetical order
  specs/       normative specs, one per draft slug — you write these
  plans/       one overview per spec slug, plus <slug>/task-NN-<name>.md per task — you write these
  done/        <slug>.draft.md, <slug>.spec.md, <slug>.plan.md and <slug>/ task files, moved here when a plan completes
  log.md       append-only, one line per phase of work — gitignored, never committed
  contract.md  this file
  memory.md    what the factory has learned about this codebase — committed, read every iteration, added to before every commit
  state.json   the flow's state: iteration counter, cap, session — gitignored, never edit
  pointer.md   the prompt the Stop hook feeds back each iteration — gitignored, never edit
  work/        scratch for IMPLEMENT and REVIEW: diffs, stats, anything bulky — gitignored
```

A `slug` is the draft's file name without `.md`. Spec, plan and done entries keep that slug so the whole trail of one idea is greppable.

## The Iteration Contract

Every iteration, in order:

1. **Orient.** Read this file, then `memory.md`. Run `git status --porcelain`. If the tree is dirty, the previous iteration died mid-phase: inspect the changes and either finish and commit that phase or `git checkout -- .` and `git clean -fd` the paths you own. Check `state.json`, `pointer.md`, `log.md` and `work/` are gitignored and never count as dirt. Never start a phase on a dirty tree. Never touch `drafts/` files except to move them.
2. **Do the phase you were handed.** The picker chose it from the floor before you were launched; your task line names it and the slug. Never do a second phase, and never substitute a different one — if the phase makes no sense for this floor, say so in your report and stop.
3. **Verify** with the gates — once per task in the `IMPLEMENT` phase, once before the commit in the `ARCHIVE` phase; the `SPECIFY`, `PLAN` and `REVIEW` phases write no code and skip them,
4. **Record and commit** — add what you learned to `memory.md` (see *Memory*), then one commit per phase, `<type>(<slug>): <what changed>`, with the memory edit inside it.
5. **Log** one line to `log.md`, then stop the iteration. The log is gitignored and never enters a commit; write it after the commit, once the phase is on record. In the `IMPLEMENT` phase the plan tick is one `chore(<slug>): …` commit after the task commits.

> Work in progress always wins: a started plan is finished and archived before the next spec is planned, and every spec is planned before the next draft is read. New drafts wait until the floor ahead of them is clear.

### Three strikes

If a phase defeats you, append `(strike N)` to its log line and skip it next time by picking the following candidate in the same stage. On the third strike move the offending file to `done/` with the suffix `.blocked.md`, log the reason, and continue. Never delete a draft, spec or plan.

## Verification Gates

Run every command in the block below from the repository root: once per task in the `IMPLEMENT` phase, before that task's commit, and once in the `ARCHIVE` phase before archiving. Every line must exit 0.

```bash
# project-specific gates, one command per line, You may change it
{{GATES}}
```

No completion claim without fresh evidence. A gate that has not run this iteration has not passed; a partial run does not stand for the whole.

## Memory

`memory.md` is what you know about this codebase; this contract is what you know about the job. You arrive with neither, so both are files.

**Read it in Orient, every iteration, before you touch anything else.** Trust it over your assumptions about the project, and over a habit from another repository.

**Add to it in step 4, before the commit**, so the entry rides inside the phase commit and the tree stays clean.

Its own header carries the rules for what earns a line — the three tests, the four sections, the size limits — and is not repeated here. Only the phase agent handling this iteration writes the file: it applies the tests itself, so the file keeps one voice.

## Log Format

Append to `log.md`, never edit earlier lines. The timestamp is the output of `date -u +%FT%RZ`, run in this iteration — never a time typed from memory. No commit SHA: `git log` is the ledger of commits, this file the ledger of phases.

```text
- 2026-09-07T19:40Z · SPECIFY · <slug> · spec written, 3 assumptions
- 2026-09-07T19:52Z · IMPLEMENT · <slug> · Task 2/6 done · tests 41/41
- 2026-09-07T20:10Z · ARCHIVE · <slug> · moved to done · tsc 0, tests 58/58, lint 0
- 2026-09-07T20:11Z · PLAN · <slug> · plan: 6 tasks (strike 1: spec §4 contradicts §2)
```

Numbers, never adjectives. A log line without numbers did not run the gates.

## Constraints

- DO NOT Overcomplicate things: Be concise, simple and straightforward as possible.
- DO NOT Ask the user anything: Decide and record.
- DO NOT Edit a file under `drafts/` — only move it.
- DO NOT Delete a draft, spec or plan.
- DO NOT Weaken a gate to pass.
- DO NOT Log narration into `memory.md` — durable, reusable, non-obvious, or it is not a memory.
