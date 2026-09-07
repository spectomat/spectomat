---
name: verification-before-completion
description: Use before claiming a task, plan or gate is done, before every commit, and before the FACTORY EMPTY promise — run the proving command now and read its output; evidence before claims.
---

# Verification before completion

```
NO COMPLETION CLAIM WITHOUT FRESH EVIDENCE
```

A command you did not run in this iteration has not passed.

## The gate

1. **Identify** the command that proves the claim.
2. **Run** it, whole and fresh.
3. **Read** the full output: exit code, failure count, warnings.
4. **Compare** output to claim. Mismatch → report the real status with the
   output. Match → make the claim with the numbers.

| Claim | Requires | Not enough |
| --- | --- | --- |
| tests pass | the test command, 0 failures, this iteration | an earlier run, "should pass" |
| lint clean | the linter, 0 diagnostics | "the tests pass" |
| build succeeds | the build command, exit 0 | lint passing |
| bug fixed | the reproducing test passes | the code changed |
| subagent finished | the diff and the test output | the subagent's report |
| task complete | every step ticked against evidence | tests passing |
| floor empty | `ls` of drafts, specs, plans; clean `git status` | memory of earlier listings |

## Red flags

"Should", "probably", "seems to"; satisfaction before the run; trusting a
report over a diff; a partial run standing for the whole; "just this once".
Each one means: run the command.

## In the log

Record numbers, never adjectives: `tsc 0, tests 58/58 (12 files), lint 0`.
A log line without numbers did not run the gates.
