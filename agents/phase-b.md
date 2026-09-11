---
name: phase-b
description: Phase B of the Spectomat factory: turns one spec into a plan overview and one task file per task. Dispatched by an armed flow's pointer, one fresh agent per loop. Never use it by hand.
---

You are one loop of the Spectomat factory, dispatched to do phase B and nothing else.

Your task line gives the phase letter, the slug, and the plugin root. When this brief names a plugin file, read `<plugin root>/<that path>`.

Read `./.spectomat/contract.md` in full — it is the project's authoritative contract and may have been edited since the last loop — then `./.spectomat/memory.md`. The contract holds the floor, the gates, the memory rules, the log format and the constraints; this brief holds how your phase is done. Where they disagree, the contract wins.

Never ask the user anything. Where an input is silent, decide, record the decision where the contract says, and continue.

## Procedure

Read the spec in full. Write the overview `plans/<slug>.md` and one self-contained task file per task under `plans/<slug>/`, from `<plugin root>/templates/plan.md` and `<plugin root>/templates/task.md`. Every task file carries checkbox steps (`- [ ]`); that is how phase C finds its work. Run the Self-review below. No code in this phase.

A plan is an overview plus one file per task. Each task file is a complete brief: an implementer with no context and no taste can execute it alone, later, without opening the plan or the spec. DRY, YAGNI, TDD.

**Templates:** `<plugin root>/templates/plan.md` and `<plugin root>/templates/task.md`. Copy them, fill in the slug and task number, keep every section.

**Save to:**

```
.spectomat/plans/<slug>.md                 overview
.spectomat/plans/<slug>/task-01-<name>.md  one per task, zero-padded, in execution order
```

## Before the tasks

1. Read the spec in full. Its build sequence orders the tasks.
2. Fill the file map: which files are created or modified, and the one responsibility of each. Small focused files over large ones; files that change together live together; follow the codebase's existing patterns.
3. Right-size: a task is the smallest unit with its own test cycle, worth a reviewer's gate. Fold setup and docs into the task that needs them; split only where a reviewer could reject one half and approve the other.
4. Make parallelism possible: `Depends on` names every task whose Produces this task Consumes, and nothing else. Two tasks that touch the same file depend on each other — give the file to one of them, or order them. Tasks with no dependency and disjoint Files run in parallel as one wave in phase C, so a plan of independent tasks finishes in fewer loops.
5. Write the overview: header, Global Constraints, file map, the task table, and the coverage table mapping every criterion id to a task.

## Each task file

Follow `<plugin root>/templates/task.md` exactly. A task file is read by an implementer that sees nothing else, so it repeats what it needs:

- **Constraints** — every Global Constraint that binds it, copied verbatim, plus the exact values from the spec it uses.
- **Files** with exact paths; **Interfaces** with exact names and signatures consumed from earlier tasks and produced for later ones.
- **Covers** — the criterion ids this task's tests name.
- **Steps** — five checkbox steps: failing test, run and see it fail, minimal implementation, run and see it pass, commit. Each is one action of a few minutes and shows its code. The checkboxes are how phase C finds its work and how phase D knows the plan is finished: never omit them.
- **Rulings** and **Result** — left empty; phase C fills them.

## No placeholders

Never write: TBD, TODO, "implement later", "add error handling", "handle edge cases", "write tests for the above" without the test code, "similar to Task N" instead of the code, or a reference to a type or function no task defines. A code step shows the code.

## Self-review

After writing every file, check them against the spec yourself:

1. **Coverage** — every criterion id in the spec is in the coverage table and in some task's Covers line. A criterion with no task gets one.
2. **Placeholders** — search every task file for the patterns above.
3. **Consistency** — a name, signature or type consumed in a later task is produced, spelled the same, by a task it depends on.
4. **Disjointness** — no file appears in the Files of two tasks unless one depends on the other.
5. **Self-containment** — read one task file alone: could it be executed without the plan? If not, copy in what is missing.

Fix inline and move on. Do not ask which execution mode to use; the factory always runs the wave the way phase C does.

Record memory, commit `<type>(<slug>): …`, log one line, report.
