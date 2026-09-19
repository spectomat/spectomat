# Architecture

§6 of [the specification](../docs/specification.md), numbered as it is cited. A `§` number names a section of the specification; a `D<n>` id names a row of [the design decisions](./decisions.md).

## 6. Architecture

### 6.1 Component map

Every file of the plugin and its role is in [`references/file-structure.md`](./file-structure.md). The agent file names there are normative: `agents/<phase lowercased>.md` must exist for every verdict that dispatches (§3.3).

### 6.2 The contract

`.spectomat/contract.md` is rendered from the template at the first `/spectomat:run` and never overwritten, so it is **the operator's only steering surface**. It holds the invariants that outlive the briefs: the floor, the Iteration Contract, when to gate and the path of the gate script, and how to read and write `memory.md`. Three strikes and the log format are named here but not spelled out: both are one copy under `references/`, cited by the contract and by every brief that needs them, so the procedure cannot drift between the briefs that follow it (the same reasoning as D28). Its Constitution carries the rules binding every phase, grouped by what they govern: judgement, what may be written, honest reporting, ending a phase, and where work happens.

**Where a rule lives.** A rule that binds every phase belongs in the Constitution and nowhere else, under one of those five groups; a brief's Rules list holds only what is true of that one phase. A rule that would read the same in two briefs is a contract rule — it is moved, and the copies deleted. A change to what a phase does belongs in its brief, not in the contract or the pointer; a change to the verdict grammar must keep `phase.sh`, `pointer_prompt` in `utils.sh`, `print.sh` and `agent-archive.sh` in step.

**A phase agent is confined to the project under flow.** It must never `git stash`, commit or checkout in another repository — the plugin's own checkout included — and must never ask its caller to run a command a permission check denied it. Both were observed in one live run: an `ARCHIVE` agent stashed the operator's uncommitted template edits in the plugin checkout to get past `agent-archive.sh`'s dirty-tree guard, then asked the caller to run the blocked script. The two rules live under *Where you work* and *Honest reporting*.

It holds no phase sections (D3) and no craft prose (D11): text no operator would ever edit is not steering, and belongs in the brief that uses it. What earns a line in `memory.md` lives in that file's own header, not here (D10).

### 6.3 The briefs

Each brief holds the craft of one phase and is read only on that phase's iterations. A brief carries no `{{KEY}}` placeholder — it is never rendered — and no plugin path: its task's `plugin_root:` field supplies one at dispatch (§3.3).

`agents/task.md` is the largest brief by a wide margin, carrying task execution, TDD and systematic debugging, and it is the one brief that reads no contract: it restates the few Constitution rules that bind a worker, because the worker's context holds only the task file and the code. That is the point of the design and not a smell: the `SPECIFY` phase pays nothing for it, and `agents/implement.md` is left with orchestration alone — pick, dispatch, verify, record, advance.

`IMPLEMENT` is the one brief that dispatches another agent (D30), and the only text it sends is five lines — slug, task number, task path, gates-log path, plugin root — never a brief verbatim. The task file is the worker's whole brief, which is why the `PLAN` and `REVIEW` phases inline the spec into its `## Context` instead of citing it. Every other phase does its own work: `REVIEW-SPEC` revises the spec itself and `REVIEW` reads the plan itself, so a brief is only ever read as guidance by the one agent it names.

### 6.4 The state and the pointer

The flow's state lives in two files. The gitignored `state.json` holds the flow level — which slugs exist, which phase each is at, finished ones included, and how many times each phase has failed — and its `active` flag is what "armed" means. Each planned slug's `tasks.json` holds its tasks (D31): the list, each task's `dependsOn` and `status`, and the `commits`, `tests` and `gates` it closed with. It is committed, so a task's evidence survives in git where `state.json` cannot follow, and `scripts/tasks.sh` is its only writer. The pointer prompt fed back each iteration is not a file — `pointer_prompt()` in `scripts/utils.sh` generates it fresh from a fixed heredoc every time it is called, substituting `PLUGIN_ROOT` (already a shell variable in every script that sources `utils.sh`) the same way `render_template` substitutes a template's `{{KEY}}` placeholders (D12).

| File | Schema | Read by | Written by |
| --- | --- | --- | --- |
| `state.json` | `{active: bool, iteration: int, max_iterations: int, session_id: string, started_at: timestamp, plugin_root: path, current: {phase: string, slug: string}, slugs: {<slug>: {phase: string, strikes: {<phase>: int}, reason: string, finished_at: timestamp}}}` | `phase.sh`, `print.sh`, `stop-hook.sh`, phase agents (via `state_field` and slug helpers) | `command-run.sh` at seeding and arming; every phase brief and `agent-archive.sh` after their commit; `stop-hook.sh` bumps `iteration` and records `current`; `/spectomat:cancel` sets `active: false` |
| `<slug>/tasks.json` | `{slug: string, tasks: [{id: int, name: string, file: path, component: string, covers: [string], dependsOn: [int], status: "pending"\|"done", commits: string, tests: string, gates: string}]}` | `print.sh`, the `IMPLEMENT` and `REVIEW` phases (via `scripts/tasks.sh`) | `PLAN` writes it, `IMPLEMENT` closes each task, `REVIEW` appends fix tasks — all through `scripts/tasks.sh`, never by hand |

| Field | Holds |
| --- | --- |
| `slugs[<slug>].phase` | one of the six working phases, or the terminal `DONE` or `BLOCKED` (§2.1) |
| `tasks[].status` | `pending` until the `IMPLEMENT` phase closes the task, `done` after; nothing else. Set by `tasks.sh` alone — a caller's own value is discarded, so a plan cannot arm itself closed |
| `tasks[].dependsOn` | the ids of every task under this one's `From previous tasks`; only lower ids. `tasks.sh next` picks the lowest-id pending task whose every dependency is `done`, and prints nothing on a cycle |
| `tasks[].commits` | the `<base7>..<head7>` range of that task's one `feat` commit, recorded at close. The `REVIEW` phase reconstructs the plan's whole diff from the first task's base to the last task's head |
| `slugs[<slug>].reason` | why the slug finished — the gate that failed, or `gates passed`; written by `slug_done` or `block_slug.sh`, absent while the slug is working |
| `slugs[<slug>].finished_at` | when it finished, UTC; written by `slug_done` or `block_slug.sh` alongside `reason` |
| `plugin_root` | the plugin copy that armed the flow, written once at arming |
| `current` | the phase and slug of the last working verdict the picker handed out: written by `arm_flow` for the first iteration and by the Stop hook, in the same write that bumps `iteration`, for every later one. A `RECOVER` or `FINISH` verdict leaves it as it was, so after a dirty death it names the iteration that died, and the picker hands that slug to `RECOVER` (D33) |

`plugin_root` is authoritative for the floor, not for the scripts. A floor-side reader — the operator, `/spectomat:status`, the janitor — has no other way to name which plugin copy armed this flow, and `print_iteration` prints it as a `plugin:` line. No script reads it to locate anything: each derives `PLUGIN_ROOT` from its own `BASH_SOURCE`, and a phase agent resolves `<plugin_root>` from the picker's verdict block, as `templates/contract.md` directs.

A finished slug keeps its entry, its task counters and its strikes. Nothing is deleted, so `/spectomat:status` can still report what a shipped or blocked slug ended with, and re-arming over that state neither resurrects it nor counts it as active.

**The resume path:** When `/spectomat:run` is invoked with an inactive flow (`state.json` exists and `active: false`), `command-run.sh` re-arms by setting `active: true` instead of refusing. This restores the flow from where it stopped, continuing from the same `iteration` counter, with all slug phases and strike counts preserved in `state.json.slugs`. There is no second file to re-render on resume — `pointer_prompt()` produces the same text on the first call and the hundredth.

**Disarming:** `disarm()` is called only at FINISH (all work done), at the iteration cap, or on corrupt state. It removes `state.json`; there is nothing else on disk for it to clean up. `/spectomat:cancel` is different: it only sets `active: false`, leaving `state.json` intact so `/spectomat:run` can resume.

Generating the prompt instead of rendering it to disk keeps it honest: `state.json` is data a script parses, the pointer is a prompt a model reads, and there is no file that can go stale — a plugin reinstalled at a new cache path can never leave a pointer holding the old one — or outlive the state it belongs to (D12).

Drafts arrive in `.wishlist/` already named: the plugin issues no numbers and renames nothing (D13). Arming moves each into its own `<slug>/draft.md` and empties `.wishlist/` (D26, D32). The picker reads slugs in plain alphabetical order of that name, which is the operator's only lever on the order they are worked.
