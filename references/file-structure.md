# Spectomat plugin file structure index

- `.claude-plugin/`
  - `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
  - `plugin.json` (the plugin attribution)

- `commands/`
  - `run.md`, `status.md`, `cancel.md`, `help.md`.

- `agents/`
  - `specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`, `archive.md`, `recover.md` — one per verdict the picker can emit,
  - `task.md` — the task agent, dispatched by `implement.md` once per task, never by the picker.

- `hooks/`
  - `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the flow iterations going.

- `scripts/`
  - `utils.sh` holds the shared paths and helpers the others source,
  - `command-run.sh` sets up the floor `.spectomat/`, renders `contract.md`, `memory.md` and `gates.sh`, moves each draft into its own slug dir, and arms the flow by writing `state.json`,
  - `phase.sh` is the picker: one verdict block per iteration, naming the phase and the subagent/brief to dispatch it to,
  - `agent-archive.sh` is the `ARCHIVE` phase end to end: ticks, gates, writes the slug's `done.md` (or `blocked.md`), commits, and records the terminal phase in `state.json`,
  - `command-status.sh` summarises flow and floor; its sections live in `print.sh`,
  - `command-cancel.sh` disarms the flow and reports the iteration it was at,
  - `command-help.sh` prints `docs/guide.md` and `references/glossary.md` verbatim,
  - `gates.sh` compiles the gate lines from `package.json` scripts; `run` renders them into the project's own `.spectomat/gates.sh`, which is what every phase runs.

- `docs/`
  - `specification.md` (the normative specification),
  - `guide.md` (the user guide `/spectomat:help` prints).

- `references/`
  - `brainstorm.md` (the `REVIEW-SPEC` phase's brainstorming procedure),
  - `gates.md` (how the task agent reads the gates log and debugs a red gate),
  - `memorize.md` (the memory-writing procedure `IMPLEMENT` and `REVIEW-SPEC` each follow inline before their own commit),
  - `file-structure.md` (this file),
  - `floor.md` (the floor layout, rendered into the project's `contract.md`),
  - `three-strikes.md` (the strike and blocked-slug procedure every phase follows when it is defeated),
  - `log-format.md` (the `log.md` message shape every writer of a log line follows),
  - `glossary.md` (the terms this repo uses consistently, printed by `/spectomat:help` alongside `guide.md`).

- `templates/`
  - `contract.md` (the flow-level contract),
  - `memory.md` (the codebase facts every iteration reads and adds to, committed in the project),
  - `gates.sh` (the project's single gate command, rendered once),
  - `spec.md` (the skeleton for `spec` document),
  - `plan.md` (the skeletonfor `plan` document)
  - `task.md` (the per-task brief skeleton)
