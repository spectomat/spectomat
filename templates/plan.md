# {{SLUG}} — Implementation Plan

**Goal:** one sentence.
**Architecture:** two or three sentences.
**Tech stack:** the libraries and tools.
**Spec:** docs/.spectomat/specs/{{SLUG}}.md

## Global Constraints

- one line per project-wide rule, exact values copied verbatim from the spec

## File map

| File | Responsibility | Created in |
| --- | --- | --- |
| `src/<module>.js` | one sentence | Task 1 |

---

### Task 1: <component>

**Files:**
- Create: `exact/path.js`
- Modify: `exact/existing.js:120-140`
- Test: `exact/path.test.js`

**Interfaces:**
- Consumes: exact names and signatures from earlier tasks (none for Task 1)
- Produces: exact names and signatures later tasks rely on

**Covers:** AC-1.1, AC-1.2

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
- [ ] **Step 5: Commit** — `git add exact/path.js exact/path.test.js && git commit -m "feat({{SLUG}}): <what>"`

### Task 2: <component>

(same shape: Files, Interfaces, Covers, five checkbox steps with real code)

## Rulings

(appended by executing-tasks: `- Task N · <decision> — <why> — <cost if wrong>`)
