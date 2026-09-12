---
description: "Run the unattended dark factory"
argument-hint: "[max-iterations]  (default 100)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Agent", "Task"]
---

# Spectomat run

Run the unattended dark factory - floor setup
and the start of iterations over `drafts → specs → plans → executed plans → done` phases:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/run.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report why and stop.

If the factory is armed, begin iteration 1 now: follow the prompt printed at the end of the output. Each iteration is one picker verdict, dispatched to a fresh phase agent (`spectomat:specify|plan|implement|review`, or `general-purpose` carrying the brief when that type is not listed), to `scripts/archive.sh`, or to the janitor; this session only launches it, relays its report and stops. The Stop hook feeds the same prompt back after every iteration until you relay `<promise>FACTORY EMPTY</promise>` or the cap is reached.

**This flow is unattended.** Nobody answers questions. Decide, record the decision where `.spectomat/contract.md` says, and continue.

Emit the promise only when `drafts/`, `specs/` and `plans/` are all empty and the tree is clean, checked this iteration.

## The floor

```
.spectomat/
  drafts/     ideas the user drops in, one .md each — the file name is the slug, worked in alphabetical order
  specs/      SPECIFY writes one per draft; or a finished spec placed by hand
  plans/      PLAN writes an overview per spec plus <slug>/task-NN-<name>.md per task
  done/       ARCHIVE moves spec + plan here when every step is ticked and gates pass
  work/       per-task briefs, reports and diffs, gitignored
  contract.md the rules, rendered once from the plugin template, re-read every iteration
  memory.md   codebase facts the factory has learned, read every iteration, added to before every commit
  state.json  the flow's state: iteration counter, cap, session — gitignored
  pointer.md  the prompt the Stop hook feeds back each iteration — gitignored
  log.md      one line per phase, gitignored
```

## One phase per iteration

```
drafts/*.md  ──SPECIFY──▶  specs/<slug>.md  ──PLAN──▶  plans/<slug>.md  ──IMPLEMENT×n──▶  code + commits  ──REVIEW──▶  verdict  ──ARCHIVE──▶  done/
```

Priority is `ARCHIVE`, `REVIEW`, `IMPLEMENT`, `PLAN`, `SPECIFY`: work in progress is finished before the next spec is planned, and every spec is planned before the next draft is read. Every phase is a commit and a log line.

| Phase | Brief |
| --- | --- |
| `SPECIFY` · draft → spec | `agents/specify.md` |
| `PLAN` · spec → plan | `agents/plan.md` |
| `IMPLEMENT` · next ready task (one per iteration, dependency order) | `agents/implement.md`, which carries TDD and systematic debugging |
| `REVIEW` · finished plan → verdict or fix tasks | `agents/review.md`, at most two rounds |
| any failing gate | the systematic-debugging section of `agents/implement.md` |
| end of an `IMPLEMENT` task, `ARCHIVE` · plan → done, the promise | the gates in `contract.md`, run fresh this iteration, numbers in the log |

## Rules that make it terminate

- One phase per iteration. Never ask the user; record choices as `assumed` rows in the spec or rulings in the plan.
- Three strikes → `done/<slug>.blocked.md` with a reason, never deleted.
- Never weaken a gate. Never fake a promise.
