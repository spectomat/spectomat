# Task {{N}}: {{SLUG}}  <component>

## Goal

One sentence: what exists when this task is done that did not before.

## Context

**Covers:** AC-1.1, AC-1.2
**Depends on:** Task <M> (or none)
**Branch:** `feat/{{SLUG}}` — the only branch this task commits to
**Source:** `.spectomat/{{SLUG}}/plan.md`, `.spectomat/{{SLUG}}/spec.md` §<sections> — provenance for the `REVIEW` phase; the task agent never opens them

### Purpose

Two to four sentences: the plan's goal, the architecture this task sits in, what this task adds. Readable with no other file open.

### Spec, verbatim

Every requirement, criterion, constant, format and message this task implements, quoted from the spec with its id and section — the full text, never the id alone:

> **AC-1.1** (§3.2) — <the criterion's full text>
> **§4.1** — <the rule's full text>

### Codebase

What the task agent must know and cannot read off this file or the code it names: the existing files and signatures it touches (`path:lines`), the exemplar to copy (`path`), how tests run here, and every `memory.md` line that applies — copied, not referenced.

## Constraints

- every Global Constraint from the plan that binds this task, copied verbatim
- exact values from the spec: constants, formats, messages

## Files

- Create: `exact/path.js`
- Modify: `exact/existing.js:120-140`
- Test: `exact/path.test.js`

## Steps

1. **Step 1: Write the failing test** — create `exact/path.test.js` with the content of `.spectomat/{{SLUG}}/snippets/task-{{N}}-step1.js.snippet`
2. **Step 2: Run it, expect FAIL** — `npm test -- exact/path.test.js`, fails with "fn is not defined"
3. **Step 3: Minimal implementation** — create `exact/path.js` with the content of `.spectomat/{{SLUG}}/snippets/task-{{N}}-step3.js.snippet`
4. **Step 4: Run it, expect PASS** — same command; the full suite stays green
5. **Step 5: Commit** — message `feat({{SLUG}}): <what>`; the task agent stages exactly this task's Files and makes one commit

## Interfaces

### Consumes

- exact names and signatures produced by earlier tasks (none for Task 1)

### Produces
  
- exact names and signatures later tasks rely on
