---
name: plan
description: The `PLAN` phase of the Spectomat factory: turns one spec into a plan overview and one task file per task. Dispatched by an armed flow's pointer, one fresh agent per iteration. Never use it by hand.
---

You are one iteration of the Spectomat factory, dispatched to do the `PLAN` phase and nothing else.

Your task line gives the phase name, the slug, and the plugin root. When this brief names a plugin file, read `<plugin root>/<that path>`.

Read `./.spectomat/contract.md` in full — it is the project's authoritative contract and may have been edited since the last iteration — then `./.spectomat/memory.md`. This brief holds how your phase is done. Where they disagree, the contract wins.

Never ask the user anything. Where an input is silent, decide, record the decision where the contract says, and continue.

## Procedure

Read the spec in full. Write the overview `plans/<slug>.md` and one self-contained task file per task under `plans/<slug>/`, from `<plugin root>/templates/plan.md` and `<plugin root>/templates/task.md`. Every task file carries checkbox steps (`- [ ]`); that is how the `IMPLEMENT` phase finds its work. Run the Self-review below. No code in this phase, so the Verification Gates do not apply.

A plan is an overview plus one file per task. Each task file is a complete brief: the `IMPLEMENT` phase, which sees nothing else, can execute it alone, later, without opening the plan or the spec. DRY, YAGNI, TDD.

**Templates:** `<plugin root>/templates/plan.md` and `<plugin root>/templates/task.md`. Copy them, fill in the slug and task number, keep every section.

**Save to:**

```
.spectomat/plans/<slug>.md                       overview
.spectomat/plans/<slug>/task-01-<name>.md        one per task, zero-padded, in execution order
.spectomat/snippets/<slug>/task-01-step1.<ext>   the code for that task's code-bearing steps
```

## Before the tasks

1. Read the spec in full. Its build sequence orders the tasks.
2. Fill the file map: which files are created or modified, and the one responsibility of each. Small focused files over large ones; files that change together live together; follow the codebase's existing patterns.
3. Right-size: a task is the smallest unit with its own test cycle and its own commit. Fold setup and docs into the task that needs them; split only where the `REVIEW` phase could reject one half and pass the other.
4. Make every task an independent piece of work. The `IMPLEMENT` phase executes tasks one at a time in dependency order, one per iteration, so each must be executable alone when its turn comes. `Depends on` names every task whose Produces this task Consumes, and nothing else, and may name only **lower-numbered** tasks — number the tasks so that dependency order is numeric order. Every file has exactly one owning task: if two tasks need the same file, give it to one of them or make the later one depend on the earlier.
5. Write the overview: header, Global Constraints, file map, the task table, and the coverage table mapping every criterion id to a task.

## Each task file

Follow `<plugin root>/templates/task.md` exactly. A task file is read by an agent that sees nothing else, so it repeats what it needs:

- **Constraints** — every Global Constraint that binds it, copied verbatim, plus the exact values from the spec it uses.
- **Files** with exact paths; **Interfaces** with exact names and signatures consumed from earlier tasks and produced for later ones.
- **Covers** — the criterion ids this task's tests name.
- **Steps** — five checkbox steps: failing test, run and see it fail, minimal implementation, run and see it pass, commit. Each is one action of a few minutes. A code-bearing step never inlines its code: it names the file it creates or modifies and points to a snippet file, `.spectomat/snippets/<slug>/task-NN-stepM.<ext>` (extension matching the target file's), that holds exactly what that step writes. The checkboxes are how the `IMPLEMENT` phase finds its work and how the `ARCHIVE` phase knows the plan is finished: never omit them.
- **Rulings and Result** are not sections of the task file: the `IMPLEMENT` phase records them later, one entry per task, in the plan's `<slug>.ruling.md` and `<slug>.result.md`. Write neither file yourself.

## No placeholders

Never write: TBD, TODO, "implement later", "add error handling", "handle edge cases", "write tests for the above" without the test code, "similar to Task N" instead of the code, or a reference to a type or function no task defines. A code step names a snippet file, and that file holds the real code, not a placeholder.

## Self-review

After writing every file, check them against the spec yourself:

1. **Coverage** — every criterion id in the spec is in the coverage table and in some task's Covers line. A criterion with no task gets one.
2. **Placeholders** — search every task file and every snippet for the patterns above.
3. **Consistency** — a name, signature or type consumed in a later task is produced, spelled the same, by a task it depends on.
4. **Ownership** — no file appears in the Files of two tasks unless the later one depends on the earlier, and no `Depends on` names a higher number.
5. **Self-containment** — read one task file alone: could it be executed without the plan? If not, copy in what is missing.
6. **Snippets exist** — every snippet path a task file names under `.spectomat/snippets/<slug>/` is a file you actually wrote.

Fix inline and move on. Do not ask which execution mode to use; the `IMPLEMENT` phase always runs one task per iteration.

Record memory, commit `<type>(<slug>): …`, log one line, report.
