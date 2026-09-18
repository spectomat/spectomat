# Spectomat

A Claude Code plugin that turns raw ideas into committed, tested code without anyone watching. The operator drops a Markdown draft into `.wishlist/` and runs `/spectomat:run`; a Stop hook then generates and feeds the session the same pointer prompt over and over, and each pass — an **iteration** — advances exactly one idea by exactly one phase.

The organising idea: **a deterministic picker decides *what* happens, a specialist brief decides *how*, and the project-owned contract holds only the invariants that outlive both.**

Six phases carry an idea end to end: **`SPECIFY`** draft → spec, **`REVIEW-SPEC`** spec → reviewed spec, **`PLAN`** reviewed spec → plan, **`IMPLEMENT`** plan → one task's code, **`REVIEW`** finished plan → a verdict or fix tasks, **`ARCHIVE`** reviewed plan → archive. Every phase, plus `RECOVER`, is a subagent with its own brief, dispatched the same way by the pointer (D2); `FINISH` is the exception — the Stop hook ends the flow itself, dispatching nobody (D24). `ARCHIVE`'s brief does no archiving itself — it only invokes `scripts/agent-archive.sh` and relays its exit code, because a script that exits non-zero on a failing gate is still stronger evidence than an agent claiming the gate passed.

## 1. System Overview

### 1.1 Actors

| Actor | Is | Does |
| --- | --- | --- |
| Operator | the human | drops drafts in `.wishlist/`, runs `/spectomat:run`, reads `/spectomat:status`, edits `contract.md` and `memory.md` |
| Session | the Claude Code session that ran `/spectomat:run` | holds the flow; per iteration, runs the picker and dispatches exactly one subagent; does no factory work |
| Picker | `scripts/phase.sh` | reads `state.json` and `git status`, and nothing else; prints one frontmatter block naming the phase and everything needed to dispatch it |
| Phase agent | `spectomat:specify`, `review-spec`, `plan`, `implement`, `review` | one fresh subagent per iteration; performs one phase and commits it |
| Task agent | `spectomat:task` | one fresh subagent per task, dispatched by the `IMPLEMENT` phase agent; builds, gates and commits that task from its task file alone; touches no floor state (D30) |
| Archiver | `spectomat:archive`, wrapping `scripts/agent-archive.sh` | the brief invokes the script and relays its result unchanged; the script performs the `ARCHIVE` phase: gates, moves, commit, log |
| Janitor | `spectomat:recover` | recovers a dirty tree, or a floor the picker cannot classify |

### 1.2 The system in one picture

```text
Stop hook
  └─ session receives the pointer prompt, generated fresh and fed back by the Stop hook
       │
       └─ bash {{PLUGIN_ROOT}}/scripts/phase.sh   →  exactly one frontmatter block:
          │                                            phase, slug, subagent, brief, plugin_root
          ├─ phase:SPECIFY        →  Agent(spectomat:specify)     draft → spec
          ├─ phase:REVIEW-SPEC    →  Agent(spectomat:review-spec) spec → reviewed spec
          ├─ phase:PLAN           →  Agent(spectomat:plan)        reviewed spec → plan
          ├─ phase:IMPLEMENT      →  Agent(spectomat:implement)   plan → next task
          │                            └─ Agent(spectomat:task)    one task, built from its task file alone
          ├─ phase:REVIEW         →  Agent(spectomat:review)      finished plan → verdict
          ├─ phase:ARCHIVE        →  Agent(spectomat:archive)      bash scripts/agent-archive.sh <slug>, relayed
          ├─ phase:RECOVER        →  Agent(spectomat:recover)
          └─ phase:FINISH         →  dispatches nothing; the Stop hook ends the flow and reports
```

Every arrow's target — the `subagent` and `brief` field — is computed by `phase.sh` itself, not looked up by the pointer: the agent name is the phase lowercased (`REVIEW-SPEC` → `review-spec`), so the block is the one place that mapping lives.

## 2. Domain Model

The floor is `.spectomat/`, entered from `.wishlist/` beside it: one directory `<slug>/` per idea holding that idea's whole trail, `work/`, plus `log.md`, `contract.md`, `memory.md`, `gates.sh` and `state.json`. Membership in the flow is a `state.json` field and nothing else: a slug is finished when its `.slugs[<slug>].phase` is `DONE` or `BLOCKED`, and the `done.md` or `blocked.md` its dir carries is the committed human record, written and committed by `agent-archive.sh` but read by nothing (D27). The contract's *The floor* section defines it and is not restated here. Three further entities are the system's own.

### 2.1 `verdict`

The picker's entire output: a single YAML-frontmatter-shaped block (`---` … `---`) on stdout, exit code 0.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | `SPECIFY`\|`REVIEW-SPEC`\|`PLAN`\|`IMPLEMENT`\|`REVIEW`\|`ARCHIVE`\|`FINISH`\|`RECOVER` | which phase applies, or `FINISH` for none, or `RECOVER` for a dirty tree |
| `slug` | string, empty for `FINISH` and `RECOVER` | the draft file name without `.md`, as the operator named it |
| `subagent` | string, e.g. `spectomat:review-spec` | the `subagent_type` to pass the Agent tool — `spectomat:` plus `phase` lowercased |
| `brief` | absolute path | the brief file to hand that subagent, `{{PLUGIN_ROOT}}/agents/<phase lowercased>.md` |
| `plugin_root` | absolute path | the plugin root, so a brief can still reach `templates/` and other plugin files with no plugin path of its own |

Identity: there is exactly one verdict per iteration, and it is not stored — the picker is re-run, never remembered. Written by: `scripts/phase.sh` only. `subagent`, `brief` and `plugin_root` are derived fields, not independent state — all three follow from `phase` and `PLUGIN_ROOT`, so the pointer needs no lookup table of its own (§3.3).

**Two vocabularies, six shared values.** `state.json`'s `.slugs[<slug>].phase` holds the six working phases (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`) plus the two terminal phases `DONE` and `BLOCKED`. The verdict's `phase` field holds the same six working phases plus `RECOVER` and `FINISH`. The sets overlap on six values and are not the same set: `DONE` and `BLOCKED` are never emitted as a verdict, never lowercased into an agent name, and have no row in the dispatch table; `RECOVER` and `FINISH` are never stored as a slug's phase.

### 2.2 `strike ledger`

A `state.json` field: `.slugs[SLUG].strikes[PHASE]`, holding the strike count for a `(phase, slug)` pair.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | phase name | the phase that was defeated |
| `slug` | string | the slug it was defeated on |
| `count` | integer 0..`STRIKE_LIMIT` | how many times |

Identity: `(phase, slug)`. Written by: any phase agent, and `agent-archive.sh`, by calling `slug_strike` (§5.2). Read by: the picker (§5.2) and `agent-archive.sh` (§5.6).

### 2.3 `gates`

`.spectomat/gates.sh`: one executable script holding every check this project must pass. It is run, never parsed, so only its interface is normative.

| Field | Type | Meaning |
| --- | --- | --- |
| path | `.spectomat/gates.sh` | fixed; the contract names it and no phase may substitute another command |
| exit code | integer | 0 means every gate passed; anything else is a failure |

Identity: one per floor. Written by: `command-run.sh` at first render, from `package.json` (§5.5), and the operator by hand thereafter — never rewritten by the factory (D9). Read by: nobody; run by the `IMPLEMENT` agent and `agent-archive.sh` through `run_gates` (§5.4).

## 3. Behaviour

### 3.1 Trigger and input

Trigger: the Stop hook blocks a session exit and feeds back the pointer prompt. Input: the floor as the previous iteration left it. Idempotency: the picker is a pure function of `state.json` and `git status` — it reads no floor file at all (D27) — so running it twice with no intervening change yields the same verdict.

### 3.2 The iteration

1. The session runs `bash {{PLUGIN_ROOT}}/scripts/phase.sh` and reads one frontmatter block.
2. It dispatches per §3.3.
3. It prints at most five lines of the report and stops, which fires the Stop hook again.

The session reads no contract, no floor file and no source. Its context accumulates one short report per iteration.

### 3.3 Dispatch

The pointer has no lookup table: every field it needs is in the block. It launches exactly one subagent — `run_in_background: false`, `subagent_type` set to the block's `subagent` field, and the body of the file named by `brief` (after that file's own frontmatter) as the task's brief — for every `phase` from `SPECIFY` through `RECOVER`. `FINISH` is the exception: its block names no `subagent` and no `brief`, because the Stop hook ends the flow on that verdict before the pointer ever sees it (§3.5). A pointer that does see a `FINISH` block — from `/spectomat:status`, or a janitor running the picker by hand — dispatches nothing.

The task handed to the subagent is the picker's frontmatter block, verbatim, fences included — the pointer neither reformats it nor extracts fields from it. A brief therefore carries no plugin path of its own but can still reach `templates/` by reading `plugin_root:` out of its own task.

`subagent` and `brief` are not a rule the pointer applies — they are fields `phase.sh` already computed, one rule stated once, in the script: the phase lowercased is the agent name, so `REVIEW-SPEC` names `spectomat:review-spec` and `agents/review-spec.md`; §6.1 fixes the file names so the mapping holds for every phase.

`IMPLEMENT` is the one phase that dispatches a second agent: `spectomat:task`, once per iteration, with a three-line task (slug, task file path, gates log path) and never a brief verbatim (D30). `task` is not a phase and not a verdict: `phase.sh` never emits it, it has no row in the dispatch table, and it writes nothing to `state.json` or `log.md` — the phase agent that dispatched it verifies its commit against git and the gates log, records the result and advances the slug.

### 3.4 Failure path

A phase agent that cannot finish appends `(strike N)` to its log line and stops; the next iteration's picker skips that slug in favour of the next candidate in the same stage (§5.2). On its own third strike the agent writes `<slug>/blocked.md` with the reason, calls `slug_finish <slug> blocked <reason>` to move the slug's `state.json` entry to `BLOCKED`, and logs the reason (D5); the state call is what takes the slug out of the flow, so a marker written without it leaves the slug sitting at its working phase for the rest of the flow — at `STRIKE_LIMIT` the picker skips it and falls through to `RECOVER`, and below the limit it hands the slug back to the same phase again (D27). `agent-archive.sh` does the same for the `ARCHIVE` phase (§5.5). Nothing moves: the trail stays in the slug dir.

An iteration that dies mid-phase leaves a dirty tree; the next picker returns `RECOVER` before any other test, and the janitor either finishes and commits the phase or discards the paths the factory owns.

### 3.5 Completion

The Stop hook ends the flow if and only if the picker answers `FINISH` in that hook invocation. The picker answers `FINISH` only when `state.json` holds no slug at a non-terminal phase — every entry is at `DONE` or `BLOCKED` — **and** `git status --porcelain` is silent, both evaluated in that invocation. An empty `.slugs` object satisfies the first test too, but it is not what a finished flow looks like: a finished slug keeps its entry. No model output is consulted: the hook runs `scripts/phase.sh` itself and reads no transcript, so nothing a session writes can end a flow or keep one alive.

The hook composes the closing report from `state.json`: shipped is the count of slugs at `DONE`, blocked the count at `BLOCKED`, one `jq` call each over the terminal phases, and the blocked names come from the same call. No marker file is opened. It reaches the operator as the hook's `systemMessage`.

## 4. Boundaries

Each is an interface the design depends on and does not own.

| Boundary | Interface used | Fake used in tests |
| --- | --- | --- |
| git | `status --porcelain`, `rev-parse --show-toplevel`, `mv`, `add`, `commit`, `log` | a real throwaway repo under `mktemp -d` (§10.3) |
| filesystem | the floor tree, read as flow state by `command-run.sh` alone — its intake scan is the system's only directory listing (D27) | a fabricated floor under `mktemp -d` (§10.3) |
| `log.md` | append-only text, written only through `log.sh`'s `<PHASE> <slug> <message>` CLI — never hand-formatted — by phase agents, `agent-archive.sh` and `recover.md`, for audit trail | a fabricated log file (§10.3) |
| `state.json` | JSON; written by every phase's brief/`agent-archive.sh` after their commit; read by `phase.sh`, `print.sh`, `stop-hook.sh`; the flow's entire state — which slugs exist, which phase each is at, terminal ones included, their task counters and their strike ledger (D27) | a fabricated state file (§10.3) |
| Claude Code agent runtime | plugin agent types `spectomat:<name>` from `agents/*.md` frontmatter | none; verified out-of-band per §10.5 |
| the operator's gate commands | `.spectomat/gates.sh`, run as a script | fabricated `gates.sh` scripts, including a failing one (§10.3) |

## 5. Normative Algorithms

Named constants, each defined once here and nowhere else in the system:

| Constant | Value | Owned by |
| --- | --- | --- |
| `STRIKE_LIMIT` | 3 | `scripts/utils.sh` |
| `MAX_REVIEW_ROUNDS` | 2 | `agents/review.md` |
| `AGENT_COUNT` | 8 | this spec, asserted by AC-5.1 |

### 5.1 `pick_phase` — `scripts/phase.sh`

```text
# emit(phase, slug='') prints the frontmatter block (§2.1): phase, slug, and
# subagent/brief/plugin_root derived from phase alone.

pick_phase():
  cd_root()
  if not exists(STATE_FILE):                 emit('FINISH'); return 0
  if `git status --porcelain` is non-empty:  emit('RECOVER'); return 0

  for phase in [ 'ARCHIVE', 'REVIEW', 'IMPLEMENT', 'PLAN', 'REVIEW-SPEC', 'SPECIFY' ]:
      pick = least_struck(phase, slugs_at_phase(phase))
      if pick is not NONE:  emit(phase, pick); return 0

  if slugs_unfinished() is empty:  emit('FINISH')
  else:                            emit('RECOVER')
  return 0
```

Normative notes, each of which a naive reading would get wrong:

1. **`ARCHIVE` and `REVIEW` are tested before `IMPLEMENT`**, matching the contract's priority: work in progress is finished before anything new starts.
2. **A slug's phase is stored in `state.json.slugs[slug].phase`**, not derived from floor files. Once in a phase, the slug stays until the brief advances it.
3. **Slugs enter state at arm time and only there.** `command-run.sh` moves each `.wishlist/*.md` to `<slug>/draft.md`, commits it, and `seed_state` calls `slug_add` for every slug dir with no entry yet — `SPECIFY` for a dir holding only a draft, `REVIEW-SPEC` for a hand-written `spec.md`, `DONE`/`BLOCKED` for a dir already carrying a marker, `BLOCKED` for one the files place nowhere, which it writes a `blocked.md` for and commits so arming still ends on a clean tree. That scan is the only directory listing in the system: after arming, every script reads `state.json` and nothing walks the floor again (D27).
4. **`ARCHIVE` and `REVIEW` are split by phase** (`state.json.slugs[slug].phase` is `ARCHIVE` or `REVIEW`), not by a line in the plan. The `REVIEW` phase advances a slug from `IMPLEMENT` to `REVIEW`; only `REVIEW` returning a verdict advances it to `ARCHIVE`.
5. **The fall-through `RECOVER` now means exactly one thing:** every unfinished slug is at `STRIKE_LIMIT` in its current phase, which is the only way `least_struck` skips a candidate. Nothing else reaches that branch — a slug dir with no state entry is not in the flow, and the picker cannot see it to call it an anomaly.
6. **`RECOVER` precedes every stage test**; only the state-file guard runs before it. A dirty tree with no unfinished slug is a phase having died between its writes and its commit.
7. The picker **never mutates** anything. It is safe to run from `/spectomat:status`.

### 5.2 `least_struck` — `scripts/utils.sh`

```text
least_struck(phase, set):
  if set is empty:  return NONE
  scored = [ (strike_count(phase, s), s) for s in set ]
  eligible = [ (n, s) in scored : n < STRIKE_LIMIT ]
  if eligible is empty:  return NONE            # fall through to the next stage
  sort eligible by (n ascending, s ascending)
  return the s of the first
```

A slug at `STRIKE_LIMIT` is skipped so a failed block-move cannot wedge the factory; if every candidate of a stage is skipped, the stage is treated as empty and the next stage is tried.

### 5.3 `strike_count` — `scripts/utils.sh`

```text
strike_count(phase, slug):
  return .slugs[slug].strikes[phase] // 0  from state.json
```

Returns 0 when the slug has no `strikes` entry for that phase, or when the slug is absent from `state.json`.

### 5.4 `run_gates` — `scripts/utils.sh`

```text
run_gates():
  if not exists(.spectomat/gates.sh):  return 0
  bash .spectomat/gates.sh
  if exit status != 0:
      GATE_FAILED = '.spectomat/gates.sh'
      return that status
  return 0
```

The gates are always `./.spectomat/gates.sh` and nothing else (D6). The script is generated once by `command-run.sh` from the repository's `package.json` (§5.5), committed, and is the operator's editable surface for what gets verified — the contract only names it. Running it as a script rather than parsing commands out of the contract is deliberate: it is operator-authored shell in a committed file of their own repository, at the same trust level as a `package.json` script, and its own `set -e` chains its lines, so one exit code answers for the whole run. A floor with no `gates.sh` has nothing to verify and passes.

### 5.5 `detect_gates` — `scripts/gates.sh`

```text
detect_gates():
  if package.json defines a 'gates' script:  GATES = 'npm run gates'
  else: GATES = one line per script of typecheck, lint, test that
        package.json defines, in that order
        ('npm test' for test, 'npm run <s>' otherwise)
```

`command-run.sh` renders `GATES` into `templates/gates.sh` at the one and only render, or, when nothing was detected, `GATES_NONE`: commented example lines and an `echo "ok: …"` that exits 0. A repo with no gates yet has not failed anything, so the generated script must never exit non-zero to signal its own emptiness (D25). `gates.sh` run directly prints what it would render for the repository it is run in.

### 5.6 `archive` — `scripts/agent-archive.sh`

Invoked by the `spectomat:archive` subagent (`agents/archive.md`), which relays its stdout/stderr and exit code unchanged and performs no mutation of its own (D21).

```text
archive(slug):
  cd_root()
  require `git status --porcelain` silent                            else exit 1
  require state.slugs[slug].phase == 'ARCHIVE'                       else exit 1

  if run_gates() != 0:
      n = slug_strike(slug, 'ARCHIVE')
      log '- <ts> · ARCHIVE · <slug> · gate failed: <cmd> (strike ' + n + ')'
      if n >= STRIKE_LIMIT:  block = true  and continue to the marker
      else:                  exit 1
  else:
      block = false
      gate_result = 'passed'

  if block:  write <slug>/blocked.md  with the strike count and the failed gate
  else:      write <slug>/done.md     with the timestamp and the gate result

  git add -A <slug>/
  git commit -m 'chore(<slug>): archived' (or '… blocked after 3 strikes')
      or strike_and_exit

  slug_finish(slug, block ? 'blocked' : 'done', reason)   # terminal phase, after the commit lands
  log '- <ts> · ARCHIVE · <slug> · archived · gates passed'
```

**One marker, no moves.** Finishing a slug writes a single new file in that slug's own directory, so there is no partial state to survive: either the marker and its commit landed or neither did (D26). This replaces a six-move sequence whose every step had to be checked, because a partial move that still committed left a CLEAN tree — the picker never answered `RECOVER`, the janitor never ran, and a spec whose plan had already been archived read as a fresh `PLAN` phase. The marker is now the committed human record and nothing else: `state.json` is gitignored, so `done.md` and `blocked.md` are the only trace of how a slug ended that survives in git, and no script reads them back (D27).

**The commit is still checked.** The script runs under `set -uo pipefail` with no `-e`, so a failed command does not abort. `strike_and_exit` records a strike in `state.json` — so the slug blocks after three — then exits 1, leaving the marker uncommitted and the tree dirty for the janitor. Exiting without a strike would wedge the flow, because the picker answers `ARCHIVE` again next iteration and the same commit fails again until the cap.

**Only a slug at `ARCHIVE` is archived.** One state check replaces the three file checks it supersedes and is stronger than all of them: a slug reaches `ARCHIVE` only through `REVIEW`, which only happens after `PLAN` wrote a plan and `IMPLEMENT` closed every task, so the spec and the plan exist by construction. It keeps a second `ARCHIVE` from committing over finished work and keeps a blocked slug from being silently promoted to shipped, because neither `DONE` nor `BLOCKED` is `ARCHIVE` (D27). The third strike differs from a pass only in which marker is written, so the path is written once. `print_blocked` lists `.spectomat/<slug>/blocked.md` for every slug at `BLOCKED`, building the path from the slug name without stat'ing it: the marker is written before the terminal phase is recorded, so a slug at that phase has its file.

The log line reports the gate outcome, not test counts: a script has first-hand knowledge that `gates.sh` exited 0, and no knowledge of what it printed (D4).

## 6. Architecture

### 6.1 Component map

| File | Role |
| --- | --- |
| `scripts/command-run.sh` | prepares the floor, renders and commits, arms the Stop hook |
| `scripts/phase.sh` | the picker (§5.1) |
| `scripts/agent-archive.sh` | the archiver, the `ARCHIVE` phase (§5.5) |
| `scripts/utils.sh` | shared helpers (§5.2–§5.4), paths, `cd_root`, `state_field`, `render_template`; sourced by every script |
| `scripts/stop-hook.sh` | runs the picker, ends the flow on `FINISH`, composes the closing report, blocks the session exit on other verdicts, bumps the iteration counter, feeds back the pointer |
| `scripts/command-status.sh`, `print.sh`, `command-cancel.sh`, `command-help.sh` | operator surface (§7) |
| `scripts/gates.sh` | gate detection (§5.5); sourced by `command-run.sh`, and runnable to preview what a repo would get |
| `scripts/selftest.sh` | runs every `tests/*_test.sh` file and reports the combined tally |
| `tests/*.sh` | the suite (§10), one file per section, each independently runnable |
| `agents/specify.md` | draft → spec — `spectomat:specify` |
| `agents/review-spec.md` | spec → reviewed spec — `spectomat:review-spec` |
| `agents/plan.md` | reviewed spec → plan — `spectomat:plan` |
| `agents/implement.md` | plan → next task: dispatches, verifies and closes — `spectomat:implement` |
| `agents/task.md` | one task, built from its task file alone — `spectomat:task`, dispatched by `implement` |
| `agents/review.md` | finished plan → verdict or fix tasks — `spectomat:review` |
| `agents/recover.md` | the janitor — `spectomat:recover` |
| `templates/contract.md`, `memory.md` | rendered into the project once, then owned by it |
| `templates/spec.md`, `plan.md`, `task.md` | the shapes the `SPECIFY`, `REVIEW-SPEC` and `PLAN` phases fill in |
| `docs/guide.md` | the user guide, printed by `/spectomat:help` |
| `references/glossary.md` | the glossary, printed by `/spectomat:help` alongside `guide.md` |
| `references/three-strikes.md`, `log-format.md` | the strike procedure and the log message shape, cited by the contract and every brief that needs them |
| `commands/run.md`, `status.md`, `cancel.md`, `help.md` | the four slash commands |
| `hooks/hooks.json` | wires the Stop hook |

### 6.2 The contract

`.spectomat/contract.md` is rendered from the template at the first `/spectomat:run` and never overwritten, so it is **the operator's only steering surface**. It holds the invariants that outlive the briefs: the floor, the Iteration Contract, when to gate and the path of the gate script, and how to read and write `memory.md`. Three strikes and the log format are named here but not spelled out: both are one copy under `references/`, cited by the contract and by every brief that needs them, so the procedure cannot drift between the briefs that follow it (the same reasoning as D28). Its Constitution carries the rules binding every phase, grouped by what they govern: judgement, what may be written, honest reporting, ending a phase, and where work happens.

It holds no phase sections (D3) and no craft prose (D11): text no operator would ever edit is not steering, and belongs in the brief that uses it. What earns a line in `memory.md` lives in that file's own header, not here (D10).

### 6.3 The briefs

Each brief holds the craft of one phase and is read only on that phase's iterations. A brief carries no `{{KEY}}` placeholder — it is never rendered — and no plugin path: its task's `plugin_root:` field supplies one at dispatch (§3.3).

`agents/task.md` is the largest brief by a wide margin, carrying task execution, TDD and systematic debugging, and it is the one brief that reads no contract: it restates the few Constitution rules that bind a worker, because the worker's context holds only the task file and the code. That is the point of the design and not a smell: the `SPECIFY` phase pays nothing for it, and `agents/implement.md` is left with orchestration alone — pick, dispatch, verify, record, advance.

`IMPLEMENT` is the one brief that dispatches another agent (D30), and the only text it sends is three lines — slug, task path, gates-log path — never a brief verbatim. The task file is the worker's whole brief, which is why the `PLAN` and `REVIEW` phases inline the spec into its `## Context` instead of citing it. Every other phase does its own work: `REVIEW-SPEC` revises the spec itself and `REVIEW` reads the plan itself, so a brief is only ever read as guidance by the one agent it names.

### 6.4 The state and the pointer

The flow's state lives in two files. The gitignored `state.json` holds the flow level — which slugs exist, which phase each is at, finished ones included, and how many times each phase has failed — and its `active` flag is what "armed" means. Each planned slug's `tasks.json` holds its tasks (D31): the list, each task's `dependsOn` and `status`, and the `commits`, `tests` and `gates` it closed with. It is committed, so a task's evidence survives in git where `state.json` cannot follow, and `scripts/tasks.sh` is its only writer. The pointer prompt fed back each iteration is not a file — `pointer_prompt()` in `scripts/utils.sh` generates it fresh from a fixed heredoc every time it is called, substituting `PLUGIN_ROOT` (already a shell variable in every script that sources `utils.sh`) the same way `render_template` substitutes a template's `{{KEY}}` placeholders (D12).

| File | Schema | Read by | Written by |
| --- | --- | --- | --- |
| `state.json` | `{active: bool, iteration: int, max_iterations: int, session_id: string, started_at: timestamp, plugin_root: path, slugs: {<slug>: {phase: string, strikes: {<phase>: int}, reason: string, finished_at: timestamp}}}` | `phase.sh`, `print.sh`, `stop-hook.sh`, phase agents (via `state_field` and slug helpers) | `command-run.sh` at seeding and arming; every phase brief and `agent-archive.sh` after their commit; `stop-hook.sh` bumps `iteration`; `/spectomat:cancel` sets `active: false` |
| `<slug>/tasks.json` | `{slug: string, tasks: [{id: int, name: string, file: path, component: string, covers: [string], dependsOn: [int], status: "pending"\|"done", commits: string, tests: string, gates: string}]}` | `print.sh`, the `IMPLEMENT` and `REVIEW` phases (via `scripts/tasks.sh`) | `PLAN` writes it, `IMPLEMENT` closes each task, `REVIEW` appends fix tasks — all through `scripts/tasks.sh`, never by hand |

| Field | Holds |
| --- | --- |
| `slugs[<slug>].phase` | one of the six working phases, or the terminal `DONE` or `BLOCKED` (§2.1) |
| `tasks[].status` | `pending` until the `IMPLEMENT` phase closes the task, `done` after; nothing else. Set by `tasks.sh` alone — a caller's own value is discarded, so a plan cannot arm itself closed |
| `tasks[].dependsOn` | the ids of every task whose Produced Interfaces this one consumes; only lower ids. `tasks.sh next` picks the lowest-id pending task whose every dependency is `done`, and prints nothing on a cycle |
| `tasks[].commits` | the `<base7>..<head7>` range of that task's one `feat` commit, recorded at close. The `REVIEW` phase reconstructs the plan's whole diff from the first task's base to the last task's head |
| `slugs[<slug>].reason` | why the slug finished — the gate that failed, or `gates passed`; written by `slug_finish`, absent while the slug is working |
| `slugs[<slug>].finished_at` | when it finished, UTC; written by `slug_finish` alongside `reason` |
| `plugin_root` | the plugin copy that armed the flow, written once at arming |

`plugin_root` is authoritative for the floor, not for the scripts. A floor-side reader — the operator, `/spectomat:status`, the janitor — has no other way to name which plugin copy armed this flow, and `print_iteration` prints it as a `plugin:` line. No script reads it to locate anything: each derives `PLUGIN_ROOT` from its own `BASH_SOURCE`, and a phase agent resolves `<plugin_root>` from the picker's verdict block, as `templates/contract.md` directs.

A finished slug keeps its entry, its task counters and its strikes. Nothing is deleted, so `/spectomat:status` can still report what a shipped or blocked slug ended with, and re-arming over that state neither resurrects it nor counts it as active.

**The resume path:** When `/spectomat:run` is invoked with an inactive flow (`state.json` exists and `active: false`), `command-run.sh` re-arms by setting `active: true` instead of refusing. This restores the flow from where it stopped, continuing from the same `iteration` counter, with all slug phases and strike counts preserved in `state.json.slugs`. There is no second file to re-render on resume — `pointer_prompt()` produces the same text on the first call and the hundredth.

**Disarming:** `disarm()` is called only at FINISH (all work done), at the iteration cap, or on corrupt state. It removes `state.json`; there is nothing else on disk for it to clean up. `/spectomat:cancel` is different: it only sets `active: false`, leaving `state.json` intact so `/spectomat:run` can resume.

Generating the prompt instead of rendering it to disk keeps it honest: `state.json` is data a script parses, the pointer is a prompt a model reads, and there is no file that can go stale — a plugin reinstalled at a new cache path can never leave a pointer holding the old one — or outlive the state it belongs to (D12).

Drafts arrive in `.wishlist/` already named: the plugin issues no numbers and renames nothing (D13). Arming moves each into its own `<slug>/draft.md` and empties `.wishlist/` (D26, D32). The picker reads slugs in plain alphabetical order of that name, which is the operator's only lever on the order they are worked.

## 7. Operator surface

### 7.1 Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the wishes it finds, arms the Stop hook for `n` iterations (default 100), starts iteration 1; resumes an inactive flow if one exists, else refuses when a flow is armed, no unfinished slug remains, or the tree is dirty |
| `/spectomat:status` | the next verdict, the current iteration and the plugin copy that armed the flow, floor counts, per-slug progress including finished slugs, blocked files, log tail — every count from `state.json` |
| `/spectomat:cancel` | marks the flow inactive and removes the pointer; keeps `state.json` so `/spectomat:run` can resume it |
| `/spectomat:help` | prints `docs/guide.md` and `references/glossary.md` |

### 7.2 `status` predicts the next phase

`command-status.sh` calls `print_next`, which prints a `--- next ---` section holding the picker's frontmatter block verbatim, e.g. `phase:IMPLEMENT` / `slug:003-auth` / … . Because it is the identical code path the next iteration takes, the prediction cannot drift from the decision. The picker mutates nothing (§5.1 note 7), so this is safe to run at any time.

### 7.3 Installation

The plugin runs from a cache copy under `~/.claude/plugins/cache/spectomat/`, so a source edit is not live until `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run`.

## 8. Design decisions

| Id | Decision | Rejected | Why |
| --- | --- | --- | --- |
| D1 | A bash picker (`phase.sh`) decides the phase | a thin foreman agent; the session deciding from the contract | deterministic, testable, costs no tokens, and makes a false completion promise structurally impossible |
| D2 | Five phase agents (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`); the `ARCHIVE` phase is `agent-archive.sh` | six agents; two agents (author / builder) | `ARCHIVE` is mechanical — gates, three moves, one commit; a script that exits non-zero on a failing gate is stronger evidence than an agent claiming the gate passed. Superseded in dispatch shape by D21: the reliability guarantee stated here still holds, since `agent-archive.sh` still does the work and still owns the exit code |
| D3 | The contract keeps no phase sections at all | per-phase stubs with a "Project overrides" list | one source per phase; an override mechanism is complexity bought before anyone has needed it |
| D4 | The `ARCHIVE` phase's log line carries the gate outcome (`gates passed`) | parsing test counts out of gate output | a script knows that `gates.sh` exited 0; it cannot know what the script printed, and guessing would be the adjective the Log Format forbids. Since D25 made the gates one script, a count of gate lines is no longer the script's to know either |
| D5 | A phase agent performs its own third-strike block-move | the picker detecting the third strike and a `block.sh` doing the move | the agent knows why it failed and must write the reason; the picker stays free of mutation |
| D6 | `run_gates` runs `.spectomat/gates.sh` as a script | a restricted parser, or `npm run` only | the script is operator-authored shell in their own committed repository, at the same trust level as a `package.json` script the factory already runs. Superseded in shape by D25, which replaced the parsed contract fence with the script; the trust argument stated here is what carried over |
| D7 | `PLAN` also claims a plan overview with no task files | leaving it stranded | otherwise a half-finished `PLAN` phase matches no stage and the plan is unreachable for the life of the floor |
| D8 | The `IMPLEMENT` phase executes exactly one task per iteration, in dependency order | packing file-disjoint ready tasks into one iteration as a "wave" | a wave is the only place where the unit of dispatch differs from the unit of work, and it pays for that with file-disjointness analysis in the `IMPLEMENT` phase, packability planning in the `PLAN` phase, shared-tree race rules, ordered commits and concurrent fix loops. One task per iteration deletes all of it: the picker is unaffected, an iteration stays one commit and one log line, and a task's blast radius is one revert. The cost is iterations, which are cheap and unattended |
| D9 | `command-run.sh` renders `contract.md` once and never rewrites it | a migration that regenerates an old contract from the template, carrying the gate lines across | a migration path can only overwrite the file the operator is told to edit, and one that has never migrated anything is untested weight on the script every run executes |
| D10 | `templates/memory.md`'s own header carries what earns a line; the contract carries only when to read and write it | the rules in both files, kept in step by hand | duplicated rules drift, and keeping them in step was a manual instruction to a human. Every iteration reads `memory.md` in Orient anyway, so the header costs no extra read |
| D11 | Craft prose lives in the brief that uses it — gate-reading in `agents/implement.md`, "`SPECIFY` and `PLAN` skip the gates" in those two briefs | keeping it in the contract, where every phase reads it | the contract is the operator's only editable surface; text no operator would ever edit is craft, not steering, and D3 already put craft in the briefs |
| D12 | State and the pointer prompt are addressed as two different kinds of thing: `state.json` is data a script parses with `jq`, the prompt is text a model reads | one Markdown file with the state in frontmatter and the prompt in its body | one file forced every reader to parse past the other: `awk '/^---$/{i++; next} i>=2'` in two scripts to reach the prompt, and a `sed \| grep \| sed` pipeline to reach a field. Kept apart, the state is `jq`-addressable in one call and the prompt needs no parsing at all. The names stop competing too — neither thing pretends to be the other. See D23 for how the prompt itself is produced without a second file |
| D13 | The operator puts drafts into the inbox and names them; `command-run.sh` only moves and commits what it finds there (D26) | `command-run.sh` moving `wishlist/*.md` into `drafts/` under a number issued from a committed `.inc` counter | intake is the project's business, not the factory's. It cost a second inbox directory, a counter file with a git lifecycle opposite to the state it sat next to, and staging both ends of every move so arming still ended on a clean tree. Without it the floor has one entrance and drafts are worked in plain alphabetical order of whatever the operator called them |
| D14 | The `IMPLEMENT` phase writes its task's code itself | an implementer subagent it dispatches, reports back from and resumes | the picker already gives one fresh agent per task, so a subagent bought no context isolation and cost a placeholder-filled brief sent verbatim, a report file as the return channel, a `DONE / BLOCKED / NEEDS_CONTEXT` protocol and a re-dispatch rule — all of it deleted. What it loses is real but small: a cheap model for code writing, and a stronger one on the last fix round. Superseded by D30 |
| D15 | `REVIEW` is one phase per plan, run when `state.json` says every task is closed | a reviewer subagent per task commit, with `MAX_FIX_ROUNDS` fix rounds inside the `IMPLEMENT` phase | per-task review was the one unit of work the picker could not see: no verdict, no log line, no strike, not resumable, a sub-state-machine with its own constant hidden inside another phase. As a phase it is an iteration like any other; its findings become task files that get the full TDD cycle instead of "send the findings back" rounds; and it reads the plan whole, which is the only way to see a helper written twice, code one task orphaned, or an interface that drifted between one task's `Produces` and another's `Consumes`. The cost is latency — a defect in task 1 surfaces after task 8 — bounded because the gates still run on every task and the plan's `Interfaces` rows are what guard the seams |
| D16 | `REVIEW-SPEC` is one phase per spec, run once between `SPECIFY` and `PLAN`, and it revises the spec in place | a self-review checklist inside the `SPECIFY` brief; an approve-or-flag reviewer that sends the spec back to `SPECIFY` | the author cannot read its own spec cold, and the planner is the first reader that can be misled; a fresh agent with only the spec and the draft is the cheapest cold read. It fixes rather than flags because the fix for a spec is a sentence, and a `SPECIFY` round trip would rewrite the whole file to change one line. Each fix is a `revised` row in §10, so the trail is as traceable as an `assumed` one. One round, latched by `- Verdict: READY` in §16, the same grammar as the plan latch, so the picker learns nothing new |
| D17 | The picker reads `state.json.slugs` to determine each slug's phase, instead of deriving it from floor-file checks | file-content checks (`- Verdict:` lines, task file existence, etc.) | deterministic and testable: the phase decision is now an explicit field, not an inference. The picker never mutates files, so the state is the only thing that changes when a phase advances. This makes the state the single source of truth for the flow's progress and makes resume possible |
| D18 | Strike counts are stored in `state.json.slugs[slug].strikes[phase]`, not derived from `log.md` | log-line-counting logic in the picker and `strike_count` | the state is now the authoritative record of phase failures, and `log.md` becomes write-only audit trail. This makes `strike_count` fast (one `jq` call, no grep) and makes strikes observable in the state, enabling inspection and recovery |
| D19 | `/spectomat:cancel` sets `active: false` but keeps `state.json` | full disarm, removing `state.json` | this enables resume: a session can pause a flow with `/spectomat:cancel`, and `/spectomat:run` resumes it from the same iteration, with all slug phases and strikes preserved. Without it, a pause-and-resume would restart the flow and lose all progress |
| D20 | Each slug carries `phase`, `tasks_total`, `tasks_done`, and `strikes` in `state.json.slugs[slug]` | per-phase tracking only, rebuilt at each phase | observable progress: the state encodes not just what phase a slug is in, but how many tasks are in its plan and how many are done. This makes the flow's progress queryable without parsing floor files, and makes recovery from a crashed phase more precise. Superseded in part by D31: the counters move to the slug's own `tasks.json`, which answers the same questions in more detail and survives in git; `state.json` keeps `phase` and `strikes` |
| D21 | Every verdict, `ARCHIVE` and `FINISH` included, dispatches through a subagent, so dispatch has one row shape for all seven — `spectomat:archive` invokes `agent-archive.sh` and relays its exit code unchanged; `spectomat:finish` reads the log and floor to compose the closing report, and the session still emits the promise | keeping `ARCHIVE` a bare script call and `FINISH` pointer-only text, as D2 and D14 both argue for mechanical work | operator preference for a uniform dispatch table outweighed the extra hop, once each wrapper was written to add no judgement of its own: `spectomat:archive`'s brief forbids moving a file, running a gate, or reinterpreting a non-zero exit as success, and `spectomat:finish`'s brief forbids writing to `state.json` or emitting the promise itself. D2's reliability guarantee is unweakened by the wrapper, since `agent-archive.sh` still performs every mutation and still owns its own exit code — the agent can only relay it, not launder it. Superseded for `FINISH` by D24; `ARCHIVE`'s wrapper stands |
| D22 | `phase.sh` computes `subagent` and `brief` itself and emits them in its frontmatter block (§2.1, §3.3), so the uniform row shape D21 fixed lives in one script instead of also being restated as a table in the pointer prompt | keeping a dispatch table in the pointer prompt, matching each verdict to a `subagent_type` and brief path by hand | the mapping is a pure function of `phase` (lowercase it, prefix `spectomat:`, join with `PLUGIN_ROOT`) that `phase.sh` already has every input for; a table restating it in the pointer was a second place the same seven rows could drift out of step with `agents/*.md`'s actual file names, with no test catching the mismatch until a dispatch failed. The picker still only prints and mutates nothing (§5.1 note 7) |
| D23 | The pointer prompt is generated by `pointer_prompt()` in `scripts/utils.sh` — a fixed heredoc with `PLUGIN_ROOT` substituted at call time — and never written to disk | `templates/pointer.md`, rendered into `.spectomat/pointer.md` at arm time and re-rendered on every resume | the text never varies except for `PLUGIN_ROOT`, which every script that sources `utils.sh` already holds as a shell variable; rendering it to a gitignored file bought nothing but a second path for `disarm()` to clean up, a resume step that had to re-render it, and a file that could hold a stale `PLUGIN_ROOT` if the plugin was reinstalled at a new cache path between arms. Generating it fresh in `continue_iteration()` and in `command-run.sh`'s arm preview removes all three at once, and it is exercised directly in `pointer_prompt_test.sh` (§10) rather than through a rendered file's contents |
| D24 | The Stop hook runs `phase.sh` itself and ends the flow on `FINISH`, composing the closing report in bash; `FINISH` dispatches no agent and the `<promise>FACTORY EMPTY</promise>` string is retired | keeping the promise as the signal; keeping `agents/finish.md` and latching the finished iteration in `state.json` | the promise put the verdict's authority in the model's hands: `check_promise` never consulted the picker, so any text carrying the string ended a flow, a tool-call-final turn stranded one, and a dirty tree at finish time ended the flow instead of reaching the janitor. D1 claimed a false completion promise was structurally impossible; this makes that true. Supersedes D21 for `FINISH` only — `ARCHIVE`'s wrapper is untouched, and D2's and D14's argument that mechanical work stays mechanical is what `FINISH` returns to. A `state.json` latch was rejected because `FINISH` is a stable predicate and an actuator inside the process that evaluates it fires exactly once with no memory |
| D25 | The gates are always `./.spectomat/gates.sh`, generated once by `command-run.sh` from `package.json` and edited there by the operator | the gate commands living as lines inside `contract.md`'s Verification Gates fence, parsed out by `gate_block` | the fence made the contract both prose and executable data, and paid for it twice: an awk fence parser plus a comment/blank filter in `utils.sh`, with its own test file, and an operator whose gates were shell but whose editing surface was Markdown — one stray fence in the file above and the gates silently changed. A script is the honest shape for a list of commands: `set -e` chains them, `bash gates.sh` is the whole of `run_gates`, and the exit code is the script's own rather than something the factory assembles. It is also directly runnable by hand, which the fence never was. The operator keeps one editable file per concern — `contract.md` for the rules, `gates.sh` for the checks — and the contract's Verification Gates section disappears entirely: with the path fixed and `run_gates` hardcoding it, step 3 of the Iteration Contract names the script in passing and that is the whole of it (D11). The cost is a fourth rendered file on the floor, checked on its own like the others, so an older floor picks it up on the next `run` |
| D26 | The floor is slug-major: everything of one idea lives in `.spectomat/<slug>/` for its whole life, and `ARCHIVE` finishes it by writing a `done.md` (or `blocked.md`) marker in place | stage directories `specs/`, `plans/`, `snippets/` with a `done/` the trail is moved into, under a `.blocked` infix on the third strike | the stage-major floor spread one idea across four directories under three naming schemes, so reading a slug's trail meant four `ls`es and archiving it meant six checked `git mv`s. Its worst failure was structural: a partial move that still committed left a CLEAN tree, so the picker never answered `RECOVER`, the janitor never ran, and a spec whose plan had already moved read as a fresh `PLAN` phase (§5.6). A marker cannot partially apply — either the file and its commit landed or neither did — and moving nothing means nothing can half-move. The trail also stays where every task file, `result.md` entry and commit message already points, which a move invalidated. The cost is that finished work stays on the floor: `done/` no longer separates it, so the picker must skip a marked dir, `slug_dirs`/`slug_active_dirs` in `utils.sh` carry that rule for every script, and the inbox becomes a pure entrance that arming empties into slug dirs — which in exchange lets a hand-written `spec.md` arm at `REVIEW-SPEC` instead of stranding the floor at `RECOVER`. Superseded in part by D27: the marker stays, but nothing reads it back, and the floor helpers it needed are gone |
| D27 | `state.json` is the entire flow state: which slugs exist and what phase each is at, including the terminal phases `DONE` and `BLOCKED` that a finished slug keeps, with its `reason`, `finished_at`, counters and strikes retained; `command-run.sh`'s intake scan is the only directory listing left in the system, and `done.md`/`blocked.md` stay as the committed human record that nothing reads | keeping `check_orphans` reconciling the floor against the state; a separate `status` field beside `phase`; deleting the markers along with the reads that used them | two authorities need a reconciler, and the reconciler was the most fragile part of the flow: a phase that wrote its marker but died before its `slug_delete` left the two disagreeing, `check_orphans` then answered `RECOVER` for every remaining iteration, and the defence was a rule in every brief about that exact ordering — a correctness argument spread across six prose files, which is where it was always going to rot. One authority deletes the reconciler, the orphan class it detected, and the ordering rule at once, and the picker gets shorter and stops touching the disk. A separate `status` field beside `phase` was rejected because the picker's candidate sets are built by phase: two fields would have to agree on every read and could disagree on any single write, which is the same two-authority problem moved inside one file. Deleting the markers was rejected because `state.json` is gitignored, so `done.md` and `blocked.md` are the only trace of how a slug ended that survives in git, and they cost one write inside a commit `ARCHIVE` was making anyway. The cost is the mirror image of the old failure: deleting a slug dir by hand no longer removes it from the accounting, since the state is authoritative and no longer looks — the operator who wants a slug gone edits `state.json`, or cancels and re-arms. Arming absorbs the migration: `seed_state` reads a marker for a slug with no entry and seeds the terminal phase, and it blocks a dir whose files match no phase rather than leaving it stranded |
| D28 | `log.md`'s line format is produced by one script, `scripts/log.sh <PHASE> <slug> <message>` — timestamp, `·` separators and all — and every writer (`agent-archive.sh`, each phase brief, `recover.md`) calls it instead of composing the line itself | the contract's *Log Format* section giving a template and worked examples, left to each brief and script to reproduce with its own `printf`/`date` | a format restated in seven briefs and `agent-archive.sh`'s own `log_line`/`now` pair drifts the moment one of them is edited without the others — the contract already showed this once, since `agent-archive.sh` carried a private copy of both instead of calling out. `log.sh` fixes the timestamp itself (never a caller-supplied or remembered time, matching the contract's existing rule) and is the only line `log.md` ever sees, so a hand-written `printf >> log.md` is now simply wrong rather than one of several accepted shapes. The cost is one more script and one more subprocess per log line; `agent-archive.sh` keeps a thin `log_line` wrapper over it rather than inlining the call at each of its three sites |
| D29 | The contract's *Iteration Contract* section states only the cross-cutting rule (do exactly the phase handed, work in progress always wins) and the gate script's identity; Orient's dirty-tree/inbox check, gate-timing, and the commit-and-log steps are each folded into the phase brief that runs them (`specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`, `recover.md`) | keeping the five generic steps centralized in the contract per D3/D11, with each brief's own Procedure restating them in phase-specific terms as it already did | D3 and D11 held that craft prose belongs in the brief that uses it and the contract stays the operator's one editable surface for invariants — sound for the log line format (D28) and the gate script's identity, both byte-exact and rarely touched. Orient's dirty-tree recovery and the inbox-untouched rule are not steering an operator tunes; they are the same few sentences every brief needed anyway to be self-contained and independently readable, the same argument D26 made for the floor and D17 made for state. Six near-identical one-line contract references, each requiring the reader to jump to a second file to learn what "Orient" means for *this* phase, cost more than six brief-local paragraphs cost in drift risk — unlike the log line, this text has no script to keep it honest, so distributing it trades a hand-checked duplication (already present, since every brief already restated its own version in the Procedure) for a slightly larger one, in exchange for a brief nobody has to leave to execute. `archive.md` is unchanged: its Orient is `agent-archive.sh` refusing on a dirty tree, not prose. Supersedes D3 and D11 for the Iteration Contract's steps only; D3's "no override mechanism" and D11's placement of gate-reading and phase-skip rules in the briefs that use them both stand |
| D30 | The `IMPLEMENT` phase dispatches one `spectomat:task` agent (`agents/task.md`, sonnet) per task, with a three-line task — slug, task file path, gates log path — and the task file's `## Context` carries the spec verbatim, the purpose and the codebase facts, so the worker opens only that file, its snippets and the code. The worker builds under TDD, runs the gates into `.spectomat/work/<slug>/task-NN.gates.log`, makes the one `feat` commit and reports `DONE` or `FAILED`; `implement` (haiku) verifies the commit against git and the log, records `ruling.md`/`memory.md`, closes the task in the ledger and commits the close (D31 — `result.md` in the original shape) | D14's in-phase build (superseded); a report file as the return channel; a `NEEDS_CONTEXT` verdict and a re-dispatch rule; letting the worker read `memory.md` or the contract | D14 held that a subagent bought no context isolation, which was true of D14's shape, where the worker still read the contract, the memory and the plan. This shape gives the worker a context holding one task file and the code, and nothing that orchestration needs — the contract, `memory.md`, `state.json`, the counters — which is the isolation D14 could not buy; and a cheap orchestrator with a capable coder recovers exactly the loss D14 named. The return channel is the Agent tool's own report, checked against `git rev-list`, `git show --stat` and the gates log rather than trusted, so there is no report file and no protocol beyond `DONE`/`FAILED`; a `FAILED` report or a failed check is the strike the phase already had, so the picker, `state.json` and `log.md` learn nothing new. The worker touches no floor state, which keeps one task one entry. The cost is one extra dispatch per task, longer task files (the `PLAN` and `REVIEW` phases quote instead of cite), and a contract line that names the exception — an older floor's rendered contract keeps the old line and must be re-rendered by the operator (D9) |
| D31 | Each planned slug carries a committed `tasks.json` ledger — the list `PLAN` writes prepopulated, every task's `dependsOn` and `status`, and the `commits`/`tests`/`gates` each one closed with — written only through `scripts/tasks.sh`. It replaces `result.md` and takes `tasks_total`/`tasks_done` out of `state.json`, and the plan overview's task table loses its `Depends on` column | keeping `result.md` and reading `Depends on` out of the overview's Markdown table; folding the ledger into `state.json`; a `tasks.json` that also carries phase and strikes, replacing `state.json` entirely | the same facts lived in three places that could disagree: `state.json`'s counters, `result.md`'s entries, and the overview's `Depends on` column. Readiness was defined as "every task it depends on has an entry in `result.md`" — a Markdown table parsed against a Markdown file, by an agent, once per iteration. The ledger makes readiness one `jq` walk (`tasks.sh next`) and makes the close atomic with the phase move it earns, so a closed task and a slug still at `IMPLEMENT` cannot coexist. Committing it is what `state.json` could not do: the per-task commit range is the `REVIEW` phase's only way to reconstruct the diff, and a gitignored record of it is lost to any reader outside the flow — which is exactly what `result.md` existed to prevent. It stays per-slug rather than merging into `state.json` for that reason, and `state.json` stays for the flow level, which is genuinely ephemeral. The cost is one more committed file per slug, one extra read per slug in `/spectomat:status`, and a close that now writes a tracked file — so `IMPLEMENT` closes the ledger before its `chore` commit and `REVIEW` adds fix tasks before its own, rather than after as every other phase transition does |
| D32 | The inbox is `.wishlist/` at the repo root, beside the floor rather than inside it | keeping it as `.spectomat/drafts/`, one directory under the floor | the floor is the factory's own working area — state, contract, gates, one dir per slug in flight — and every one of its files is written by a phase. The inbox is the opposite: the only thing on it is written by the operator, and no phase may touch it (contract, *Where you work*). Sitting inside `.spectomat/` it read as factory storage, and every rule about it had to carve it back out as an exception. At the root it is plainly the operator's, next to the other things they own, and the carve-outs say so by name. It costs `command-run.sh` a second `mkdir` — `.spectomat/` no longer comes into being as the inbox's parent — plus a `WISHLIST` path in `utils.sh` and one more directory in a project's root listing. D13's one-entrance rule is unchanged: the name moved, the intake did not |

## 9. Acceptance Criteria

### 9.1 Per component

| Id | Criterion | Verified by |
| --- | --- | --- |
| AC-1.1 | `phase.sh` prints exactly one frontmatter block and exits 0 for every floor state in §10.3 | selftest |
| AC-1.2 | Priority holds: with candidates in all six stages, the verdict is `ARCHIVE` | selftest |
| AC-1.3 | A slug dir with a `plan.md` and zero `task-*.md` files does not yield `ARCHIVE` | selftest |
| AC-1.4 | A reviewed spec whose plan overview exists but has zero task files yields `PLAN` | selftest |
| AC-1.5 | A spec whose slug's phase is `REVIEW-SPEC` yields `REVIEW-SPEC` in the picker; when advanced to `PLAN` it yields `PLAN` | selftest |
| AC-1.6 | A strike logged at `REVIEW-SPEC` does not count at `REVIEW`, nor the reverse | selftest |
| AC-1.7 | A dirty tree yields `RECOVER`, even when no unfinished slug remains | selftest |
| AC-1.8 | `FINISH` requires `state.json` to hold no slug at a non-terminal phase — every entry at `DONE` or `BLOCKED` — **and** a silent `git status` | selftest |
| AC-1.9 | A floor whose every slug is at a terminal phase yields `FINISH`, not `RECOVER`, and a terminal slug is never picked as a candidate | selftest |
| AC-1.10 | A slug dir with no `state.json` entry is not in the flow: the picker neither picks it nor treats it as an anomaly | selftest |
| AC-1.11 | Given two candidates in one stage, the one with fewer strikes is named | selftest |
| AC-1.12 | A candidate at `STRIKE_LIMIT` is skipped; if all are, the next stage is used; if every unfinished slug is at the limit, the verdict is `RECOVER` | selftest |
| AC-1.13 | `phase.sh` leaves the floor and the git index byte-identical | selftest |
| AC-1.14 | The block's `subagent` and `brief` fields are `spectomat:<phase lowercased>` and `{{PLUGIN_ROOT}}/agents/<phase lowercased>.md`, for a hyphenated phase too | selftest |
| AC-2.1 | `command-run.sh` renders an executable `.spectomat/gates.sh` once, from `package.json`, and never overwrites an existing one | selftest |
| AC-2.2 | `run_gates` returns non-zero when `gates.sh` exits non-zero, and names it; a floor without `gates.sh` passes | selftest |
| AC-2.3 | `strike_count` returns 0 when the slug has no `strikes` entry for that phase | selftest |
| AC-3.1 | `agent-archive.sh` with a failing gate writes no marker, commits nothing and exits non-zero | selftest |
| AC-3.2 | `agent-archive.sh` logs `(strike N)` with N one higher than the log showed | selftest |
| AC-3.3 | At the third strike `agent-archive.sh` writes `<slug>/blocked.md` and no `done.md`, records the slug `BLOCKED` in `state.json`, and `print_blocked` lists that slug | selftest |
| AC-3.4 | `agent-archive.sh` makes exactly one commit, touches no file outside the floor, and refuses a slug not at phase `ARCHIVE` | selftest |
| AC-4.1 | `command-status.sh` prints the picker's verdict verbatim | manual, scratch repo |
| AC-4.2 | Arming writes a valid `state.json` with `active: true`, `iteration: 1`, numeric `max_iterations`, `session_id`, `started_at`, `plugin_root` naming the plugin copy that armed it, and one `slugs` entry per slug dir | selftest |
| AC-4.3 | `/spectomat:cancel` sets `active: false` and keeps `state.json` and the floor | selftest |
| AC-4.4 | `command-run.sh` moves a draft dropped into `.wishlist/` to `<slug>/draft.md`, tracked or not, commits it and leaves a clean tree; a hand-written `<slug>/spec.md` arms at `REVIEW-SPEC` | selftest |
| AC-4.6 | `command-run.sh` refuses to arm when anything outside the floor is uncommitted | selftest |
| AC-4.7 | The Stop hook blocks the exit for the owning session, bumps `iteration`, and feeds back the pointer prompt verbatim | selftest |
| AC-4.8 | A session that did not arm the flow neither advances nor ends it, and an unreadable state file is left in place for `/spectomat:cancel` | selftest |
| AC-4.9 | An empty floor with a clean tree disarms the flow and reports what shipped and what was blocked; the iteration cap disarms it too | selftest |
| AC-4.11 | An empty floor with a dirty tree does not end the flow: the hook blocks and the next verdict is `RECOVER` | selftest |
| AC-4.10 | `pointer_prompt()` resolves `PLUGIN_ROOT` with no unresolved `{{KEY}}` placeholder left in its output | selftest |
| AC-4.5 | Drafts are taken in alphabetical order of the file name, whatever their modification times | selftest |
| AC-4.12 | Re-arming over a `state.json` holding terminal entries neither resurrects them nor counts them as active; a slug dir carrying a marker but no entry is seeded at its terminal phase, and a dir whose files match no phase is blocked and committed | selftest |
| AC-5.1 | The plugin loads `AGENT_COUNT` agents | `--debug-file` grep, §10.5 |
| AC-5.2 | Both plugin manifests validate `--strict` | manual |
| AC-5.3 | `agents/task.md` exists, is named `task`, and never calls a `slug_*` helper, `slug_set_phase.sh`, `tasks.sh` or `log.sh` | selftest |
| AC-5.4 | `agents/implement.md` names `spectomat:task` and allows the Agent tool; `agents/task.md` forbids it | selftest |
| AC-5.5 | `templates/task.md`'s `## Context` carries the `Purpose`, `Spec, verbatim` and `Codebase` subsections | selftest |
| AC-6.1 | No brief carries a `{{KEY}}` placeholder | selftest |
| AC-6.2 | No brief points at a `prompts/` file, and every phase brief calls a state helper to advance its slug's phase — `slug_set_phase` for the phases that carry no tasks, `scripts/tasks.sh` for `PLAN`, `IMPLEMENT` and `REVIEW` | selftest |
| AC-6.3 | No brief names `result.md`, and none edits `tasks.json` with `jq`, `Write` or `Edit`: `scripts/tasks.sh` is the ledger's only writer | selftest |
| AC-6.3 | `NOTICE.md` names only files that exist | grep, selftest |

### 9.2 End-to-end

| Id | Criterion | Verified by |
| --- | --- | --- |
| E2E-1 | A scratch repo with two drafts runs until the Stop hook reports the flow complete, producing two slug dirs each carrying `done.md` and committed code | `claude -p` run, §10.5 |
| E2E-2 | An iteration killed mid-`IMPLEMENT` leaves a dirty tree; the next iteration's verdict is `RECOVER` and the janitor restores a clean tree | manual, scratch repo |

### 9.3 Non-functional

| Target | Measured by |
| --- | --- |
| `phase.sh` completes in under 200 ms on a floor of 20 plans | `time` in the scratch repo; it is on the path of every iteration and of `status` |
| `selftest.sh` stays under 8s, and one test case — fixture setup plus one subject invocation — costs at or below 200ms | wall time for the total; the per-case figure by A/B against a scratch harness of N identical cases |
| bash 3.2 compatible, no GNU-only flags, `jq` the only non-base dependency | the dependency test in `selftest.sh` |

## 10. Building and testing

### 10.1 Toolchain

bash 3.2, `jq`, no build, no package manager, no network. `scripts/utils.sh` is sourced by every script and sets no shell options; each script chooses its own `set -e/-u/pipefail`.

### 10.2 Configuration contract

| Placeholder | Rendered into | Value |
| --- | --- | --- |
| `{{PLUGIN_ROOT}}` | `pointer_prompt()` in `scripts/utils.sh` (in memory, never a file) | absolute plugin path; locates `scripts/phase.sh`, `scripts/agent-archive.sh` and `agents/*.md` |
| `{{REPO}}` | `contract.md`, `memory.md` | the repository root, substituted at the one and only render |
| `{{GATES}}` | `.spectomat/gates.sh` | the gate lines compiled by `detect_gates` (§5.5), or `GATES_NONE` when none were detected, substituted at the one and only render |

A new placeholder requires a matching value in the `render_template` call in `command-run.sh`. `state.json` has no template: `arm_flow` writes its six fields inline (`active`, `iteration`, `max_iterations`, `session_id`, `started_at`, `slugs`), with `max_iterations` and `iteration` unquoted, `slugs` starting as `{}`, so `parse_args` must keep requiring `^[0-9]+$` for the iteration cap.

### 10.3 Fixtures

The bash equivalent of a port and a fake. Every case in `tests/*.sh` builds one, using the shared fixture helpers in `tests/lib.sh`:

```text
floor(dir, spec):   under a fresh `mktemp -d`, `git init`, then create the
                    floor described by spec — one <slug>/ directory per idea
                    holding its draft, spec, plan overview and a given number
                    of task files (their contents inert — the task counters in
                    state.json carry the progress), a done.md or blocked.md
                    marker and its terminal state.json phase for a finished
                    slug, a state.json with given slugs, phases, task counters,
                    and strikes, a log.md with given strike lines for audit
                    trail, and a gates.sh running given commands
```

State is built programmatically via jq to create the `.slugs` object:

```text
state = {
  active: false,
  iteration: 0,
  max_iterations: 0,
  session_id: "fixture",
  started_at: "1970-01-01T00:00:00Z",
  slugs: {
    <slug1>: {phase: "PLAN", strikes: {SPECIFY: 0, PLAN: 1}},
    <slug2>: {phase: "IMPLEMENT", strikes: {}},
    <slug3>: {phase: "DONE", strikes: {}}
  }
}
```

Cases are then a verdict assertion (`pk NAME want`) or an effect assertion over the resulting tree. Every fixture is a real git repository, because `git status --porcelain` is normative input and must not be stubbed.

### 10.4 The gates

```bash
bash -n scripts/*.sh tests/*.sh templates/gates.sh
scripts/selftest.sh
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

### 10.5 What the gates do not cover

| Not covered | Checked instead by |
| --- | --- |
| whether the runtime loads `AGENT_COUNT` agents | `claude -p … --debug-file <f> --model opus`, then grep `<f>` for `Loaded 8 agents from plugin`; a `-p` prompt asking Claude to list agent types reports NONE even when they are loaded, so it must not be used |
| whether a full flow reaches `FINISH` | `claude -p "/spectomat:run 25" --plugin-dir . --model opus` in a scratch repo with two drafts |
| whether the Stop hook releases against the real runtime | the selftest drives it with a fabricated payload; only a live session proves Claude Code honours the `block` decision |
| whether `command-run.sh` keeps an edited contract | arming twice in a scratch repo, editing `contract.md` between runs |

Nested `claude -p` must always be given `--model opus`; the CLI rejects the default model.

### 10.6 The invariants that must be tests

| Invariant | Why a test and not a rule |
| --- | --- |
| the picker mutates nothing | it is called by `status` on demand and by every iteration; a stray write would corrupt the floor silently |
| `ARCHIVE` never fires on a plan with no task files | the failure archives unbuilt work and is invisible until someone reads the slug dir |
| a blocked slug is still listed by `print_blocked` | a blocked slug that nothing reports is a silently dropped idea |
| a slug at a terminal phase is never archived again | a second `ARCHIVE` would commit over finished work, and would promote a blocked slug to shipped |
| the picker reads no directory | one stat of a slug dir brings back the two-authority reconciliation D27 deleted, and no behavioural test would catch it; enforceable by grepping `scripts/phase.sh` for floor access |
| no brief carries a `{{KEY}}` placeholder | briefs are never rendered, so a placeholder would reach an agent literally |
| the task agent touches no floor state | a worker that advanced `state.json` or logged would make one task two entries, and the phase agent's close would count it twice; enforceable by grepping `agents/task.md` for `slug_` and `log.sh` |
| arming and cancelling touch only `state.json` | a second file for the pointer prompt would need its own cleanup on every disarm path, and could go stale if the plugin moved between arms (D23) |
| only the session that armed a flow may end it, an unreadable state file included | the hook fires in every session of the project, so a guard that runs before the session check lets a stranger delete a flow it does not own |
| `command-run.sh` refuses to arm on a dirty tree | the picker answers `RECOVER` to any dirt, so arming over work in progress spends the entire cap on the janitor |
| `NOTICE.md` names only files that exist | a licence notice pointing at deleted files does not discharge the obligation |
