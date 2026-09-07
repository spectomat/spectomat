---
name: systematic-debugging
description: Use when a gate fails, a test breaks, or behaviour is unexpected, before proposing any fix — find the root cause first, then fix once with a test.
---

# Systematic debugging

```
NO FIX WITHOUT A ROOT CAUSE FIRST
```

Symptom fixes are failures that come back. This process is faster than
guess-and-check, especially when it feels too urgent for it.

## Four phases, in order

### 1. Root cause

- Read the whole error and stack trace: file, line, code. It often names
  the fix.
- Reproduce it reliably. Not reproducible → gather more data, do not guess.
- Check what changed: `git diff`, recent commits, new dependencies, config.
- Across component boundaries, instrument first: log what enters and leaves
  each layer, run once, and read where the data goes wrong.
- Trace the bad value backwards to where it originates. Fix at the source,
  never at the symptom.

### 2. Pattern

- Find working code in the same codebase that does the same kind of thing.
- List every difference between working and broken, however small.
- Read a reference implementation completely before applying its pattern.

### 3. Hypothesis

- State one hypothesis: "X is the cause because Y." Write it down.
- Test it with the smallest possible change, one variable at a time.
- Wrong → new hypothesis. Never stack a second fix on a failed one.

### 4. Fix

1. A failing test that reproduces the bug (`spectomat:test-driven-development`).
2. One change addressing the root cause. No bundled refactoring.
3. Verify: the new test passes, the suite passes, the symptom is gone
   (`spectomat:verification-before-completion`).
4. Did not work → count your attempts. Under three: back to phase 1 with the
   new evidence. Three failed fixes → the design is wrong, not the fix:
   record a ruling about the smallest structural change and take that path.

## Red flags

Stop and return to phase 1 if you think: "quick fix now, investigate later",
"just try changing X", "several changes then run the tests", "it's probably
X", "I don't fully understand but this might work", or "one more attempt"
after two failures.

## When there is truly no root cause

Environmental, timing-dependent or external causes exist, but most "no root
cause" is unfinished investigation. When the investigation is complete,
record what you checked, add the right handling (retry, timeout, clear error)
and the logging that will settle it next time.
