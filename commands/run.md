---
description: "Run the unattended dark factory"
argument-hint: "[max-loops]  (default 100)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Task"]
---

# Spectomat run

Run the unattended dark factory - floor setup
and the start of loops over `drafts → specs → plans → executed plans → done` phases:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/run.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report why and stop.

If the factory is armed, begin loop 1 now: follow the prompt printed at the end of the output. Every loop is one fresh `general-purpose` subagent that reads the contract and does one phase; this session only launches it, relays its report and stops. The Stop hook feeds the same prompt back after every loop until you relay `<promise>FACTORY EMPTY</promise>` or the cap is reached.

**This flow is unattended.** Nobody answers questions. Decide, record the decision where `.spectomat/contract.md` says, and continue.

Emit the promise only when `drafts/`, `specs/` and `plans/` are all empty and the tree is clean, checked this loop.

## The floor

```
.spectomat/
  drafts/     ideas the user drops in, one .md each — the file name is the slug;
  specs/      phase A writes one per draft; or a finished spec placed by hand
  plans/      phase B writes an overview per spec plus <slug>/task-NN-<name>.md per task
  done/       phase D moves spec + plan here when every step is ticked and gates pass
  work/       per-task briefs, reports and diffs, gitignored
  contract.md the rules, rendered once from the plugin template, re-read every loop
  memory.md   codebase facts the factory has learned, read every loop, added to before every commit
  state.md    the Stop hook's state, gitignored
  log.md      one line per phase, gitignored
  .inc        the last NNN issued to a wish; committed with the drafts
```

## One phase per loop

```
drafts/*.md  ──A──▶  specs/<slug>.md  ──B──▶  plans/<slug>.md  ──C×n──▶  code + commits  ──D──▶  done/
```

Priority is D, C, B, A: work in progress is finished before the next spec is planned, and every spec is planned before the next draft is read. Every phase is a commit and a log line.

| Phase | Reference (plugin `references/`, absolute path in `contract.md`) |
| --- | --- |
| A · draft → spec | `writing-specs.md` |
| B · spec → plan | `writing-plans.md` |
| C · next wave of ready tasks (parallel implementers, disjoint files) | `executing-tasks.md`, with `test-driven-development.md` |
| any failing gate | `systematic-debugging.md` |
| end of a C wave, D · plan → done, the promise | the gates in `contract.md`, run fresh this loop, numbers in the log |

## Rules that make it terminate

- One phase per loop. Never ask the user; record choices as `assumed` rows in the spec or rulings in the plan.
- Three strikes → `done/<slug>.blocked.md` with a reason, never deleted.
- Never weaken a gate. Never fake a promise.
