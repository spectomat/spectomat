# Spectomat

A Claude Code plugin that turns raw ideas into committed, tested code without anyone watching. The operator drops a Markdown draft into `.spectomat/drafts/` and runs `/spectomat:run`; a Stop hook then feeds the session the same pointer prompt over and over, and each pass — an **iteration** — advances exactly one idea by exactly one phase.

The organising idea: **a deterministic picker decides *what* happens, a specialist brief decides *how*, and the project-owned contract holds only the invariants that outlive both.**

Six phases carry an idea end to end: **`SPECIFY`** draft → spec, **`REVIEW-SPEC`** spec → reviewed spec, **`PLAN`** reviewed spec → plan, **`IMPLEMENT`** plan → one task's code, **`REVIEW`** finished plan → a verdict or fix tasks, **`ARCHIVE`** reviewed plan → archive. Five are subagents with their own brief; `ARCHIVE` is a script, because it needs no judgement.

## 1. System Overview

### 1.1 Actors

| Actor | Is | Does |
| --- | --- | --- |
| Operator | the human | drops drafts in `.spectomat/drafts/`, runs `/spectomat:run`, reads `/spectomat:status`, edits `contract.md` and `memory.md` |
| Session | the Claude Code session that ran `/spectomat:run` | holds the flow; per iteration, runs the picker and dispatches one agent or one script; does no factory work |
| Picker | `scripts/phase.sh` | reads the floor, `log.md` and `git status`; prints one line naming the phase |
| Phase agent | `spectomat:specify`, `review-spec`, `plan`, `implement`, `review` | one fresh subagent per iteration; performs one phase and commits it |
| Archiver | `scripts/archive.sh` | performs the `ARCHIVE` phase: gates, moves, commit, log |
| Janitor | `spectomat:recover` | recovers a dirty tree, or a floor the picker cannot classify |

### 1.2 The system in one picture

```text
Stop hook
  └─ session receives pointer.md, fed back by the Stop hook
       │
       ├─ bash {{PLUGIN_ROOT}}/scripts/phase.sh   →  exactly one line
       │
       ├─ "SPECIFY <slug>"    →  Agent(spectomat:specify)     draft → spec
       ├─ "REVIEW-SPEC <slug>" → Agent(spectomat:review-spec) spec → reviewed spec
       ├─ "PLAN <slug>"       →  Agent(spectomat:plan)        reviewed spec → plan
       ├─ "IMPLEMENT <slug>"  →  Agent(spectomat:implement)   plan → next task
       ├─ "REVIEW <slug>"     →  Agent(spectomat:review)      finished plan → verdict
       ├─ "ARCHIVE <slug>"    →  bash scripts/archive.sh <slug>
       ├─ "RECOVER"           →  Agent(spectomat:recover)
       └─ "FINISH"            →  emit <promise>FACTORY EMPTY</promise>
       │
       └─ print at most five lines, stop
```

## 2. Domain Model

The floor is `.spectomat/`: `drafts/`, `specs/`, `plans/`, `done/`, `work/`, plus `log.md`, `contract.md`, `memory.md`, `state.json` and `pointer.md`. The contract's *The floor* section defines it and is not restated here. Three further entities are the system's own.

### 2.1 `verdict`

The picker's entire output. One line on stdout, exit code 0.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | `SPECIFY`\|`REVIEW-SPEC`\|`PLAN`\|`IMPLEMENT`\|`REVIEW`\|`ARCHIVE`\|`FINISH`\|`RECOVER` | which phase applies, or `FINISH` for none, or `RECOVER` for a dirty tree |
| `slug` | string, absent for `FINISH` and `RECOVER` | the draft file name without `.md`, as the operator named it |

Identity: there is exactly one verdict per iteration, and it is not stored — the picker is re-run, never remembered. Written by: `scripts/phase.sh` only.

### 2.2 `strike ledger`

Not a file of its own: the strike count for a `(phase, slug)` pair is derived by counting `(strike N)` markers in `log.md`, which is append-only and gitignored.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | phase name | the phase that was defeated |
| `slug` | string | the slug it was defeated on |
| `count` | integer 0..`STRIKE_LIMIT` | how many times |

Identity: `(phase, slug)`. Written by: any phase agent, and `archive.sh`, by appending a log line. Read by: the picker (§5.2) and `archive.sh` (§5.5).

### 2.3 `gate block`

The fenced `bash` block under `## Verification Gates` in `contract.md`. A script reads it, so its shape is normative.

| Field | Type | Meaning |
| --- | --- | --- |
| `lines` | list of shell commands | every non-empty, non-comment line inside the first fenced `bash` block after the `## Verification Gates` heading |

Identity: one per floor. Written by: `prepare.sh` at first render, and the operator by hand thereafter — never rewritten by the factory (D9). Read by: the `IMPLEMENT` agent and `archive.sh`.

## 3. Behaviour

### 3.1 Trigger and input

Trigger: the Stop hook blocks a session exit and feeds back `pointer.md`. Input: the floor as the previous iteration left it. Idempotency: the picker is a pure function of the floor, `log.md` and `git status`, so running it twice with no intervening change yields the same verdict.

### 3.2 The iteration

1. The session runs `bash {{PLUGIN_ROOT}}/scripts/phase.sh` and reads one line.
2. It dispatches per §3.3.
3. It prints at most five lines of the report and stops, which fires the Stop hook again.

The session reads no contract, no floor file and no source. Its context accumulates one short report per iteration.

### 3.3 Dispatch

| Verdict | Action |
| --- | --- |
| `SPECIFY <slug>` / `REVIEW-SPEC <slug>` / `PLAN <slug>` / `IMPLEMENT <slug>` / `REVIEW <slug>` | launch exactly one subagent, `run_in_background: false`, `subagent_type: "spectomat:<phase>"` when that type is listed; otherwise `general-purpose` with the body of `{{PLUGIN_ROOT}}/agents/<phase>.md` after its frontmatter as the brief |
| `ARCHIVE <slug>` | run `bash {{PLUGIN_ROOT}}/scripts/archive.sh <slug>` |
| `RECOVER` | launch one subagent as above, with `spectomat:recover` / `agents/recover.md` |
| `FINISH` | print the closing report and emit the promise as the last line |

The task line handed to a subagent is two lines: the verdict verbatim, then `Plugin root: <absolute path>`. A brief therefore carries no plugin path of its own but can still reach `templates/`.

The fallback rule is one rule stated once and applied to all six agents; the verdict's first word lowercased is the agent name, so `REVIEW-SPEC` dispatches `spectomat:review-spec` from `agents/review-spec.md`; §6.1 fixes the file names so the fallback path is computable from the phase name.

### 3.4 Failure path

A phase agent that cannot finish appends `(strike N)` to its log line and stops; the next iteration's picker skips that slug in favour of the next candidate in the same stage (§5.2). On its own third strike the agent moves the offending file to `done/<slug>.blocked.md` and logs the reason (D5). `archive.sh` does the same for the `ARCHIVE` phase by moving the whole trail with a `.blocked` infix (§5.5).

An iteration that dies mid-phase leaves a dirty tree; the next picker returns `RECOVER` before any other test, and the janitor either finishes and commits the phase or discards the paths the factory owns.

### 3.5 Completion

The session emits `<promise>FACTORY EMPTY</promise>` if and only if the picker printed `FINISH`. The picker prints `FINISH` only when `drafts/`, `specs/` and `plans/` hold no `.md` files **and** `git status --porcelain` is silent, both evaluated in that invocation.

## 4. Boundaries

Each is an interface the design depends on and does not own.

| Boundary | Interface used | Fake used in tests |
| --- | --- | --- |
| git | `status --porcelain`, `rev-parse --show-toplevel`, `mv`, `add`, `commit`, `log` | a real throwaway repo under `mktemp -d` (§10.3) |
| filesystem | the floor tree | a fabricated floor under `mktemp -d` (§10.3) |
| `log.md` | append-only text, read by `grep` for `(strike N)` | a fabricated log file (§10.3) |
| Claude Code agent runtime | plugin agent types `spectomat:<name>` from `agents/*.md` frontmatter | none; verified out-of-band per §10.5 |
| the operator's gate commands | lines of the gate block, executed with `eval` | fabricated gate blocks, including `false` (§10.3) |

## 5. Normative Algorithms

Named constants, each defined once here and nowhere else in the system:

| Constant | Value | Owned by |
| --- | --- | --- |
| `STRIKE_LIMIT` | 3 | `scripts/utils.sh` |
| `MAX_REVIEW_ROUNDS` | 2 | `agents/review.md` |
| `AGENT_COUNT` | 6 | this spec, asserted by AC-6.1 |

### 5.1 `pick_phase` — `scripts/phase.sh`

```text
pick_phase():
  cd_root()
  if not isdir(FLOOR):                       print "FINISH"; return 0
  if `git status --porcelain` is non-empty:  print "RECOVER"; return 0

  # candidate sets, each a list of slugs
  FINISHED  = [ s for plans/<s>.md : isdir(plans/<s>)
                                     and count(plans/<s>/task-*.md) >= 1
                                     and no line matching '^- \[ \]' in plans/<s>/task-*.md ]
  ARCHIVE   = [ s in FINISHED     : a line matching '^- Verdict: ' in plans/<s>.md ]
  REVIEW    = [ s in FINISHED     : no such line ]
  IMPLEMENT = [ s for plans/<s>.md : any line matching '^- \[ \]' in plans/<s>/task-*.md ]
  REVIEWED  = [ s for specs/<s>.md : a line matching '^- Verdict: ' in specs/<s>.md ]
  PLAN      = [ s in REVIEWED      : not exists(plans/<s>.md)
                                     or count(plans/<s>/task-*.md) == 0 ]
  REVIEW_SPEC = [ s for specs/<s>.md : s not in REVIEWED
                                     and not exists(plans/<s>.md) ]
  SPECIFY   = [ basename(f, '.md') for f in drafts/*.md ]

  for (phase, set) in [ ('ARCHIVE',ARCHIVE), ('REVIEW',REVIEW), ('IMPLEMENT',IMPLEMENT), ('PLAN',PLAN), ('REVIEW-SPEC',REVIEW_SPEC), ('SPECIFY',SPECIFY) ]:
      pick = least_struck(phase, set)
      if pick is not NONE:  print phase + " " + pick; return 0

  if drafts/, specs/ and plans/ hold no .md:  print "FINISH"
  else:                                       print "RECOVER"
  return 0
```

Normative notes, each of which a naive reading would get wrong:

1. **`ARCHIVE` and `REVIEW` are tested before `IMPLEMENT`**, matching the contract's priority: work in progress is finished before anything new starts.
2. **`ARCHIVE` and `REVIEW` split one candidate set on the verdict line.** `FINISHED` is the plan whose every step is ticked; `REVIEW` writes `- Verdict: ...` into the overview, and that line — a one-way latch, never removed — is the only thing that moves a plan from one set to the other. The picker reads it and judges nothing: a plan the `REVIEW` phase sent back for fixes has unchecked steps again, leaves `FINISHED` on its own, and is claimed by `IMPLEMENT` with no extra rule.
3. **`FINISHED` requires at least one task file.** A plan directory with no task files has no unchecked step and would otherwise satisfy it vacuously, reviewing and archiving an unbuilt plan.
4. **`PLAN` also claims a plan overview with no task files** (D7). The `PLAN` phase's output is the overview plus the task files; an overview without them is a `PLAN` phase that did not finish, and re-running it overwrites the overview. Without this clause such a plan matches no stage and is stranded for the life of the floor.
5. **`REVIEW-SPEC` and `PLAN` split the specs on the same kind of latch.** `REVIEW-SPEC` writes `- Verdict: READY` into the spec's §17 and that line is what admits the spec to `PLAN`. A spec is reviewed once, before planning: one that already has a plan overview is never a `REVIEW-SPEC` candidate, so an unreviewed spec with an overview (a floor from before this phase existed, or a hand-placed overview) matches no stage and goes to the janitor.
6. **A floor that matches no stage is `RECOVER`, not `FINISH`.** `FINISH` means finished; a leftover file means an anomaly only the janitor can clear — an orphan plan overview whose spec is gone, or a slug parked at `STRIKE_LIMIT` that was never blocked.
7. **`RECOVER` precedes every stage test**; only the floor-existence guard runs before it. A dirty tree with an empty floor is `archive.sh` having died between its moves and its commit. That reading is sound only because §5.5 checks every mutation: an unchecked failure there can commit a partial move and leave the tree CLEAN, in which case `RECOVER` never fires and the janitor never runs. The picker cannot detect that state — the archiver has to not create it.
8. The picker **never mutates** anything. It is safe to run from `/spectomat:status`.

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
  return number of lines in log.md matching all of:
      ' · ' + phase + ' · ' + slug + ' · '
      '(strike '
```

Returns 0 when `log.md` is absent. The log line format is the contract's.

### 5.4 `gate_block` and `run_gates` — `scripts/utils.sh`

```text
gate_block():
  emit every line that is inside the first fenced bash block following the
  line '## Verification Gates' in CONTRACT, excluding lines that are
  empty or whose first non-space character is '#'

run_gates():
  for cmd in gate_block():
      eval cmd
      if exit status != 0:  return that status
  return 0
```

`eval` is deliberate: the gate block is operator-authored content in a committed file of their own repository, at the same trust level as a `package.json` script (D6). `run_gates` stops at the first failure and reports which command failed.

### 5.5 `archive` — `scripts/archive.sh`

```text
archive(slug):
  cd_root()
  require `git status --porcelain` silent                       else exit 1
  require exists(specs/<slug>.md) and exists(plans/<slug>.md)   else exit 1

  total = count(gate_block())
  if run_gates() != 0:
      n = strike_count('ARCHIVE', slug) + 1
      log '- <ts> · ARCHIVE · <slug> · gate failed: <cmd> (strike ' + n + ')'
      if n >= STRIKE_LIMIT:  block = '.blocked'  and continue to the moves
      else:                  exit 1
  else:
      block = ''

  git mv specs/<slug>.md  done/<slug>.spec<block>.md  or strike_and_exit
  git mv plans/<slug>.md  done/<slug>.plan<block>.md  or strike_and_exit
  if isdir(plans/<slug>):
      git mv plans/<slug>  done/<slug>              or strike_and_exit


  git commit -m 'chore(<slug>): archived' (or '… blocked after 3 strikes')
      or strike_and_exit
  log '- <ts> · ARCHIVE · <slug> · archived · gates <total>/<total>'
```

**Every mutation is checked.** The script runs under `set -uo pipefail` with no `-e`, so a failed command does not abort, and an unchecked failure here is the one defect this design cannot survive: a partial move that still commits leaves a CLEAN tree, so the picker never answers `RECOVER`, the janitor never runs, and a spec whose plan was already archived reads as a fresh `PLAN` phase. `strike_and_exit` logs a strike in the shape `strike_count` counts — so the slug blocks after three — then exits 1 leaving the tree exactly as it landed: dirty for the janitor if a move partially applied, unchanged and safe to retry if none did. Exiting without a strike would wedge the flow, because the picker answers `ARCHIVE` again next iteration and the same move fails again until the cap.

The third strike takes the `.blocked` infix rather than a separate code path, so the moves are written once. `print_blocked` matches `*.blocked.md`.

The log line's numbers are the gate count, not test counts: a script has first-hand knowledge of how many gate commands ran and that every one exited 0, and no knowledge of what any of them printed (D4).

## 6. Architecture

### 6.1 Component map

| File | Role |
| --- | --- |
| `scripts/prepare.sh` | prepares the floor, renders and commits, arms the Stop hook |
| `scripts/phase.sh` | the picker (§5.1) |
| `scripts/archive.sh` | the archiver, the `ARCHIVE` phase (§5.5) |
| `scripts/utils.sh` | shared helpers (§5.2–§5.4), paths, `cd_root`, `state_field`, `render_template`; sourced by every script |
| `scripts/stop-hook.sh` | blocks the session exit, bumps the iteration counter, feeds back the pointer |
| `scripts/status.sh`, `print.sh`, `cancel.sh`, `gates.sh` | operator surface (§7) and gate-command detection |
| `scripts/selftest.sh` | the suite (§10) |
| `agents/specify.md` | draft → spec — `spectomat:specify` |
| `agents/review-spec.md` | spec → reviewed spec — `spectomat:review-spec` |
| `agents/plan.md` | reviewed spec → plan — `spectomat:plan` |
| `agents/implement.md` | plan → next task — `spectomat:implement` |
| `agents/review.md` | finished plan → verdict or fix tasks — `spectomat:review` |
| `agents/recover.md` | the janitor — `spectomat:recover` |
| `templates/contract.md`, `memory.md` | rendered into the project once, then owned by it |
| `templates/pointer.md` | the prompt fed back every iteration, re-rendered every run, gitignored |
| `templates/spec.md`, `plan.md`, `task.md` | the shapes the `SPECIFY`, `REVIEW-SPEC` and `PLAN` phases fill in |
| `templates/guide.md` | the user guide, printed by `/spectomat:help`; holds the glossary |
| `commands/run.md`, `status.md`, `cancel.md`, `help.md` | the four slash commands |
| `hooks/hooks.json` | wires the Stop hook |

### 6.2 The contract

`.spectomat/contract.md` is rendered from the template at the first `/spectomat:run` and never overwritten, so it is **the operator's only steering surface**. It holds the invariants that outlive the briefs: the floor, the Iteration Contract, three strikes, when to gate plus the project's own gate block, how to read and write `memory.md`, the log format, and the constraints.

It holds no phase sections (D3) and no craft prose (D11): text no operator would ever edit is not steering, and belongs in the brief that uses it. What earns a line in `memory.md` lives in that file's own header, not here (D10).

### 6.3 The briefs

Each brief holds the craft of one phase and is read only on that phase's iterations. A brief carries no `{{KEY}}` placeholder — it is never rendered — and no plugin path: the task line supplies one at dispatch (§3.3).

`agents/implement.md` is the largest brief by a wide margin, carrying task execution, TDD and systematic debugging. That is the point of the design and not a smell: the `SPECIFY` phase pays nothing for it.

No brief dispatches another agent. The `IMPLEMENT` phase writes its task's code itself, the `REVIEW-SPEC` phase revises the spec itself and the `REVIEW` phase reads the plan itself, so a brief is only ever read as guidance by the one agent it names — there is no text a phase sends verbatim to somebody else.

### 6.4 The state and the pointer

An armed flow is two gitignored files, created and removed together by `arm_flow()` and `disarm()`:

| File | Holds | Read by | Written by |
| --- | --- | --- | --- |
| `state.json` | `iteration`, `max_iterations`, `session_id`, `started_at` | `stop-hook.sh` (one `jq` call per iteration), `print.sh`, `cancel.sh` | `prepare.sh` at arming; `stop-hook.sh` bumps `iteration` each pass |
| `pointer.md` | the picker call plus the §3.3 dispatch table | fed back verbatim to the session | `prepare.sh` only — never mutated |

Splitting them is what keeps each one honest: the state is data a script parses, the pointer is a prompt a model reads, and neither has to skip past the other. `state.json` is the armed flag — the five existence tests point at it — and `pointer.md` is its payload, so `disarm()` removes both and a pointer can never outlive its counter (D12).

Drafts arrive in `drafts/` already named: the plugin has no intake step (D13). The picker reads them in plain alphabetical order of the file name, which is the operator's only lever on the order they are worked.

## 7. Operator surface

### 7.1 Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the drafts it finds, arms the Stop hook for `n` iterations (default 100), starts iteration 1; refuses when a flow is armed, the floor is empty, or the tree is dirty |
| `/spectomat:status` | the next verdict, the current iteration, floor counts, per-plan step progress, blocked files, log tail |
| `/spectomat:cancel` | disarms the flow; the floor stays and `run` resumes from it |
| `/spectomat:help` | prints `templates/guide.md` |

### 7.2 `status` predicts the next phase

`status.sh` calls `print_next`, which prints a `--- next ---` section holding the picker's verdict verbatim, e.g. `IMPLEMENT 003-auth`. Because it is the identical code path the next iteration takes, the prediction cannot drift from the decision. The picker mutates nothing (§5.1 note 6), so this is safe to run at any time.

### 7.3 Installation

The plugin runs from a cache copy under `~/.claude/plugins/cache/spectomat/`, so a source edit is not live until `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run`.

## 8. Design decisions

| Id | Decision | Rejected | Why |
| --- | --- | --- | --- |
| D1 | A bash picker (`phase.sh`) decides the phase | a thin foreman agent; the session deciding from the contract | deterministic, testable, costs no tokens, and makes a false completion promise structurally impossible |
| D2 | Five phase agents (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`); the `ARCHIVE` phase is `archive.sh` | six agents; two agents (author / builder) | `ARCHIVE` is mechanical — gates, three moves, one commit; a script that exits non-zero on a failing gate is stronger evidence than an agent claiming the gate passed |
| D3 | The contract keeps no phase sections at all | per-phase stubs with a "Project overrides" list | one source per phase; an override mechanism is complexity bought before anyone has needed it |
| D4 | The `ARCHIVE` phase's log line carries the gate count | parsing test counts out of gate output | a script knows how many gates ran and that each exited 0; it cannot know what they printed, and guessing would be the adjective the Log Format forbids |
| D5 | A phase agent performs its own third-strike block-move | the picker detecting the third strike and a `block.sh` doing the move | the agent knows why it failed and must write the reason; the picker stays free of mutation |
| D6 | `run_gates` executes gate lines with `eval` | a restricted parser, or `npm run` only | the gate block is operator-authored content in their own committed repository, at the same trust level as a `package.json` script the factory already runs |
| D7 | `PLAN` also claims a plan overview with no task files | leaving it stranded | otherwise a half-finished `PLAN` phase matches no stage and the plan is unreachable for the life of the floor |
| D8 | The `IMPLEMENT` phase executes exactly one task per iteration, in dependency order | packing file-disjoint ready tasks into one iteration as a "wave" | a wave is the only place where the unit of dispatch differs from the unit of work, and it pays for that with file-disjointness analysis in the `IMPLEMENT` phase, packability planning in the `PLAN` phase, shared-tree race rules, ordered commits and concurrent fix loops. One task per iteration deletes all of it: the picker is unaffected, an iteration stays one commit and one log line, and a task's blast radius is one revert. The cost is iterations, which are cheap and unattended |
| D9 | `prepare.sh` renders `contract.md` once and never rewrites it | a migration that regenerates an old contract from the template, carrying the gate lines across | a migration path can only overwrite the file the operator is told to edit, and one that has never migrated anything is untested weight on the script every run executes |
| D10 | `templates/memory.md`'s own header carries what earns a line; the contract carries only when to read and write it | the rules in both files, kept in step by hand | duplicated rules drift, and keeping them in step was a manual instruction to a human. Every iteration reads `memory.md` in Orient anyway, so the header costs no extra read |
| D11 | Craft prose lives in the brief that uses it — gate-reading in `agents/implement.md`, "`SPECIFY` and `PLAN` skip the gates" in those two briefs | keeping it in the contract, where every phase reads it | the contract is the operator's only editable surface; text no operator would ever edit is craft, not steering, and D3 already put craft in the briefs |
| D12 | An armed flow is `state.json` (data) plus `pointer.md` (prompt), created and removed together | one Markdown file with the state in frontmatter and the prompt in its body | one file forced every reader to parse past the other: `awk '/^---$/{i++; next} i>=2'` in two scripts to reach the prompt, and a `sed \| grep \| sed` pipeline to reach a field. Split, the state is `jq`-addressable in one call and the prompt is a file you `cat`. The names stop competing too — neither file is both things |
| D13 | The operator puts drafts into `drafts/` and names them; `prepare.sh` only commits what it finds there | `prepare.sh` moving `wishlist/*.md` into `drafts/` under a number issued from a committed `.inc` counter | intake is the project's business, not the factory's. It cost a second inbox directory, a counter file with a git lifecycle opposite to the state it sat next to, and staging both ends of every move so arming still ended on a clean tree. Without it the floor has one entrance and drafts are worked in plain alphabetical order of whatever the operator called them |
| D14 | The `IMPLEMENT` phase writes its task's code itself | an implementer subagent it dispatches, reports back from and resumes | the picker already gives one fresh agent per task, so a subagent bought no context isolation and cost a placeholder-filled brief sent verbatim, a report file as the return channel, a `DONE / BLOCKED / NEEDS_CONTEXT` protocol and a re-dispatch rule — all of it deleted. What it loses is real but small: a cheap model for code writing, and a stronger one on the last fix round |
| D15 | `REVIEW` is one phase per plan, run when every task is ticked | a reviewer subagent per task commit, with `MAX_FIX_ROUNDS` fix rounds inside the `IMPLEMENT` phase | per-task review was the one unit of work the picker could not see: no verdict, no log line, no strike, not resumable, a sub-state-machine with its own constant hidden inside another phase. As a phase it is an iteration like any other; its findings become task files that get the full TDD cycle instead of "send the findings back" rounds; and it reads the plan whole, which is the only way to see a helper written twice, code one task orphaned, or an interface that drifted between one task's `Produces` and another's `Consumes`. The cost is latency — a defect in task 1 surfaces after task 8 — bounded because the gates still run on every task and the plan's `Interfaces` rows are what guard the seams |
| D16 | `REVIEW-SPEC` is one phase per spec, run once between `SPECIFY` and `PLAN`, and it revises the spec in place | a self-review checklist inside the `SPECIFY` brief; an approve-or-flag reviewer that sends the spec back to `SPECIFY` | the author cannot read its own spec cold, and the planner is the first reader that can be misled; a fresh agent with only the spec and the draft is the cheapest cold read. It fixes rather than flags because the fix for a spec is a sentence, and a `SPECIFY` round trip would rewrite the whole file to change one line. Each fix is a `revised` row in §10, so the trail is as traceable as an `assumed` one. One round, latched by `- Verdict: READY` in §17, the same grammar as the plan latch, so the picker learns nothing new |

## 9. Acceptance Criteria

### 9.1 Per component

| Id | Criterion | Verified by |
| --- | --- | --- |
| AC-1.1 | `phase.sh` prints exactly one line and exits 0 for every floor state in §10.3 | selftest |
| AC-1.2 | Priority holds: with candidates in all six stages, the verdict is `ARCHIVE` | selftest |
| AC-1.3 | A plan directory with zero `task-*.md` files does not yield `ARCHIVE` | selftest |
| AC-1.4 | A reviewed spec whose plan overview exists but has zero task files yields `PLAN` | selftest |
| AC-1.6 | A spec with no `- Verdict: ` line and no plan overview yields `REVIEW-SPEC`; with the line it yields `PLAN` | selftest |
| AC-1.7 | A strike logged at `REVIEW-SPEC` does not count at `REVIEW`, nor the reverse | selftest |
| AC-1.5 | A dirty tree yields `RECOVER`, even when the floor is empty | selftest |
| AC-1.6 | `FINISH` requires all three directories empty **and** a silent `git status` | selftest |
| AC-1.7 | Given two candidates in one stage, the one with fewer strikes is named | selftest |
| AC-1.8 | A candidate at `STRIKE_LIMIT` is skipped; if all are, the next stage is used | selftest |
| AC-1.9 | `phase.sh` leaves the floor and the git index byte-identical | selftest |
| AC-2.1 | `gate_block` returns the operator's edited lines, dropping comments and blanks | selftest |
| AC-2.2 | `run_gates` returns non-zero on the first failing line and names it | selftest |
| AC-2.3 | `strike_count` returns 0 when `log.md` is absent | selftest |
| AC-3.1 | `archive.sh` with a failing gate moves nothing and exits non-zero | selftest |
| AC-3.2 | `archive.sh` logs `(strike N)` with N one higher than the log showed | selftest |
| AC-3.3 | At the third strike `archive.sh` moves the trail with the `.blocked` infix, and `print_blocked` lists both files | selftest |
| AC-3.4 | `archive.sh` makes exactly one commit, and touches no file outside the floor | selftest |
| AC-4.1 | `status.sh` prints the picker's verdict verbatim | manual, scratch repo |
| AC-4.2 | Arming writes a valid `state.json` with `iteration` 1 and a numeric `max_iterations`, and a `pointer.md` with no frontmatter and no unresolved `{{KEY}}` | selftest |
| AC-4.3 | `/spectomat:cancel` removes both `state.json` and `pointer.md`, and keeps the floor | selftest |
| AC-4.4 | `prepare.sh` commits a draft dropped into `drafts/`, tracked or not, and leaves a clean tree | selftest |
| AC-4.6 | `prepare.sh` refuses to arm when anything outside the floor is uncommitted | selftest |
| AC-4.7 | The Stop hook blocks the exit for the owning session, bumps `iteration`, and feeds back `pointer.md` verbatim | selftest |
| AC-4.8 | A session that did not arm the flow neither advances nor ends it, and an unreadable state file is left in place for `/spectomat:cancel` | selftest |
| AC-4.9 | The promise and the iteration cap both disarm the flow | selftest |
| AC-4.5 | Drafts are taken in alphabetical order of the file name, whatever their modification times | selftest |
| AC-5.1 | The plugin loads `AGENT_COUNT` agents | `--debug-file` grep, §10.5 |
| AC-5.2 | Both plugin manifests validate `--strict` | manual |
| AC-6.1 | No brief carries a `{{KEY}}` placeholder | selftest |
| AC-6.2 | No brief points at a `prompts/` file, and `agents/review.md` and `agents/review-spec.md` each write the `- Verdict: ` line §5.1 greps | selftest |
| AC-6.3 | `NOTICE.md` names only files that exist | grep, selftest |

### 9.2 End-to-end

| Id | Criterion | Verified by |
| --- | --- | --- |
| E2E-1 | A scratch repo with two drafts runs to `<promise>FACTORY EMPTY</promise>`, producing two archived trails and committed code | `claude -p` run, §10.5 |
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
| `{{PLUGIN_ROOT}}` | `pointer.md` | absolute plugin path; locates `scripts/phase.sh`, `scripts/archive.sh` and `agents/*.md` |
| `{{REPO}}` | `contract.md`, `memory.md` | the repository root, substituted at the one and only render |
| `{{GATES}}` | `contract.md` | the gate command compiled by `gates.sh`, substituted at the one and only render |

A new placeholder requires a matching value in the `render_template` call in `prepare.sh`. `state.json` has no template: `arm_flow` writes its four fields inline, with `max_iterations` unquoted, so `parse_args` must keep requiring `^[0-9]+$`.

### 10.3 Fixtures

The bash equivalent of a port and a fake. Every case in `selftest.sh` builds one:

```text
floor(dir, spec):   under a fresh `mktemp -d`, `git init`, then create the
                    floor described by spec — drafts, specs, plan overviews,
                    task files with a given number of ticked and open steps,
                    a log.md with given strike lines, and a contract.md with
                    a given gate block
```

Cases are then a verdict assertion (`pk NAME want`) or an effect assertion over the resulting tree. Every fixture is a real git repository, because `git status --porcelain` is normative input and must not be stubbed.

### 10.4 The gates

```bash
bash -n scripts/*.sh
scripts/selftest.sh
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

### 10.5 What the gates do not cover

| Not covered | Checked instead by |
| --- | --- |
| whether the runtime loads `AGENT_COUNT` agents | `claude -p … --debug-file <f> --model opus`, then grep `<f>` for `Loaded 6 agents from plugin`; a `-p` prompt asking Claude to list agent types reports NONE even when they are loaded, so it must not be used |
| whether a full flow reaches the promise | `claude -p "/spectomat:run 25" --plugin-dir . --model opus` in a scratch repo with two drafts |
| whether the Stop hook releases against the real runtime | the selftest drives it with a fabricated payload; only a live session proves Claude Code honours the `block` decision |
| whether `prepare.sh` keeps an edited contract | arming twice in a scratch repo, editing `contract.md` between runs |

Nested `claude -p` must always be given `--model opus`; the CLI rejects the default model.

### 10.6 The invariants that must be tests

| Invariant | Why a test and not a rule |
| --- | --- |
| the picker mutates nothing | it is called by `status` on demand and by every iteration; a stray write would corrupt the floor silently |
| `ARCHIVE` never fires on a plan with no task files | the failure archives unbuilt work and is invisible until someone reads `done/` |
| a `.blocked` trail is still listed by `print_blocked` | a blocked slug that nothing reports is a silently dropped idea |
| no brief carries a `{{KEY}}` placeholder | briefs are never rendered, so a placeholder would reach an agent literally |
| arming and cancelling touch both `state.json` and `pointer.md` | a pointer outliving its state would be fed back to a later flow with no counter behind it; a state without a pointer stops the flow with a corruption message |
| only the session that armed a flow may end it, an unreadable state file included | the hook fires in every session of the project, so a guard that runs before the session check lets a stranger delete a flow it does not own |
| `prepare.sh` refuses to arm on a dirty tree | the picker answers `RECOVER` to any dirt, so arming over work in progress spends the entire cap on the janitor |
| `NOTICE.md` names only files that exist | a licence notice pointing at deleted files does not discharge the obligation |
