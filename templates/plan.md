# {{SLUG}} — Implementation Plan

**Goal:** one sentence. **Architecture:** two or three sentences. **Tech stack:** the libraries and tools. **Spec:** .spectomat/specs/{{SLUG}}.md

## Global Constraints

- one line per project-wide rule, exact values copied verbatim from the spec

## File map

| File | Responsibility | Created in |
| --- | --- | --- |
| `src/<module>.js` | one sentence | Task 1 |

## Tasks

One file per task under `.spectomat/plans/{{SLUG}}/`, from `templates/task.md`. The `IMPLEMENT` phase executes them one at a time, in this order, one task per iteration; the `REVIEW` phase may append further ones after the last. Each task is an independent piece of work; `Depends on` may name only lower-numbered tasks, and every file in the map has exactly one owning task.

| # | File | Component | Covers | Depends on |
| --- | --- | --- | --- | --- |
| 1 | `task-01-<name>.md` | `<component>` | AC-1.1, AC-1.2 | — |
| 2 | `task-02-<name>.md` | `<component>` | AC-2.1 | 1 |

## Coverage

Every criterion id in the spec, and the task that covers it. A criterion with no task is a plan defect.

| Criterion | Task |
| --- | --- |
| AC-1.1 | 1 |

## Rulings

appended by the `IMPLEMENT` phase for decisions that cross tasks, and by the `REVIEW` phase for the Minor findings it parks:
`- Task N · <decision> — <why> — <cost if wrong>`

## Review

written by the `REVIEW` phase once every task is ticked, one line per round. The `Verdict:` line is what releases the plan to `ARCHIVE`; while it is absent the plan comes back for another round.

`- Round R — N findings (C critical, I important, M minor) — tasks NN–MM added`
`- Verdict: CLEAN | PARKED`
