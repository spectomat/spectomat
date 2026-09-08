# {{SLUG}} · Task {{N}}: <component>

**Plan:** docs/.spectomat/plans/{{SLUG}}.md **Spec:** docs/.spectomat/specs/{{SLUG}}.md — §<sections this task implements> **Covers:** AC-1.1, AC-1.2 **Depends on:** Task <M> (or none)

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

- [ ] **Step 1: Write the failing test** — create `exact/path.test.js`:

```js
test("specific behaviour", () => {
  expect(fn(input)).toBe(expected);
});
```

- [ ] **Step 2: Run it, expect FAIL** — `npm test -- exact/path.test.js`, fails with "fn is not defined"
- [ ] **Step 3: Minimal implementation** — create `exact/path.js`:

```js
export function fn(input) {
  return expected;
}
```

- [ ] **Step 4: Run it, expect PASS** — same command; the full suite stays green
- [ ] **Step 5: Commit** — message `feat({{SLUG}}): <what>`; the controller stages this task's Files and commits — an implementer subagent never runs git

## Rulings

(appended by executing-tasks: `- <decision> — <why> — <cost if wrong>`)

## Result

(filled by executing-tasks when the task is done)

- Commits: <base7>..<head7>
- Tests: <n>/<n> (<files>)
- Review: spec ✅ · quality: <clean | K parked>
