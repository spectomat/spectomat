---
name: writing-plans
description: Use when the factory's phase B turns a spec in docs/.spectomat/specs into a plan — an overview file plus one self-contained task file per task, each a brief an implementer can execute later without the plan or the spec.
---

# Writing a plan

A plan is an overview plus one file per task. Each task file is a complete
brief: an implementer with no context and no taste can execute it alone,
later, without opening the plan or the spec. DRY, YAGNI, TDD.

**Templates:** `templates/plan.md` and `templates/task.md` in this plugin.
Copy them, replace `{{SLUG}}` and `{{N}}`, keep every section.

**Save to:**

```
docs/.spectomat/plans/<slug>.md                 overview
docs/.spectomat/plans/<slug>/task-01-<name>.md  one per task, zero-padded, in execution order
```

## Before the tasks

1. Read the spec in full. Its build sequence orders the tasks.
2. Fill the file map: which files are created or modified, and the one
   responsibility of each. Small focused files over large ones; files that
   change together live together; follow the codebase's existing patterns.
3. Right-size: a task is the smallest unit with its own test cycle, worth a
   reviewer's gate. Fold setup and docs into the task that needs them; split
   only where a reviewer could reject one half and approve the other.
4. Make parallelism possible: `Depends on` names every task whose Produces
   this task Consumes, and nothing else. Two tasks that touch the same file
   depend on each other — give the file to one of them, or order them. Tasks
   with no dependency and disjoint Files run in parallel as one wave in
   phase C, so a plan of independent tasks finishes in fewer iterations.
5. Write the overview: header, Global Constraints, file map, the task table,
   and the coverage table mapping every criterion id to a task.

## Each task file

Follow `templates/task.md` exactly. A task file is read by an implementer
that sees nothing else, so it repeats what it needs:

- **Constraints** — every Global Constraint that binds it, copied verbatim,
  plus the exact values from the spec it uses.
- **Files** with exact paths; **Interfaces** with exact names and signatures
  consumed from earlier tasks and produced for later ones.
- **Covers** — the criterion ids this task's tests name.
- **Steps** — five checkbox steps: failing test, run and see it fail, minimal
  implementation, run and see it pass, commit. Each is one action of a few
  minutes and shows its code. The checkboxes are how phase C finds its work
  and how phase D knows the plan is finished: never omit them.
- **Rulings** and **Result** — left empty; phase C fills them.

## No placeholders

Never write: TBD, TODO, "implement later", "add error handling", "handle
edge cases", "write tests for the above" without the test code, "similar to
Task N" instead of the code, or a reference to a type or function no task
defines. A code step shows the code.

## Self-review

After writing every file, check them against the spec yourself:

1. **Coverage** — every criterion id in the spec is in the coverage table and
   in some task's Covers line. A criterion with no task gets one.
2. **Placeholders** — search every task file for the patterns above.
3. **Consistency** — a name, signature or type consumed in a later task is
   produced, spelled the same, by a task it depends on.
4. **Disjointness** — no file appears in the Files of two tasks unless one
   depends on the other.
5. **Self-containment** — read one task file alone: could it be executed
   without the plan? If not, copy in what is missing.

Fix inline and move on. Do not ask which execution mode to use; the factory
always runs `spectomat:executing-tasks`.
