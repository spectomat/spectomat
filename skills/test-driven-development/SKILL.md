---
name: test-driven-development
description: Use when implementing any task step or bug fix, before writing production code — write the failing test, watch it fail, write minimal code, watch it pass.
---

# Test-driven development

If you did not watch the test fail, you do not know it tests the right thing.

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before its test? Delete it and start from the test. Not "keep as
reference", not "adapt it": delete.

## The cycle

1. **RED** — one minimal test for one behaviour, named after that
   behaviour, against real code (a mock only where a boundary forces it).
2. **Verify RED** — run it. It must *fail*, not error, and fail because the
   behaviour is missing. Passes at once? You are testing what already exists.
3. **GREEN** — the simplest code that passes. No options, no generality, no
   "while I'm here".
4. **Verify GREEN** — run it and the rest of the suite. Output pristine: no
   warnings, no stray logs. Fails? Fix the code, never the test.
5. **REFACTOR** — remove duplication, improve names, extract helpers. Stay
   green. Add no behaviour.
6. Next behaviour, back to 1.

## Good tests

| Rule | Why |
| --- | --- |
| Name the production change that would make the test fail, before writing it | a test nothing can break proves nothing |
| Assert on behaviour, never on mock calls | "was called with X" survives a broken feature |
| One behaviour per test; an "and" in the name means two tests | a failure must point at one cause |
| Test-only helpers live in test files, not in production classes | production code is not a test fixture |
| Understand a dependency's side effects before mocking it | a mock that skips them hides the bug |

## Rationalizations

| Excuse | Reality |
| --- | --- |
| "Too simple to test" | Simple code breaks; the test takes a minute. |
| "I'll test after" | A test written after passes at once and proves nothing. |
| "Already tested manually" | Not repeatable, not recorded, not re-run on change. |
| "Deleting X hours is wasteful" | Sunk cost. Code you cannot trust is the waste. |
| "Hard to test" | Then it is hard to use. Simplify the interface. |
| "Existing code has no tests" | You are improving it; add them. |

## Bug fixes

First a failing test that reproduces the bug, then the fix. The test proves
the fix and pins the regression. Never fix a bug without one.

## Before ticking a step

- the test existed first and was seen failing for the right reason
- minimal code made it pass; the whole suite is green and clean
- tests use real code; edge cases and error paths are covered
