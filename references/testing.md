# Acceptance criteria, building and testing

§9 and §10 of [the specification](../docs/specification.md), numbered as they are cited. A `§` number below 9 names a section of the specification; a `D<n>` id names a row of [the design decisions](./decisions.md).

## 9. Acceptance Criteria

### 9.1 Per component

| Id | Criterion | Verified by |
| --- | --- | --- |
| AC-1.1 | `phase.sh` prints exactly one frontmatter block and exits 0 for every floor state in §10.3 | selftest |
| AC-1.2 | Priority holds: with candidates in all six stages, the verdict is `ARCHIVE` | selftest |
| AC-1.3 | A slug dir with a `plan.md` and zero `task-*.md` files does not yield `ARCHIVE` | selftest |
| AC-1.4 | A reviewed spec whose plan overview exists but has zero task files yields `PLAN` | selftest |
| AC-1.5 | A spec whose slug's phase is `REVIEW-SPEC` yields `REVIEW-SPEC` in the picker; when advanced to `PLAN` it yields `PLAN` | selftest |
| AC-1.6 | A strike logged at `REVIEW-SPEC` does not count at `REVIEW`, nor the reverse | selftest |
| AC-1.7 | A dirty tree yields `RECOVER`, even when no unfinished slug remains, and its `slug` is the one `state.json`'s `current` names; a clean-tree `RECOVER` names no slug | selftest |
| AC-1.8 | `FINISH` requires `state.json` to hold no slug at a non-terminal phase — every entry at `DONE` or `BLOCKED` — **and** a silent `git status` | selftest |
| AC-1.9 | A floor whose every slug is at a terminal phase yields `FINISH`, not `RECOVER`, and a terminal slug is never picked as a candidate | selftest |
| AC-1.10 | A slug dir with no `state.json` entry is not in the flow: the picker neither picks it nor treats it as an anomaly | selftest |
| AC-1.11 | Given two candidates in one stage, the one with fewer strikes is named | selftest |
| AC-1.12 | A candidate at `STRIKE_LIMIT` is skipped; if all are, the next stage is used; if every unfinished slug is at the limit, the verdict is `RECOVER` | selftest |
| AC-1.13 | `phase.sh` leaves the floor and the git index byte-identical | selftest |
| AC-1.14 | The block's `subagent` and `brief` fields are `spectomat:<phase lowercased>` and `{{PLUGIN_ROOT}}/agents/<phase lowercased>.md`, for a hyphenated phase too | selftest |
| AC-2.1 | `command-run.sh` renders an executable `.spectomat/gates.sh` once, from `package.json`, and never overwrites an existing one | selftest |
| AC-2.2 | `run_gates` returns non-zero when `gates.sh` exits non-zero, and names it; a floor without `gates.sh` passes | selftest |
| AC-2.3 | `strike_count` returns 0 when the slug has no `strikes` entry for that phase | selftest |
| AC-3.1 | `agent-archive.sh` with a failing gate writes no marker, commits nothing and exits non-zero | selftest |
| AC-3.2 | `agent-archive.sh` logs `(strike N)` with N one higher than the log showed | selftest |
| AC-3.3 | At the third strike `agent-archive.sh` writes `<slug>/blocked.md` and no `done.md`, records the slug `BLOCKED` in `state.json`, and `print_blocked` lists that slug | selftest |
| AC-3.4 | `agent-archive.sh` makes exactly one commit, touches no file outside the floor, and refuses a slug not at phase `ARCHIVE` | selftest |
| AC-4.1 | `command-status.sh` prints the picker's verdict verbatim | manual, scratch repo |
| AC-4.2 | Arming writes a valid `state.json` with `active: true`, `iteration: 1`, numeric `max_iterations`, `session_id`, `started_at`, `plugin_root` naming the plugin copy that armed it, `current` holding the first iteration's verdict, and one `slugs` entry per slug dir | selftest |
| AC-4.3 | `/spectomat:cancel` sets `active: false` and keeps `state.json` and the floor | selftest |
| AC-4.4 | `command-run.sh` moves a draft dropped into `.wishlist/` to `<slug>/draft.md`, tracked or not, commits it and leaves a clean tree; a hand-written `<slug>/spec.md` arms at `REVIEW-SPEC` | selftest |
| AC-4.6 | `command-run.sh` refuses to arm when anything outside the floor is uncommitted | selftest |
| AC-4.7 | The Stop hook blocks the exit for the owning session, bumps `iteration`, records the next working verdict as `current` (a `RECOVER` leaves it unchanged), and feeds back the pointer prompt verbatim | selftest |
| AC-4.8 | A session that did not arm the flow neither advances nor ends it, and an unreadable state file is left in place for `/spectomat:cancel` | selftest |
| AC-4.9 | An empty floor with a clean tree disarms the flow and reports what shipped and what was blocked; the iteration cap disarms it too | selftest |
| AC-4.11 | An empty floor with a dirty tree does not end the flow: the hook blocks and the next verdict is `RECOVER` | selftest |
| AC-4.10 | `pointer_prompt()` resolves `PLUGIN_ROOT` with no unresolved `{{KEY}}` placeholder left in its output | selftest |
| AC-4.5 | Drafts are taken in alphabetical order of the file name, whatever their modification times | selftest |
| AC-4.12 | Re-arming over a `state.json` holding terminal entries neither resurrects them nor counts them as active; a slug dir carrying a marker but no entry is seeded at its terminal phase, and a dir whose files match no phase is blocked and committed | selftest |
| AC-5.1 | The plugin loads `AGENT_COUNT` agents | `--debug-file` grep, §10.5 |
| AC-5.2 | Both plugin manifests validate `--strict` | manual |
| AC-5.3 | `agents/task.md` exists, is named `task`, and never calls a `slug_*` helper, `slug_set_phase.sh`, `tasks.sh` or `log.sh` | selftest |
| AC-5.4 | `agents/implement.md` names `spectomat:task` and allows the Agent tool; `agents/task.md` forbids it | selftest |
| AC-5.5 | `templates/task.md` carries `## Scope`, and its `## Context` carries the `Excerpts from Spec`, `From Memory`, `From existing codebase` and `From previous tasks` subsections | selftest |
| AC-6.1 | No brief carries a `{{KEY}}` placeholder | selftest |
| AC-6.2 | No brief points at a `prompts/` file, and every phase brief calls a state helper to advance its slug's phase — `slug_set_phase` for the phases that carry no tasks, `scripts/tasks.sh` for `PLAN`, `IMPLEMENT` and `REVIEW` | selftest |
| AC-6.3 | No brief names `result.md`, and none edits `tasks.json` with `jq`, `Write` or `Edit`: `scripts/tasks.sh` is the ledger's only writer | selftest |
| AC-6.3 | `NOTICE.md` names only files that exist | grep, selftest |

### 9.2 End-to-end

| Id | Criterion | Verified by |
| --- | --- | --- |
| E2E-1 | A scratch repo with two drafts runs until the Stop hook reports the flow complete, producing two slug dirs each carrying `done.md` and committed code | `claude -p` run, §10.5 |
| E2E-2 | An iteration killed mid-`IMPLEMENT` leaves a dirty tree; the next iteration's verdict is `RECOVER` and the janitor restores a clean tree | manual, scratch repo |

### 9.3 Non-functional

| Target | Measured by |
| --- | --- |
| `phase.sh` completes in under 200 ms on a floor of 20 plans | `time` in the scratch repo; it is on the path of every iteration and of `status` |
| `selftest.sh` stays under 8s, and one test case — fixture setup plus one subject invocation — costs at or below 200ms | wall time for the total; the per-case figure by A/B against a scratch harness of N identical cases |
| bash 3.2 compatible, no GNU-only flags, `jq` the only non-base dependency | the dependency test in `selftest.sh` |

## 10. Building and testing

### 10.1 Toolchain

bash 3.2, `jq`, no build, no package manager, no network. `scripts/utils.sh` is sourced by every script and sets no shell options; each script chooses its own `set -e/-u/pipefail`.

### 10.2 Configuration contract

| Placeholder | Rendered into | Value |
| --- | --- | --- |
| `{{PLUGIN_ROOT}}` | `pointer_prompt()` in `scripts/utils.sh` (in memory, never a file) | absolute plugin path; locates `scripts/phase.sh`, `scripts/agent-archive.sh` and `agents/*.md` |
| `{{REPO}}` | `contract.md`, `memory.md` | the repository root, substituted at the one and only render |
| `{{GATES}}` | `.spectomat/gates.sh` | the gate lines compiled by `detect_gates` (§5.5), or `GATES_NONE` when none were detected, substituted at the one and only render |

A new placeholder requires a matching value in the `render_template` call in `command-run.sh`. Substitution is literal, and literally means literally: a value carrying `&`, `\`, `$` or `{{X}}` lands as written, and `tests/render_template_test.sh` holds a case for each. `{{GATES}}` lands under the rendered script's `set -e`, so every line must be a real command whose exit code means what it says (§5.5). `state.json` has no template: `arm_flow` writes its seven fields inline (`active`, `iteration`, `max_iterations`, `session_id`, `started_at`, `plugin_root`, `current`) over the `slugs` that `seed_state` filled, with `max_iterations` and `iteration` unquoted, so `parse_args` must keep requiring `^[0-9]+$` for the iteration cap.

### 10.3 Fixtures

The bash equivalent of a port and a fake. Every case in `tests/*.sh` builds one, using the shared fixture helpers in `tests/lib.sh`:

```text
floor(dir, spec):   under a fresh `mktemp -d`, `git init`, then create the
                    floor described by spec — one <slug>/ directory per idea
                    holding its draft, spec, plan overview and a given number
                    of task files (their contents inert — the task counters in
                    state.json carry the progress), a done.md or blocked.md
                    marker and its terminal state.json phase for a finished
                    slug, a state.json with given slugs, phases, task counters,
                    and strikes, a log.md with given strike lines for audit
                    trail, and a gates.sh running given commands
```

State is built programmatically via jq to create the `.slugs` object:

```text
state = {
  active: false,
  iteration: 0,
  max_iterations: 0,
  session_id: "fixture",
  started_at: "1970-01-01T00:00:00Z",
  slugs: {
    <slug1>: {phase: "PLAN", strikes: {SPECIFY: 0, PLAN: 1}},
    <slug2>: {phase: "IMPLEMENT", strikes: {}},
    <slug3>: {phase: "DONE", strikes: {}}
  }
}
```

Cases are then a verdict assertion (`pk NAME want`) or an effect assertion over the resulting tree. Every fixture is a real git repository, because `git status --porcelain` is normative input and must not be stubbed.

### 10.4 The gates

```bash
bash -n scripts/*.sh tests/*.sh templates/gates.sh
scripts/selftest.sh
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

### 10.5 What the gates do not cover

| Not covered | Checked instead by |
| --- | --- |
| whether the runtime loads `AGENT_COUNT` agents | `claude -p … --debug-file <f> --model opus`, then grep `<f>` for `Loaded 8 agents from plugin`; a `-p` prompt asking Claude to list agent types reports NONE even when they are loaded, so it must not be used |
| whether a full flow reaches `FINISH` | `claude -p "/spectomat:run 25" --plugin-dir . --model opus` in a scratch repo with two drafts |
| whether the Stop hook releases against the real runtime | the selftest drives it with a fabricated payload; only a live session proves Claude Code honours the `block` decision |
| whether `command-run.sh` keeps an edited contract | arming twice in a scratch repo, editing `contract.md` between runs |

Nested `claude -p` must always be given `--model opus`; the CLI rejects the default model.

### 10.6 The invariants that must be tests

| Invariant | Why a test and not a rule |
| --- | --- |
| the picker mutates nothing | it is called by `status` on demand and by every iteration; a stray write would corrupt the floor silently |
| `ARCHIVE` never fires on a plan with no task files | the failure archives unbuilt work and is invisible until someone reads the slug dir |
| a blocked slug is still listed by `print_blocked` | a blocked slug that nothing reports is a silently dropped idea |
| a slug at a terminal phase is never archived again | a second `ARCHIVE` would commit over finished work, and would promote a blocked slug to shipped |
| the picker reads no directory | one stat of a slug dir brings back the two-authority reconciliation D27 deleted, and no behavioural test would catch it; enforceable by grepping `scripts/phase.sh` for floor access |
| no brief carries a `{{KEY}}` placeholder | briefs are never rendered, so a placeholder would reach an agent literally |
| the task agent touches no floor state | a worker that advanced `state.json` or logged would make one task two entries, and the phase agent's close would count it twice; enforceable by grepping `agents/task.md` for `slug_` and `log.sh` |
| arming and cancelling touch only `state.json` | a second file for the pointer prompt would need its own cleanup on every disarm path, and could go stale if the plugin moved between arms (D23) |
| only the session that armed a flow may end it, an unreadable state file included | the hook fires in every session of the project, so a guard that runs before the session check lets a stranger delete a flow it does not own |
| `command-run.sh` refuses to arm on a dirty tree | the picker answers `RECOVER` to any dirt, so arming over work in progress spends the entire cap on the janitor |
| `NOTICE.md` names only files that exist | a licence notice pointing at deleted files does not discharge the obligation |

### 10.7 The suite

`scripts/selftest.sh` runs every `tests/*_test.sh` file and reports the combined tally: the picker, the archiver, the task ledger, `command-run.sh` arming and refusing, and the Stop hook driven with a fabricated `{session_id}` payload. Each file is one section (`phase_test.sh`, `archive_test.sh`, `tasks_test.sh`, `prepare_test.sh`, …), owns its fixtures through the shared harness in `tests/lib.sh` (§10.3), and runs alone: `bash tests/phase_test.sh` drives just the picker. Within a file, assertions are one linear script of `is NAME GOT WANT` calls, printing `ok` or `FAIL` per assertion.

An optional `DIR` argument — to `scripts/selftest.sh` or to any one test file — points the run at a different `scripts/` copy, such as the installed cache (§7.3), instead of the one next to it.

What the suite cannot cover is the live runtime (§10.5). A real flow is exercised in a scratch git repository, never in the plugin's own checkout (§6.2).

### 10.8 Two bash generations

`.github/workflows/ci.yml` runs the manifest checks, `bash -n` and `scripts/selftest.sh` on both `ubuntu-latest` and `macos-latest`, for every push and pull request. **The two runners are not redundant:** macOS carries bash 3.2 and Ubuntu bash 5.x, and a passing local run on one proves nothing about the other. Bash 5.2 gave an unquoted `&` in a `${var//pat/repl}` replacement the sed meaning "the text that matched"; that broke `render_template` on Linux only, while every macOS run stayed green.

Rule: prefer constructs whose meaning does not move between the two generations; where one is unavoidable, cover it with a test rather than a comment.
