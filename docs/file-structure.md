# Spectomat plugin file structure index

- `.claude-plugin/` 
  - `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
  - `plugin.json` (the plugin attribution) 

- `commands/` 
  - `run.md`, `status.md`, `cancel.md`, `help.md`. 

- `agents/` 
  -  `specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`, `archive.md`, `recover.md`.

- `hooks/` 
  - `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the flow iterations going.

- `scripts/` 
  - `utils.sh` holds the shared paths and helpers the others source,
  - `prepare.sh` sets up the floor `.spectomat/`, renders `contract.md` and `memory.md`, and arms the flow by writing `state.json`,
  - `phase.sh` is the picker: one verdict block per iteration, naming the phase and the subagent/brief to dispatch it to,
  - `archive.sh` is the `ARCHIVE` phase end to end: ticks, gates, moves the trail to `done/` and commits,
  - `status.sh` summarises flow and floor; its sections live in `print.sh`,
  - `cancel.sh` disarms the flow and reports the iteration it was at,
  - `gates.sh` compiles the gate command from `package.json` scripts; `run` renders it into the contract's Verification Gates block.

- `docs/`
  - `specification.md` (the normative specification),
  - `guide.md` (the user guide `/spectomat:help` prints).

- `templates/`
  - `contract.md` (the flow-level contract),
  - `memory.md` (the codebase facts every iteration reads and adds to, committed in the project),
  - `state.json` (the flow's state),
  - `spec.md` (the skeleton for `spec` document),
  - `plan.md` (the skeletonfor `plan` document)
  - `task.md` (the per-task brief skeleton)