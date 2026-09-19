# CLAUDE.md

An agentic ledger, transient by nature. Durable knowledge lives in the files below: read it there, write it there, and keep only pointers and unsettled notes here.

## Where the knowledge lives

| Need | Read |
| --- | --- |
| What this repo is, requirements, verifying a change, installing, conventions, commits | `CONTRIBUTING.md` |
| Overview, boundaries, operator surface, and the map of every section — read before changing behaviour | `docs/specification.md` |
| Domain model (§2): verdict, strike ledger, gates | `references/domain-model.md` |
| Behaviour (§3): iteration, dispatch, failure path, completion | `references/behaviour.md` |
| Algorithms (§5): constants, the picker, strikes, gates, the archiver — in pseudocode | `references/algorithms.md` |
| Architecture (§6): contract, briefs, state and ledger schemas, the pointer | `references/architecture.md` |
| Design decisions (§8): what was decided, what was rejected, and why — check before proposing a change | `references/decisions.md` |
| Where a rule lives, phase-agent confinement | `references/architecture.md` §6.2 |
| Placeholders and literal substitution | `references/testing.md` §10.2 |
| Acceptance criteria, fixtures, the test suite; bash 3.2 vs 5.x in CI | `references/testing.md` §9, §10.3, §10.7, §10.8 |
| The terms — flow, iteration, phase, task, floor, contract, slug, strike. Use these words, not synonyms | `references/glossary.md` |
| What lives where in the plugin, the dispatch picture (§1.2, §6.1) | `references/file-structure.md` |
| The floor's files in the user's project | `references/floor.md` |
| Logo and social card: drawing, rendering, publishing | `references/assets.md` |
| Phase procedures: brainstorm, gates, memorize, three strikes, log format | `references/` |
| The user guide | `docs/guide.md` |
| Third-party material and licences | `NOTICE.md` |

## Ledger

Rules learned from the operator's edits, newest first. Once a rule settles, move it to its durable home above and delete it here.

- (empty)
