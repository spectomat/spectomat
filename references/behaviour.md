# Behaviour

§3 of [the specification](../docs/specification.md), numbered as it is cited. A `§` number names a section of the specification; a `D<n>` id names a row of [the design decisions](./decisions.md).

## 3. Behaviour

### 3.1 Trigger and input

Trigger: the Stop hook blocks a session exit and feeds back the pointer prompt. Input: the floor as the previous iteration left it. Idempotency: the picker is a pure function of `state.json` and `git status` — it reads no floor file at all (D27) — so running it twice with no intervening change yields the same verdict; the Stop hook relies on exactly this to run the picker once per iteration and embed its block in the pointer prompt (D34), rather than have the session run it again for a verdict that cannot have moved.

### 3.2 The iteration

1. The Stop hook has already run the picker for this iteration (§3.5) and embedded its frontmatter block in the pointer prompt; the session reads that block from the prompt rather than running `phase.sh` itself.
2. It dispatches per §3.3.
3. It prints at most five lines of the report and stops, which fires the Stop hook again.

The session reads no contract, no floor file and no source. Its context accumulates one short report per iteration.

### 3.3 Dispatch

The pointer has no lookup table: every field it needs is in the block. It launches exactly one subagent — `run_in_background: false`, `subagent_type` set to the block's `subagent` field, and the body of the file named by `brief` (after that file's own frontmatter) as the task's brief — for every `phase` from `SPECIFY` through `RECOVER`. `FINISH` is the exception: its block names no `subagent` and no `brief`, because the Stop hook ends the flow on that verdict before the pointer ever sees it (§3.5). A pointer that does see a `FINISH` block — from `/spectomat:status`, or a janitor running the picker by hand — dispatches nothing.

The task handed to the subagent is the picker's frontmatter block, verbatim, fences included — the pointer neither reformats it nor extracts fields from it. A brief therefore carries no plugin path of its own but can still reach `templates/` by reading `plugin_root:` out of its own task.

`subagent` and `brief` are not a rule the pointer applies — they are fields `phase.sh` already computed, one rule stated once, in the script: the phase lowercased is the agent name, so `REVIEW-SPEC` names `spectomat:review-spec` and `agents/review-spec.md`; §6.1 fixes the file names so the mapping holds for every phase.

`IMPLEMENT` is the one phase that dispatches a second agent: `spectomat:task`, once per iteration, with a five-line task (slug, task number, task file path, gates log path, plugin root) and never a brief verbatim (D30). `task` is not a phase and not a verdict: `phase.sh` never emits it, it has no row in the dispatch table, and it writes nothing to `state.json` or `log.md` — the phase agent that dispatched it verifies its work against git and the gates log, commits it, records the result and advances the slug.

### 3.4 Failure path

A phase agent that cannot finish appends `(strike N)` to its log line and stops; the next iteration's picker skips that slug in favour of the next candidate in the same stage (§5.2). On its own third strike the agent writes `<slug>/blocked.md` with the reason, runs `scripts/block_slug.sh <slug> <reason>` to move the slug's `state.json` entry to `BLOCKED`, and logs the reason (D5); the state call is what takes the slug out of the flow, so a marker written without it leaves the slug sitting at its working phase for the rest of the flow — at `STRIKE_LIMIT` the picker skips it and falls through to `RECOVER`, and below the limit it hands the slug back to the same phase again (D27). `agent-archive.sh` does the same for the `ARCHIVE` phase (§5.6), via the same script. Nothing moves: the trail stays in the slug dir.

An iteration that dies mid-phase leaves a dirty tree; the next picker returns `RECOVER` before any other test, naming the slug `state.json`'s `current` records, and the janitor either finishes and commits the phase or stashes the paths the factory owns.

### 3.5 Completion

The Stop hook ends the flow if and only if the picker answers `FINISH` in that hook invocation. The picker answers `FINISH` only when `state.json` holds no slug at a non-terminal phase — every entry is at `DONE` or `BLOCKED` — **and** `git status --porcelain` is silent, both evaluated in that invocation. An empty `.slugs` object satisfies the first test too, but it is not what a finished flow looks like: a finished slug keeps its entry. No model output is consulted: the hook runs `scripts/phase.sh` itself and reads no transcript, so nothing a session writes can end a flow or keep one alive.

The hook composes the closing report from `state.json`: shipped is the count of slugs at `DONE`, blocked the count at `BLOCKED`, one `jq` call each over the terminal phases, and the blocked names come from the same call. No marker file is opened. It reaches the operator as the hook's `systemMessage`.
