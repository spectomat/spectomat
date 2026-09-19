# Spectomat plugin file structure index

What lives where in the plugin, and how the pieces dispatch. This is §6.1 of [the specification](../docs/specification.md):

> a `§` number names a section there, and a `D<n>` id names a row of [the design decisions](./decisions.md).

## The files

- `.claude-plugin/`
  - `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
  - `plugin.json` (the plugin attribution)

- `commands/`
  - `run.md`, `status.md`, `cancel.md`, `help.md` — the four slash commands; each runs its script in a `!` block, then tells Claude what to do with the output (§7.1).

- `agents/`
  - one brief per verdict the picker can emit, each serving the agent type `spectomat:<file name>`:
    - `specify.md` — draft → spec,
    - `review-spec.md` — spec → reviewed spec,
    - `plan.md` — reviewed spec → plan,
    - `implement.md` — plan → next task: dispatches, verifies and closes,
    - `review.md` — finished plan → verdict or fix tasks,
    - `archive.md` — invokes `agent-archive.sh` and relays its result unchanged (D21),
    - `recover.md` — the janitor,
  - `task.md` — the task agent: one task, built from its task file alone; dispatched by `implement.md` once per task, never by the picker (D30).

- `hooks/`
  - `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the flow iterations going.

- `scripts/`
  - `utils.sh` holds the shared paths and helpers every other script sources: `least_struck`, `strike_count`, `run_gates` (§5.2–§5.4), `cd_root`, `state_field`, `render_template`, `pointer_prompt`,
  - `command-run.sh` sets up the floor `.spectomat/`, renders `contract.md`, `memory.md` and `gates.sh`, moves each draft into its own slug dir, and arms the flow by writing `state.json`,
  - `phase.sh` is the picker (§5.1): one verdict block per iteration, naming the phase and the subagent/brief to dispatch it to,
  - `agent-archive.sh` is the archiver (§5.6), the `ARCHIVE` phase end to end: ticks, gates, writes the slug's `done.md` (or `blocked.md`), commits, and records the terminal phase in `state.json`,
  - `command-status.sh` summarises flow and floor (§7); its sections live in `print.sh`,
  - `command-cancel.sh` disarms the flow and reports the iteration it was at,
  - `command-help.sh` prints `docs/guide.md` and `references/glossary.md` verbatim,
  - `gates.sh` compiles the gate lines from `package.json` scripts (§5.5), and run directly previews what a repo would get; `run` renders them into the project's own `.spectomat/gates.sh`, which is what every phase runs,
  - `stop-hook.sh` runs the picker each time the session stops: ends the flow on `FINISH` and composes the closing report, otherwise blocks the exit, bumps the iteration counter and feeds back the pointer prompt (§3.5),
  - `tasks.sh` is the only writer of a slug's task ledger, `tasks.json` (§6.4, D31): `write`/`start`/`init`/`next`/`dispatch`/`show`/`count`/`close`/`add`; the phase move rides inside `close` and `add`,
  - `slug_set_phase.sh` and `block_slug.sh` are thin CLIs over the slug helpers in `utils.sh`: advance a slug that carries no tasks, or take one out of the flow at `BLOCKED` (§3.4),
  - `log.sh` formats and appends every `log.md` line — the one place that format lives (D28),
  - `selftest.sh` runs every `tests/*_test.sh` file and reports the combined tally,
  - `verify_all.sh` runs every check a change must pass — manifests, syntax, the suite, doc links, whitespace — in parallel.

- `tests/`
  - `*_test.sh` — the suite (§10.7), one section each, independently runnable,
  - `lib.sh` — the shared fixture harness.

- `.github/workflows/`
  - `ci.yml` runs `scripts/verify_all.sh` on `ubuntu-latest` and `macos-latest` — two bash generations (§10.8).

- `assets/`
  - `logo.svg`, `social.svg` and the PNGs rendered from them.

- `docs/`
  - `specification.md` (the normative specification: overview, boundaries, operator surface, and a pointer to every section kept under `references/`),
  - `guide.md` (the user guide `/spectomat:help` prints).

- `references/`
  - `brainstorm.md` (the `REVIEW-SPEC` phase's brainstorming procedure, cited, not inlined, by `agents/review-spec.md` for when the spec and the draft are both silent),
  - `gates.md` (how the task agent reads the gates log and debugs a red gate, cited by `agents/task.md` — the one plugin file the worker reads, which is why its task carries `plugin_root` as the fifth line),
  - `memorize.md` (the memory-writing procedure `IMPLEMENT` and `REVIEW-SPEC` each follow inline before their own commit),
  - `file-structure.md` (this file),
  - `domain-model.md` (the domain model, §2: the verdict, the strike ledger, the gates),
  - `behaviour.md` (the behaviour, §3: the iteration, dispatch, the failure path, completion),
  - `algorithms.md` (the normative algorithms, §5: the named constants, the picker, strikes, gates and the archiver in pseudocode),
  - `architecture.md` (the architecture, §6: the contract, the briefs, the state and the pointer),
  - `decisions.md` (the design decisions, §8: what was decided, what was rejected, and why),
  - `testing.md` (acceptance criteria, fixtures, the gates and the suite, §9–§10),
  - `assets.md` (how the logo and the social card are drawn, rendered and published),
  - `floor.md` (the floor layout, rendered into the project's `contract.md`),
  - `three-strikes.md` (the strike and blocked-slug procedure every phase follows when it is defeated),
  - `log-format.md` (the `log.md` message shape every writer of a log line follows),
  - `glossary.md` (the terms this repo uses consistently, printed by `/spectomat:help` alongside `guide.md`).

- `templates/`
  - rendered into the project once, each checked on its own so an older floor picks up a newly added file, then owned by the project:
    - `contract.md` (the flow-level contract),
    - `memory.md` (the codebase facts every iteration reads and adds to, committed in the project),
    - `gates.sh` (the project's single gate command),
  - the shapes the `SPECIFY`, `REVIEW-SPEC` and `PLAN` phases fill in:
    - `spec.md` (the skeleton for the `spec` document),
    - `plan.md` (the skeleton for the `plan` document),
    - `task.md` (the per-task brief skeleton).
