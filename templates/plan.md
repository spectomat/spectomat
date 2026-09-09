# {{SLUG}} — Implementation Plan

**Goal:** one sentence. **Architecture:** two or three sentences. **Tech stack:** the libraries and tools. **Spec:** .spectomat/specs/{{SLUG}}.md

## Global Constraints

- one line per project-wide rule, exact values copied verbatim from the spec

## File map

| File | Responsibility | Created in |
| --- | --- | --- |
| `src/<module>.js` | one sentence | Task 1 |

## Tasks

One file per task under `.spectomat/plans/{{SLUG}}/`, from `templates/task.md`, executed in this order. Tasks with no dependency between them and disjoint Files run in parallel as one wave.

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

appended by executing-tasks for decisions that cross tasks:
`- Task N · <decision> — <why> — <cost if wrong>`
