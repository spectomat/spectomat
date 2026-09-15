# {{SLUG}} · Task {{N}}: <component>

**Plan:** .spectomat/plans/{{SLUG}}.md **Spec:** .spectomat/specs/{{SLUG}}.md — §<sections this task implements> **Covers:** AC-1.1, AC-1.2 **Depends on:** Task <M> (or none)

## Goal

One sentence: what exists when this task is done that did not before.

## Constraints

- every Global Constraint from the plan that binds this task, copied verbatim
- exact values from the spec: constants, formats, messages

## Files

- Create: `exact/path.js`
- Modify: `exact/existing.js:120-140`
- Test: `exact/path.test.js`

## Interfaces

- Consumes: exact names and signatures produced by earlier tasks (none for Task 1)
- Produces: exact names and signatures later tasks rely on

## Steps

- [ ] **Step 1: Write the failing test** — create `exact/path.test.js` with the content of `.spectomat/snippets/{{SLUG}}/task-{{N}}-step1.js`
- [ ] **Step 2: Run it, expect FAIL** — `npm test -- exact/path.test.js`, fails with "fn is not defined"
- [ ] **Step 3: Minimal implementation** — create `exact/path.js` with the content of `.spectomat/snippets/{{SLUG}}/task-{{N}}-step3.js`
- [ ] **Step 4: Run it, expect PASS** — same command; the full suite stays green
- [ ] **Step 5: Commit** — message `feat({{SLUG}}): <what>`; the `IMPLEMENT` phase stages exactly this task's Files and makes one commit

Rulings and Result are not sections of this file: the `IMPLEMENT` phase records them as this task's entry in the plan's `{{SLUG}}.ruling.md` and `{{SLUG}}.result.md`.
