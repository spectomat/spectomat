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
| Task agent | `spectomat:task` | one fresh subagent per task, dispatched by the `IMPLEMENT` phase agent; builds and gates that task from its task file alone; never writes to git and touches no floor state (D30) |
| Archiver | `spectomat:archive`, wrapping `scripts/agent-archive.sh` | the brief invokes the script and relays its result unchanged; the script performs the `ARCHIVE` phase: gates, moves, commit, log |
| Janitor | `spectomat:recover` | recovers a dirty tree, or a floor the picker cannot classify |

### 1.2 The system in one picture

```text
Stop hook
  └─ bash {{PLUGIN_ROOT}}/scripts/phase.sh   →  exactly one frontmatter block:
       │                                          phase, slug, subagent, brief, plugin_root
       └─ session receives that block, embedded in the pointer prompt fed back by the Stop hook (D34)
          │
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

Every arrow's target — the `subagent` and `brief` field — is computed by `phase.sh` itself, not looked up by the pointer: the agent name is the phase lowercased (`REVIEW-SPEC` → `review-spec`), so the block is the one place that mapping lives (§3.3).

## 2. Domain Model

The floor and the system's own entities — the `verdict` (§2.1), the `strike ledger` (§2.2) and the `gates` (§2.3) — in [`references/domain-model.md`](../references/domain-model.md) under the same numbers.

## 3. Behaviour

Trigger and input (§3.1), the iteration (§3.2), dispatch (§3.3), the failure path (§3.4) and completion (§3.5), in [`references/behaviour.md`](../references/behaviour.md) under the same numbers.

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

The named constants and the six algorithms in pseudocode — `pick_phase` (§5.1), `least_struck` (§5.2), `strike_count` (§5.3), `run_gates` (§5.4), `detect_gates` (§5.5) and `archive` (§5.6) — in [`references/algorithms.md`](../references/algorithms.md) under the same numbers.

## 6. Architecture

The component map (§6.1), the contract (§6.2), the briefs (§6.3), and the state and the pointer (§6.4), in [`references/architecture.md`](../references/architecture.md) under the same numbers.

## 7. Operator surface

### 7.1 Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares the floor, commits the wishes it finds, arms the Stop hook for `n` iterations (default 100), starts iteration 1; resumes an inactive flow if one exists, else refuses when a flow is armed, no unfinished slug remains, or the tree is dirty |
| `/spectomat:status` | the next verdict, the current iteration, the current phase and slug (`current`) and the plugin copy that armed the flow, floor counts, per-slug progress including finished slugs, blocked files, log tail — every count from `state.json` |
| `/spectomat:cancel` | marks the flow inactive and removes the pointer; keeps `state.json` so `/spectomat:run` can resume it |
| `/spectomat:help` | prints `docs/guide.md` and `references/glossary.md` |

### 7.2 `status` predicts the next phase

`command-status.sh` calls `print_next`, which prints a `--- next ---` section holding the picker's frontmatter block verbatim, e.g. `phase:IMPLEMENT` / `slug:003-auth` / … . Because it is the identical code path the next iteration takes, the prediction cannot drift from the decision. The picker mutates nothing (§5.1 note 7), so this is safe to run at any time.

### 7.3 Installation

The plugin runs from a cache copy under `~/.claude/plugins/cache/spectomat/`, so a source edit is not live until `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run`.

## 8. Design decisions

One row per decision — what was decided, what was rejected, and why — in [`references/decisions.md`](../references/decisions.md). A `D<n>` id in this file names a row there.

## 9. Acceptance Criteria

Per component (§9.1), end-to-end (§9.2) and non-functional (§9.3), in [`references/testing.md`](../references/testing.md) under the same numbers.

## 10. Building and testing

Toolchain (§10.1), configuration contract (§10.2), fixtures (§10.3), the gates (§10.4), what they do not cover (§10.5), the invariants that must be tests (§10.6), the suite (§10.7) and the two bash generations (§10.8), in [`references/testing.md`](../references/testing.md) under the same numbers.
