# User guide

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the drafts it finds, arms the Stop hook for `n` iterations (default 100) and starts iteration 1; refuses on a dirty tree |
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
.spectomat/
  drafts/     ideas, one .md each; the file name is the slug, worked in alphabetical order
  specs/      written by SPECIFY from each draft, then revised once by REVIEW-SPEC; or put a finished spec here yourself
  plans/      PLAN writes an overview per spec plus <slug>/task-NN-<name>.md per task, each a self-contained brief
  done/       spec + plan moved here by ARCHIVE once REVIEW has passed the plan and the gates are green
  log.md      one line per phase, gitignored
  contract.md the rules and gates, re-read every iteration
  memory.md   durable valuable facts about the codebase, accumulated all along the time
  state.json  the flow's state: iteration counter, cap, session — gitignored
  work/       per-task briefs, reports and diffs, gitignored
```

## The Flow

The flow is a sequence of iterations. Each one asks the picker for a verdict and dispatches on it — a fresh phase agent, the archiver, or the janitor — then commits, logs, and stops for the Stop hook to feed the next iteration in; `FINISH` is the exception, where the Stop hook itself ends the flow instead of dispatching anyone.

```text
Stop hook ──▶ feeds back the pointer prompt ──▶ picker (scripts/phase.sh) ──▶ one verdict per iteration
```

```text
drafts/*.md ──SPECIFY──▶ specs/*.md ──REVIEW-SPEC──▶ reviewed spec ──PLAN──▶ plans/<slug>.md
                                                                                   │
                                                                            IMPLEMENT×n (TDD, gates, one commit)
                                                                                   │
                                                                                   ▼
                                         done/ ◀──ARCHIVE── verdict ◀──REVIEW── finished plan
                                                                │
                                                                └──fix tasks──▶ back to IMPLEMENT (≤2 rounds)
```

`RECOVER` sends a dirty tree to the janitor instead of any of the above; `FINISH` fires once `drafts/`, `specs/` and `plans/` are all empty and the tree is clean, and the Stop hook ends the flow and prints what shipped. Nothing the session says can end a flow: the hook runs the picker itself.

Work in progress is finished before a new draft is read: `ARCHIVE` and `REVIEW` outrank `IMPLEMENT`, which outranks `PLAN`, which outranks `REVIEW-SPEC`, which outranks a fresh `SPECIFY`. Drafts are read in alphabetical order of the file name, so the name is how you fix the order they are worked in.

`contract.md` and `memory.md` are rendered from the plugin templates at the first run and committed. Next `run`s never overwrite them, so edit them in the project to change the rules, the gates or what the Flow believes about the codebase. Each is checked on its own, so a floor armed before `memory.md` existed gets it on the next `run`.

> It is dark! Nobody is asked anything. Every open choice becomes an `assumed` row in the spec's Decisions table. Three failed attempts at a phase move the file to `done/<slug>.blocked.md` with the reason.

## Operating it

- **Feed it.** Drop a `.md` idea into `.spectomat/drafts/`. `run` commits whatever it finds there. Drafts are worked in alphabetical order of the file name, so name them to get the order you want. A finished spec can go straight into `specs/`; the Flow then starts at reviewing it.
- **Steer it.** Edit a spec or a plan between iterations. Edit `contract.md` to change the rules, `memory.md` to correct what the Flow believes about the codebase.
- **Read what it learned.** `memory.md` is committed: the map, commands, patterns and traps every iteration reads before working and adds to before committing. Seed it by hand before the first run and the Flow starts informed; it keeps itself under ~40 lines and deletes what the code contradicts.
- **Gate it.** The gates run once per task in the `IMPLEMENT` phase, before its commit, and once in the `ARCHIVE` phase before archiving. `run` compiles the gate command from `package.json` scripts: a `gates` script, if present, is the single gate; otherwise every `typecheck`, `test`, `lint` and `build` script found, chained with `&&` in that order. The command is the first line of the block under Verification Gates in `contract.md`, rendered once at the first `run`; edit it there when `package.json` changes. Gates that are not npm scripts go into the same block, one command per line; every line must exit 0. An iteration may never weaken a gate to pass.
- **Resume it.** After a cancel or the iteration cap, run `/spectomat:run` again. The filesystem is the ledger, so nothing is re-planned.
- **Start clean.** `run` refuses to arm while anything outside the floor is uncommitted: the picker answers `RECOVER` to any dirt, so a flow armed over work in progress would send every iteration to the janitor. Commit or stash first.

## Glossary

- **Plugin** a Claude Code plugin made of commands, a hooks, skills, scripts, templates and reference files etc.
- **Command** is a slash command the user types: `/spectomat:run`, `/spectomat:status`, `/spectomat:cancel` or `/spectomat:help`. Each runs a script first, then tells Claude what to do with its output.
- **Session** is the Claude Code session where `/spectomat:run` was called. It holds the flow, launches one subagent per iteration and relays its report; it does no Flow work itself.
- **Iteration** is one picker verdict, one phase, one commit, one log line.
- **State file** is `.spectomat/state.json`: the iteration counter, the iteration cap and the session that armed the flow. Its existence is what "armed" means; `/spectomat:cancel` deletes it.
- **Pointer** is the prompt the Stop hook feeds back every iteration, telling the session to run the picker and dispatch on its verdict. Fixed text, generated by `pointer_prompt` in `scripts/utils.sh` — no file on disk.
- **Picker** is the script `scripts/phase.sh` that prints one verdict block per iteration: `phase` (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, or `FINISH`), `slug`, and the `subagent`/`brief`/`plugin_root` the pointer dispatches with. The `FINISH` verdict names no `subagent` and no `brief`, because it dispatches nothing.
- **Phase agent** is a fresh subagent per phase: `spectomat:specify|review-spec|plan|implement|review|archive`; each brief contains the craft of its phase (`agents/specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`, `archive.md`). A phase agent does its own work and never dispatches another agent — except `archive`, whose own work is invoking `scripts/archive.sh` and relaying its result, never repeating its mutation by hand.
- **Archiver** is `spectomat:archive` (`agents/archive.md`), a subagent that invokes the script `scripts/archive.sh` and relays its result unchanged. The script performs the `ARCHIVE` phase: verifies gates, moves the trail to `done/`, commits, and drops the slug from `state.json`. The agent does none of that mutation itself.
- **Janitor** is `spectomat:recover` (`agents/recover.md`): a subagent that recovers from a dirty tree by finishing or discarding a crashed phase's changes, or reconciles a floor the picker could not classify.
- **Verdict** is the picker's frontmatter block, naming `phase` (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, or `FINISH`), `slug`, and the `subagent`/`brief`/`plugin_root` fields derived from `phase` alone. (What releases a spec to `PLAN` or a plan to `ARCHIVE` is the slug's phase in `state.json`, written by the phase that finished; a `- Verdict:` line in a spec's §16 or a plan overview is a record of that decision, not the switch.) The `FINISH` verdict names no `subagent` and no `brief`, because it dispatches nothing.
- **Phase** is one of `SPECIFY` (draft → spec), `REVIEW-SPEC` (spec → reviewed spec), `PLAN` (reviewed spec → plan), `IMPLEMENT` (plan → next task), `REVIEW` (finished plan → verdict), `ARCHIVE` (reviewed plan → done). An iteration does exactly one. Verdicts are upper case; the agent types and brief files that serve them are lower case. The two remaining verdicts are not phases: `RECOVER` hands the floor to the janitor, `FINISH` ends the flow.
- **Task** is one independent piece of work in a plan, with its own file, its own test cycle and its own commit. The `IMPLEMENT` phase executes exactly one per iteration, in dependency order; the `REVIEW` phase may add more.
- **Flow** is the sequence of iterations from the first `/spectomat:run` until the picker answers `FINISH` and the Stop hook ends it, or until the iteration cap.
- **Strike** is one failed attempt at a phase for a slug, counted per phase in `state.json`. Three strikes move the file to `done/<slug>.blocked.md` with the reason and drop the slug from `state.json`, so the flow moves on.
- **Slug** is a draft's file name without `.md`. Spec, plan and done entries keep it.
- **Floor** is `.spectomat/`: the directories and files the Flow creates and works with in the user's project.
- **Contract** is `.spectomat/contract.md`: the rules, the gates and the steps every iteration re-reads.
- **Memory** is `.spectomat/memory.md`: durable facts about the codebase — map, commands, patterns, traps — read by every iteration, added to inside the phase commit. The contract is what the Flow knows about the job, the memory what it knows about the project.
- **Verification Gate** is one command in the Verification Gates block of the contract that must exit 0 once per task in the `IMPLEMENT` phase and once in the `ARCHIVE` phase.
- **code development flow** is a production line that runs *unattended*, lights off. Here: a flow that turns ideas into committed code without asking anyone.
