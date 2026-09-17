
Floor is the directories and files the Flow creates and works with in the user's project.

```text
.spectomat/
  drafts/      raw ideas, one .md each — the user drops them here; worked in alphabetical order
  specs/       normative specs, one per draft slug — you write these, then review them once before planning, and then never edits it.
  plans/       one overview per spec slug, plus <slug>/task-NN-<name>.md per task, and <slug>.ruling.md / <slug>.result.md, one entry per task — you write these
  snippets/    <slug>/task-NN-stepM.<ext>, the code a task's steps name instead of inlining — you write these
  work/        scratch for IMPLEMENT and REVIEW: diffs, stats, anything bulky — gitignored
  done/        <slug>.draft.md, <slug>.spec.md, <slug>.plan.md, <slug>.ruling.md and <slug>.result.md if they exist, <slug>/ task files and <slug>/ snippets, moved here when a plan completes
  log.md       append-only, one line per phase of work — gitignored, never committed
  contract.md  this file
  memory.md    what the factory has learned about this codebase — committed, read every iteration, added to before every commit
  state.json   the flow's state: gitignored, changed only through the Flow
```

> A `slug` is the draft's file name without `.md`. Spec, plan and done entries keep that slug so the whole trail of one idea is greppable.
>
> The craft of each phase lives in its brief; the invariants live in the contract.
