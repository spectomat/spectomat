# User guide

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, takes in the wishlist, commits, arms the Stop hook for `n` loops (default 100) and starts loop 1 |
| `/spectomat:status` | shows the current loop, floor counts, per-plan step progress, blocked files and the log tail |
| `/spectomat:cancel` | removes the state file; the floor stays, `run` resumes from it |
| `/spectomat:help` | shows this guide |

## The Floor

```text
docs/.spectomat/
  drafts/     ideas, one .md each, named NNN-<name>.md; the file name is the slug
  .inc        the last NNN issued; committed with the drafts
  specs/      written by phase A from each draft; or put a finished spec here yourself
  plans/      phase B writes an overview per spec plus <slug>/task-NN-<name>.md per task, each a self-contained brief
  done/       spec + plan moved here by phase D after every step is ticked and gates pass
  log.md      one line per phase, gitignored
  contract.md the rules and gates, re-read every loop
  state.md    the Stop hook's state, gitignored
  work/       per-task briefs, reports and diffs, gitignored
```

## The Flow

The flow is a sequence of loops. Each loop is one fresh `general-purpose` subagent that reads `contract.md` and does exactly one phase, the first that applies:

- **D** finished plan → `done/`, when every task step is ticked and the gates are green; the patch version in `package.json` becomes the slug's `NNN`,
- **C×n** plan → next wave of ready tasks: one fresh implementer per task in parallel, TDD, one commit and one reviewed diff per task,
- **B** spec → plan: an overview plus one task file per task,
- **A** draft → spec,
- **E** nothing left: `drafts/`, `specs/` and `plans/` are empty and the tree is clean, so the loop emits `<promise>FACTORY EMPTY</promise>` and the flow ends.

Work in progress is finished before a new draft is read. Drafts are read in intake order, because the `NNN` prefix makes alphabetical order equal intake order.

## Loops Mechanics

The Stop hook runs when Claude tries to end its turn.

While `state.md` exists for this session, the hook blocks the exit and returns the state prompt as the next input.

The state launches the next loop's subagent, so every phase starts with an empty context and the session itself only accumulates one short report per loop.

The hook removes the state file, and so releases the session, on the promise, on the loop cap, or on a corrupt state file.

`contract.md` is rendered from the plugin template at the first run and committed. Next `run`s never overwrites it, so edit it in the project to change the rules or the gates.

> It is dark! Nobody is asked anything. Every open choice becomes an `assumed` row in the spec's Decisions table. Three failed attempts at a phase move the file to `done/<slug>.blocked.md` with the reason.

## Operating it

- **Feed it.** Drop a `.md` idea into `wishlist/` at the project root. `run` moves it into `drafts/` as `NNN-<name>.md`, oldest modification first, and commits it. The counter in `.inc` keeps numbers growing across runs. A finished spec can go straight into `specs/`; the factory then starts at planning.
- **Steer it.** Edit a spec or a plan between loops. Edit `contract.md` to change the rules.
- **Gate it.** Every commit in phases C and D must pass the gates. `run` compiles the gate command from `package.json` scripts: a `gates` script, if present, is the single gate; otherwise every `typecheck`, `test`, `lint` and `build` script found, chained with `&&` in that order. The command is the first line of the block under Verification Gates in `contract.md`, rendered once at the first `run`; edit it there when `package.json` changes. Gates that are not npm scripts go into the same block, one command per line; every line must exit 0. A loop may never weaken a gate to pass.
- **Resume it.** After a cancel or the loop cap, run `/spectomat:run` again. The filesystem is the ledger, so nothing is re-planned.

## Glossary

- **Plugin** a Claude Code plugin made of commands, a hooks, skills, scripts, templates and reference files etc.
- **Command** is a slash command the user types: `/spectomat:run`, `/spectomat:status`, `/spectomat:cancel` or `/spectomat:help`. Each runs a script first, then tells Claude what to do with its output.
- **Session** is the Claude Code session where `/spectomat:run` was called. It holds the flow, launches one subagent per loop and relays its report; it does no factory work itself.
- **Loop** is one turn of the flow between two `Stop`-hook responses: one fresh subagent, one phase, one commit, one log line.
- **Phase** is one of `A` (draft → spec), `B` (spec → plan), `C` (plan → wave of tasks), `D` (plan → done). A loop does exactly one.
- **Wave** is the set of ready tasks of one plan whose files do not overlap, implemented in parallel within one phase `C` loop.
- **Flow** is the sequence of loops from the first `/spectomat:run` until the promise `FACTORY EMPTY`.
- **Strike** is one failed attempt at a phase for a slug. Three strikes move the file to `done/<slug>.blocked.md` with the reason.
- **Slug** is a draft's file name without `.md`, including its `NNN-` prefix. Spec, plan and done entries keep it.
- **Floor** is `docs/.spectomat/`: the directories and files the factory works from.
- **Contract** is `docs/.spectomat/contract.md`: the rules, the gates and the steps every loop re-reads.
- **Verification Gate** is one command in the Verification Gates block of the contract that must exit 0 before every commit in phases `C` and `D`. A loop may never weaken a gate to pass.
- **Dark factory** is a production line that runs *unattended*, lights off. Here: a flow that turns ideas into committed code without asking anyone.
