# spectomat

Spec-driven dark factory for Claude Code.

Drop ideas into a `wishlist` folder, call one `/spectomat:run` command, and an unattended loop turns each idea into a spec, each spec into a plan and tasks, and then executes all of them to produce well-tested, committed code.

```text
idea  ──A──▶  specs  ──B──▶  plans/tasks×n  ──C×n──▶  code + commits  ──D──▶  done
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

- `agents/` — `phase-a.md`, `phase-b.md`, `phase-c.md`, `recover.md`. The picker dispatches to one per loop: `spectomat:phase-a|b|c`, `spectomat:recover`, or `scripts/archive.sh`.

- `hooks/` — `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the flow alive.

- `scripts/` — bash, no other runtime:
  - `utils.sh` holds the shared paths and helpers the others source,
  - `run.sh` prepares `.spectomat/`, renders `contract.md` and `memory.md`, and writes the state file with the factory prompt and promise `FACTORY EMPTY`,
  - `phase.sh` is the picker: one verdict line per loop, dispatching to a phase brief, the archiver or the janitor,
  - `archive.sh` is phase D end to end: ticks, gates, moves the trail to `done/` and commits,
  - `status.sh` summarises flow and floor; its sections live in `print.sh`,
  - `cancel.sh` removes the state file and reports the loop it was at,
  - `gates.sh` compiles the gate command from `package.json` scripts; `run` renders it into the contract's Verification Gates block.

- `templates/`
  - `guide.md` (the user guide `/spectomat:help` prints),
  - `contract.md` (placeholders `{{REPO}}` and `{{GATES}}`),
  - `memory.md` (placeholder `{{REPO}}`; the codebase facts every loop reads and adds to, committed in the project),
  - `state.md` (the state file: frontmatter with `{{SESSION_ID}}`, `{{MAX_LOOPS}}`, `{{STARTED_AT}}`, then the pointer prompt the Stop hook feeds back, with `{{PLUGIN_ROOT}}` locating `agents/` briefs),
  - `spec.md` (the skeleton `writing-specs` points at),
  - `plan.md` (overview skeleton, placeholder `{{SLUG}}`)
  - `task.md` (per-task brief skeleton, placeholders `{{SLUG}}`, `{{N}}`); `writing-plans` points at the last two.
- `prompts/` — `implementer.md` and `reviewer.md`, the subagent briefs `executing-tasks` sends verbatim, placeholders in `<...>`.

## Developing

Exercise the scripts in a scratch git repo, never in this one: `run.sh` on an empty floor (expect refusal), drop a draft and run again (expect armed), then pipe a fake hook payload (`{"session_id","transcript_path"}`) into `scripts/stop-hook.sh` and check `decision`, the loop counter, and that the state file is removed on `<promise>FACTORY EMPTY</promise>` and at the cap. For a full run, `claude -p "/spectomat:run 25" --plugin-dir <this repo>` inside a scratch project with a draft on the floor.

## Licence

MIT, see `LICENSE`.

Third-party material and its licences are listed in `NOTICE.md`.
