# `state.json` as the picker's single source of truth

## Motivation

`scripts/phase.sh` currently derives every candidate set by scanning committed Markdown on every iteration: `grep -qE '^- \[ \]'` across every `task-*.md` of every plan, `grep -qE '^- Verdict: '` in every spec and plan overview, a `task_count` glob per plan. This is re-derived from scratch each iteration even though nothing but the last phase's own artifacts changed. It works, but it is the wrong shape for the §9.3 non-functional target (`phase.sh` under 200ms on 20 plans) as the floor grows, and it makes the picker's real logic (priority order, least-struck selection) hard to see under the file-scanning that surrounds it.

This design moves per-slug progress into `state.json`, which becomes the picker's only input besides `git status`. File-content scanning is deleted from the hot path, not relocated to a rebuild step — see "Why no rebuild step" below.

## `state.json` schema

```json
{
  "active": true,
  "iteration": 5,
  "max_iterations": 100,
  "session_id": "...",
  "started_at": "...",
  "slugs": {
    "003-auth": {
      "phase": "IMPLEMENT",
      "tasks_total": 4,
      "tasks_done": 2,
      "strikes": { "IMPLEMENT": 0, "REVIEW": 0 }
    }
  }
}
```

- `phase` is one of `SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE` — the slug's current stage. This is the field `phase.sh` groups on; it replaces every `candidates_*` function in the current script.
- `tasks_total` / `tasks_done` exist only while `phase` is `IMPLEMENT` or `REVIEW`; absent otherwise.
- `strikes` is a map of phase name to count, replacing the `grep -F '(strike '` count over `log.md`.
- `active` (new) distinguishes an armed-and-running flow from a cancelled one that has not finished — see Lifecycle below.

## Lifecycle: arm, cancel, resume, finish

Today, `state.json`'s existence *is* the armed flag (§6.4), and `/spectomat:cancel` deletes it (`disarm()`). This design changes that:

| Event | `state.json` | `pointer.md` |
| --- | --- | --- |
| `/spectomat:run` (fresh floor) | created, `active: true`, `slugs: {}` populated for existing drafts | rendered |
| `/spectomat:run` (floor has an inactive `state.json`) | `active` set back to `true`, `session_id`/`started_at` refreshed | rendered |
| `/spectomat:run` (floor has an active `state.json`) | refused, as today | refused |
| `/spectomat:cancel` | kept as-is, only `active` set to `false` | deleted |
| `FINISH` reached, or iteration cap hit | deleted (full `disarm()`) | deleted |

Consequences:
- `prepare.sh`'s `require_startable` check changes from "`state.json` exists → refuse" to "`state.json` exists **and `active`** → refuse"; an inactive `state.json` is a resume, not a conflict.
- `stop-hook.sh` and `phase.sh` only proceed when `active: true` (in addition to the existing session-id match in `stop-hook.sh`).
- `cancel.sh` no longer calls `disarm()`; it does a `jq '.active = false'` write and removes only `pointer.md`.
- A cancelled-and-resumed flow keeps every slug's `phase`/`tasks_done`/`strikes` exactly where they were. This is what makes `state.json` an actual single source of truth: nothing about a slug's progress is reconstructed from anywhere else, ever, across a cancel.

### Why no rebuild step

An earlier version of this design considered a `prepare.sh` rebuild pass (reconstructing `state.json` by scanning the floor) to cover the case where `state.json` is lost — the cancel path, originally. Preserving `state.json` across cancel removes that need for the common case. The remaining case — `state.json` deleted by hand, or a fresh clone picking up a mid-flight floor — is deliberately not solved by a scanning rebuild; see "Orphan detection" below for the safety net that keeps this failure mode from being *silent*, and D-9 for why a full rebuild was rejected.

Two files that might look like rebuild fuel already exist for unrelated reasons and are untouched by this design: `plans/<slug>.result.md` (one entry per task, written by `IMPLEMENT`, read by `REVIEW` to reconstruct a plan's diff) and `plans/<slug>.ruling.md` (decisions and defects, written by `IMPLEMENT`/`REVIEW`). Neither was ever read by `phase.sh`; both keep doing exactly what they do today.

## Phase transition table

Each phase agent (and `archive.sh`) advances its slug's `state.json` entry as the last thing it does, strictly *after* its git commit (see Ordering invariant):

| Phase finishing | New `state.json` for the slug |
| --- | --- |
| `SPECIFY` | `phase: "REVIEW-SPEC"` |
| `REVIEW-SPEC` | `phase: "PLAN"` |
| `PLAN` | `phase: "IMPLEMENT"`, `tasks_total: N`, `tasks_done: 0` |
| `IMPLEMENT` (one task) | `tasks_done += 1`; if `tasks_done == tasks_total`, also `phase: "REVIEW"` |
| `REVIEW`, verdict CLEAN | `phase: "ARCHIVE"` |
| `REVIEW`, verdict PARKED (fix tasks added) | stays `phase: "IMPLEMENT"`, `tasks_total` raised by the number of fix tasks added, `tasks_done` unchanged |
| `ARCHIVE` (`archive.sh`), success or blocked | the slug's entire entry under `slugs` is deleted |
| any phase's failure | `strikes.<PHASE> += 1`; `phase` unchanged |

`phase.sh`'s priority order is unchanged: group slugs by `phase`, and for each of `ARCHIVE, REVIEW, IMPLEMENT, PLAN, REVIEW-SPEC, SPECIFY` in that order, pick the least-struck slug in that group (ties broken alphabetically, as today); the first non-empty group wins. `SPECIFY` candidates are the drafts recorded in `state.json.slugs` with `phase: "SPECIFY"` — new drafts are added to `state.json` once, when `prepare.sh` arms or resumes the flow (drafts never arrive mid-flow per D13, so this is the only time new slugs enter `state.json`).

`FINISH` is `state.json.slugs` being empty **and** a silent `git status --porcelain`, the same two-part test as today's `floor_is_empty` check, just against the map instead of three directory listings. Anything else — a non-empty `slugs` map that matched no stage above, which cannot happen given the transition table, or the orphan mismatches below — is `RECOVER`.

`phase.sh` reads `state.json.slugs` regardless of the top-level `active` flag: `/spectomat:status` must keep predicting the next verdict on a cancelled flow, and the picker stays "a pure function of the floor, `state.json` and `git status`" (§3.1's idempotency claim, unchanged in spirit). Only `stop-hook.sh` (whether to advance an iteration) and `prepare.sh`/`cancel.sh` (whether arming is a fresh start, a refusal, or a resume) branch on `active`.

## Ordering invariant

Every phase agent and `archive.sh` **commits its git changes first, then writes `state.json`**, never the reverse. A crash between the two leaves a dirty git tree (today's existing `RECOVER` trigger — `git status --porcelain` non-empty — is unaffected) with `state.json` still describing the last *committed* reality. The janitor (`agents/recover.md`) then either:
- discards the uncommitted work, in which case `state.json` is already correct and needs no repair, or
- finishes the commit itself, in which case it also applies the `state.json` transition the crashed agent would have made — the one case where the janitor, not a phase agent, writes `state.json`.

## Orphan detection (the safety net)

Without a rebuild step, a `state.json` that is lost, hand-edited, or absent on a fresh clone of a mid-flight floor would otherwise make its untracked slugs silently invisible to the picker — worse than today, where a stray file at least falls through to `RECOVER`. `phase.sh` therefore does one more O(number of slugs) check before its normal priority walk, using directory listings only, never file content:

- every `.md` file directly under `drafts/`, `specs/`, `plans/` must have a matching entry in `state.json.slugs`;
- every entry in `state.json.slugs` must have its phase-appropriate file present (a `SPECIFY`-phase slug needs a draft; an `IMPLEMENT`-phase slug needs a plan directory; and so on).

Either mismatch prints `RECOVER` before any candidate set is computed. `agents/recover.md` gains the responsibility of reconciling such a slug — inspecting its git history (e.g. which of its tasks already have shipped commits, going by `plans/<slug>.result.md`) and writing a reasonable `state.json` entry for it, a judgment call left to the subagent rather than a deterministic script.

## Other components touched

- **`scripts/utils.sh`**: new helpers to read/write a slug's `state.json` entry (get phase, set phase, bump `tasks_done`, bump a strike) — one `jq` call per mutation, matching the existing `state_field` pattern. `strike_count` and `least_struck` are rewritten against `state.json.slugs.*.strikes` instead of `log.md`.
- **`scripts/archive.sh`**: `strike()` writes to `state.json` instead of counting `log.md` lines back out (it still also appends the human-readable log line, unchanged); on success or block, deletes the slug's `state.json` entry after the commit.
- **`scripts/status.sh` / `scripts/print.sh`**: `print_plans` reads `tasks_total`/`tasks_done`/`phase` straight from `state.json` instead of `cat`-ing and `grep`-ing every task file; `print_iteration` and `print_next` account for `active`.
- **`agents/specify.md`, `review-spec.md`, `plan.md`, `implement.md`, `review.md`**: each gains one instruction — advance the slug's `state.json` phase (and counters) per the transition table, after the commit.
- **`templates/task.md`**: steps become a plain numbered list, no `- [ ]` checkboxes.
- **`templates/plan.md`**: the `## Review` section drops the `- Verdict: CLEAN | PARKED` grammar; review rounds are still logged (to `log.md` and `state.json`), just not latched via a line in the plan file.
- **`templates/spec.md`** (§17): same change — no `- Verdict: READY` line; the `REVIEW-SPEC` → `PLAN` release is `state.json`'s `phase` field alone.
- **`docs/spectomat.md`**: §2 (`strike ledger` moves from "derived from `log.md`" to "a `state.json` field"), §5.1/§5.2/§5.3 (`pick_phase`, `least_struck`, `strike_count` rewritten against `state.json`), §6.4 (the state/pointer lifecycle table gains the `active` column and the resume path), §8 (new design decisions — see below), §9 (acceptance criteria updated for the new algorithms and the orphan-detection behavior), §10.3 (fixtures build a `state.json` instead of checkbox/Verdict-line Markdown).

## New design decisions (for §8)

| Decision | Rejected | Why |
| --- | --- | --- |
| `state.json` is the picker's only progress record; a phase agent advances it, never re-derives it | scanning committed Markdown every iteration (today's design) | the floor grows over a run; re-deriving candidate sets from file content on every iteration is the cost this design removes, and the picker's real logic (priority, least-struck) was hard to read under the scanning code that surrounded it |
| `/spectomat:cancel` sets `active: false` and keeps `state.json`; only `FINISH` deletes it | `cancel` deletes `state.json` as today (D12) | a state.json that survives cancel needs no rebuild-from-files step to resume correctly, which is what makes it a true single source of truth rather than a cache that happens to usually be right |
| No rebuild-from-files step; a `state.json` lost outside of cancel is a `RECOVER` case for the janitor, not an automatic reconstruction | a `prepare.sh` scan that reconstructs `state.json` from checkboxes/Verdict-lines/`.result.md` on every arm | the common loss case (cancel) no longer needs it; the rare case (hand-deleted file, fresh clone mid-flight) genuinely needs judgment — which tasks' commits actually shipped — that a deterministic script would have to guess at anyway |
| Checkboxes and `- Verdict:` lines are removed from the templates | keeping them as inert human-readable prose | with `state.json` no longer reconstructed from them, they would be pure duplication of `phase`/`tasks_done` with no reader — a second place the same fact could drift from |

## Out of scope

`plans/<slug>.result.md` and `plans/<slug>.ruling.md` are unchanged — they serve `REVIEW`'s diff reconstruction and defect-recording, unrelated to phase selection. `log.md`'s format is unchanged; it remains the human-readable append-only report, it simply stops being parsed for strike counts.
