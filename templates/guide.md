# User guide

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the drafts it finds, arms the Stop hook for `n` iterations (default 100) and starts iteration 1; refuses on a dirty tree |
| `/spectomat:status` | shows the current iteration, floor counts, per-plan step progress, blocked files and the log tail |
| `/spectomat:cancel` | disarms the flow; the floor stays, `run` resumes from it |
| `/spectomat:help` | shows this guide |

## The Floor

```text
.spectomat/
  drafts/     ideas, one .md each; the file name is the slug, worked in alphabetical order
  specs/      written by SPECIFY from each draft; or put a finished spec here yourself
  plans/      PLAN writes an overview per spec plus <slug>/task-NN-<name>.md per task, each a self-contained brief
  done/       spec + plan moved here by ARCHIVE after every step is ticked and gates pass
  log.md      one line per phase, gitignored
  contract.md the rules and gates, re-read every iteration
  memory.md   durable valuable facts about the codebase, accumulated all along the time
  state.json  the flow's state: iteration counter, cap, session — gitignored
  pointer.md  the prompt the Stop hook feeds back each iteration — gitignored
  work/       per-task briefs, reports and diffs, gitignored
```

## The Flow

The flow is a sequence of iterations. Each iteration is one picker verdict, dispatched to a fresh phase agent, to the archiver, or to the janitor. The picker reads the floor and prints one verdict per iteration: `SPECIFY <slug>`, `PLAN <slug>`, `IMPLEMENT <slug>`, `ARCHIVE <slug>`, `RECOVER`, or `FINISH`.

- **`ARCHIVE`** `finished plan` → `done/`, when every task step is ticked and the gates are green,
- **`IMPLEMENT`×n** `plan` → `next ready task`: one task per iteration in dependency order, one fresh implementer, TDD, one commit and one reviewed diff,
- **`PLAN`** `spec` → `plan`: an overview plus one task file per task,
- **`SPECIFY`** `draft` → `spec`,
- **`FINISH`** `nothing left`: `drafts/`, `specs/` and `plans/` are empty and the tree is clean, so the iteration emits `<promise>FACTORY EMPTY</promise>` and the flow ends.

Work in progress is finished before a new draft is read. Drafts are read in alphabetical order of the file name, so the name is how you fix the order they are worked in.

## Iteration Mechanics

The Stop hook runs when Claude tries to end its turn. While `state.json` exists for this session, the hook blocks the exit and returns `pointer.md` as the next input.

The picker dispatches to exactly one phase per iteration: `SPECIFY <slug>` → a fresh phase agent writes draft → spec (`specify.md`); `PLAN <slug>` → a fresh phase agent writes an overview plus one task file per task (`plan.md`); `IMPLEMENT <slug>` → a phase agent implements the next ready task with TDD and code review (`implement.md`); `ARCHIVE <slug>` → `scripts/archive.sh` ticks all steps, verifies gates, and moves the trail to `done/`; `recover` → the janitor recovers from a dirty tree; `finalize` → the floor is empty and the flow ends. Each iteration emits one short report; when the flow ends, `state.json` and `pointer.md` are both removed.

`contract.md` and `memory.md` are rendered from the plugin templates at the first run and committed. Next `run`s never overwrite them, so edit them in the project to change the rules, the gates or what the factory believes about the codebase. Each is checked on its own, so a floor armed before `memory.md` existed gets it on the next `run`.

> It is dark! Nobody is asked anything. Every open choice becomes an `assumed` row in the spec's Decisions table. Three failed attempts at a phase move the file to `done/<slug>.blocked.md` with the reason.

## Operating it

- **Feed it.** Drop a `.md` idea into `.spectomat/drafts/`. `run` commits whatever it finds there. Drafts are worked in alphabetical order of the file name, so name them to get the order you want. A finished spec can go straight into `specs/`; the factory then starts at planning.
- **Steer it.** Edit a spec or a plan between iterations. Edit `contract.md` to change the rules, `memory.md` to correct what the factory believes about the codebase.
- **Read what it learned.** `memory.md` is committed: the map, commands, patterns and traps every iteration reads before working and adds to before committing. Seed it by hand before the first run and the factory starts informed; it keeps itself under ~40 lines and deletes what the code contradicts.
- **Gate it.** The gates run once per task in the `IMPLEMENT` phase, after the fix rounds and before the tick commit, and once in the `ARCHIVE` phase before archiving. `run` compiles the gate command from `package.json` scripts: a `gates` script, if present, is the single gate; otherwise every `typecheck`, `test`, `lint` and `build` script found, chained with `&&` in that order. The command is the first line of the block under Verification Gates in `contract.md`, rendered once at the first `run`; edit it there when `package.json` changes. Gates that are not npm scripts go into the same block, one command per line; every line must exit 0. An iteration may never weaken a gate to pass.
- **Resume it.** After a cancel or the iteration cap, run `/spectomat:run` again. The filesystem is the ledger, so nothing is re-planned.
- **Start clean.** `run` refuses to arm while anything outside the floor is uncommitted: the picker answers `RECOVER` to any dirt, so a flow armed over work in progress would send every iteration to the janitor. Commit or stash first.

## Glossary

- **Plugin** a Claude Code plugin made of commands, a hooks, skills, scripts, templates and reference files etc.
- **Command** is a slash command the user types: `/spectomat:run`, `/spectomat:status`, `/spectomat:cancel` or `/spectomat:help`. Each runs a script first, then tells Claude what to do with its output.
- **Session** is the Claude Code session where `/spectomat:run` was called. It holds the flow, launches one subagent per iteration and relays its report; it does no factory work itself.
- **Iteration** is one picker verdict, one phase, one commit, one log line.
- **State file** is `.spectomat/state.json`: the iteration counter, the iteration cap and the session that armed the flow. Its existence is what "armed" means; `/spectomat:cancel` deletes it.
- **Pointer** is `.spectomat/pointer.md`: the prompt the Stop hook feeds back every iteration, telling the session to run the picker and dispatch on its verdict. Fixed text, rendered once per `run`.
- **Picker** is the script `scripts/phase.sh` that prints one verdict per iteration: `SPECIFY <slug>`, `PLAN <slug>`, `IMPLEMENT <slug>`, `ARCHIVE <slug>`, `RECOVER`, or `FINISH`.
- **Phase agent** is a fresh subagent per phase: `spectomat:specify|plan|implement` or `spectomat:recover`; each brief contains the craft of its phase (`agents/specify.md`, `plan.md`, `implement.md`, `recover.md`).
- **Archiver** is the script `scripts/archive.sh` that performs the `ARCHIVE` phase: ticks all steps, verifies gates, moves the trail to `done/` and commits.
- **Janitor** is the same as the Archiver: the script `scripts/archive.sh` recovers from a dirty tree by moving the current trail to `done/` and committing a blocked file.
- **Verdict** is the one-line output of the picker: `SPECIFY <slug>`, `PLAN <slug>`, `IMPLEMENT <slug>`, `ARCHIVE <slug>`, `RECOVER`, or `FINISH`.
- **Phase** is one of `SPECIFY` (draft → spec), `PLAN` (spec → plan), `IMPLEMENT` (plan → next task), `ARCHIVE` (plan → done). An iteration does exactly one. Verdicts are upper case; the agent types and brief files that serve them are lower case. The two remaining verdicts are not phases: `RECOVER` hands the floor to the janitor, `FINISH` ends the flow.
- **Task** is one independent piece of work in a plan, with its own file, its own test cycle, its own commit and its own review. The `IMPLEMENT` phase executes exactly one per iteration, in dependency order.
- **Flow** is the sequence of iterations from the first `/spectomat:run` until the promise `FACTORY EMPTY`.
- **Strike** is one failed attempt at a phase for a slug. Three strikes move the file to `done/<slug>.blocked.md` with the reason.
- **Slug** is a draft's file name without `.md`. Spec, plan and done entries keep it.
- **Floor** is `.spectomat/`: the directories and files the factory works from.
- **Contract** is `.spectomat/contract.md`: the rules, the gates and the steps every iteration re-reads.
- **Memory** is `.spectomat/memory.md`: durable facts about the codebase — map, commands, patterns, traps — read by every iteration and every implementer, added to inside the phase commit. The contract is what the factory knows about the job, the memory what it knows about the project.
- **Verification Gate** is one command in the Verification Gates block of the contract that must exit 0 once per task in the `IMPLEMENT` phase and once in the `ARCHIVE` phase.
- **Dark factory** is a production line that runs *unattended*, lights off. Here: a flow that turns ideas into committed code without asking anyone.
