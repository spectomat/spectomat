# spectomat

Spec-driven dark factory for Claude Code.

Drop ideas into `.spectomat/drafts/`, call one `/spectomat:run` command, and an unattended flow turns each idea into a spec, each spec into a plan and tasks, and then executes all of them to produce well-tested, committed code.

```text
idea  ──SPECIFY──▶  specs  ──REVIEW-SPEC──▶  reviewed specs  ──PLAN──▶  plans/tasks×n  ──IMPLEMENT×n──▶  code + commits  ──REVIEW──▶  verdict  ──ARCHIVE──▶  done
```

Commands, the floor, the flow and the skills are in `templates/guide.md` with a glossary, shown by `/spectomat:help`.

## Requires

- `jq` on PATH.

## Workflow

Install

```bash
claude plugin marketplace add ~/Projects/spectomat
claude plugin install spectomat@spectomat
```

Update

```bash
claude plugin update spectomat@spectomat
```

Restart Claude Code to apply an install or update: the plugin runs from a cache copy, so a live session keeps the old one.

Verify

```bash
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

## File Layout

A Claude Code plugin, not an application. No dependencies, no build.

- `.claude-plugin/` — `plugin.json` (the plugin) and `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
- `commands/` — `/spectomat:run`, `status`, `cancel`, `help`. Each `!` block runs a script before Claude reads the command.

- `agents/` — `specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`, `recover.md`. The picker dispatches to one per iteration: `spectomat:specify|review-spec|plan|implement|review`, `spectomat:recover`, or `scripts/archive.sh`.

- `hooks/` — `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the flow alive.

- `scripts/` — bash, no other runtime:
  - `utils.sh` holds the shared paths and helpers the others source,
  - `run.sh` prepares `.spectomat/`, renders `contract.md` and `memory.md`, and arms the flow by writing `state.json` and `pointer.md`,
  - `phase.sh` is the picker: one verdict line per iteration, dispatching to a phase brief, the archiver or the janitor,
  - `archive.sh` is the `ARCHIVE` phase end to end: ticks, gates, moves the trail to `done/` and commits,
  - `status.sh` summarises flow and floor; its sections live in `print.sh`,
  - `cancel.sh` disarms the flow and reports the iteration it was at,
  - `gates.sh` compiles the gate command from `package.json` scripts; `run` renders it into the contract's Verification Gates block.

- `templates/`
  - `guide.md` (the user guide `/spectomat:help` prints),
  - `contract.md` (placeholders `{{REPO}}` and `{{GATES}}`),
  - `memory.md` (placeholder `{{REPO}}`; the codebase facts every iteration reads and adds to, committed in the project),
  - `state.json` (the flow's state: `{{SESSION_ID}}`, `{{MAX_ITERATIONS}}`, `{{STARTED_AT}}`) and `pointer.md` (the prompt the Stop hook feeds back, with `{{PLUGIN_ROOT}}` locating `agents/` briefs),
  - `spec.md` (the skeleton `writing-specs` points at),
  - `plan.md` (overview skeleton, placeholder `{{SLUG}}`)
  - `task.md` (per-task brief skeleton, placeholders `{{SLUG}}`, `{{N}}`); `writing-plans` points at the last two.

## Developing

`scripts/selftest.sh` covers the helpers, the picker, the archiver, `run.sh` and the Stop hook, all against real throwaway git repos. For the live runtime, `claude -p "/spectomat:run 25" --plugin-dir <this repo>` inside a scratch project with a draft on the floor.

## Licence

MIT, see `LICENSE`.

Third-party material and its licences are listed in `NOTICE.md`.
