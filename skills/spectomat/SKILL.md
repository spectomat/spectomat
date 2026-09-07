---
name: spectomat
description: Use when the user wants a project built autonomously from a written spec — "build this from the spec", "run the loop", "spec-driven", "ralph it" — or asks how the spec / ralph-loop-prompt / ledger fit together. Explains the flow and routes to the spectomat commands.
metadata:
  tags: spectomat, ralph, superpowers
---

# Spectomat — spec-driven autonomous development

Three artefacts, three owners, one loop.

| Artefact | Owner | Role |
| --- | --- | --- |
| `docs/<project>.md` (the spec) | user | **what** to build. Normative, numbered sections, criteria with ids. The loop never edits it. |
| `ralph-loop-prompt.md` | user | **how** the loop runs: mission, environment, loop contract, phases, gates, completion gate. Re-read every iteration. |
| `.claude/build-ledger.local.md` | loop | **progress**: one checkbox per item, conventions, spec reconciliations. Gitignored. |

## The flow

1. **Spec** — write the spec with `superpowers:brainstorming`; shape it per
   `spectomat:writing-specs`.
2. **Scaffold** — `/spectomat:init [name]` writes `ralph-loop-prompt.md` from
   the template, a spec skeleton if none exists, and the ledger ignore. Fill
   the `<!-- EDIT -->` blocks.
3. **Build** — `/spectomat:build [n]` arms the plugin's own Stop hook with a
   one-line pointer prompt (state in `.claude/spectomat-loop.local.md`). Iteration 1 is Phase 0: parallel readers over the
   spec, `superpowers:writing-plans`, ledger written. Every later iteration:
   orient → claim first unchecked item → TDD it → gates → commit → record →
   stop.
4. **Steer** — `/spectomat:status`; edit the ledger or the prompt between
   iterations; `/spectomat:cancel` to stop.
5. **Finish** — the loop emits `<promise>DONE</promise>` only when every item
   is ticked or BLOCKED, every gate passed this iteration, every criterion has
   a named test or a stated block, and `README.md` + `CLAUDE.md` are true.

## Superpowers skills the loop composes

| Where | Skill |
| --- | --- |
| Phase 0 | `dispatching-parallel-agents`, `writing-plans` |
| every build item | `test-driven-development`; `subagent-driven-development` for heavy items |
| gate failure | `systematic-debugging` |
| review phase | `requesting-code-review`, `receiving-code-review` |
| completion | `verification-before-completion` |

## Rules that make it terminate

- One item per iteration. Never re-open a ticked item.
- Three strikes → `BLOCKED` with a reason, never silently dropped.
- Never weaken a gate. Never fake a promise.
- The spec is never edited; contradictions become ledger reconciliations.

Requires the `superpowers` plugin. The Ralph-style Stop hook is built in.
