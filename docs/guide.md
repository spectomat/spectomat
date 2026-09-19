# User guide

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the wishes it finds, arms the Stop hook for `n` iterations (default 100) and starts iteration 1; refuses on a dirty tree |
| `/spectomat:status` | shows the current iteration, floor counts, per-plan step progress, blocked files and the log tail |
| `/spectomat:cancel` | disarms the flow; the floor stays, `run` resumes from it |
| `/spectomat:help` | shows this guide |

## Install

Requires `jq` on PATH.

```bash
claude plugin marketplace add ~/Projects/spectomat
claude plugin install spectomat@spectomat
```

## The Floor

```text
.wishlist/    the inbox: ideas, one .md each; the file name is the slug. `run` moves each into its own slug dir
.spectomat/
  <slug>/     everything of one idea, for its whole life — nothing is moved when it finishes
    draft.md    the idea as you wrote it
    spec.md     written by SPECIFY from the draft, then revised once by REVIEW-SPEC; or put a finished spec here yourself
    plan.md     the overview PLAN writes
    tasks/      task-NN-<name>.md per task, each a self-contained brief; snippets/ holds the code their steps name
    ruling.md   decisions and defects that bind one task; tasks.json is the task ledger, holding each task's status, dependsOn and closing commits
    done.md     written by ARCHIVE once REVIEW has passed the plan and the gates are green
    blocked.md  written instead, with the reason, when a phase fails three times
  log.md      one line per phase, gitignored
  contract.md the rules, re-read every iteration
  gates.sh    the project's single gate command — generated once, yours to edit
  memory.md   durable valuable facts about the codebase, accumulated all along the time
  state.json  the whole of the flow's state: every slug and its phase, task counters, strikes, iteration counter, cap, session, plugin copy, current phase and slug — gitignored
  work/       per-task briefs, reports and diffs, gitignored
```

## The Flow

The flow is a sequence of iterations. Each one asks the picker for a verdict and dispatches on it — a fresh phase agent, the archiver, or the janitor — then commits, logs, and stops for the Stop hook to feed the next iteration in; `FINISH` is the exception, where the Stop hook itself ends the flow instead of dispatching anyone.

```text
Stop hook ──▶ feeds back the pointer prompt ──▶ picker (scripts/phase.sh) ──▶ one verdict per iteration
```

```text
<slug>/draft.md ──SPECIFY──▶ spec.md ──REVIEW-SPEC──▶ reviewed spec ──PLAN──▶ plan.md + tasks/task-NN-*.md
                                                                                   │
                                                                            IMPLEMENT×n (one task agent each: TDD, gates, one commit)
                                                                                   │
                                                                                   ▼
                                       done.md ◀──ARCHIVE── verdict ◀──REVIEW── finished plan
                                                                │
                                                                └──fix tasks──▶ back to IMPLEMENT (≤2 rounds)
```

`RECOVER` sends a dirty tree to the janitor instead of any of the above; `FINISH` fires once no slug is left at a working phase in `state.json` and the tree is clean, and the Stop hook ends the flow and prints what shipped. Nothing the session says can end a flow: the hook runs the picker itself.

Work in progress is finished before a new draft is read: `ARCHIVE` and `REVIEW` outrank `IMPLEMENT`, which outranks `PLAN`, which outranks `REVIEW-SPEC`, which outranks a fresh `SPECIFY`. Drafts are read in alphabetical order of the file name, so the name is how you fix the order they are worked in.

`contract.md`, `memory.md` and `gates.sh` are rendered from the plugin templates at the first run and committed. Next `run`s never overwrite them, so edit them in the project to change the rules, the gates or what the Flow believes about the codebase. Each is checked on its own, so a floor armed before `gates.sh` existed gets it on the next `run`.

> It is dark! Nobody is asked anything. Every open choice becomes an `assumed` row in the spec's Decisions table. Three failed attempts at a phase write `.spectomat/<slug>/blocked.md` with the reason and mark the slug `BLOCKED` in `state.json`, which takes it out of the flow.

## Operating it

- **Feed it.** Drop a `.md` idea into `.wishlist/`. `run` moves each draft into its own `.spectomat/<slug>/draft.md` and commits it, leaving `.wishlist/` empty. Drafts are worked in alphabetical order of the file name, so name them to get the order you want. A finished spec can go straight into `.spectomat/<slug>/spec.md`; the Flow then starts at reviewing it.
- **Steer it.** Edit a spec or a plan between iterations. Edit `contract.md` to change the rules, `memory.md` to correct what the Flow believes about the codebase.
- **Read what it learned.** `memory.md` is committed: the map, commands, patterns and traps every iteration reads before working and adds to before committing. Seed it by hand before the first run and the Flow starts informed; it keeps itself under ~40 lines and deletes what the code contradicts.
- **Gate it.** The gates are always `./.spectomat/gates.sh`, run once per task in the `IMPLEMENT` phase, before its commit, and once in the `ARCHIVE` phase before archiving. The first `run` writes that script from your `package.json`: a `gates` script, if present, is the single gate; otherwise every `typecheck`, `lint` and `test` script found, one line each in that order. Nothing was detected? You get the script anyway, with commented examples and an honest no-op. Edit the script — it is the one place gates are defined, and gates that are not npm scripts are just more lines in it. `set -e` stops at the first failure, so its exit code is the whole run's. An iteration may never weaken a gate to pass.
- **Resume it.** After a cancel or the iteration cap, run `/spectomat:run` again. The filesystem is the ledger, so nothing is re-planned.
- **Start clean.** `run` refuses to arm while anything outside the floor is uncommitted: the picker answers `RECOVER` to any dirt, so a flow armed over work in progress would send every iteration to the janitor. Commit or stash first.
