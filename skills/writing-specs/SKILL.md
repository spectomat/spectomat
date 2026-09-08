---
name: writing-specs
description: Use when writing or reviewing a normative specification that an autonomous loop will build from — "write the spec", "is this spec buildable", "spec for the ralph loop". Defines the shape a spec needs so code can cite it and tests can name its criteria.
metadata:
  tags: spectomat, spec
---

# Writing a buildable spec

A spec is a contract, not a story. 

You should be able then

- reads it once in full
- build executable plan from it, 
- cite it from code, 
- and reconcile against it when it contradicts itself.

## Shape

Start from `templates/spec.md` in this plugin; 

phase A of the factory follows it when turning a draft into a spec. 

Two parts:
| Part | Role | Edited by |
| --- | --- | --- |
| Part I — Functional Specification | normative: domain, behaviour, algorithms, architecture, acceptance criteria, decisions | user only |
| Part II — Design Document | toolchain, boundaries, gates, invariants, build sequence | user, and the loop's README/CLAUDE phase may cite it |

## Rules

- **Number every section** (`## 3.`, `### 3.4`). Code cites `§3.4 L316`; a
  citation test keeps the line inside the section it names.
- **Every acceptance criterion has an id** (`AC-3.2`, `E2E-5`). A test names
  the id; an audit test fails when a declared id has no test, and when a test
  names an undeclared id.
- **Algorithms are pseudocode with named constants.** `THRESHOLD = 0.85`, not
  "a high similarity". The loop implements them as written; a suspected error
  is a reconciliation, not a silent improvement.
- **State what is normative and what is illustrative.** A diagram is
  illustrative unless the text says otherwise.
- **Decisions are numbered and dated**, with the rejected alternative. When
  two sections disagree, the later explicitly resolved one wins — say so.
- **Reconciliations get a section** (`§11` in the skeleton) that starts empty.
  The loop appends a numbered row per divergence.
- **Name every external boundary** and its interface. Each becomes a port with
  an in-memory fake; a boundary the spec does not name becomes a test that
  touches the network.
- **Give the build sequence, bottom-up.** Pure domain first, adapters next,
  wiring after, UI last. The loop derives its phases from this list.
- **Say what cannot be verified locally** (deploy-gated criteria) and what
  residue to deliver instead: the harness, the file format, the alarm.

## Smells

| Smell | Consequence in the loop |
| --- | --- |
| "should", "ideally", "consider" | the planner guesses, and the guess ships |
| a count in a heading that the list below disagrees with | a reconciliation row, and a pinned test of the actual count |
| the same constant written twice | two modules, and drift |
| a field used in pseudocode but absent from the entity table | a reconciliation row about which one is the schema |
| a criterion with no observable | BLOCKED, never verified |

## Review checklist

Before dropping a hand-written spec into `docs/.spectomat/specs/`:

- [ ] every `##` and `###` in Part I is numbered
- [ ] every criterion has an id and a "verified by"
- [ ] every constant appears once, in the section that owns it
- [ ] every external boundary is named
- [ ] the build sequence exists and is bottom-up
- [ ] the reconciliations section exists and is empty
