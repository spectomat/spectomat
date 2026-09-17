# Brainstorm

**Classify the draft** before the first question, and state the class in §1.1:

| Class | Test | What it changes |
| --- | --- | --- |
| Bounded | a change to a flow that already exists in this codebase — the flow is here to read | read that flow first, then `memory.md`; the spec follows its patterns and §6 stays a paragraph |
| Architectural | a new project, a new subsystem, or a change to an interface others depend on | every step below, in full |

When in doubt between the two, take architectural. A draft that looks bounded and grows while you write is upgraded, never the reverse.

**Ask the clarifying questions yourself**, one per doubt, in this order: purpose (what must be true after), constraints (what must not change), success criteria (what an observer would see). Answer each from, in order: another sentence of the draft, the codebase, `memory.md`, the simplest reading. Every answer the draft did not give is an `assumed` row in §10, with the alternative you rejected and why.

**Propose two or three approaches** to every doubt that is a design choice rather than a fact, with trade-offs, and pick one. Lead with the simplest that satisfies the draft; cut from every approach anything the draft did not ask for. The chosen approach goes into Part I; the rejected ones go into the Rejected column of its §10 row. An approach nobody recorded is a guess the planner cannot trace.

**Design for isolation.** Break the system into units that each have one purpose and talk through named interfaces (§6, §13). For each unit you can answer: what it does, how it is used, what it depends on. A unit whose internals must be read to understand it has the wrong boundary.

**In an existing codebase**, read the structure before proposing, follow its patterns, and include a targeted improvement only where existing code blocks the draft. Nothing unrelated.

**A draft that asks for several independent systems** is neither brainstormed into one spec nor silently cut to one: it is a strike. Write no spec, leave the draft in place, bump the slug's `state.json` strike count for `SPECIFY` (`scripts/utils.sh`'s `slug_strike`), log `(strike N: draft asks for K independent systems: a, b)`, and stop; the operator splits it. `slug_strike` prints the new count: if it is the third, the slug is blocked, so follow the contract's *Three strikes* — move the draft to `done/<slug>.draft.blocked.md`, then `slug_delete <slug>` so `state.json` keeps no entry the floor cannot back.
