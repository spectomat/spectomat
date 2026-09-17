# {{PROJECT}}

# Part I — Specification

## 1. System Overview

### 1.1 Purpose

### 1.2 Actors

### 1.3 The system in one picture

## 2. Domain Model

One subsection per entity. For each: fields (name, type, meaning), identity, invariants, and which component owns writes.

### 2.1 `<entity>`

## 3. Behaviour

One subsection per stage, flow, or use case, in execution order. For each: trigger, input, algorithm (pseudocode with named constants), output, failure path, idempotency.

### 3.1 `<stage>`

## 4. External Integrations

One subsection per boundary. Protocol, auth, limits, and the interface the code sees.

## 5. Normative Algorithms

Algorithms given as explicit pseudocode with named constants. The factory implements them as written; a suspected error is a ruling in the plan's `<slug>.ruling.md`, never a silent improvement.

## 6. Architecture

Component map, storage design, messaging, permissions, observability.

## 7. User Interface

Route tree, pages, actions with exact signatures and role checks, computations.

## 8. Deployment

Environments, stacks, hosting, seeding, cutover.

## 9. Acceptance Criteria

Every criterion has an id a test can name.

### 9.1 Per component

| Id | Criterion | Verified by |
| --- | --- | --- |
| AC-1.1 | ... | unit test |

### 9.2 End-to-end

| Id | Criterion | Verified by |
| --- | --- | --- |
| E2E-1 | ... | harness over fakes |

### 9.3 Non-functional

Targets that need a running system are deploy-gated. Name the mechanism that will measure each one.

## 10. Decisions

Numbered, dated, with the alternative rejected. The later, explicitly resolved section wins over an earlier one.

| Id | Decision | Rejected | Why |
| --- | --- | --- | --- |
| D1 | ... | ... | ... |

# Part II — Building it

## 11. Toolchain and layout

## 12. Configuration contract

## 13. Boundaries: ports and fakes

Every external boundary is an interface with an in-memory fake. List them.

## 14. Verification

### 14.1 The gates

```bash
# every command that must pass before a commit
```

### 14.2 What the gates do not cover

### 14.3 The invariants that must be tests

| Invariant | Why a test and not a rule |
| --- | --- |

## 15. Build sequence

Bottom-up, numbered. Each step ends with all gates green. The factory derives its build phases from this list.

1. Toolchain
2. Domain
3. Ports and fakes
4. Normative algorithms
5. Adapters
6. Wiring
7. Infrastructure
8. UI
9. Operations
10. Cross-cutting
