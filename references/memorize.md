---
name: memorize
description: A reference brief for the memory-writing step every phase brief runs inline, before its own commit. Read this file's body in place of duplicating its prose.
---

# MEMORIZE

This is not a phase and nothing dispatches it. `SPECIFY`, `PLAN`, `REVIEW` and `ARCHIVE` write no code and earn no entries most iterations; `IMPLEMENT` and `REVIEW-SPEC` are the two phases with a "Memory" step in their own `## Commit boundary` / step 5, and that step says: apply this brief, inline, in your own context, before your own commit. Nobody reads `memory.md`'s findings back from you — you fold them into the commit you were already making.

## Procedure

1. Ask what would have saved you time at the start of this phase: where something lives, what a command costs, a convention to copy, a trap and its symptom.
2. Apply `.spectomat/memory.md`'s own header — the three tests (durable past this plan, reusable by a *different* task, not one grep from a file that task already reads), the four sections (Map, Commands, Patterns, Traps), and the size limits (~12 lines a section, ~40 total) — exactly as written there. That header is the one copy of the rule; this step does not restate it.
3. Add what survives to the section it belongs to, one line, newest last: `- <the fact> — <why the next iteration cares>`.
4. On contradiction, correct or delete the stale line rather than adding beside it.
5. Zero new entries is a normal outcome. Do not strain to find one.

## Rules

- The edit rides inside the phase's own commit — never a separate commit, never a separate iteration.
- A trap that cost you a strike or a review round this iteration is the entry most worth having; anything true only of this task or this spec never is.
- Do not log narration — a fact, not what happened. What happened is `log.md`.
