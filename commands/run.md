---
description: "Run the unattended dark factory"
argument-hint: "[max-iterations]  (default 100)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Task", "Skill"]
---

# Spectomat run

Run the unattended dark factory - floor setup and loop start iterations over
`drafts → specs → plans → executed plans → done` phases:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/run.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report why and stop.

If the factory is armed, begin iteration 1 now: follow the prompt printed at
the end of the output. The Stop hook feeds that same prompt back after every
iteration until you output `<promise>FACTORY EMPTY</promise>` or the cap is
reached.

**This loop is unattended.**
Nobody answers questions.
Decide, record the decision where `docs/.spectomat/contract.md` says, and continue.
Emit the  promise only when `drafts/`, `specs/` and `plans/` are all empty and the tree
is clean, checked this iteration.

## The floor

```
docs/.spectomat/
  drafts/     ideas the user drops in, one .md each — the file name is the slug; `run` names them NNN-<name>.md
  .inc        the last NNN issued to a wish; committed with the drafts
  specs/      phase A writes one per draft; or a finished spec placed by hand
  plans/      phase B writes an overview per spec plus <slug>/task-NN-<name>.md per task
  done/       phase D moves spec + plan here when every step is ticked and gates pass
  log.md      one line per phase, gitignored
  contract.md the rules, rendered once from the plugin template, re-read every iteration
  state.md    the Stop hook's state, gitignored
  work/       per-task briefs, reports and diffs, gitignored
```

## One phase per iteration

```
drafts/*.md  ──A──▶  specs/<slug>.md  ──B──▶  plans/<slug>.md  ──C×n──▶  code + commits  ──D──▶  done/
```

Priority is D, C, B, A: work in progress is finished before the next spec is
planned, and every spec is planned before the next draft is read. Every phase
is a commit and a log line.

| Phase | Skill |
| --- | --- |
| A · draft → spec | `spectomat:writing-specs` |
| B · spec → plan | `spectomat:writing-plans` |
| C · next wave of ready tasks (parallel implementers, disjoint files) | `spectomat:executing-tasks`, with `spectomat:test-driven-development` |
| any failing gate | `spectomat:systematic-debugging` |
| D · plan → done, every commit, the promise | the gates in `contract.md`, run fresh this iteration, numbers in the log |

## Rules that make it terminate

- One phase per iteration. Never ask the user; record choices as `assumed`
  rows in the spec or rulings in the plan.
- Three strikes → `done/<slug>.blocked.md` with a reason, never deleted.
- Never weaken a gate. Never fake a promise.

## Operating it

- **Feed it:** drop a `.md` idea into `wishlist/` at the project root; `run`
  moves it into `docs/.spectomat/drafts/` as `NNN-<name>.md`, oldest
  modification first, and commits it. The counter lives in
  `docs/.spectomat/.inc`, so numbers keep growing across runs. Already have a
  finished spec? Put it in `docs/.spectomat/specs/` and the factory starts
  at planning.
- **Watch:** `/spectomat:status` shows floor counts, plan progress and the
  log tail.
- **Steer:** edit a spec or plan between iterations; edit `contract.md` to
  change the rules or the gates.
- **Stop:** `/spectomat:cancel`. Re-run `/spectomat:run` to resume; the
  filesystem is the ledger, so nothing is re-planned.
