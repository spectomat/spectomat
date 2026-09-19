# Normative algorithms

§5 of [the specification](../docs/specification.md), numbered as it is cited. A `§` number names a section of the specification; a `D<n>` id names a row of [the design decisions](./decisions.md).

## 5. Normative Algorithms

Named constants, each defined once here and nowhere else in the system:

| Constant | Value | Owned by |
| --- | --- | --- |
| `STRIKE_LIMIT` | 3 | `scripts/utils.sh` |
| `MAX_REVIEW_ROUNDS` | 2 | `agents/review.md` |
| `AGENT_COUNT` | 8 | this spec, asserted by AC-5.1 |

### 5.1 `pick_phase` — `scripts/phase.sh`

```text
# emit(phase, slug='') prints the frontmatter block (§2.1): phase, slug, and
# subagent/brief/plugin_root derived from phase alone.

pick_phase():
  cd_root()
  if not exists(STATE_FILE):                 emit('FINISH'); return 0
  if `git status --porcelain` is non-empty:  emit('RECOVER', current.slug); return 0

  for phase in [ 'ARCHIVE', 'REVIEW', 'IMPLEMENT', 'PLAN', 'REVIEW-SPEC', 'SPECIFY' ]:
      pick = least_struck(phase, slugs_at_phase(phase))
      if pick is not NONE:  emit(phase, pick); return 0

  if slugs_unfinished() is empty:  emit('FINISH')
  else:                            emit('RECOVER')
  return 0
```

Normative notes, each of which a naive reading would get wrong:

1. **`ARCHIVE` and `REVIEW` are tested before `IMPLEMENT`**, matching the contract's priority: work in progress is finished before anything new starts.
2. **A slug's phase is stored in `state.json.slugs[slug].phase`**, not derived from floor files. Once in a phase, the slug stays until the brief advances it.
3. **Slugs enter state at arm time and only there.** `command-run.sh` moves each `.wishlist/*.md` to `<slug>/draft.md`, commits it, and `seed_state` calls `slug_add` for every slug dir with no entry yet — `SPECIFY` for a dir holding only a draft, `REVIEW-SPEC` for a hand-written `spec.md`, `IMPLEMENT` or `REVIEW` for a dir with a committed `tasks.json`, depending on whether any task is still pending (D31), `DONE`/`BLOCKED` for a dir already carrying a marker, `BLOCKED` for one the files place nowhere, which it writes a `blocked.md` for and commits so arming still ends on a clean tree. That scan is the only directory listing in the system: after arming, every script reads `state.json` and nothing walks the floor again (D27). Arming must end on a clean tree: the picker answers `RECOVER` to any dirt, so an unstaged leftover costs the flow its first iteration.
4. **`ARCHIVE` and `REVIEW` are split by phase** (`state.json.slugs[slug].phase` is `ARCHIVE` or `REVIEW`), not by a line in the plan. The `REVIEW` phase advances a slug from `IMPLEMENT` to `REVIEW`; only `REVIEW` returning a verdict advances it to `ARCHIVE`.
5. **The fall-through `RECOVER` now means exactly one thing:** every unfinished slug is at `STRIKE_LIMIT` in its current phase, which is the only way `least_struck` skips a candidate. Nothing else reaches that branch — a slug dir with no state entry is not in the flow, and the picker cannot see it to call it an anomaly.
6. **`RECOVER` precedes every stage test**; only the state-file guard runs before it. A dirty tree with no unfinished slug is a phase having died between its writes and its commit. A dirty-tree `RECOVER` carries `current.slug` — the last working verdict, which the Stop hook and arming record and a `RECOVER` never replaces (D33); a clean-tree `RECOVER` carries no slug.
7. The picker **never mutates** anything. It is safe to run from `/spectomat:status`.

### 5.2 `least_struck` — `scripts/utils.sh`

```text
least_struck(phase, set):
  if set is empty:  return NONE
  scored = [ (strike_count(phase, s), s) for s in set ]
  eligible = [ (n, s) in scored : n < STRIKE_LIMIT ]
  if eligible is empty:  return NONE            # fall through to the next stage
  sort eligible by (n ascending, s ascending)
  return the s of the first
```

A slug at `STRIKE_LIMIT` is skipped so a failed block-move cannot wedge the factory; if every candidate of a stage is skipped, the stage is treated as empty and the next stage is tried.

### 5.3 `strike_count` — `scripts/utils.sh`

```text
strike_count(phase, slug):
  return .slugs[slug].strikes[phase] // 0  from state.json
```

Returns 0 when the slug has no `strikes` entry for that phase, or when the slug is absent from `state.json`.

### 5.4 `run_gates` — `scripts/utils.sh`

```text
run_gates():
  if not exists(.spectomat/gates.sh):  return 0
  bash .spectomat/gates.sh
  if exit status != 0:
      GATE_FAILED = '.spectomat/gates.sh'
      return that status
  return 0
```

The gates are always `./.spectomat/gates.sh` and nothing else (D6). The script is generated once by `command-run.sh` from the repository's `package.json` (§5.5), committed, and is the operator's editable surface for what gets verified — the contract only names it. Running it as a script rather than parsing commands out of the contract is deliberate: it is operator-authored shell in a committed file of their own repository, at the same trust level as a `package.json` script, and its own `set -e` chains its lines, so one exit code answers for the whole run. A floor with no `gates.sh` has nothing to verify and passes.

### 5.5 `detect_gates` — `scripts/gates.sh`

```text
detect_gates():
  if package.json defines a 'gates' script:  GATES = 'npm run gates'
  else: GATES = one line per script of typecheck, lint, test that
        package.json defines, in that order
        ('npm test' for test, 'npm run <s>' otherwise)
```

`command-run.sh` renders `GATES` into `templates/gates.sh` at the one and only render, or, when nothing was detected, `GATES_NONE`: commented example lines and an `echo "ok: …"` that exits 0. A repo with no gates yet has not failed anything, so the generated script must never exit non-zero to signal its own emptiness (D25). `gates.sh` run directly prints what it would render for the repository it is run in.

### 5.6 `archive` — `scripts/agent-archive.sh`

Invoked by the `spectomat:archive` subagent (`agents/archive.md`), which relays its stdout/stderr and exit code unchanged and performs no mutation of its own (D21).

```text
archive(slug):
  cd_root()
  require `git status --porcelain` silent                            else exit 1
  require state.slugs[slug].phase == 'ARCHIVE'                       else exit 1

  if run_gates() != 0:
      n = slug_strike(slug, 'ARCHIVE')
      log '- <ts> · ARCHIVE · <slug> · gate failed: <cmd> (strike ' + n + ')'
      if n >= STRIKE_LIMIT:  block = true  and continue to the marker
      else:                  exit 1
  else:
      block = false
      gate_result = 'passed'

  if block:  write <slug>/blocked.md  with the strike count and the failed gate
  else:      write <slug>/done.md     with the timestamp and the gate result

  git add -A <slug>/
  git commit -m 'chore(<slug>): archived' (or '… blocked after 3 strikes')
      or strike_and_exit

  (block ? block_slug(slug, reason) : slug_done(slug, reason))   # terminal phase, after the commit lands
  log '- <ts> · ARCHIVE · <slug> · archived · gates passed'
```

**One marker, no moves.** Finishing a slug writes a single new file in that slug's own directory, so there is no partial state to survive: either the marker and its commit landed or neither did (D26). This replaces a six-move sequence whose every step had to be checked, because a partial move that still committed left a CLEAN tree — the picker never answered `RECOVER`, the janitor never ran, and a spec whose plan had already been archived read as a fresh `PLAN` phase. The marker is now the committed human record and nothing else: `state.json` is gitignored, so `done.md` and `blocked.md` are the only trace of how a slug ended that survives in git, and no script reads them back (D27).

**The commit is still checked.** The script runs under `set -uo pipefail` with no `-e`, so a failed command does not abort. `strike_and_exit` records a strike in `state.json` — so the slug blocks after three — then exits 1, leaving the marker uncommitted and the tree dirty for the janitor. Exiting without a strike would wedge the flow, because the picker answers `ARCHIVE` again next iteration and the same commit fails again until the cap.

**Only a slug at `ARCHIVE` is archived.** One state check replaces the three file checks it supersedes and is stronger than all of them: a slug reaches `ARCHIVE` only through `REVIEW`, which only happens after `PLAN` wrote a plan and `IMPLEMENT` closed every task, so the spec and the plan exist by construction. It keeps a second `ARCHIVE` from committing over finished work and keeps a blocked slug from being silently promoted to shipped, because neither `DONE` nor `BLOCKED` is `ARCHIVE` (D27). The third strike differs from a pass only in which marker is written, so the path is written once. `print_blocked` lists `.spectomat/<slug>/blocked.md` for every slug at `BLOCKED`, building the path from the slug name without stat'ing it: the marker is written before the terminal phase is recorded, so a slug at that phase has its file.

The log line reports the gate outcome, not test counts: a script has first-hand knowledge that `gates.sh` exited 0, and no knowledge of what it printed (D4).
