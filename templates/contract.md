<!-- spectomat-contract: 2 -->
# Spectomat Factory — `.spectomat/`

You are running unattended inside a Stop-hook flow. Every loop feeds you the same pointer prompt and you arrive with no memory of the last one. **This file is your only memory of intent, `memory.md` your only memory of this codebase, and the filesystem under `.spectomat/` your only memory of progress.** Read this file in full before doing anything.

Repository: `{{REPO}}`

Nobody is watching. **Never ask a question.** Where an input is silent, decide, record the decision where this file says, and continue. A recorded assumption beats a stalled factory.

## The floor

```text
.spectomat/
  drafts/      raw ideas, one .md each, named NNN-<name>.md in intake order — the user drops them here
  .inc         the last NNN issued at intake — never edit
  specs/       normative specs, one per draft slug — you write these
  plans/       one overview per spec slug, plus <slug>/task-NN-<name>.md per task — you write these
  done/        <slug>.draft.md, <slug>.spec.md, <slug>.plan.md and <slug>/ task files, moved here when a plan completes
  log.md       append-only, one line per phase of work — gitignored, never committed
  contract.md  this file
  memory.md    what the factory has learned about this codebase — committed, read every loop, added to before every commit
  state.md     the Stop hook's state (loop counter, prompt) — gitignored, never edit
  work/        per-task briefs, reports and diffs for executing-tasks — gitignored
```

A `slug` is the draft's file name without `.md`. Spec, plan and done entries keep that slug so the whole trail of one idea is greppable.

## The Loop Contract

Every loop, in order:

1. **Orient.** Read this file, then `memory.md`. Run `git status --porcelain`. If the tree is dirty, the previous loop died mid-phase: inspect the changes and either finish and commit that phase or `git checkout -- .` and `git clean -fd` the paths you own. Check `state.md`, `log.md` and `work/` are gitignored and never count as dirt. Never start a phase on a dirty tree. Never touch `drafts/` files except to move them.
2. **Do the phase you were handed.** The picker chose it from the floor before you were launched; your task line names it and the slug. Never do a second phase, and never substitute a different one — if the phase makes no sense for this floor, say so in your report and stop.
3. **Verify** with the gates — once per wave in phase C, once before the commit in phase D,
4. **Record and commit** — add what you learned to `memory.md` (see *Memory*), then one commit per phase, `<type>(<slug>): <what changed>`, with the memory edit inside it.
5. **Log** one line to `log.md`, then stop the loop. The log is gitignored and never enters a commit; write it after the commit, once the phase is on record. In phase C the plan tick is one `chore(<slug>): …` commit after the implementer's own commits.

> Work in progress always wins: a started plan is finished and archived before the next spec is planned, and every spec is planned before the next draft is read. New drafts wait until the floor ahead of them is clear.

### Three strikes

If a phase defeats you, append `(strike N)` to its log line and skip it next time by picking the following candidate in the same stage. On the third strike move the offending file to `done/` with the suffix `.blocked.md`, log the reason, and continue. Never delete a draft, spec or plan.

## Verification Gates

Run every command in the block below from the repository root: once per wave in phase C, after the fix rounds and before the `chore(<slug>)` tick commit, and once in phase D before archiving. Every line must exit 0.

```bash
# project-specific gates, one command per line, You may change it
{{GATES}}
```

No completion claim without fresh evidence. A gate that has not run this loop has not passed; a partial run does not stand for the whole.

Run each gate whole, read the full output — exit code, failure count, warnings — and compare it to the claim you are about to make.

Mismatch: record the real status with the output. Match: claim it with the numbers. "Should pass", "probably", "seems to" mean run it again. Never weaken a gate to pass: no `.skip`, no `any`, no suppression.

If a gate fails unexpectedly, use the `systematic-debugging` reference.

Phases A and B produce only Markdown and skip the gates.

## Memory

`memory.md` is what you know about this codebase; this contract is what you know about the job. You arrive with neither, so both are files.

**Read it in Orient, every loop, before you touch anything else.** Trust it over your assumptions about the project, and over a habit from another repository.

**Add to it in step 4, before the commit**, so the entry rides inside the phase commit and the tree stays clean. Write the entry for a reader with no other context: yourself, next loop.

Record a fact when all three hold:

- **durable** — still true once the current plan is in `done/`,
- **reusable** — a loop working on a *different* task would want it,
- **non-obvious** — not one grep away from a file that loop already reads.

Anything that fails a test belongs elsewhere: what happened is `log.md`, what is being built is the spec, how it is being built is the plan, a decision binding one task is that task's `## Rulings`.

Four sections, one line each, `- <the fact> — <why the next loop cares>`:

- **Map** — where a kind of thing lives, when the path is not guessable from the name.
- **Commands** — how to run, test and inspect this project, with what it costs.
- **Patterns** — a convention a new file must follow to look like the ones around it.
- **Traps** — what cost a strike or a fix round: symptom, cause, the rule that avoids it.

```text
- Zod schemas live in `lib/schemas/`, one per boundary — a new boundary needs one there, not beside its handler
- Full suite `npx vitest run` ~90s, one file `npx vitest run test/x.test.ts` ~4s — iterate focused, run whole once at the end
- A relative import carrying `.js` compiles and 500s at runtime — the bundler does not substitute the extension, so no gate catches it
```

**Correct or delete an entry the code contradicts** — a wrong memory costs more than no memory. Keep a section under ~12 lines and the file under ~40 by merging or dropping the weakest entries; a memory nobody reads is a memory nobody trusts.

Zero new entries in a loop is a normal outcome. Two or three is a good loop. Ten means you are writing a log.

Only you write `memory.md`. Implementers report candidates at the end of their reports; you apply the three tests, and keep the file one voice.

## Log Format

Append to `log.md`, never edit earlier lines. The timestamp is the output of `date -u +%FT%RZ`, run in this loop — never a time typed from memory. No commit SHA: `git log` is the ledger of commits, this file the ledger of phases.

```text
- 2026-09-07T19:40Z · A · <slug> · spec written, 3 assumptions
- 2026-09-07T19:52Z · C · <slug> · Task 2/6 done · tests 41/41
- 2026-09-07T20:10Z · D · <slug> · moved to done · tsc 0, tests 58/58, lint 0
- 2026-09-07T20:11Z · B · <slug> · plan: 6 tasks (strike 1: spec §4 contradicts §2)
```

Numbers, never adjectives. A log line without numbers did not run the gates.

## Constraints

- DO NOT Overcomplicate things: Be concise, simple and straightforward as possible.
- DO NOT Ask the user anything: Decide and record.
- DO NOT Edit a file under `drafts/` — only move it.
- DO NOT Delete a draft, spec or plan.
- DO NOT Weaken a gate to pass.
- DO NOT Log narration into `memory.md` — durable, reusable, non-obvious, or it is not a memory.
