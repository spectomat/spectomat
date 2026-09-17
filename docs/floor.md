Floor is the directories and files the Flow creates and works with in the user's project.

```text
.spectomat/
  drafts/      the one entrance: raw ideas, one .md each — the user drops them here, and /spectomat:run moves each into its own slug dir
  <slug>/      everything of one idea, named after its draft — you write all of these
    draft.md     the idea as the user wrote it, moved here when the flow arms; never edited afterwards
    spec.md      the normative spec, written once from the draft, reviewed once, then never edited again
    plan.md      the plan overview: goal, constraints, file map, task table
    task-NN-<name>.md   one self-contained brief per task, zero-padded, in execution order
    task-NN-stepM.<ext> the code a task's step names instead of inlining it
    ruling.md    decisions and defects that bind one task, one entry per task — created when the first one is earned
    result.md    one entry per closed task, each giving that task's commit range
    done.md      written by ARCHIVE when the plan ships: the slug is finished and leaves the flow
    blocked.md   written instead, with the reason, when a phase fails three times: the slug is finished and leaves the flow
  work/        scratch for IMPLEMENT and REVIEW: diffs, stats, anything bulky — gitignored
  log.md       append-only, one line per phase of work — gitignored, never committed
  contract.md  this file
  gates.sh     the project's single gate command — generated once from package.json, committed, yours to edit
  memory.md    what the factory has learned about this codebase — committed, read every iteration, added to before every commit
  state.json   the flow's state: gitignored, changed only through the Flow
```

> A `slug` is the draft's file name without `.md`. Everything of one idea lives under `.spectomat/<slug>/` for its whole life: nothing is moved when it finishes, so the trail of one idea is one directory.
>
> A slug dir carrying `done.md` or `blocked.md` is finished. It leaves the flow, keeps its files where they are, and is never picked, edited or re-archived. The two markers never coexist.
>
> The craft of each phase lives in its brief; the invariants live in the contract.
