# Spectomat Factory — `docs/.spectomat/`

You are running unattended inside a Stop-hook loop. Every iteration feeds you
the same pointer prompt and you arrive with no memory of the last one. **This
file is your only memory of intent; the filesystem under `docs/.spectomat/` is
your only memory of progress.** Read this file in full before doing anything.

Repository: `{{REPO}}`

Nobody is watching. **Never ask a question.** Where an input is silent, decide,
record the decision where this file says, and continue. A recorded assumption
beats a stalled factory.

## The floor

```
docs/.spectomat/
  drafts/      raw ideas, one .md each — the user drops them here
  specs/       normative specs, one per draft slug — you write these
  plans/       one overview per spec slug, plus <slug>/task-NN-<name>.md per task — you write these
  done/        <slug>.draft.md, <slug>.spec.md, <slug>.plan.md and <slug>/ task files, moved here when a plan completes
  log.md       append-only, one line per unit of work
  factory.md   this file
  loop.md      the Stop hook's state (iteration counter, prompt) — gitignored, never edit
  work/        per-task briefs, reports and diffs for executing-tasks — gitignored
```

A `slug` is the draft's file name without `.md`. Spec, plan and done entries
keep that slug so the whole trail of one idea is greppable.

## The Loop Contract

Every iteration, in order:

1. **Orient.** Read this file. Run `git status --porcelain`. If the tree is
   dirty, the previous iteration died mid-unit: inspect the changes and either
   finish and commit that unit or `git checkout -- .` and `git clean -fd` the
   paths you own. `loop.md` and `work/` are gitignored and never count as dirt. Never start a
   unit on a dirty tree. Never touch `drafts/` files except to move them.
2. **Pick exactly one unit**, the first that applies:
   - **A · Draft → Spec**: a file exists in `drafts/` (alphabetical order,
     first one).
   - **B · Spec → Plan**: a file in `specs/` has no `plans/<slug>.md`
     (alphabetical, first one).
   - **C · Plan → Wave**: a task file under `plans/<slug>/` has an unchecked
     `- [ ]` step (alphabetical first plan; within it, every ready task with
     disjoint Files, lowest numbers first, at most three — see unit C).
   - **D · Plan → Done**: every task file under `plans/<slug>/` has all steps
     checked.
   - **E · Empty**: none of the above. Go to *Completion*.
3. **Do that one unit** (definitions below). Not two.
4. **Verify** with the gates, then **commit** — one commit per unit,
   `<type>(<slug>): <what changed>`.
5. **Log** one line to `log.md`, then stop the iteration. In unit C the plan
   tick and the log line share one `chore(<slug>): …` commit after the
   implementer's own commits; in every other unit the log line rides in the
   unit's commit. Never a separate commit just for the log.

Drafts always win: while `drafts/` holds a file, no plan advances. That is the
order the user asked for — every idea is specified before any is built.

### Three strikes

If a unit defeats you, append ` (strike N)` to its log line and skip it next
time by picking the following candidate in the same stage. On the third strike
move the offending file to `done/` with the suffix `.blocked.md`, log the reason,
and continue. Never delete a draft, spec or plan.

## Units

### A · Draft → Spec

Read the draft in full. Read `spectomat:writing-specs`. Write
`specs/<slug>.md` in that shape: numbered sections, criteria with ids,
constants named once, decisions numbered, a bottom-up build sequence, an empty
reconciliations section. Scope it to what the draft asks; do not invent
features. Every choice the draft did not make is a row in the spec's Decisions
table marked `assumed`. The draft's own words go into §1 verbatim where they
are precise.

Then `git mv drafts/<slug>.md done/<slug>.draft.md`. The draft is consumed.

No code in this unit, and no questions: where the draft is silent, decide
and record.

### B · Spec → Plan

Read the spec in full. Use `spectomat:writing-plans` to write the overview
`plans/<slug>.md` and one self-contained task file per task under
`plans/<slug>/`, from the plugin's `plan.md` and `task.md` templates. Every
task file carries checkbox steps (`- [ ]`); that is how unit C finds its work.
Run the skill's self-review. No code in this unit.

### C · Plan → Wave

In the alphabetically first plan with open work, take the **wave**: every
task file whose `Depends on` tasks are all closed and whose Files are
pairwise disjoint with the others in the wave, lowest numbers first, at most
three. Execute the wave with `spectomat:executing-tasks`: one fresh
implementer per task in parallel, none of them running git, then one commit
per task by you, one review per task, at most three fix rounds each, then
rulings and the Result in each task file. A wave of one is the common case.
`spectomat:test-driven-development` governs every step. If the task
reveals work the plan lacks, add a new task file with the next number and a
row in the overview; do not absorb it.

Work on the current branch. Never create branches or worktrees.

### D · Plan → Done

Run every gate and read the output. Then move the trail into `done/` under
names that cannot collide:

```bash
git mv specs/<slug>.md  done/<slug>.spec.md
git mv plans/<slug>.md  done/<slug>.plan.md
git mv plans/<slug>     done/<slug>
```

The draft is already there as `done/<slug>.draft.md`. Log the unit with the
gate numbers.

## Verification Gates

Before every commit in units C and D:

```bash
cd {{REPO}}
{{GATES}}
```

A gate that has not run this iteration has not passed. Never weaken a gate to
pass: no `.skip`, no `any`, no suppression. If a gate fails unexpectedly, use
`spectomat:systematic-debugging`. Units A and B produce only Markdown and skip
the gates.

## Log Format

Append to `log.md`, never edit earlier lines. The timestamp is the output of
`date -u +%FT%RZ`, run in this iteration — never a time typed from memory:

```
- 2026-09-07T19:40Z · A · <slug> · spec written, 3 assumptions · a1b2c3d
- 2026-09-07T19:52Z · C · <slug> · Task 2/6 done · tests 41/41 · b4c5d6e
- 2026-09-07T20:10Z · D · <slug> · moved to done · tsc 0, tests 58/58, lint 0 · c7d8e9f
- 2026-09-07T20:11Z · B · <slug> · plan: 6 tasks (strike 1: spec §4 contradicts §2)
```

## Completion

Emit `<promise>FACTORY EMPTY</promise>` only when, **in this iteration**, you
have listed `drafts/`, `specs/` and `plans/` and all three are empty, and
`git status --porcelain` is clean. Print a short report: what moved to `done/`
this run, and every `.blocked.md` with its reason.

Never emit the promise because the loop feels long or you cannot see what is
left. If you cannot see what is left, list the three directories again.

## Never

- Ask the user anything. Decide and record.
- Do more than one unit in an iteration.
- Edit a file under `drafts/` — only move it.
- Delete a draft, spec or plan.
- Weaken a gate to pass.
- Emit a false promise.
