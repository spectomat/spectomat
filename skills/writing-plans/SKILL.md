---
name: writing-plans
description: Use when the factory's unit B turns a spec in docs/.spectomat/specs into a plan in docs/.spectomat/plans — bite-sized TDD tasks with checkbox steps, no placeholders, self-reviewed against the spec.
---

# Writing a plan

The plan is what an implementer with no context and no taste can follow.
Every task carries its own test cycle and ends in a commit. DRY, YAGNI, TDD.

**Shape:** `templates/plan.md` in this plugin. Copy it, replace `{{SLUG}}`,
keep every section. **Save to:** `docs/.spectomat/plans/<slug>.md`, same slug
as the spec.

## Before the tasks

1. Read the spec in full. Its build sequence orders the tasks.
2. Fill the file map: which files are created or modified, and the one
   responsibility of each. Small focused files over large ones; files that
   change together live together; follow the codebase's existing patterns.
3. Right-size: a task is the smallest unit with its own test cycle, worth a
   reviewer's gate. Fold setup and docs into the task that needs them; split
   only where a reviewer could reject one half and approve the other.

## Each task

Follow the template's task block exactly: Files with exact paths, Interfaces
with exact names and signatures (a task's implementer sees only its own
task), Covers with the spec's criterion ids, then five checkbox steps: failing
test, run and see it fail, minimal implementation, run and see it pass, commit.
Each step is one action of a few minutes and shows its code. The checkbox
steps are how unit C finds its work: never omit them.

## No placeholders

Never write: TBD, TODO, "implement later", "add error handling", "handle
edge cases", "write tests for the above" without the test code, "similar to
Task N" instead of the code, or a reference to a type or function no task
defines. A code step shows the code.

## Self-review

After writing the whole plan, check it against the spec yourself:

1. **Coverage** — every spec section and criterion id appears in some task's
   Covers line. A criterion with no task gets one.
2. **Placeholders** — search for the patterns above and replace them.
3. **Consistency** — names, signatures and types used in later tasks match
   the ones earlier tasks produce.

Fix inline and move on. Do not ask which execution mode to use; the factory
always runs `spectomat:executing-tasks`.
