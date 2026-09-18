# {{SLUG}} — Implementation Plan

**Goal:**

one sentence.

**Architecture:**

two or three sentences.

**Tech stack:**

the libraries and tools.

**Spec:**

`.spectomat/{{SLUG}}/spec.md`

> Code cites Spec by section and line (`§3.4 L316`).

## Global Constraints

- one line per project-wide rule, exact values copied verbatim from the spec

## File map

| File | Responsibility | Created in |
| --- | --- | --- |
| `src/<module>.js` | one sentence | Task 1 |

## Tasks

Each task is an independent piece of work.

One file per task, `task-NN-<name>.md`, under `.spectomat/{{SLUG}}/tasks/`, from `templates/task.md`.
The `IMPLEMENT` phase executes them one at a time, in this order, one task per iteration;
the `REVIEW` phase may append further ones after the last.
`Depends on` may name only lower-numbered tasks, and every file in the map has exactly one owning task.

| # | File | Component | Covers | Depends on |
| --- | --- | --- | --- | --- |
| 1 | `task-01-<name>.md` | `<component>` | AC-1.1, AC-1.2 | — |
| 2 | `task-02-<name>.md` | `<component>` | AC-2.1 | 1 |

## Coverage

Every criterion id in the spec, and the task that covers it.

| Criterion | Task |
| --- | --- |
| AC-1.1 | 1 |
