# Domain model

§2 of [the specification](../docs/specification.md), numbered as it is cited. A `§` number names a section of the specification; a `D<n>` id names a row of [the design decisions](./decisions.md).

## 2. Domain Model

The floor is `.spectomat/`, entered from `.wishlist/` beside it: one directory `<slug>/` per idea holding that idea's whole trail, `work/`, plus `log.md`, `contract.md`, `memory.md`, `gates.sh` and `state.json`. Membership in the flow is a `state.json` field and nothing else: a slug is finished when its `.slugs[<slug>].phase` is `DONE` or `BLOCKED`, and the `done.md` or `blocked.md` its dir carries is the committed human record, written and committed by `agent-archive.sh` but read by nothing (D27). The contract's *The floor* section defines it and is not restated here. Three further entities are the system's own.

### 2.1 `verdict`

The picker's entire output: a single YAML-frontmatter-shaped block (`---` … `---`) on stdout, exit code 0.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | `SPECIFY`\|`REVIEW-SPEC`\|`PLAN`\|`IMPLEMENT`\|`REVIEW`\|`ARCHIVE`\|`FINISH`\|`RECOVER` | which phase applies, or `FINISH` for none, or `RECOVER` for a dirty tree |
| `slug` | string, empty for `FINISH` and for a clean-tree `RECOVER` | the draft file name without `.md`, as the operator named it; for a dirty-tree `RECOVER`, the slug `state.json`'s `current` names — the iteration that died (D33) |
| `subagent` | string, e.g. `spectomat:review-spec` | the `subagent_type` to pass the Agent tool — `spectomat:` plus `phase` lowercased |
| `brief` | absolute path | the brief file to hand that subagent, `{{PLUGIN_ROOT}}/agents/<phase lowercased>.md` |
| `plugin_root` | absolute path | the plugin root, so a brief can still reach `templates/` and other plugin files with no plugin path of its own |

Identity: there is exactly one verdict per iteration. The picker never reads an earlier verdict to choose the next one — it is re-run, never remembered — but the working verdicts it hands out are recorded as `state.json`'s `current` by the Stop hook and by arming, so a dirty-tree `RECOVER` can name the iteration that died (D33). Written by: `scripts/phase.sh` only. `subagent`, `brief` and `plugin_root` are derived fields, not independent state — all three follow from `phase` and `PLUGIN_ROOT`, so the pointer needs no lookup table of its own (§3.3).

**Two vocabularies, six shared values.** `state.json`'s `.slugs[<slug>].phase` holds the six working phases (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`) plus the two terminal phases `DONE` and `BLOCKED`. The verdict's `phase` field holds the same six working phases plus `RECOVER` and `FINISH`. The sets overlap on six values and are not the same set: `DONE` and `BLOCKED` are never emitted as a verdict, never lowercased into an agent name, and have no row in the dispatch table; `RECOVER` and `FINISH` are never stored as a slug's phase.

### 2.2 `strike ledger`

A `state.json` field: `.slugs[SLUG].strikes[PHASE]`, holding the strike count for a `(phase, slug)` pair.

| Field | Type | Meaning |
| --- | --- | --- |
| `phase` | phase name | the phase that was defeated |
| `slug` | string | the slug it was defeated on |
| `count` | integer 0..`STRIKE_LIMIT` | how many times |

Identity: `(phase, slug)`. Written by: any phase agent, and `agent-archive.sh`, by calling `slug_strike` (§5.2). Read by: the picker (§5.2) and `agent-archive.sh` (§5.6).

### 2.3 `gates`

`.spectomat/gates.sh`: one executable script holding every check this project must pass. It is run, never parsed, so only its interface is normative.

| Field | Type | Meaning |
| --- | --- | --- |
| path | `.spectomat/gates.sh` | fixed; the contract names it and no phase may substitute another command |
| exit code | integer | 0 means every gate passed; anything else is a failure |

Identity: one per floor. Written by: `command-run.sh` at first render, from `package.json` (§5.5), and the operator by hand thereafter — never rewritten by the factory (D9). Read by: nobody; run by the `IMPLEMENT` agent and `agent-archive.sh` through `run_gates` (§5.4).
