# Spectomat — phase-specialized agents

Spectomat runs one generic `looper` subagent per loop; that looper reads a 179-line contract, decides for itself which of four phases applies, and does it. This design replaces the looper with three phase-specialized agents, a bash picker that decides the phase, and a script for the one phase that needs no judgement. The organising idea: **a deterministic picker decides *what* happens, a specialist brief decides *how*, and the project-owned contract holds only the invariants that outlive both.**

Code cites this document by section and line (`§3.4 L316`). Part I is normative: the build follows it and never edits it. A divergence found during the build is a **reconciliation**, recorded in §11 with a number and a reason.

# Part I — Specification

## 1. System Overview

### 1.1 Purpose

Give each phase of the factory room to be precise. Phase C gets 11 lines of the current contract because a longer treatment would bury phase A; a dedicated brief can carry 80 lines of wave discipline at no cost to the other phases, because it is read only on phase C loops.

Three secondary outcomes fall out of the same change, and are normative goals, not side effects:

1. The completion promise stops being a model's claim and becomes a relayed bash verdict (§3.5, §5.1).
2. The five-hop `references/` path (plugin → `run.sh` → `{{PLUGIN_ROOT}}` → task line → agent → file) disappears; each reference becomes the brief that uses it (§6.3).
3. `/spectomat:status` stops summarising counts and starts predicting the next phase, by calling the same picker the next loop will call (§7.2).

### 1.2 Actors

| Actor | Is | Does |
| --- | --- | --- |
| Operator | the human | drops drafts in `wishlist/`, runs `/spectomat:run`, reads `/spectomat:status`, edits `contract.md` and `memory.md` |
| Session | the Claude Code session that ran `/spectomat:run` | holds the flow; per loop, runs the picker and dispatches one agent or one script; does no factory work |
| Picker | `scripts/phase.sh` | reads the floor, `log.md` and `git status`; prints one line naming the phase |
| Phase agent | `spectomat:phase-a`, `phase-b`, `phase-c` | one fresh subagent per loop; performs one phase and commits it |
| Archiver | `scripts/archive.sh` | performs phase D: gates, moves, version bump, commit, log |
| Janitor | `spectomat:recover` | performs recovery when a loop died mid-phase and left a dirty tree |
| Implementer / Reviewer | subagents of the phase C agent | unchanged; `prompts/implementer.md`, `prompts/reviewer.md` |

### 1.3 The system in one picture

Illustrative.

```text
Stop hook (unchanged)
  └─ session receives the pointer prompt from state.md
       │
       ├─ bash {{PLUGIN_ROOT}}/scripts/phase.sh   →  exactly one line
       │
       ├─ "A <slug>"  →  Agent(spectomat:phase-a)   draft → spec
       ├─ "B <slug>"  →  Agent(spectomat:phase-b)   spec → plan
       ├─ "C <slug>"  →  Agent(spectomat:phase-c)   plan → wave
       ├─ "D <slug>"  →  bash scripts/archive.sh <slug>
       ├─ "R"         →  Agent(spectomat:recover)
       └─ "E"         →  emit <promise>FACTORY EMPTY</promise>
       │
       └─ print at most five lines, stop
```

## 2. Domain Model

The floor (`drafts/`, `specs/`, `plans/`, `done/`, `log.md`, `contract.md`, `memory.md`, `state.md`, `work/`) is unchanged and is not restated here; see the contract's *The floor* section, which survives the cut (§6.2). Three entities are new or newly explicit.

### 2.1 `verdict`

The picker's entire output. One line on stdout, exit code 0.

| Field | Type | Meaning |
| --- | --- | --- |
| `letter` | `A`\|`B`\|`C`\|`D`\|`E`\|`R` | which phase applies, or `E` for none, or `R` for a dirty tree |
| `slug` | string, absent for `E` and `R` | the draft file name without `.md`, including its `NNN-` prefix |

Identity: there is exactly one verdict per loop, and it is not stored — the picker is re-run, never remembered. Written by: `scripts/phase.sh` only.

### 2.2 `strike ledger`

Not a file of its own: the strike count for a `(letter, slug)` pair is derived by counting `(strike N)` markers in `log.md`, which is append-only and gitignored.

| Field | Type | Meaning |
| --- | --- | --- |
| `letter` | phase letter | the phase that was defeated |
| `slug` | string | the slug it was defeated on |
| `count` | integer 0..`STRIKE_LIMIT` | how many times |

Identity: `(letter, slug)`. Written by: any phase agent, and `archive.sh`, by appending a log line. Read by: the picker (§5.2) and `archive.sh` (§5.5).

### 2.3 `gate block`

The fenced `bash` block under `## Verification Gates` in `contract.md`. Already exists; what is new is that a script must now read it, so its shape becomes normative.

| Field | Type | Meaning |
| --- | --- | --- |
| `lines` | list of shell commands | every non-empty, non-comment line inside the first fenced `bash` block after the `## Verification Gates` heading |

Identity: one per floor. Written by: `run.sh` at first render, and the operator by hand thereafter. Read by: the phase C agent, `archive.sh`, and `run.sh` during migration (§8.1).

## 3. Behaviour

### 3.1 Trigger and input

Trigger: the Stop hook blocks a session exit and feeds back the body of `state.md`. Input: the floor as the previous loop left it. Idempotency: the picker is a pure function of the floor, `log.md` and `git status`, so running it twice with no intervening change yields the same verdict.

### 3.2 The loop

1. The session runs `bash {{PLUGIN_ROOT}}/scripts/phase.sh` and reads one line.
2. It dispatches per §3.3, passing the verdict line verbatim as the task line.
3. It prints at most five lines of the report and stops, which fires the Stop hook again.

The session reads no contract, no floor file and no source. Its context accumulates one short report per loop, as today.

### 3.3 Dispatch

| Verdict | Action |
| --- | --- |
| `A <slug>` / `B <slug>` / `C <slug>` | launch exactly one subagent, `run_in_background: false`, `subagent_type: "spectomat:phase-<letter>"` when that type is listed; otherwise `general-purpose` with the body of `{{PLUGIN_ROOT}}/agents/phase-<letter>.md` after its frontmatter as the brief |
| `D <slug>` | run `bash {{PLUGIN_ROOT}}/scripts/archive.sh <slug>` |
| `R` | launch one subagent as above, with `spectomat:recover` / `agents/recover.md` |
| `E` | print the closing report and emit the promise as the last line |

The fallback rule is one rule stated once and applied to all four agents; §6.1 fixes the file names so the fallback path is computable from the letter.

### 3.4 Failure path

A phase agent that cannot finish appends `(strike N)` to its log line and stops; the next loop's picker skips that slug in favour of the next candidate in the same stage (§5.2). On its own third strike the agent moves the offending file to `done/<slug>.blocked.md` and logs the reason (D5). `archive.sh` does the same for phase D by moving the whole trail with a `.blocked` infix (§5.5).

A loop that dies mid-phase leaves a dirty tree; the next picker returns `R` before any other test, and the janitor either finishes and commits the phase or discards the paths the factory owns.

### 3.5 Completion

The session emits `<promise>FACTORY EMPTY</promise>` if and only if the picker printed `E`. The picker prints `E` only when `drafts/`, `specs/` and `plans/` hold no `.md` files **and** `git status --porcelain` is silent, both evaluated in that invocation. The Stop hook's `promised_empty` test is unchanged.

## 4. Boundaries

Each is an interface the design depends on and does not own.

| Boundary | Interface used | Fake used in tests |
| --- | --- | --- |
| git | `status --porcelain`, `rev-parse --show-toplevel`, `mv`, `add`, `commit`, `log` | a real throwaway repo under `mktemp -d` (§14) |
| filesystem | the floor tree | a fabricated floor under `mktemp -d` (§14) |
| `log.md` | append-only text, read by `grep` for `(strike N)` | a fabricated log file (§14) |
| npm | `npm version --no-git-tag-version <v>` | skipped when no `package.json`; asserted on a fixture `package.json` |
| Claude Code agent runtime | plugin agent types `spectomat:<name>` from `agents/*.md` frontmatter | none; verified out-of-band per §15.2 |
| the operator's gate commands | lines of the gate block, executed with `eval` | fabricated gate blocks, including `false` (§14) |

## 5. Normative Algorithms

Named constants, each defined once here and nowhere else in the system:

| Constant | Value | Owned by |
| --- | --- | --- |
| `STRIKE_LIMIT` | 3 | `scripts/utils.sh` |
| `MAX_WAVE` | 3 | `agents/phase-c.md` |
| `MAX_FIX_ROUNDS` | 3 | `agents/phase-c.md` |
| `AGENT_COUNT` | 4 | this spec, asserted by AC-6.1 |

### 5.1 `pick_phase` — `scripts/phase.sh`

```text
pick_phase():
  cd_root()
  if not isdir(FLOOR):                       print "E"; return 0
  if `git status --porcelain` is non-empty:  print "R"; return 0

  # candidate sets, each a list of slugs
  D = [ s for plans/<s>.md : isdir(plans/<s>)
                             and count(plans/<s>/task-*.md) >= 1
                             and no line matching '^- \[ \]' in plans/<s>/task-*.md ]
  C = [ s for plans/<s>.md : any line matching '^- \[ \]' in plans/<s>/task-*.md ]
  B = [ s for specs/<s>.md : not exists(plans/<s>.md)
                             or count(plans/<s>/task-*.md) == 0 ]
  A = [ basename(f, '.md') for f in drafts/*.md ]

  for (letter, set) in [ ('D',D), ('C',C), ('B',B), ('A',A) ]:
      pick = least_struck(letter, set)
      if pick is not NONE:  print letter + " " + pick; return 0

  print "E"; return 0
```

Normative notes, each of which a naive reading would get wrong:

1. **`D` is tested before `C`**, matching the contract's priority: work in progress is finished before anything new starts.
2. **`D` requires at least one task file.** A plan directory with no task files has no unchecked step and would otherwise satisfy `D` vacuously, archiving an unbuilt plan.
3. **`B` also claims a plan overview with no task files.** Phase B's output is the overview plus the task files; an overview without them is a phase B that did not finish, and re-running B overwrites it. Without this clause such a plan matches no stage and is stranded for the life of the floor. This is a defect in the current contract, fixed here.
4. **`R` precedes every stage test and `E`**; only the floor-existence guard runs before it. A dirty tree with an empty floor is `archive.sh` having died between its moves and its commit.
5. The picker **never mutates** anything. It is safe to run from `/spectomat:status`.

### 5.2 `least_struck` — `scripts/utils.sh`

```text
least_struck(letter, set):
  if set is empty:  return NONE
  scored = [ (strike_count(letter, s), s) for s in set ]
  eligible = [ (n, s) in scored : n < STRIKE_LIMIT ]
  if eligible is empty:  return NONE            # fall through to the next stage
  sort eligible by (n ascending, s ascending)
  return the s of the first
```

A slug at `STRIKE_LIMIT` is skipped so a failed block-move cannot wedge the factory; if every candidate of a stage is skipped, the stage is treated as empty and the next stage is tried.

### 5.3 `strike_count` — `scripts/utils.sh`

```text
strike_count(letter, slug):
  return number of lines in log.md matching all of:
      ' · ' + letter + ' · ' + slug + ' · '
      '(strike '
```

Returns 0 when `log.md` is absent. The log line format is the contract's, unchanged.

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
  require `git status --porcelain` silent          else exit 1
  require exists(specs/<slug>.md) and exists(plans/<slug>.md)  else exit 1

  total = count(gate_block())
  if run_gates() != 0:
      n = strike_count('D', slug) + 1
      log '- <ts> · D · <slug> · gate failed: <cmd> (strike ' + n + ')'
      if n >= STRIKE_LIMIT:  block = '.blocked'  and continue to the moves
      else:                  exit 1
  else:
      block = ''

  git mv specs/<slug>.md  done/<slug>.spec<block>.md
  git mv plans/<slug>.md  done/<slug>.plan<block>.md
  git mv plans/<slug>     done/<slug>

  if exists(package.json) and block == '':
      N = slug's NNN prefix as an integer
      npm version --no-git-tag-version <major>.<minor>.<N>

  git commit -m 'chore(<slug>): archived' (or '… blocked after 3 strikes')
  log '- <ts> · D · <slug> · archived · gates <total>/<total> · v<version>'
```

The third strike takes the `.blocked` infix rather than a separate code path, so the moves are written once. `print_blocked` already matches `*.blocked.md` and needs no change.

The log line's numbers are the gate count and the new version, not test counts: a script has first-hand knowledge of how many gate commands ran and that every one exited 0, and no knowledge of what any of them printed. This is a deliberate narrowing of what a phase D log line carries (D4).

## 6. Architecture

### 6.1 Component map

New:

| File | Role | Agent type |
| --- | --- | --- |
| `scripts/phase.sh` | §5.1 | — |
| `scripts/archive.sh` | §5.5 | — |
| `agents/phase-a.md` | draft → spec | `spectomat:phase-a` |
| `agents/phase-b.md` | spec → plan | `spectomat:phase-b` |
| `agents/phase-c.md` | plan → wave | `spectomat:phase-c` |
| `agents/recover.md` | dirty-tree recovery | `spectomat:recover` |

Deleted: `agents/looper.md`, and all five files of `references/`.

Changed: `templates/state.md`, `templates/contract.md`, `scripts/utils.sh`, `scripts/run.sh`, `scripts/selftest.sh`, `scripts/print.sh`, `scripts/status.sh`, `README.md`, `.claude/CLAUDE.md`, `templates/guide.md`, `NOTICE.md`, `.claude-plugin/plugin.json`.

Untouched: `hooks/hooks.json`, `scripts/stop-hook.sh`, `scripts/cancel.sh`, `scripts/gates.sh`, `prompts/`, `templates/{spec,plan,task,memory}.md`, `commands/`.

### 6.2 The contract after the cut

Survives, unchanged in intent: the opening paragraphs, `Repository`, `The floor`, `The Loop Contract`, `Three strikes`, `Verification Gates`, `Memory`, `Log Format`, `Constraints`.

Leaves:

| Removed | Because |
| --- | --- |
| `## Phases` (45 lines) | moved to the briefs of §6.1 |
| `References:` line | `references/` no longer exists |
| Loop Contract step 2, *"Pick exactly one phase"* | the picker decides; the step becomes *"do the phase you were handed"* |
| `## Completion` | §3.5; the session relays a bash verdict |
| constraint *"DO NOT Emit a false promise"* | structurally impossible once bash emits `E` |
| constraint *"DO NOT more than one phase in a loop"* | an agent that only knows one phase cannot do two |

Target: ~105 lines, every one of them about *this project* rather than about the craft of a phase.

### 6.3 Where each reference lands

| Reference file | Lands in |
| --- | --- |
| `writing-specs.md` | `agents/phase-a.md` |
| `writing-plans.md` | `agents/phase-b.md` |
| `executing-tasks.md` | `agents/phase-c.md` |
| `test-driven-development.md` | `agents/phase-c.md` |
| `systematic-debugging.md` | `agents/phase-c.md` |

`prompts/implementer.md` and `prompts/reviewer.md` stay files, because phase C sends their text verbatim to subagents rather than reading them as guidance.

`agents/phase-c.md` is expected to be the largest brief by a wide margin. That is the point of the design and not a smell: it is loaded only on phase C loops.

Each brief carries no `{{KEY}}` placeholder (it is never rendered) and no plugin path (the task line carries the slug; nothing else is needed). This preserves the existing property of `agents/looper.md`.

### 6.4 The pointer

`templates/state.md` keeps its frontmatter (`active`, `loop`, `session_id`, `max_loops`, `started_at`) and its `{{PLUGIN_ROOT}}` placeholder. Its body becomes the picker call plus the §3.3 dispatch table. `stop-hook.sh` reads the body with `awk '/^---$/{i++; next} i>=2'` and is unaffected by its content.

## 7. Operator surface

### 7.1 Commands

`/spectomat:run`, `:status`, `:cancel`, `:help` keep their names, arguments and behaviour.

### 7.2 `status` gains a prediction

`status.sh` calls `phase.sh` and prints its verdict as a new first line of the floor section, e.g. `next: C · 003-auth`. Because it is the identical code path the next loop takes, the prediction cannot drift from the decision. The picker mutates nothing (§5.1 note 5), so this is safe to run at any time.

### 7.3 Text that names the removed mechanism

Three user-visible strings assert that the model decides completion and must be corrected, or they will contradict §3.5:

| Location | Currently says |
| --- | --- |
| `scripts/run.sh` `announce()` | *"To finish, output … ONLY when drafts/, specs/ and plans/ are all empty … Never output a false promise to escape."* |
| `scripts/stop-hook.sh` `continue_loop()` `system_msg` | *"ONLY when the statement is TRUE - do not lie to exit!"* |
| `templates/guide.md` | the Flow, Loops Mechanics and Glossary sections, which define **Looper** |

### 7.4 Glossary changes

`.claude/CLAUDE.md` requires the guide's terms to be used consistently and without synonyms, so the vocabulary change is normative.

| Term | Change |
| --- | --- |
| **Looper** | removed |
| **Phase agent** | new: the subagent that performs one phase — `spectomat:phase-a`, `phase-b`, `phase-c` |
| **Picker** | new: `scripts/phase.sh`, which decides the phase of a loop and prints one verdict line |
| **Archiver** | new: `scripts/archive.sh`, which performs phase D |
| **Janitor** | new: `spectomat:recover`, which recovers a dirty tree |
| **Verdict** | new: the picker's one-line output (§2.1) |
| **Loop** | amended: one picker verdict, one phase, one commit, one log line |

## 8. Migration

### 8.1 Existing floors

`contract.md` is rendered once and never overwritten, so an armed floor keeps a contract whose `## Phases` section contradicts the new briefs. `render_factory()` in `run.sh` gains a migration branch:

```text
migrate_contract():
  if not exists(CONTRACT):            return        # first render, nothing to migrate
  if CONTRACT has no '^## Phases':    return        # already migrated
  gates = gate_block()                              # the operator's lines, preserved verbatim
  render templates/contract.md over CONTRACT with REPO and GATES=gates
  stage CONTRACT for the floor-setup commit
  report 'contract.md: migrated to the phase-agent contract (gates preserved)'
```

The previous text stays recoverable in git history, because `contract.md` is committed. `memory.md` is untouched by the migration: it belongs to the project.

Known floor requiring this: `~/Projects/telegator` — idle, `drafts/`, `specs/` and `plans/` all empty, no `state.md`.

### 8.2 Future migrations

The new contract carries a marker `<!-- spectomat-contract: 2 -->` as its first line, so the next migration greps a version rather than a section name that may itself have moved (D7).

### 8.3 Installation

`.claude-plugin/plugin.json` version is bumped; the operator reinstalls and restarts Claude Code, because the plugin runs from a cache copy. A project with an active flow needs `/spectomat:cancel` then `/spectomat:run`.

### 8.4 Licence

`NOTICE.md` names four superpowers-derived files by path under `references/`. When they dissolve, the attribution moves with them: the notice must name `agents/phase-b.md` and `agents/phase-c.md` as the files carrying condensed superpowers material, and describe the change. This is a licence obligation, not documentation housekeeping.

## 9. Acceptance Criteria

### 9.1 Per component

| Id | Criterion | Verified by |
| --- | --- | --- |
| AC-1.1 | `phase.sh` prints exactly one line and exits 0 for every floor state in §14 | selftest |
| AC-1.2 | Priority holds: with candidates in all four stages, the verdict is `D` | selftest |
| AC-1.3 | A plan directory with zero `task-*.md` files does not yield `D` | selftest |
| AC-1.4 | A spec whose plan overview exists but has zero task files yields `B` | selftest |
| AC-1.5 | A dirty tree yields `R`, even when the floor is empty | selftest |
| AC-1.6 | `E` requires all three directories empty **and** a silent `git status` | selftest |
| AC-1.7 | Given two candidates in one stage, the one with fewer strikes is named | selftest |
| AC-1.8 | A candidate at `STRIKE_LIMIT` is skipped; if all are, the next stage is used | selftest |
| AC-1.9 | `phase.sh` leaves the floor and the git index byte-identical | selftest |
| AC-2.1 | `gate_block` returns the operator's edited lines, dropping comments and blanks | selftest |
| AC-2.2 | `run_gates` returns non-zero on the first failing line and names it | selftest |
| AC-2.3 | `strike_count` returns 0 when `log.md` is absent | selftest |
| AC-3.1 | `archive.sh` with a failing gate moves nothing and exits non-zero | selftest |
| AC-3.2 | `archive.sh` logs `(strike N)` with N one higher than the log showed | selftest |
| AC-3.3 | At the third strike `archive.sh` moves the trail with the `.blocked` infix, and `print_blocked` lists both files | selftest |
| AC-3.4 | `archive.sh` sets the patch version to the slug's `NNN` as an integer, keeping major and minor | selftest |
| AC-3.5 | `archive.sh` makes exactly one commit | selftest |
| AC-4.1 | `migrate_contract` rewrites a contract containing `## Phases` and preserves the gate lines verbatim | selftest |
| AC-4.2 | `migrate_contract` is a no-op on a contract carrying the §8.2 marker | selftest |
| AC-5.1 | `status.sh` prints the picker's verdict verbatim | manual, scratch repo |
| AC-6.1 | The plugin loads `AGENT_COUNT` agents | `--debug-file` grep, §15.2 |
| AC-6.2 | Both plugin manifests validate `--strict` | manual |
| AC-7.1 | No file under `scripts/`, `agents/` or `templates/` mentions `references/` or `looper` | grep, selftest |
| AC-7.2 | `NOTICE.md` names only files that exist | grep, selftest |

### 9.2 End-to-end

| Id | Criterion | Verified by |
| --- | --- | --- |
| E2E-1 | A scratch repo with two drafts runs to `<promise>FACTORY EMPTY</promise>`, producing two archived trails and committed code | `claude -p` run, §15.2 |
| E2E-2 | The `telegator` floor migrates on the next `/spectomat:run`: contract rewritten, gate lines unchanged, `memory.md` untouched | manual |
| E2E-3 | A loop killed mid-phase C leaves a dirty tree; the next loop's verdict is `R` and the janitor restores a clean tree | manual, scratch repo |

### 9.3 Non-functional

| Target | Measured by |
| --- | --- |
| `phase.sh` completes in under 200 ms on a floor of 20 plans | `time` in the scratch repo; it is on the path of every loop and of `status` |
| `selftest.sh` stays under 8s, and one test case — fixture setup plus one subject invocation — costs at or below 200ms | wall time for the total; the per-case figure by A/B against a scratch harness of N identical cases |
| bash 3.2 compatible, no GNU-only flags, `jq` the only non-base dependency | the existing dependency test in `selftest.sh`, extended |

## 10. Decisions

| Id | Date | Decision | Rejected | Why |
| --- | --- | --- | --- | --- |
| D1 | 2026-09-11 | A bash picker (`phase.sh`) decides the phase | a thin foreman agent; the session deciding from the contract | deterministic, testable, costs no tokens, and makes a false completion promise structurally impossible |
| D2 | 2026-09-11 | Three phase agents (A, B, C); phase D is `archive.sh` | four agents; two agents (author / builder) | D is mechanical — gates, three moves, a version bump; a script that exits non-zero on a failing gate is stronger evidence than an agent claiming the gate passed |
| D3 | 2026-09-11 | The contract keeps no phase sections at all | per-phase stubs with a "Project overrides" list | one source per phase; an override mechanism is complexity bought before anyone has needed it |
| D4 | 2026-09-11 | Phase D's log line carries the gate count and the new version | parsing test counts out of gate output | a script knows how many gates ran and that each exited 0; it cannot know what they printed, and guessing would be the adjective the Log Format forbids |
| D5 | 2026-09-11 | A phase agent performs its own third-strike block-move | the picker detecting the third strike and a `block.sh` doing the move | the agent knows why it failed and must write the reason; the picker stays free of mutation |
| D6 | 2026-09-11 | `run_gates` executes gate lines with `eval` | a restricted parser, or `npm run` only | the gate block is operator-authored content in their own committed repository, at the same trust level as a `package.json` script the factory already runs |
| D7 | 2026-09-11 | The new contract carries a `<!-- spectomat-contract: 2 -->` marker | grepping `## Phases` forever | this migration greps a section name that is being removed; the next one needs a marker that does not move |
| D8 | 2026-09-11 | `B` also claims a plan overview with no task files | leaving it stranded, as today | otherwise a half-finished phase B matches no stage and the plan is unreachable for the life of the floor |

## 11. Reconciliations

Filled during the build. One row per divergence from Part I.

| Id | Sections | Contradiction | Reading built to |
| --- | --- | --- | --- |
| R1 | §5.1, §3.5 | The `pick_phase` pseudocode prints `E` once no stage matches, but §3.5 and AC-1.6 require `E` to mean all three directories are empty. A floor can match no stage and still hold files: an orphan plan overview whose spec was deleted, or a slug parked at `STRIKE_LIMIT` that was never blocked. | After the four stages the picker prints `E` only when `drafts/`, `specs/` and `plans/` are empty; anything left over prints `R`. The janitor's brief widens from "a dirty tree" to "a dirty tree, or a floor the picker could not classify", and gains the two block-moves that clear those cases. |
| R2 | §3.3, §6.4 | The task line is specified as the verdict line verbatim, but phase A must read `templates/spec.md`, phase B `templates/plan.md` and `templates/task.md`, and phase C `prompts/implementer.md` and `prompts/reviewer.md` — all plugin files reachable only by absolute path. | The task line is two lines: the verdict, then `Plugin root: <absolute path>`. §6.3 is unaffected — a brief still carries no plugin path of its own; it is told one at dispatch, exactly as the old task line told the looper where `references/` lived. |
| R3 | §9.3 | The non-functional target "`selftest.sh` still runs in under a second" was carried over from the file's own header, written when the suite was 29 pure-text assertions that spawned no subprocesses. The suite this spec designs creates roughly 36 real repositories and runs ~120 assertions, most through command substitutions that spawn a subprocess each. At Task 3 it measured 0.904s, 1.213s and 1.295s across three runs, with user time steady at 0.35-0.39s — the variance is filesystem and process-spawn time, not computation. | The target becomes three seconds, and gains a second half the one-second figure never had: the marginal cost of one `floor()` call must stay at or below ~20ms. This is a recalibration to what is being measured, not a weakened gate — the per-call cost IMPROVED 8-10x in Task 2 (from ~150ms), and the per-call clause is what would catch a real regression, which a wall-clock total cannot once the suite's scope grows. The "no network" half of the constraint is untouched. |
| R4 | §9.3, R3 | R3 kept a wall-clock total and added a per-`floor()`-call clause, on a measurement of ~15-20ms per call. That measurement was sound but measured the wrong unit: it appended BARE `floor()` calls, and a bare floor is the cheap part. Task 4 added ~14 real cases and the suite rose ~2s — ~140ms per case, seven times the figure R3 was built on. A guard aimed at the wrong quantity gives false assurance, which is worse than a guard set too loose. | Measured attribution, N=14 per case on a scratch harness: a bare `floor()` costs ~17ms; each fixture helper that commits (`draft`, `spec`, `plan`, `plan_bare`) costs ~52ms, spawning three subprocesses; and one `phase.sh` invocation costs ~68ms on an empty floor and ~94ms on a populated one. The subject under test is therefore as expensive as the fixtures, and its cost is irreducible without deleting coverage. So the unit changes from `floor()` calls to test cases, and the total becomes a generous 8s that the suite's real scope can meet. The per-case 200ms figure is what detects a regression; the total only detects unbounded growth. The "no network" half remains untouched. |

# Part II — Building it

## 12. Toolchain and layout

bash 3.2, `jq`, no build, no package manager, no network. Layout is the existing plugin layout of §6.1. `scripts/utils.sh` is sourced by every script and sets no shell options; each script chooses its own `set -e/-u/pipefail`, as today.

## 13. Configuration contract

| Placeholder | Rendered into | Value |
| --- | --- | --- |
| `{{PLUGIN_ROOT}}` | `state.md` | absolute plugin path; now locates `scripts/phase.sh`, `scripts/archive.sh` and `agents/phase-*.md` instead of `agents/looper.md` and `references/` |
| `{{SESSION_ID}}`, `{{MAX_LOOPS}}`, `{{STARTED_AT}}` | `state.md` frontmatter | unchanged |
| `{{REPO}}`, `{{GATES}}` | `contract.md` | unchanged; `GATES` is additionally re-supplied by the §8.1 migration |

A new placeholder requires a matching value in the `render_template` call in `run.sh`; this design adds none.

## 14. Fixtures

The bash equivalent of a port and a fake. `selftest.sh` gains one fixture builder, used by every new case:

```text
floor(dir, spec):   under a fresh `mktemp -d`, `git init`, then create the
                    floor described by spec — drafts, specs, plan overviews,
                    task files with a given number of ticked and open steps,
                    a log.md with given strike lines, a contract.md with a
                    given gate block, and optionally a package.json
```

Cases are then a verdict assertion (`pk NAME want`) or an effect assertion over the resulting tree. Every fixture is a real git repository, because `git status --porcelain` is normative input and must not be stubbed.

## 15. Verification

### 15.1 The gates

```bash
bash -n scripts/*.sh
scripts/selftest.sh
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

### 15.2 What the gates do not cover

| Not covered | Checked instead by |
| --- | --- |
| whether the runtime loads four agents | `claude -p … --debug-file <f> --model opus`, then grep `<f>` for `Loaded 4 agents from plugin`; a `-p` prompt asking Claude to list agent types reports NONE even when they are loaded, so it must not be used |
| whether a full flow reaches the promise | `claude -p "/spectomat:run 25" --plugin-dir . --model opus` in a scratch repo with two drafts |
| whether the Stop hook still releases | piping a fabricated `{"session_id","transcript_path"}` payload into `scripts/stop-hook.sh` |
| whether the `telegator` migration is clean | run `/spectomat:run` there and read the diff of `contract.md` |

Nested `claude -p` must always be given `--model opus`; the CLI rejects the default model.

### 15.3 The invariants that must be tests

| Invariant | Why a test and not a rule |
| --- | --- |
| the picker mutates nothing | it is called by `status` on demand and by every loop; a stray write would corrupt the floor silently |
| `D` never fires on a plan with no task files | the failure archives unbuilt work and is invisible until someone reads `done/` |
| a `.blocked` trail is still listed by `print_blocked` | a blocked slug that nothing reports is a silently dropped idea |
| no file mentions `references/` or `looper` | the removal is only real if nothing still points at it; a stale pointer would send an agent to read a missing file |
| `NOTICE.md` names only files that exist | a licence notice pointing at deleted files does not discharge the obligation |

## 16. Build sequence

Bottom-up. Each step ends with §15.1 green.

1. **Fixtures.** `floor()` and the `pk` assertion helper in `selftest.sh`, with one trivial case each, so every later step has a harness.
2. **Shared helpers.** `strike_count`, `least_struck`, `gate_block`, `run_gates`, `STRIKE_LIMIT` in `utils.sh`. Covers AC-2.1, AC-2.2, AC-2.3, AC-1.7, AC-1.8.
3. **The picker.** `scripts/phase.sh` per §5.1. Covers AC-1.1 … AC-1.9.
4. **The archiver.** `scripts/archive.sh` per §5.5. Covers AC-3.1 … AC-3.5.
5. **The briefs.** `agents/phase-a.md`, `phase-b.md`, `phase-c.md`, `recover.md`, absorbing `references/` per §6.3; delete `agents/looper.md` and `references/`.
6. **The contract.** Cut `templates/contract.md` per §6.2 and add the §8.2 marker.
7. **The pointer.** Rewrite the body of `templates/state.md` per §6.4 and §3.3.
8. **Migration.** `migrate_contract()` in `run.sh` per §8.1. Covers AC-4.1, AC-4.2.
9. **Operator surface.** `status.sh` prediction (§7.2), the three strings of §7.3, the glossary of §7.4.
10. **Cross-cutting.** `NOTICE.md` (§8.4), `README.md`, `.claude/CLAUDE.md`, the AC-7.1 and AC-7.2 greps, plugin version bump.
